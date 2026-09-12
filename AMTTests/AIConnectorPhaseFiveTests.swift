import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseFiveTests: XCTestCase {
    func testDefinedTermFindingsKeepUTF16AnchorsAndRelatedEvidence() async throws {
        let text = "BAB I\n\"Data Pribadi\" adalah informasi tentang orang.\nKetentuan 😀: data pribadi digunakan.\n\"Data Pribadi\" adalah informasi identitas."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )

        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        )

        let source = text as NSString
        XCTAssertTrue(result.findings.contains { $0.ruleID == "defined-term-conflicting-definition" })
        XCTAssertTrue(result.findings.contains { $0.ruleID == "defined-term-case-inconsistency" })
        XCTAssertTrue(result.findings.allSatisfy {
            $0.isAnchored(to: text)
                && source.substring(with: $0.sourceRange) == $0.original
        })

        let conflict = try XCTUnwrap(
            result.findings.first { $0.ruleID == "defined-term-conflicting-definition" }
        )
        XCTAssertEqual(conflict.relatedEvidence.count, 1)
        XCTAssertTrue(conflict.relatedEvidence.allSatisfy { $0.isAnchored(to: text) })
        XCTAssertGreaterThan(result.findings.first?.sourceRange.location ?? 0, 0)
    }

    func testValidAliasIsProtectedAndDoesNotBecomeUndefinedTerm() async {
        let text = "\"Data Pribadi\" adalah informasi tentang orang. Dalam dokumen ini, \"DP\" berarti Data Pribadi dan DP wajib dijaga."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )

        XCTAssertTrue(profile.definedTerms.contains { $0.value == "DP" })
        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        )

        XCTAssertFalse(result.findings.contains {
            $0.ruleID == "defined-term-undeclared-quoted-term"
                && $0.original.contains("DP")
        })
    }

    func testInternalReferenceSeparatesMissingInternalReferenceFromExternalReference() async {
        let text = "Pasal 1 Ketentuan Umum\nPihak Pertama wajib menjaga data.\nPasal 2 Rujukan\nPihak Kedua mengacu pada Pasal 99.\nPihak Kedua tunduk pada Pasal 4 UU No. 27 Tahun 2022."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )

        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        )

        XCTAssertTrue(result.findings.contains { finding in
            finding.ruleID == "internal-reference-missing"
                && finding.original == "Pasal 99"
        })
        XCTAssertFalse(result.findings.contains { finding in
            finding.ruleID.hasPrefix("internal-reference-")
                && finding.original == "Pasal 4"
        })
    }

    func testIsolatedModalWordsDoNotCreateRiskFinding() async {
        let text = "Pihak Pertama wajib menjaga dokumen. Pihak Kedua dapat menerima dokumen."
        let result = await analyze(text: text, mode: .deterministic)

        XCTAssertFalse(result.findings.contains { $0.kind == .legalRisk })
    }

    func testUnilateralTerminationRiskRequiresNoNoticeCombination() async {
        let text = "Pihak Pertama dapat mengakhiri Perjanjian.\n"
            + "Pihak Kedua bertindak tanpa pemberitahuan sebelumnya."
        let result = await analyze(text: text, mode: .deterministic)

        XCTAssertFalse(result.findings.contains {
            $0.ruleID == "legal-risk-unilateral-termination-no-notice"
        })
    }

    func testRiskFindingsRequireConcreteConflictAndRetainEvidence() async {
        let text = "Pihak Pertama wajib menyerahkan laporan.\nPihak Pertama tidak wajib menyerahkan laporan.\nPihak Kedua dapat mengakhiri Perjanjian tanpa pemberitahuan.\nPihak Kedua wajib menyerahkan laporan jika"
        let result = await analyze(text: text, mode: .deterministic)

        XCTAssertTrue(result.findings.contains { $0.ruleID == "legal-risk-modal-negation-conflict" })
        XCTAssertTrue(result.findings.contains { $0.ruleID == "legal-risk-unilateral-termination-no-notice" })
        XCTAssertTrue(result.findings.contains { $0.ruleID == "legal-risk-dangling-condition" })
        XCTAssertTrue(result.findings.filter { $0.kind == .legalRisk }.allSatisfy { finding in
            guard finding.isAnchored(to: text) else { return false }
            return finding.ruleID != "legal-risk-modal-negation-conflict"
                || !finding.relatedEvidence.isEmpty
        })
    }

    func testRiskReviewerIsBoundedToEightCandidatesAndInvalidResponseFallsBack() async {
        var clauses: [String] = []
        for index in 0..<10 {
            clauses.append("Pihak Pertama wajib menyerahkan laporan " + String(index) + ".")
            clauses.append("Pihak Pertama tidak wajib menyerahkan laporan " + String(index) + ".")
        }
        let text = clauses.joined(separator: "\n")
        let calls = CallBox()
        let reviewer: AIConnectorDocumentReviewDetector.RiskReviewer = { request in
            calls.count += 1
            if calls.count == 1 {
                return AIConnectorRiskReviewResult(
                    candidateID: "wrong-candidate",
                    decision: .flag,
                    metrics: Self.testMetrics()
                )
            }
            return AIConnectorRiskReviewResult(
                candidateID: request.candidateID,
                decision: .flag,
                metrics: Self.testMetrics()
            )
        }

        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            riskReviewer: reviewer
        )

        XCTAssertLessThanOrEqual(calls.count, AIConnectorDocumentReviewDetector.maximumModelCandidates)
        XCTAssertLessThanOrEqual(result.metrics.riskModelCallCount, 8)
        XCTAssertGreaterThan(result.metrics.riskFallbackCount, 0)
        XCTAssertTrue(result.findings.contains { $0.origin == .deterministicFallback })
    }

    /// Opt-in only: loads the pinned local Qwen model and exercises the Phase
    /// 5 risk-review boundary. The report intentionally contains counts and
    /// timings only; it never serializes fixture text, evidence, or model
    /// output.
    func testPhaseFiveLocalModelSmoke() async throws {
        guard environmentValue("AMT_RUN_PHASE5_MODEL_SMOKE") == "1" else {
            throw XCTSkip("Set TEST_RUNNER_AMT_RUN_PHASE5_MODEL_SMOKE=1 to run the local model smoke test.")
        }

        let model = AIConnectorModelVariant.qwen35Base4B
        let service = QwenSuggestionService()
        let preparationClock = ContinuousClock()
        let preparationStartedAt = preparationClock.now
        try await service.prepareModel(for: model)
        let preparationDuration = AIConnectorObservationTiming.seconds(
            preparationStartedAt.duration(to: preparationClock.now)
        )

        let text = "Pihak Pertama wajib menyerahkan laporan.\n"
            + "Pihak Pertama tidak wajib menyerahkan laporan.\n"
            + "Pihak Kedua dapat mengakhiri Perjanjian tanpa pemberitahuan."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        let analysisClock = ContinuousClock()
        let analysisStartedAt = analysisClock.now
        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .hybrid,
            modelVariant: model,
            riskReviewer: { request in
                try await service.reviewDocumentFinding(
                    request: request,
                    downloadProgress: { _ in },
                    generationProgress: { _ in }
                )
            }
        )
        let analysisDuration = AIConnectorObservationTiming.seconds(
            analysisStartedAt.duration(to: analysisClock.now)
        )

        XCTAssertGreaterThan(result.metrics.riskCandidateCount, 0)
        XCTAssertGreaterThan(result.metrics.riskModelCallCount, 0)
        XCTAssertLessThanOrEqual(
            result.metrics.riskModelCallCount,
            AIConnectorDocumentReviewDetector.maximumModelCandidates
        )
        XCTAssertFalse(result.metrics.wasCancelled)

        let report = AIConnectorPhaseFiveModelSmokeReport(
            generatedAt: Date(),
            modelID: model.modelID,
            revision: model.revision,
            preparationDuration: preparationDuration,
            analysisDuration: analysisDuration,
            riskReviewDuration: result.metrics.riskReviewDuration,
            findingCount: result.metrics.findingCount,
            definedTermFindingCount: result.metrics.definedTermFindingCount,
            legalRiskFindingCount: result.metrics.legalRiskFindingCount,
            internalReferenceFindingCount: result.metrics.internalReferenceFindingCount,
            riskCandidateCount: result.metrics.riskCandidateCount,
            riskModelCallCount: result.metrics.riskModelCallCount,
            riskFallbackCount: result.metrics.riskFallbackCount,
            qwenFindingCount: result.findings.filter { $0.origin == .qwen }.count,
            deterministicFallbackFindingCount: result.findings.filter {
                $0.origin == .deterministicFallback
            }.count,
            wasCancelled: result.metrics.wasCancelled
        )
        let reportPath = environmentValue("AMT_PHASE5_MODEL_SMOKE_REPORT_PATH")
            ?? "/private/tmp/amt-phase5-risk-smoke.json"
        guard reportPath.hasPrefix("/private/tmp/") else {
            throw XCTSkip("AMT_PHASE5_MODEL_SMOKE_REPORT_PATH must be under /private/tmp/.")
        }
        let data = try JSONEncoder.prettySorted.encode(report)
        try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
    }

    func testCancellationPreservesCompletedLocalFindings() async {
        let text = "Pihak Pertama wajib menyerahkan laporan.\nPihak Pertama tidak wajib menyerahkan laporan.\nPihak Kedua wajib menerima laporan.\nPihak Kedua tidak wajib menerima laporan.\nPihak Kedua dapat mengakhiri Perjanjian tanpa pemberitahuan."
        let calls = CallBox()
        let reviewer: AIConnectorDocumentReviewDetector.RiskReviewer = { request in
            calls.count += 1
            if calls.count == 2 {
                throw CancellationError()
            }
            return AIConnectorRiskReviewResult(
                candidateID: request.candidateID,
                decision: .flag,
                metrics: Self.testMetrics()
            )
        }
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )

        let result = await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            riskReviewer: reviewer
        )

        XCTAssertTrue(result.metrics.wasCancelled)
        XCTAssertFalse(result.findings.isEmpty)
    }

    func testRiskParserAcceptsOnlyExpectedDecisionAndCandidate() throws {
        let parser = AIConnectorRiskReviewParser()
        let valid = try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorRiskReviewParser.toolName,
                arguments: ["candidate_id": "c1", "decision": "FLAG"]
            )],
            visibleText: "",
            expectedCandidateID: "c1"
        )
        XCTAssertEqual(valid.decision, .flag)

        XCTAssertThrowsError(try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorRiskReviewParser.toolName,
                arguments: ["candidate_id": "c2", "decision": "FLAG"]
            )],
            visibleText: "",
            expectedCandidateID: "c1"
        ))
        XCTAssertThrowsError(try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorRiskReviewParser.toolName,
                arguments: ["candidate_id": "c1", "decision": "MAYBE"]
            )],
            visibleText: "",
            expectedCandidateID: "c1"
        ))
    }

    func testFindingMappingIsReadOnlyAndKeepsRelatedEvidence() {
        let text = "Pihak Pertama wajib menyerahkan laporan."
        let finding = AIConnectorDocumentFinding(
            id: UUID(),
            ruleID: "legal-risk-modal-negation-conflict",
            kind: .legalRisk,
            sourceRange: NSRange(location: 0, length: 12),
            original: (text as NSString).substring(with: NSRange(location: 0, length: 12)),
            title: "Potensi konflik",
            reason: "Perlu diperiksa.",
            origin: .deterministic,
            relatedEvidence: [AIConnectorFindingEvidence(
                id: "evidence",
                sourceRange: NSRange(location: 0, length: 12),
                original: (text as NSString).substring(with: NSRange(location: 0, length: 12)),
                label: "Klausul terkait"
            )]
        )

        let annotations = EditorSuggestionMapper.makeFindingAnnotations(
            findings: [finding],
            documentText: text
        )
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].kind, .legalRisk)
        XCTAssertTrue(annotations[0].isReadOnlyDiagnostic)
        XCTAssertTrue(annotations[0].relatedEvidence.count == 1)
        XCTAssertTrue(annotations[0].isAnchored(to: text))
    }

    func testSnapshotV5IsDecodedButIncompatibleWithPhase6() {
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256("Dokumen"),
            analysisProfile: AIConnectorAnalysisProfile(
                pipelineVersion: "phase4",
                reviewMode: .deterministic,
                modelVariant: .qwen35Base4B,
                thinkingEnabled: false,
                generationProfilePreset: .greedy,
                corpusVersion: "test-corpus",
                semanticModelRevision: "test-semantic",
                semanticEmbeddingSchema: "test-schema",
                semanticRetrievalProfile: "test-profile"
            ),
            completedAt: Date(),
            editorSuggestions: [],
            version: 5
        )

        XCTAssertFalse(snapshot.isCompatible(
            with: "Dokumen",
            profile: snapshot.analysisProfile
        ))
    }

    func testReviewedFindingIsHiddenByDefaultAndCanBeReopened() {
        let text = "Pihak Pertama wajib menyerahkan laporan."
        let finding = AIConnectorDocumentFinding(
            id: UUID(),
            ruleID: "legal-risk-unilateral-termination-no-notice",
            kind: .legalRisk,
            sourceRange: NSRange(location: 0, length: text.utf16.count),
            original: text,
            title: "Potensi risiko",
            reason: "Perlu diperiksa.",
            origin: .deterministic
        )
        let annotation = EditorSuggestionMapper.makeFindingAnnotations(
            findings: [finding],
            documentText: text
        )[0]
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(text),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(),
            editorSuggestions: [],
            reviewAnnotations: [annotation],
            documentFindings: [finding]
        )

        XCTAssertTrue(viewModel.restoreAnalysisSnapshot(snapshot, documentText: text))
        XCTAssertEqual(viewModel.reviewItems.count, 1)
        viewModel.markReviewItemReviewed(finding.id)
        XCTAssertTrue(viewModel.reviewItems.isEmpty)
        XCTAssertEqual(viewModel.reviewedDocumentFindingCount, 1)

        viewModel.setShowReviewedFindings(true)
        XCTAssertEqual(viewModel.reviewItems.map(\.id), [finding.id])
        viewModel.reopenReviewItem(finding.id)
        XCTAssertEqual(viewModel.reviewItems.map(\.id), [finding.id])
        XCTAssertFalse(viewModel.reviewedReviewItemIDs.contains(finding.id))
    }

    func testAcceptShiftsNonOverlappingFindingAndEvidence() {
        let text = "wajib untuk. Pihak Pertama wajib menyerahkan laporan. Pihak Pertama tidak wajib menyerahkan laporan."
        let suggestionRange = (text as NSString).range(of: "wajib untuk")
        let findingRange = (text as NSString).range(of: "tidak wajib menyerahkan laporan")
        let evidenceRange = (text as NSString).range(of: "wajib menyerahkan laporan")
        let finding = AIConnectorDocumentFinding(
            id: UUID(),
            ruleID: "legal-risk-modal-negation-conflict",
            kind: .legalRisk,
            sourceRange: findingRange,
            original: (text as NSString).substring(with: findingRange),
            title: "Potensi konflik",
            reason: "Perlu diperiksa.",
            origin: .deterministic,
            relatedEvidence: [AIConnectorFindingEvidence(
                id: "evidence",
                sourceRange: evidenceRange,
                original: (text as NSString).substring(with: evidenceRange),
                label: "Klausul terkait"
            )]
        )
        let suggestion = EditorSuggestion(
            id: UUID(),
            sourceRange: suggestionRange,
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            reason: "Perbaikan lokal.",
            origin: .deterministic
        )
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        let annotation = EditorSuggestionMapper.makeFindingAnnotations(
            findings: [finding],
            documentText: text
        )[0]
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(text),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(),
            editorSuggestions: [suggestion],
            reviewAnnotations: [annotation],
            documentFindings: [finding]
        )
        XCTAssertTrue(viewModel.restoreAnalysisSnapshot(snapshot, documentText: text))

        let updated = text.replacingOccurrences(of: "wajib untuk", with: "wajib", options: [], range: text.range(of: "wajib untuk"))
        XCTAssertTrue(viewModel.reconcileAfterAccept(
            suggestion,
            previousText: text,
            updatedText: updated
        ))
        XCTAssertEqual(viewModel.documentFindings.count, 1)
        let shifted = viewModel.documentFindings[0]
        XCTAssertTrue(shifted.isAnchored(to: updated))
        XCTAssertEqual(shifted.sourceRange.location, findingRange.location - 6)
        XCTAssertTrue(viewModel.reviewAnnotations[0].isAnchored(to: updated))
    }

    private func analyze(
        text: String,
        mode: AIConnectorReviewMode
    ) async -> AIConnectorDocumentReviewResult {
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        return await AIConnectorDocumentReviewDetector().analyze(
            documentText: text,
            structure: structure,
            profile: profile,
            mode: mode,
            modelVariant: .qwen35Base4B
        )
    }

    private static func testMetrics() -> AIConnectorGenerationMetrics {
        AIConnectorGenerationMetrics(
            promptTokenCount: 1,
            generationTokenCount: 1,
            promptDuration: 0,
            generationDuration: 0,
            stopReason: .stop
        )
    }

    private final class CallBox: @unchecked Sendable {
        var count = 0
    }

    private func environmentValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }
}

private struct AIConnectorPhaseFiveModelSmokeReport: Codable {
    let generatedAt: Date
    let modelID: String
    let revision: String
    let preparationDuration: TimeInterval
    let analysisDuration: TimeInterval
    let riskReviewDuration: TimeInterval
    let findingCount: Int
    let definedTermFindingCount: Int
    let legalRiskFindingCount: Int
    let internalReferenceFindingCount: Int
    let riskCandidateCount: Int
    let riskModelCallCount: Int
    let riskFallbackCount: Int
    let qwenFindingCount: Int
    let deterministicFallbackFindingCount: Int
    let wasCancelled: Bool
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
