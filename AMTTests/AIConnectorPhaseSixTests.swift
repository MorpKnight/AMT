import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseSixTests: XCTestCase {
    func testResolutionKeepsSeparateTermAndBodyAnchorsWithUnicodeAndPunctuation() async throws {
        let text = "\"Data Pribadi\" adalah informasi lama tentang orang 😀."
        let entry = makeEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah informasi tentang orang perseorangan yang teridentifikasi."
        )
        let assessment = makeAssessment(
            text: text,
            term: "Data Pribadi",
            candidate: makeCandidate(entry: entry),
            alignment: .mismatch
        )
        let result = try await AIConnectorDefinitionResolutionService(
            dictionaryStore: LegalDictionaryStore(entries: [entry])
        ).resolve(
            assessment: assessment,
            documentText: text,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        )

        let resolution = result.resolution
        XCTAssertTrue(resolution.isAnchored(to: text))
        XCTAssertEqual(
            resolution.termRange.map { (text as NSString).substring(with: $0) },
            "Data Pribadi"
        )
        XCTAssertEqual(
            resolution.bodyRange.map { (text as NSString).substring(with: $0) },
            "informasi lama tentang orang 😀"
        )
        let useDefinition = try XCTUnwrap(
            resolution.options.first { $0.action == .useDefinition }
        )
        XCTAssertTrue(useDefinition.isActionable)
        XCTAssertEqual(useDefinition.original, "informasi lama tentang orang 😀")
        XCTAssertEqual(
            useDefinition.replacement,
            "informasi tentang orang perseorangan yang teridentifikasi."
        )
    }

    func testResolutionRetainsMultipleSourcesAndDoesNotEnableIneligibleSource() async throws {
        let text = "Data Pribadi adalah arti yang tertulis di kontrak."
        let active = makeEntry(
            id: "active",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan.",
            regulation: "UU PDP",
            applicability: .inForce
        )
        let repealed = makeEntry(
            id: "repealed",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data lama.",
            regulation: "Peraturan lama",
            applicability: .notInForce
        )
        let assessment = makeAssessment(
            text: text,
            term: "Data Pribadi",
            candidate: makeCandidate(entry: active, id: "D1"),
            candidates: [
                makeCandidate(entry: active, id: "D1"),
                makeCandidate(entry: repealed, id: "D2")
            ],
            alignment: .mismatch
        )

        let resolution = try await AIConnectorDefinitionResolutionService(
            dictionaryStore: LegalDictionaryStore(entries: [active, repealed])
        ).resolve(
            assessment: assessment,
            documentText: text,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        ).resolution

        XCTAssertEqual(resolution.sourceReferences.count, 2)
        let activeOptions = resolution.options.filter { $0.sourceCandidateID == "D1" }
        let repealedOptions = resolution.options.filter { $0.sourceCandidateID == "D2" }
        XCTAssertTrue(activeOptions.contains { $0.action == .useDefinition && $0.isActionable })
        XCTAssertTrue(repealedOptions.contains { $0.action == .useDefinition && !$0.isActionable })
        XCTAssertTrue(repealedOptions.contains { $0.statusMessage?.contains("tidak berlaku") == true })
    }

    func testContractDefinedResolutionIsReadOnly() async throws {
        let text = "Dalam perjanjian ini, Data Pribadi adalah data yang dipilih para pihak."
        let entry = makeEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan."
        )
        let assessment = makeAssessment(
            text: text,
            term: "Data Pribadi",
            candidate: makeCandidate(entry: entry),
            alignment: .mismatch
        )

        let resolution = try await AIConnectorDefinitionResolutionService(
            dictionaryStore: LegalDictionaryStore(entries: [entry])
        ).resolve(
            assessment: assessment,
            documentText: text,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        ).resolution

        XCTAssertTrue(resolution.contractDefined)
        XCTAssertFalse(resolution.options.contains(where: { $0.isActionable }))
    }

    func testAmbiguousTermOccurrenceDoesNotCreateAnEditableResolutionAnchor() async throws {
        let text = "Data Pribadi adalah Data Pribadi yang dipilih para pihak."
        let entry = makeEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan."
        )
        let assessment = makeAssessment(
            text: text,
            term: "Data Pribadi",
            candidate: makeCandidate(entry: entry),
            alignment: .mismatch
        )

        let resolution = try await AIConnectorDefinitionResolutionService(
            dictionaryStore: LegalDictionaryStore(entries: [entry])
        ).resolve(
            assessment: assessment,
            documentText: text,
            mode: .deterministic,
            modelVariant: .qwen35Base4B
        ).resolution

        XCTAssertNil(resolution.termRange)
        XCTAssertNil(resolution.bodyRange)
        XCTAssertFalse(resolution.options.contains(where: { $0.isActionable }))
    }

    /// Opt-in local-model smoke test. It records only decision/status and
    /// timing metadata; document text, source definitions, and model output
    /// are intentionally absent from the report.
    func testPhaseSixLocalModelSmoke() async throws {
        guard phaseSixEnvironmentValue("AMT_RUN_PHASE6_MODEL_SMOKE") == "1"
        else {
            throw XCTSkip("Set AMT_RUN_PHASE6_MODEL_SMOKE=1 to run the local model smoke test.")
        }

        let model = AIConnectorModelVariant.qwen35Base4B
        let qwen = QwenSuggestionService()
        let preparationClock = ContinuousClock()
        let preparationStartedAt = preparationClock.now
        try await qwen.prepareModel(for: model)
        let preparationDuration = AIConnectorObservationTiming.seconds(
            preparationStartedAt.duration(to: preparationClock.now)
        )

        let statutory = makeEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah informasi tentang orang perseorangan yang teridentifikasi."
        )
        let wrongTerm = makeEntry(
            id: "istilah-lama",
            term: "Istilah Lama",
            definition: "Istilah Lama adalah pengertian yang berbeda dan tidak sama."
        )
        let dictionaryStore = LegalDictionaryStore(entries: [wrongTerm, statutory])
        let resolver = AIConnectorDefinitionResolutionService(dictionaryStore: dictionaryStore)
        let reviewer: AIConnectorDefinitionResolutionService.Reviewer = { request in
            try await qwen.reviewDefinitionResolution(
                request: request,
                downloadProgress: { _ in },
                generationProgress: { _ in }
            )
        }

        let reverseText = "Istilah Lama adalah informasi tentang orang perseorangan yang teridentifikasi."
        let reverseAssessment = makeAssessment(
            text: reverseText,
            term: "Istilah Lama",
            candidate: makeCandidate(entry: wrongTerm),
            alignment: .mismatch
        )
        let reverseClock = ContinuousClock()
        let reverseStartedAt = reverseClock.now
        let reverseResult = try await resolver.resolve(
            assessment: reverseAssessment,
            documentText: reverseText,
            mode: .hybrid,
            modelVariant: model,
            includeReverseTermCandidates: true,
            reviewer: reviewer
        )
        let reverseDuration = AIConnectorObservationTiming.seconds(
            reverseStartedAt.duration(to: reverseClock.now)
        )

        let contractText = "Dalam perjanjian ini, Data Pribadi adalah data yang dipilih para pihak."
        let contractAssessment = makeAssessment(
            text: contractText,
            term: "Data Pribadi",
            candidate: makeCandidate(entry: statutory),
            alignment: .mismatch
        )
        let contractResult = try await resolver.resolve(
            assessment: contractAssessment,
            documentText: contractText,
            mode: .hybrid,
            modelVariant: model,
            includeReverseTermCandidates: true,
            reviewer: reviewer
        )

        var directDecision: String?
        let directClock = ContinuousClock()
        let directStartedAt = directClock.now
        do {
            let result = try await qwen.reviewDefinitionResolution(
                request: AIConnectorDefinitionResolutionReviewRequest(
                    candidateID: "contract-override",
                    targetTerm: "Data Pribadi",
                    documentDefinition: "Dalam perjanjian ini istilah tersebut memiliki arti khusus yang ditentukan para pihak.",
                    candidateTerm: statutory.term,
                    candidateDefinition: statutory.definition,
                    modelVariant: model
                ),
                downloadProgress: { _ in },
                generationProgress: { _ in }
            )
            directDecision = result.decision.rawValue
        } catch {
            directDecision = "failed"
        }
        let directDuration = AIConnectorObservationTiming.seconds(
            directStartedAt.duration(to: directClock.now)
        )

        XCTAssertGreaterThan(reverseResult.metrics.modelCallCount, 0)
        XCTAssertLessThanOrEqual(
            reverseResult.metrics.modelCallCount,
            AIConnectorDefinitionResolutionService.maximumCandidates
        )
        XCTAssertTrue(contractResult.resolution.contractDefined)
        XCTAssertEqual(contractResult.metrics.modelCallCount, 0)

        let report = PhaseSixLocalModelSmokeReport(
            generatedAt: Date(),
            modelID: model.modelID,
            revision: model.revision,
            preparationDuration: preparationDuration,
            reverseResolutionDuration: reverseDuration,
            reverseModelCallCount: reverseResult.metrics.modelCallCount,
            reverseFallbackCount: reverseResult.metrics.fallbackCount,
            contractDefinedStatus: contractResult.metrics.status,
            contractModelCallCount: contractResult.metrics.modelCallCount,
            contractOverrideDecision: directDecision,
            contractOverrideDuration: directDuration
        )
        let reportPath = phaseSixEnvironmentValue("AMT_PHASE6_MODEL_SMOKE_REPORT_PATH")
            ?? "/private/tmp/amt-phase6-definition-smoke.json"
        guard reportPath.hasPrefix("/private/tmp/") else {
            throw XCTSkip("Phase 6 smoke report path must be under /private/tmp/.")
        }
        try JSONEncoder.prettySorted.encode(report).write(
            to: URL(fileURLWithPath: reportPath),
            options: .atomic
        )
    }

    private func phaseSixEnvironmentValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment["TEST_RUNNER_\(key)"] ?? environment[key]
    }

    func testDeterministicReverseLookupOnlyActivatesIdenticalNormalizedDefinition() async throws {
        let text = "Istilah Lama adalah informasi tentang orang perseorangan yang teridentifikasi."
        let wrong = makeEntry(
            id: "wrong",
            term: "Istilah Lama",
            definition: "Istilah Lama adalah pengertian yang berbeda dan tidak sama.",
            regulation: "Sumber A"
        )
        let right = makeEntry(
            id: "right",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah informasi tentang orang perseorangan yang teridentifikasi.",
            regulation: "UU PDP"
        )
        let assessment = makeAssessment(
            text: text,
            term: "Istilah Lama",
            candidate: makeCandidate(entry: wrong),
            alignment: .mismatch
        )

        let resolution = try await AIConnectorDefinitionResolutionService(
            dictionaryStore: LegalDictionaryStore(entries: [wrong, right])
        ).resolve(
            assessment: assessment,
            documentText: text,
            mode: .deterministic,
            modelVariant: .qwen35Base4B,
            includeReverseTermCandidates: true
        ).resolution

        let reverse = try XCTUnwrap(
            resolution.options.first { $0.sourceCandidateID?.hasPrefix("R") == true }
        )
        XCTAssertEqual(reverse.action, .replaceTerm)
        XCTAssertEqual(reverse.replacement, "Data Pribadi")
        XCTAssertTrue(reverse.isActionable)
    }

    func testResolutionParserAcceptsOnlyKnownCandidateDecision() throws {
        let parser = AIConnectorDefinitionResolutionParser()
        let payload = AIConnectorToolDecisionPayload(
            name: AIConnectorDefinitionResolutionParser.toolName,
            arguments: [
                "candidate_id": "R1",
                "decision": AIConnectorDefinitionResolutionDecision.termFits.rawValue
            ]
        )
        let result = try parser.parse(
            toolCalls: [payload],
            visibleText: "",
            expectedCandidateID: "R1"
        )
        XCTAssertEqual(result.decision, .termFits)

        XCTAssertThrowsError(try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorDefinitionResolutionParser.toolName,
                arguments: ["candidate_id": "R1", "decision": "MAKE_UP_REPLACEMENT"]
            )],
            visibleText: "",
            expectedCandidateID: "R1"
        ))
    }

    func testSnapshotVersionSevenPersistsResolutionButRejectsChangedAnchor() throws {
        let text = "Data Pribadi adalah informasi lama."
        let termRange = (text as NSString).range(of: "Data Pribadi")
        let bodyRange = (text as NSString).range(of: "informasi lama")
        let option = AIConnectorDefinitionResolutionOption(
            id: "definition-option",
            action: .useDefinition,
            title: "Gunakan definisi dari sumber",
            targetRange: bodyRange,
            original: "informasi lama",
            replacement: "informasi baru",
            status: .actionable
        )
        let resolution = AIConnectorDefinitionResolution(
            id: "resolution-1",
            assessmentID: "definition-1",
            annotationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            primaryRange: NSRange(location: 0, length: text.utf16.count),
            primaryOriginal: text,
            termRange: termRange,
            termOriginal: "Data Pribadi",
            bodyRange: bodyRange,
            bodyOriginal: "informasi lama",
            options: [option],
            sourceReferences: [],
            contractDefined: false,
            sourceFingerprint: DocumentFingerprinting.contentSHA256(text),
            corpusVersion: "phase6-test"
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(text),
            analysisProfile: testProfile(),
            completedAt: Date(timeIntervalSince1970: 0),
            editorSuggestions: [],
            definitionResolutions: [resolution]
        )

        XCTAssertEqual(snapshot.version, DocumentAnalysisSnapshot.currentVersion)
        XCTAssertTrue(snapshot.isCompatible(with: text, profile: testProfile()))
        XCTAssertFalse(snapshot.isCompatible(
            with: text.replacingOccurrences(of: "lama", with: "baru"),
            profile: testProfile()
        ))
        let decoded = try JSONDecoder().decode(
            DocumentAnalysisSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.definitionResolutions, [resolution])
    }

    private func makeEntry(
        id: String,
        term: String,
        definition: String,
        regulation: String = "UU PDP",
        applicability: LegalCorpusApplicabilityStatus = .inForce
    ) -> LegalDictionaryEntry {
        LegalDictionaryEntry(
            id: id,
            term: term,
            definition: definition,
            regulation: regulation,
            regulationTitle: "Sumber hukum",
            sourceURL: URL(string: "https://example.invalid/\(id)"),
            referenceID: "ref-\(id)",
            authority: .verified,
            corpusVersion: "phase6-test",
            applicabilityStatus: applicability,
            sourcePassageID: "passage-\(id)",
            articleLocator: "Pasal 1",
            isActionable: true
        )
    }

    private func makeCandidate(
        entry: LegalDictionaryEntry,
        id: String = "D1"
    ) -> AIConnectorDefinitionCandidate {
        AIConnectorDefinitionCandidate(
            id: id,
            match: LegalDictionaryMatch(
                entry: entry,
                score: 1,
                rank: 1,
                matchedDefinitionTokenCount: 6,
                isDirectTermMatch: true,
                retrievalOrigin: .exact
            ),
            statementText: entry.definition,
            detection: .explicitPattern
        )
    }

    private func makeAssessment(
        text: String,
        term: String,
        candidate: AIConnectorDefinitionCandidate,
        candidates: [AIConnectorDefinitionCandidate]? = nil,
        alignment: AIConnectorDefinitionAlignment
    ) -> AIConnectorDefinitionAssessment {
        let segment = AIReviewSegment(
            id: 1,
            sourceLocation: 0,
            sourceLength: text.utf16.count,
            targetText: text,
            previousContext: nil,
            nextContext: nil
        )
        return AIConnectorDefinitionAssessment(
            segment: segment,
            term: term,
            statementText: text,
            candidate: candidate,
            candidateCount: candidates?.count ?? 1,
            detection: .explicitPattern,
            classification: .explicitDefinition,
            alignment: alignment,
            reason: "Definisi dibandingkan dengan evidence corpus.",
            origin: .qwen,
            modelReviewed: true,
            retrievalOrigin: .exact,
            semanticScore: 1,
            requiresHumanReview: true,
            candidates: candidates ?? [candidate]
        )
    }

    private func testProfile() -> AIConnectorAnalysisProfile {
        AIConnectorAnalysisProfile(
            pipelineVersion: "phase6-test",
            reviewMode: .deterministic,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            generationProfilePreset: .greedy,
            corpusVersion: "phase6-test",
            semanticModelRevision: "none",
            semanticEmbeddingSchema: "none",
            semanticRetrievalProfile: "none"
        )
    }
}

private struct PhaseSixLocalModelSmokeReport: Codable {
    let generatedAt: Date
    let modelID: String
    let revision: String
    let preparationDuration: TimeInterval
    let reverseResolutionDuration: TimeInterval
    let reverseModelCallCount: Int
    let reverseFallbackCount: Int
    let contractDefinedStatus: String
    let contractModelCallCount: Int
    let contractOverrideDecision: String?
    let contractOverrideDuration: TimeInterval
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
