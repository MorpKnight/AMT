import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorDefinitionAnalysisTests: XCTestCase {
    func testDetectorFindsExplicitDefinitionAndOnlyUsesVerifiedEvidence() {
        let entry = makeEntry(
            id: "data-pribadi-definition",
            term: "Data Pribadi",
            definition: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        )
        let detector = AIConnectorDefinitionDetector(
            dictionaryStore: LegalDictionaryStore(entries: [entry])
        )
        let segment = makeSegment(
            id: 7,
            location: 120,
            target: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi."
        )

        let result = detector.detect(segment: segment, glossaryMatches: [])

        XCTAssertEqual(result.detection, .explicitPattern)
        XCTAssertEqual(result.term, "Data Pribadi")
        XCTAssertEqual(
            result.statementText,
            "data tentang orang perseorangan yang teridentifikasi."
        )
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.match.entry.id, entry.id)
        XCTAssertEqual(result.candidates.first?.match.retrievalOrigin, .exact)

        let legacy = makeEntry(
            id: "legacy-data-pribadi",
            term: "Data Pribadi",
            definition: entry.definition,
            authority: .legacy,
            corpusVersion: LegalDictionaryCorpusVersion.legacyKamusV1
        )
        let legacyResult = AIConnectorDefinitionDetector(
            dictionaryStore: LegalDictionaryStore(entries: [legacy])
        ).detect(segment: segment, glossaryMatches: [])
        XCTAssertTrue(legacyResult.candidates.isEmpty)
        XCTAssertEqual(legacyResult.detection, .explicitPattern)
    }

    func testAnalyzerUsesMockedQwenForImplicitParaphrase() async throws {
        let entry = makeEntry(
            id: "data-pribadi-definition",
            term: "Data Pribadi",
            definition: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 0.91,
            rank: 1,
            matchedDefinitionTokenCount: 5,
            isDirectTermMatch: false,
            semanticScore: 0.86,
            fusionScore: 0.08,
            retrievalOrigin: .hybrid
        )
        let calls = DefinitionCallBox()
        let handler: AIConnectorDefinitionReviewHandler = {
            @MainActor request, _, _ in
            calls.requests.append(request)
            return QwenDefinitionReviewResult(
                candidateID: request.candidate.id,
                classification: .implicitDefinition,
                alignment: .matches,
                metrics: Self.testMetrics(),
                containsReasoningMarkers: false
            )
        }
        let analyzer = AIConnectorDefinitionAnalyzer(
            dictionaryStore: LegalDictionaryStore(entries: [entry]),
            reviewHandler: handler
        )

        let assessment = try await analyzer.analyze(
            segment: makeSegment(
                target: "Informasi mengenai individu yang dapat dikenali secara langsung maupun tidak langsung."
            ),
            glossaryMatches: [match],
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            forceDeterministic: false,
            generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(
                for: .qwen35_2b,
                thinkingEnabled: false
            ),
            downloadProgress: { _ in },
            generationProgress: { _ in },
            semanticProgress: { _ in },
            progressStage: { _ in }
        )

        let result = try XCTUnwrap(assessment.assessment)
        XCTAssertEqual(calls.requests.count, 1)
        XCTAssertEqual(result.detection, .retrievedCandidate)
        XCTAssertEqual(result.classification, .implicitDefinition)
        XCTAssertEqual(result.alignment, .matches)
        XCTAssertTrue(result.modelReviewed)
        XCTAssertEqual(result.semanticScore, 0.86)
        XCTAssertTrue(result.requiresHumanReview)
        XCTAssertEqual(result.candidate?.sourceDefinition, entry.definition)
    }

    func testAnalyzerLetsQwenRejectTermMentionThatIsNotADefinition() async throws {
        let entry = makeEntry(
            id: "data-pribadi-definition",
            term: "Data Pribadi",
            definition: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 42,
            rank: 1,
            matchedDefinitionTokenCount: 4,
            isDirectTermMatch: true,
            semanticScore: 0.75,
            fusionScore: 0.07,
            retrievalOrigin: .hybrid
        )
        let calls = DefinitionCallBox()
        let handler: AIConnectorDefinitionReviewHandler = {
            @MainActor request, _, _ in
            calls.requests.append(request)
            return QwenDefinitionReviewResult(
                candidateID: request.candidate.id,
                classification: .notDefinition,
                alignment: .notApplicable,
                metrics: Self.testMetrics(),
                containsReasoningMarkers: false
            )
        }
        let analyzer = AIConnectorDefinitionAnalyzer(
            dictionaryStore: LegalDictionaryStore(entries: [entry]),
            reviewHandler: handler
        )

        let result = try await analyzer.analyze(
            segment: makeSegment(
                target: "Pengendali Data Pribadi wajib menerapkan langkah keamanan yang wajar."
            ),
            glossaryMatches: [match],
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(
                for: .qwen35Base4B,
                thinkingEnabled: false
            ),
            downloadProgress: { _ in },
            generationProgress: { _ in },
            semanticProgress: { _ in },
            progressStage: { _ in }
        )

        let assessment = try XCTUnwrap(result.assessment)
        XCTAssertEqual(calls.requests.count, 1)
        XCTAssertEqual(assessment.classification, .notDefinition)
        XCTAssertEqual(assessment.alignment, .notApplicable)
        XCTAssertTrue(assessment.isFinding)
    }

    func testAnalyzerReportsQwenMismatchForDefinition() async throws {
        let entry = makeEntry(
            id: "data-pribadi-definition",
            term: "Data Pribadi",
            definition: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        )
        let calls = DefinitionCallBox()
        let handler: AIConnectorDefinitionReviewHandler = {
            @MainActor request, _, _ in
            calls.requests.append(request)
            return QwenDefinitionReviewResult(
                candidateID: request.candidate.id,
                classification: .explicitDefinition,
                alignment: .mismatch,
                metrics: Self.testMetrics(),
                containsReasoningMarkers: false
            )
        }
        let analyzer = AIConnectorDefinitionAnalyzer(
            dictionaryStore: LegalDictionaryStore(entries: [entry]),
            reviewHandler: handler
        )

        let result = try await analyzer.analyze(
            segment: makeSegment(
                target: "Data Pribadi adalah informasi mengenai perusahaan dan asetnya."
            ),
            glossaryMatches: [],
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(
                for: .qwen35Base4B,
                thinkingEnabled: false
            ),
            downloadProgress: { _ in },
            generationProgress: { _ in },
            semanticProgress: { _ in },
            progressStage: { _ in }
        )

        let assessment = try XCTUnwrap(result.assessment)
        XCTAssertEqual(calls.requests.count, 1)
        XCTAssertEqual(assessment.classification, .explicitDefinition)
        XCTAssertEqual(assessment.alignment, .mismatch)
        XCTAssertTrue(assessment.modelReviewed)
        XCTAssertTrue(assessment.requiresHumanReview)
    }

    func testDeterministicProcessorPublishesAssessmentWithoutModelCall() async throws {
        let entry = makeEntry(
            id: "advokat-definition",
            term: "Advokat",
            definition: "orang yang berprofesi memberi jasa hukum, baik di dalam maupun di luar pengadilan"
        )
        let processor = AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [entry]),
            ruleStore: AIConnectorRuleStore(version: "definition-test", rules: [])
        )

        let result = try await processor.process(
            segment: makeSegment(
                id: 3,
                location: 45,
                target: "Advokat adalah orang yang berprofesi memberi jasa hukum, baik di dalam maupun di luar pengadilan."
            ),
            documentProtectionContext: .empty,
            mode: .deterministic,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        let assessment = try XCTUnwrap(result.definitionAssessment)
        XCTAssertEqual(result.definitionModelCallCount, 0)
        XCTAssertEqual(assessment.segment.id, 3)
        XCTAssertEqual(assessment.segment.sourceLocation, 45)
        XCTAssertEqual(assessment.classification, .explicitDefinition)
        XCTAssertEqual(assessment.alignment, .matches)
        XCTAssertEqual(assessment.candidate?.match.entry.term, "Advokat")
    }

    func testDefinitionToolParserRejectsIncompatibleDecisionPair() throws {
        let parser = AIConnectorDefinitionReviewParser()
        let payload = AIConnectorToolDecisionPayload(
            name: AIConnectorDefinitionReviewParser.toolName,
            arguments: [
                "candidate_id": "D1",
                "classification": AIConnectorDefinitionClassification.notDefinition.rawValue,
                "alignment": AIConnectorDefinitionAlignment.matches.rawValue
            ]
        )

        XCTAssertThrowsError(
            try parser.parse(
                toolCalls: [payload],
                visibleText: "",
                expectedCandidateID: "D1"
            )
        ) { error in
            XCTAssertEqual(
                error as? AIConnectorDefinitionReviewParserError,
                .invalidDecision
            )
        }
    }

    func testDefinitionToolSchemaContainsOnlyApplicationDecisionFields() {
        let tool = QwenSuggestionService.definitionToolSpecification
        let function = tool["function"] as? [String: any Sendable]
        let parameters = function?["parameters"] as? [String: any Sendable]
        let required = parameters?["required"] as? [String]
        let properties = parameters?["properties"] as? [String: any Sendable]
        let additionalProperties = parameters?["additionalProperties"] as? Bool
        let propertyKeys: Set<String> = properties.map { Set($0.keys) } ?? []

        XCTAssertEqual(function?["name"] as? String, "submit_definition_review")
        XCTAssertEqual(
            required,
            ["candidate_id", "classification", "alignment"]
        )
        XCTAssertEqual(
            propertyKeys,
            ["candidate_id", "classification", "alignment"]
        )
        XCTAssertEqual(additionalProperties, false)
    }

    private func makeSegment(
        id: Int = 1,
        location: Int = 0,
        target: String
    ) -> AIReviewSegment {
        AIReviewSegment(
            id: id,
            sourceLocation: location,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }

    private func makeEntry(
        id: String,
        term: String,
        definition: String,
        authority: LegalDictionaryEntryAuthority = .verified,
        corpusVersion: String = "definition-test-v1"
    ) -> LegalDictionaryEntry {
        LegalDictionaryEntry(
            id: id,
            term: term,
            definition: definition,
            regulation: "Regulasi uji",
            regulationTitle: "Regulasi Uji",
            sourceURL: URL(string: "https://example.invalid/source/\(id)"),
            officialDocumentURL: URL(string: "https://example.invalid/document/\(id)"),
            referenceID: "reference-\(id)",
            authority: authority,
            corpusVersion: corpusVersion,
            applicabilityStatus: .inForce,
            sourcePassageID: "passage-\(id)",
            isActionable: authority == .verified
        )
    }

    private static func testMetrics() -> AIConnectorGenerationMetrics {
        AIConnectorGenerationMetrics(
            promptTokenCount: 12,
            generationTokenCount: 3,
            promptDuration: 0.01,
            generationDuration: 0.01,
            stopReason: .stop
        )
    }
}

@MainActor
private final class DefinitionCallBox {
    var requests: [AIConnectorDefinitionReviewRequest] = []
}
