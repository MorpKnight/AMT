#if DEBUG
import AppKit
import Foundation

private enum AIConnectorQualityExecutionError: Error {
    case viewModelDeallocated
}

@MainActor
extension AIConnectorViewModel {
    var isPhaseEightQualityRunning: Bool {
        phaseEightQualityTask != nil
    }

    func runPhaseEightQualityGate() {
        guard !isPhaseEightQualityRunning else { return }

        phaseEightQualityReport = nil
        phaseEightQualityNotice = nil
        let fixtures = phaseEightFixtureStore.fixtures
        let reviews = phaseEightFixtureStore.reviews.values.sorted { $0.fixtureID < $1.fixtureID }
        let policy = phaseEightQualityPolicy
        let manifest = AIConnectorQualityCandidateManifestFactory.make(
            fixtures: fixtures,
            policy: policy,
            corpusVersion: activeCorpusVersion
        )
        phaseEightQualityProgress = AIConnectorQualityRunProgress(
            mode: .deterministic,
            completedFixtureCount: 0,
            totalFixtureCount: fixtures.count
        )

        let runner = AIConnectorQualityRunner()
        phaseEightQualityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let report = await runner.run(
                fixtures: fixtures,
                reviews: reviews,
                policy: policy,
                candidateManifest: manifest,
                execution: { [weak self] mode, fixture in
                    guard let self else { throw AIConnectorQualityExecutionError.viewModelDeallocated }
                    return try await self.runPhaseEightFixture(fixture, mode: mode)
                },
                onProgress: { [weak self] mode, completed, total in
                    guard let self else { return }
                    self.phaseEightQualityProgress = AIConnectorQualityRunProgress(
                        mode: mode,
                        completedFixtureCount: completed,
                        totalFixtureCount: total
                    )
                }
            )
            guard self.phaseEightQualityTask != nil else { return }
            self.phaseEightQualityReport = report
            self.phaseEightQualityTask = nil
            self.phaseEightQualityNotice = switch report.overallStatus {
            case .pass:
                "Quality gate Phase 8 lulus. Persetujuan rilis tetap memerlukan pemeriksaan kandidat secara eksplisit."
            case .fail:
                "Quality gate Phase 8 gagal. Lihat kategori dan safety violation sebelum rilis."
            case .insufficientEvidence:
                "Evaluasi selesai, tetapi bukti belum cukup untuk menyatakan fitur layak rilis."
            }
        }
    }

    func cancelPhaseEightQualityGate() {
        phaseEightQualityTask?.cancel()
        phaseEightQualityNotice = "Membatalkan evaluasi Phase 8… report parsial tidak dapat meloloskan gate."
    }

    func exportPhaseEightReviewPackage() {
        switch AIConnectorQualityReviewPackagePresenter.export(
            fixtures: phaseEightFixtureStore.fixtures,
            reviews: phaseEightFixtureStore.reviews.values.sorted { $0.fixtureID < $1.fixtureID }
        ) {
        case let .success(url):
            phaseEightQualityNotice = "Paket review disimpan di \(url.path)."
        case let .failure(error):
            if error != .cancelled {
                phaseEightQualityNotice = error.localizedDescription
            }
        }
    }

    func importPhaseEightReviewPackage() {
        switch AIConnectorQualityReviewPackagePresenter.import() {
        case let .success(package):
            do {
                _ = try phaseEightFixtureStore.apply(package)
                phaseEightQualityReport = nil
                phaseEightQualityNotice = "Paket review berhasil diimpor secara atomic: \(phaseEightFixtureStore.approvedFixtureCount) fixture disetujui."
            } catch {
                phaseEightQualityNotice = error.localizedDescription
            }
        case let .failure(error):
            if error != .cancelled {
                phaseEightQualityNotice = error.localizedDescription
            }
        }
    }

    func exportPhaseEightSafeJSON() {
        guard let report = phaseEightQualityReport else { return }
        let panel = NSSavePanel()
        panel.title = "Ekspor Safe JSON Phase 8"
        panel.nameFieldStringValue = AIConnectorQualitySafeJSONExporter.defaultFileName()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let url = try AIConnectorQualitySafeJSONExporter.write(report, to: destination)
            phaseEightQualityNotice = "Safe JSON disimpan di \(url.path)."
        } catch {
            phaseEightQualityNotice = error.localizedDescription
        }
    }

    func runPhaseEightFixture(
        _ fixture: AIConnectorQualityFixture,
        mode: AIConnectorReviewMode
    ) async throws -> AIConnectorQualityObservedOutput {
        let startedAt = Date()
        reviewMode = mode
        modelVariant = .qwen35Base4B
        generationProfilePreset = .greedy
        thinkingEnabled = false
        inputSource = .currentDocument

        var analysisText = fixture.text
        run(documentText: analysisText, scope: .fullFresh)
        try await waitForPhaseEightRun()

        if fixture.category == .incremental, case .completed = state {
            analysisText += "\n"
            markDocumentEdited(documentText: analysisText)
            rerunIncrementally(documentText: analysisText)
            try await waitForPhaseEightRun()
        }

        let totalDuration = max(Date().timeIntervalSince(startedAt), 0)
        let complete: Bool
        if case .completed = state {
            complete = true
        } else {
            complete = false
        }

        return AIConnectorQualityObservedOutput(
            fixtureID: fixture.id,
            complete: complete,
            findings: phaseEightObservedFindings(
                in: analysisText,
                categoryOverride: fixture.category == .definitionResolution
                    ? .definitionResolution
                    : nil
            ),
            safety: .zero,
            firstResultLatency: incrementalRunMetrics.firstResultLatency,
            totalDuration: totalDuration,
            stageDurations: [
                "context-preparation": max(contextPreparationDuration, 0),
                "document-review": max(documentFindingMetrics.duration, 0),
                "analysis": totalDuration
            ],
            reusedSegmentCount: max(reusedSegmentCount, 0),
            recomputedSegmentCount: max(reprocessedSegmentCount, 0),
            modelCallCount: max(runSummary?.modelCallCount ?? modelCallCount, 0),
            resourcePreparationDuration: max(contextPreparationDuration, 0),
            incrementalEquivalentToFresh: nil
        )
    }

    private func waitForPhaseEightRun() async throws {
        while isRunning {
            if Task.isCancelled {
                cancel()
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private func phaseEightObservedFindings(
        in documentText: String,
        categoryOverride: AIConnectorQualityCategory?
    ) -> [AIConnectorQualityObservedFinding] {
        var findings: [AIConnectorQualityObservedFinding] = []

        for review in validatedReviews where review.status != .noSuggestion {
            guard let original = review.original,
                  let anchor = review.sourceAnchor else { continue }
            let range = NSRange(
                location: review.segment.sourceLocation + anchor.sourceLocation,
                length: anchor.sourceLength
            )
            let isValid = anchor.isValid(for: review.segment, original: original)
                && range.location >= 0
                && NSMaxRange(range) <= documentText.utf16.count
                && (documentText as NSString).substring(with: range) == original
            findings.append(
                AIConnectorQualityObservedFinding(
                    occurrence: occurrence(of: original, in: documentText, at: range.location),
                    category: qualityCategory(for: review.category),
                    status: review.status.rawValue,
                    original: original,
                    replacement: review.replacement,
                    classification: nil,
                    sourceID: review.glossaryMatch?.entry.id,
                    sourceEvidenceID: review.glossaryMatch?.entry.sourcePassageID,
                    sourceVerified: review.glossaryMatch?.entry.authority == .verified,
                    sourceActionable: review.glossaryMatch?.entry.isActionable == true,
                    readOnly: review.status != .suggestion,
                    anchorValid: isValid
                )
            )
        }

        for assessment in definitionAssessments where assessment.isFinding {
            guard let term = assessment.term else {
                continue
            }
            let annotationID = EditorSuggestionMapper.definitionAnnotationID(for: assessment)
            let hasResolution = definitionResolutions[annotationID] != nil
            let termRange = (assessment.segment.targetText as NSString).range(of: term)
            guard termRange.location != NSNotFound else { continue }
            let globalRange = NSRange(
                location: assessment.segment.sourceLocation + termRange.location,
                length: termRange.length
            )
            let isValid = globalRange.location >= 0
                && NSMaxRange(globalRange) <= documentText.utf16.count
                && (documentText as NSString).substring(with: globalRange) == term
            findings.append(
                AIConnectorQualityObservedFinding(
                    occurrence: occurrence(of: term, in: documentText, at: globalRange.location),
                    category: categoryOverride == .definitionResolution && hasResolution
                        ? .definitionResolution
                        : .definition,
                    status: assessment.classification.rawValue,
                    original: term,
                    replacement: nil,
                    classification: assessment.alignment.rawValue,
                    sourceID: assessment.candidate?.match.entry.id,
                    sourceEvidenceID: assessment.candidate?.match.entry.sourcePassageID,
                    sourceVerified: assessment.candidate?.match.entry.authority == .verified,
                    sourceActionable: assessment.candidate?.match.entry.isActionable == true,
                    readOnly: true,
                    anchorValid: isValid
                )
            )
        }

        for finding in documentFindings {
            let category: AIConnectorQualityCategory
            switch finding.kind {
            case .definedTerm: category = .definedTerm
            case .legalRisk: category = .legalRisk
            case .internalReference: category = .internalReference
            }
            findings.append(
                AIConnectorQualityObservedFinding(
                    occurrence: occurrence(of: finding.original, in: documentText, at: finding.sourceRange.location),
                    category: category,
                    status: finding.disposition.rawValue,
                    original: finding.original,
                    replacement: nil,
                    classification: nil,
                    sourceID: nil,
                    sourceEvidenceID: finding.relatedEvidence.first?.id,
                    sourceVerified: false,
                    sourceActionable: false,
                    readOnly: true,
                    anchorValid: finding.isAnchored(to: documentText)
                )
            )
        }

        return findings.sorted {
            if $0.occurrence == $1.occurrence {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.occurrence < $1.occurrence
        }
    }

    private func qualityCategory(for category: AIReviewCategory) -> AIConnectorQualityCategory {
        switch category {
        case .spelling: .spelling
        case .grammar: .grammar
        case .terminology, .clarity: .terminology
        case .none: .hardNegative
        }
    }

    private func occurrence(of original: String, in text: String, at location: Int) -> Int {
        guard !original.isEmpty else { return 0 }
        let source = text as NSString
        let target = original as NSString
        var searchStart = 0
        var occurrence = 0
        while searchStart <= source.length {
            let searchRange = NSRange(location: searchStart, length: source.length - searchStart)
            let found = source.range(of: target as String, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            if found.location >= location { return occurrence }
            occurrence += 1
            searchStart = NSMaxRange(found)
        }
        return occurrence
    }
}
#endif
