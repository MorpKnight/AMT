import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorP011CandidateFirstTests: XCTestCase {
    func testCandidateBuilderUsesStableIDsAndCapsAtThree() {
        let rules = [
            makeRule(
                id: "spelling-ditanda-tangani",
                category: .spelling,
                value: "ditanda tangani",
                replacement: "ditandatangani",
                priority: 10
            ),
            makeRule(
                id: "grammar-wajib-untuk",
                category: .grammar,
                value: "wajib untuk",
                replacement: "wajib",
                priority: 20
            ),
            makeRule(
                id: "spelling-di-simpan",
                category: .spelling,
                value: "di simpan",
                replacement: "disimpan",
                priority: 30
            ),
            makeRule(
                id: "spelling-di-buat",
                category: .spelling,
                value: "di buat",
                replacement: "dibuat",
                priority: 40
            )
        ]
        let builder = AIConnectorCandidateBuilder(
            ruleStore: AIConnectorRuleStore(version: "test-rules", rules: rules)
        )
        let segment = makeSegment(
            target: "Perjanjian ditanda tangani. Pihak Kedua wajib untuk menyerahkan laporan. Dokumen di simpan dan di buat oleh Pihak Kedua."
        )

        let candidates = builder.build(for: segment, glossaryMatches: [])

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.map(\.id), ["C1", "C2", "C3"])
        XCTAssertEqual(
            candidates.compactMap(\.ruleID),
            ["spelling-ditanda-tangani", "grammar-wajib-untuk", "spelling-di-simpan"]
        )
        XCTAssertTrue(candidates.allSatisfy { $0.confidenceTier == .deterministicRule })
    }

    func testLegacyGlossaryIsNotActionableButVerifiedGlossaryIs() {
        let target = "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya."
        let segment = makeSegment(target: target)
        let legacyEntry = makeDictionaryEntry(authority: .legacy)
        let verifiedEntry = makeDictionaryEntry(authority: .verified)
        let legacyMatch = makeDictionaryMatch(entry: legacyEntry)
        let verifiedMatch = makeDictionaryMatch(entry: verifiedEntry)

        let builder = AIConnectorCandidateBuilder(
            ruleStore: AIConnectorRuleStore(version: "empty", rules: [])
        )

        XCTAssertTrue(builder.build(for: segment, glossaryMatches: [legacyMatch]).isEmpty)

        let verifiedCandidates = builder.build(
            for: segment,
            glossaryMatches: [verifiedMatch]
        )
        XCTAssertEqual(verifiedCandidates.count, 1)
        XCTAssertEqual(verifiedCandidates.first?.replacement, "Data Pribadi")
        XCTAssertEqual(verifiedCandidates.first?.confidenceTier, .verifiedGlossary)
        XCTAssertEqual(verifiedCandidates.first?.glossaryMatch?.entry.id, verifiedEntry.id)
    }

    func testCandidateDecisionParserAcceptsThreeDecisionsAndRejectsMalformedCalls() throws {
        let parser = AIConnectorCandidateDecisionParser()
        let candidateID = "C1"

        for decision in [
            AIConnectorCandidateDecision.accept,
            .reject,
            .needsReview
        ] {
            let parsed = try parser.parse(
                toolCalls: [payload(decision: decision.rawValue)],
                visibleText: " \n",
                expectedCandidateID: candidateID
            )
            XCTAssertEqual(parsed.candidateID, candidateID)
            XCTAssertEqual(parsed.decision, decision)
        }

        assertParserError(.missingToolCall) {
            try parser.parse(toolCalls: [], visibleText: "", expectedCandidateID: candidateID)
        }
        assertParserError(.multipleToolCalls) {
            try parser.parse(
                toolCalls: [
                    payload(decision: AIConnectorCandidateDecision.accept.rawValue),
                    payload(decision: AIConnectorCandidateDecision.reject.rawValue)
                ],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.unknownTool) {
            try parser.parse(
                toolCalls: [
                    AIConnectorToolDecisionPayload(
                        name: "other_tool",
                        arguments: [
                            "candidate_id": candidateID,
                            "decision": AIConnectorCandidateDecision.accept.rawValue
                        ]
                    )
                ],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.malformedArguments) {
            try parser.parse(
                toolCalls: [
                    AIConnectorToolDecisionPayload(
                        name: AIConnectorCandidateDecisionParser.toolName,
                        arguments: ["candidate_id": candidateID]
                    )
                ],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.malformedArguments) {
            try parser.parse(
                toolCalls: [
                    AIConnectorToolDecisionPayload(
                        name: AIConnectorCandidateDecisionParser.toolName,
                        arguments: [
                            "candidate_id": candidateID,
                            "decision": "ACCEPT\nREJECT"
                        ]
                    )
                ],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.candidateIDMismatch) {
            try parser.parse(
                toolCalls: [payload(candidateID: "C2", decision: AIConnectorCandidateDecision.accept.rawValue)],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.invalidDecision) {
            try parser.parse(
                toolCalls: [payload(decision: "MAYBE")],
                visibleText: "",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.unexpectedText) {
            try parser.parse(
                toolCalls: [payload(decision: AIConnectorCandidateDecision.accept.rawValue)],
                visibleText: "Saya setuju.",
                expectedCandidateID: candidateID
            )
        }
        assertParserError(.reasoningOrTemplateToken) {
            try parser.parse(
                toolCalls: [payload(decision: AIConnectorCandidateDecision.accept.rawValue)],
                visibleText: "<think>internal</think>",
                expectedCandidateID: candidateID
            )
        }

        XCTAssertTrue(AIConnectorCandidateDecisionParserError.invalidDecision.isRecoverable)
        XCTAssertFalse(AIConnectorCandidateDecisionParserError.reasoningOrTemplateToken.isRecoverable)
        XCTAssertFalse(AIConnectorCandidateDecisionParserError.multipleToolCalls.isRecoverable)
    }

    func testCandidateToolSchemaHasOnlySubmitReviewDecisionFields() {
        let tool = QwenSuggestionService.candidateToolSpecification
        let function = tool["function"] as? [String: any Sendable]
        let parameters = function?["parameters"] as? [String: any Sendable]
        let required = parameters?["required"] as? [String]
        let additionalProperties = parameters?["additionalProperties"] as? Bool

        XCTAssertEqual(function?["name"] as? String, "submit_review")
        XCTAssertEqual(required, ["candidate_id", "decision"])
        XCTAssertEqual(additionalProperties, false)
    }

    func testAcceptedCandidateUsesApplicationOwnedEvidence() async throws {
        let calls = P011CallBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor [calls] request, _, _ in
            calls.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let processor = makeProcessor(candidateDecisionHandler: handler)
        let result = try await processor.process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in },
            generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(
                for: .qwen35Base4B,
                thinkingEnabled: false
            )
        )

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(result.candidates.first?.original, "wajib untuk")
        XCTAssertEqual(result.reviews.first?.original, "wajib untuk")
        XCTAssertEqual(result.reviews.first?.replacement, "wajib")
        XCTAssertEqual(result.reviews.first?.origin, .qwen)
        XCTAssertEqual(result.candidateDecisions.first?.decision, .accept)
        XCTAssertEqual(result.candidateDecisions.first?.candidateID, "C1")
    }

    func testRecoverableCandidateFailureGetsExactlyOneRepair() async throws {
        let calls = P011CallBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor [calls] request, _, _ in
            calls.append(request)
            if calls.count == 1 {
                throw AIConnectorCandidateModelFailure(
                    message: "Malformed tool arguments",
                    classification: .parserRecoverable,
                    recoverable: true,
                    metrics: self.metrics(),
                    reasoningMarkerDetected: false,
                    outputWasTruncated: false
                )
            }
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let processor = makeProcessor(candidateDecisionHandler: handler)
        let result = try await processor.process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls.request(at: 0).retryInstruction)
        XCTAssertTrue(calls.request(at: 1).retryInstruction?.contains("FORMAT REPAIR ONLY") == true)
        XCTAssertTrue(result.repairAttempted)
        XCTAssertEqual(result.modelAttempts, 2)
        XCTAssertEqual(result.reviews.first?.origin, .qwenRepaired)
    }

    func testRejectIsChallengedOnceButDoesNotBecomeFallbackSuggestion() async throws {
        let challengeCalls = P011CallBox()
        let challengeHandler: AIConnectorCandidateDecisionHandler = { @MainActor [challengeCalls] request, _, _ in
            challengeCalls.append(request)
            let decision: AIConnectorCandidateDecision = challengeCalls.count == 1
                ? .reject
                : .accept
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: decision,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let challengedProcessor = makeProcessor(candidateDecisionHandler: challengeHandler)
        let challenged = try await challengedProcessor.process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(challengeCalls.count, 2)
        XCTAssertEqual(challengeCalls.request(at: 1).retryInstruction, "RECHECK ONLY: tinjau kembali kandidat yang sama. Jangan membuat kandidat baru. Kirim tepat satu tool submit_review dengan candidate_id yang sama.")
        XCTAssertTrue(challenged.candidateDecisions.first?.challengeAttempted == true)
        XCTAssertEqual(challenged.reviews.first?.origin, .qwen)

        let rejectCalls = P011CallBox()
        let rejectHandler: AIConnectorCandidateDecisionHandler = { @MainActor [rejectCalls] request, _, _ in
            rejectCalls.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .reject,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let rejectingProcessor = makeProcessor(candidateDecisionHandler: rejectHandler)
        let rejected = try await rejectingProcessor.process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(rejectCalls.count, 2)
        XCTAssertFalse(rejected.usedFallback)
        XCTAssertFalse(rejected.candidateDecisions.first?.usedFallback ?? true)
        XCTAssertEqual(rejected.reviews.first?.status, .suggestion)
        XCTAssertEqual(rejected.reviews.first?.origin, .deterministic)
    }

    func testHybridFallbackIsIsolatedFromModelOnly() async throws {
        let failureHandler: AIConnectorCandidateDecisionHandler = { @MainActor _, _, _ in
            throw AIConnectorCandidateModelFailure(
                message: "Model unavailable",
                classification: .modelFailure,
                recoverable: false,
                metrics: self.metrics(),
                reasoningMarkerDetected: false,
                outputWasTruncated: false
            )
        }
        let hybrid = try await makeProcessor(candidateDecisionHandler: failureHandler).process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )
        let modelOnly = try await makeProcessor(candidateDecisionHandler: failureHandler).process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertTrue(hybrid.usedFallback)
        XCTAssertEqual(hybrid.reviews.first?.origin, .deterministicFallback)
        XCTAssertEqual(hybrid.rejections.first?.classification, .modelFailure)
        XCTAssertFalse(modelOnly.usedFallback)
        XCTAssertTrue(modelOnly.reviews.isEmpty)
        XCTAssertEqual(modelOnly.rejections.first?.classification, .modelFailure)
    }

    func testCacheIncludesCandidateAndGenerationProfile() async throws {
        let calls = P011CallBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor [calls] request, _, _ in
            calls.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let cache = AIConnectorSegmentCache()
        let processor = makeProcessor(
            segmentCache: cache,
            candidateDecisionHandler: handler
        )
        let segment = makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan.")
        let greedy = AIConnectorGenerationProfilePreset.greedy.profile(
            for: .qwen35Base4B,
            thinkingEnabled: false
        )
        let lowVariance = AIConnectorGenerationProfilePreset.lowVariance.profile(
            for: .qwen35Base4B,
            thinkingEnabled: false
        )

        let first = try await process(
            processor,
            segment: segment,
            profile: greedy
        )
        let second = try await process(
            processor,
            segment: segment,
            profile: greedy
        )
        let profileChanged = try await process(
            processor,
            segment: segment,
            profile: lowVariance
        )

        XCTAssertFalse(first.cacheHit)
        XCTAssertTrue(second.cacheHit)
        XCTAssertFalse(profileChanged.cacheHit)
        XCTAssertEqual(calls.count, 2)
    }

    func testCandidateQueueIsSerialAndCircuitBreakerStopsModelCalls() async {
        let activity = P011ActivityBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor request, _, _ in
            activity.begin()
            defer { activity.end() }
            try await Task.sleep(for: .milliseconds(1))
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: self.metrics(),
                containsReasoningMarkers: false
            )
        }
        let processor = makeProcessor(candidateDecisionHandler: handler)
        let queue = AIConnectorWorkQueue(processor: processor)
        let segments = (1...2).map { index in
            makeSegment(
                id: index,
                target: "Pihak Kedua wajib untuk menyerahkan laporan \(index)."
            )
        }
        let stream = await queue.start(
            runID: UUID(),
            segments: segments,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var resultCount = 0
        for await event in stream {
            if case .result = event {
                resultCount += 1
                await queue.acknowledgeResult()
            }
        }

        XCTAssertEqual(resultCount, 2)
        XCTAssertEqual(activity.maxActive, 1)

        let failures = P011CallBox()
        let failureHandler: AIConnectorCandidateDecisionHandler = { @MainActor request, _, _ in
            failures.append(request)
            throw AIConnectorCandidateModelFailure(
                message: "Unavailable",
                classification: .modelFailure,
                recoverable: false,
                metrics: self.metrics(),
                reasoningMarkerDetected: false,
                outputWasTruncated: false
            )
        }
        let failureProcessor = makeProcessor(candidateDecisionHandler: failureHandler)
        let failureQueue = AIConnectorWorkQueue(processor: failureProcessor)
        let failureSegments = (1...5).map { index in
            makeSegment(
                id: index,
                target: "Pihak Kedua wajib untuk menyerahkan laporan \(index)."
            )
        }
        let failureStream = await failureQueue.start(
            runID: UUID(),
            segments: failureSegments,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var summary: AIConnectorRunSummary?
        for await event in failureStream {
            switch event {
            case .result:
                await failureQueue.acknowledgeResult()
            case let .finished(value):
                summary = value
            default:
                break
            }
        }

        XCTAssertEqual(failures.count, 4)
        XCTAssertTrue(summary?.circuitBreakerActivated == true)
        XCTAssertEqual(summary?.processedSegmentCount, 5)
    }

    func testProfilesAndCandidateReportAreCodable() throws {
        let greedy = AIConnectorGenerationProfilePreset.greedy.profile(
            for: .qwen35Base4B,
            thinkingEnabled: false
        )
        XCTAssertEqual(greedy.maxTokens, 128)
        XCTAssertEqual(greedy.temperature, 0)
        XCTAssertEqual(greedy.topP, 1)
        XCTAssertEqual(greedy.topK, 0)
        XCTAssertNil(greedy.presencePenalty)

        let official = AIConnectorGenerationProfilePreset.officialInstruct.profile(
            for: .qwen35Base4B,
            thinkingEnabled: false
        )
        XCTAssertEqual(official.maxTokens, 128)
        XCTAssertEqual(official.temperature, 0.7)
        XCTAssertEqual(official.topP, 0.8)
        XCTAssertEqual(official.topK, 20)
        XCTAssertEqual(official.presencePenalty, 1.5)

        let thinking = AIConnectorGenerationProfilePreset.greedy.profile(
            for: .qwen35Base4B,
            thinkingEnabled: true
        )
        XCTAssertEqual(thinking.maxTokens, 512)
        XCTAssertEqual(thinking.temperature, 0.6)
        XCTAssertEqual(thinking.topP, 0.95)
        XCTAssertEqual(thinking.topK, 20)

        let record = AIConnectorBenchmarkCandidateRecord(
            sampleID: "grammar",
            sampleTitle: "Grammar",
            expectedSignal: "wajib",
            segmentID: 1,
            candidateID: "C1",
            source: .deterministicRule,
            category: .grammar,
            ruleID: "grammar-wajib-untuk",
            original: "wajib untuk",
            replacement: "wajib",
            decision: .accept,
            finalOrigin: .qwen,
            attemptCount: 1,
            repairAttempted: false,
            challengeAttempted: false,
            usedFallback: false,
            rejectionClass: nil,
            promptTokenCount: 10,
            generationTokenCount: 4,
            promptDuration: 0.1,
            generationDuration: 0.2,
            stopReason: .stop,
            repeatedSixGramRatio: 0
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            AIConnectorBenchmarkCandidateRecord.self,
            from: data
        )

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(record.id, "grammar#1#C1")
    }

    func testLengthFailureIsRejectedAndNeverAccepted() async throws {
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor _, _, _ in
            throw AIConnectorCandidateModelFailure(
                message: "Token limit",
                classification: .tokenLimit,
                recoverable: false,
                metrics: self.metrics(stopReason: .length),
                reasoningMarkerDetected: false,
                outputWasTruncated: true
            )
        }
        let result = try await makeProcessor(candidateDecisionHandler: handler).process(
            segment: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertTrue(result.outputWasTruncated)
        XCTAssertTrue(result.reviews.isEmpty)
        XCTAssertEqual(result.rejections.first?.classification, .tokenLimit)
    }

    private func makeProcessor(
        ruleStore: AIConnectorRuleStore = AIConnectorRuleStore(),
        segmentCache: AIConnectorSegmentCache = AIConnectorSegmentCache(),
        candidateDecisionHandler: @escaping AIConnectorCandidateDecisionHandler
    ) -> AIConnectorSegmentProcessor {
        AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: ruleStore,
            segmentCache: segmentCache,
            candidateDecisionHandler: candidateDecisionHandler
        )
    }

    private func process(
        _ processor: AIConnectorSegmentProcessor,
        segment: AIReviewSegment,
        profile: AIConnectorGenerationProfile
    ) async throws -> AIConnectorSegmentResult {
        try await processor.process(
            segment: segment,
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in },
            generationProfile: profile
        )
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

    private func makeRule(
        id: String,
        category: AIReviewCategory,
        value: String,
        replacement: String,
        priority: Int
    ) -> AIConnectorRuleDefinition {
        AIConnectorRuleDefinition(
            id: id,
            revision: 1,
            category: category,
            matcher: .tokenSequence,
            value: value,
            replacement: replacement,
            reason: "Koreksi lokal untuk (value).",
            priority: priority,
            exceptions: [],
            status: .active,
            sourceNote: "Test rule.",
            owner: "test",
            reviewer: "test",
            changelog: "P0.11 test",
            positiveFixtures: [value],
            negativeFixtures: [replacement]
        )
    }

    private func makeDictionaryEntry(
        authority: LegalDictionaryEntryAuthority
    ) -> LegalDictionaryEntry {
        LegalDictionaryEntry(
            id: "data-pribadi-(authority.rawValue)",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: URL(string: "https://example.invalid/data-pribadi"),
            authority: authority
        )
    }

    private func makeDictionaryMatch(entry: LegalDictionaryEntry) -> LegalDictionaryMatch {
        LegalDictionaryMatch(
            entry: entry,
            score: 42,
            rank: 1,
            matchedDefinitionTokenCount: 12,
            isDirectTermMatch: false
        )
    }

    private func payload(
        candidateID: String = "C1",
        decision: String
    ) -> AIConnectorToolDecisionPayload {
        AIConnectorToolDecisionPayload(
            name: AIConnectorCandidateDecisionParser.toolName,
            arguments: [
                "candidate_id": candidateID,
                "decision": decision
            ]
        )
    }

    private func assertParserError(
        _ expected: AIConnectorCandidateDecisionParserError,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? AIConnectorCandidateDecisionParserError, expected)
        }
    }

    private func metrics(
        stopReason: AIConnectorGenerationStopReason = .stop
    ) -> AIConnectorGenerationMetrics {
        AIConnectorGenerationMetrics(
            promptTokenCount: 10,
            generationTokenCount: 4,
            promptDuration: 0.01,
            generationDuration: 0.02,
            stopReason: stopReason
        )
    }
}

private final class P011CallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [AIConnectorCandidateReviewRequest] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests.count
    }

    func append(_ request: AIConnectorCandidateReviewRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }

    func request(at index: Int) -> AIConnectorCandidateReviewRequest {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests[index]
    }
}

private final class P011ActivityBox: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private(set) var maxActive = 0

    func begin() {
        lock.lock()
        activeCount += 1
        maxActive = max(maxActive, activeCount)
        lock.unlock()
    }

    func end() {
        lock.lock()
        activeCount -= 1
        lock.unlock()
    }
}
