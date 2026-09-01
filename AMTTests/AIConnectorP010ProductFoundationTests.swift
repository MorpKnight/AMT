import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorP010ProductFoundationTests: XCTestCase {
    func testQueueProcessesAllSegmentsInBatchesAndOnlyOneGenerationIsActive() async throws {
        let source = CannedModelOutputSource(
            outputs: Array(repeating: noSuggestionResult(), count: 25),
            delay: .milliseconds(1)
        )
        let processor = makeProcessor(source: source)
        let queue = AIConnectorWorkQueue(processor: processor)
        let text = (1...25).map { "Kalimat nomor \($0)." }.joined(separator: "\n\n")
        let segments = LegalTextSegmenter().segment(documentText: text).segments

        XCTAssertEqual(AIConnectorWorkQueue.batchSizes(for: segments.count), [12, 12, 1])

        let stream = await queue.start(
            runID: UUID(),
            segments: segments,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var resultCount = 0
        var progressCount = 0
        var sawResultBeforeFinished = false
        var finishedSummary: AIConnectorRunSummary?
        for await event in stream {
            switch event {
            case .result:
                resultCount += 1
                XCTAssertNil(finishedSummary)
                sawResultBeforeFinished = true
                await queue.acknowledgeResult()
            case .progress:
                progressCount += 1
            case let .finished(summary):
                finishedSummary = summary
            default:
                break
            }
        }

        XCTAssertTrue(sawResultBeforeFinished)
        XCTAssertEqual(resultCount, 25)
        XCTAssertEqual(progressCount, 25)
        XCTAssertEqual(finishedSummary?.processedSegmentCount, 25)
        XCTAssertEqual(finishedSummary?.totalSegmentCount, 25)
        XCTAssertFalse(finishedSummary?.wasPartial ?? true)
        XCTAssertEqual(source.maxActive, 1)
        XCTAssertEqual(source.requests.count, 25)
    }

    func testQueueCancellationKeepsPartialResultsAndDoesNotStartNextItem() async {
        let source = CannedModelOutputSource(
            outputs: Array(repeating: noSuggestionResult(), count: 8),
            delay: .milliseconds(100)
        )
        let processor = makeProcessor(source: source)
        let queue = AIConnectorWorkQueue(processor: processor)
        let text = (1...8).map { "Kalimat nomor \($0)." }.joined(separator: "\n\n")
        let segments = LegalTextSegmenter().segment(documentText: text).segments
        let stream = await queue.start(
            runID: UUID(),
            segments: segments,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var resultCount = 0
        var summary: AIConnectorRunSummary?
        for await event in stream {
            switch event {
            case .result:
                resultCount += 1
                if resultCount == 1 {
                    queue.requestCancellation()
                    await queue.cancel()
                }
            case let .finished(value):
                summary = value
            default:
                break
            }
        }

        XCTAssertEqual(resultCount, 1)
        XCTAssertEqual(source.requests.count, 1)
        XCTAssertTrue(summary?.wasPartial ?? false)
        XCTAssertEqual(summary?.processedSegmentCount, 1)
    }

    func testCacheHitReanchorsReviewToCurrentSegmentLocation() async throws {
        let source = CannedModelOutputSource(outputs: [suggestionResult()])
        let cache = AIConnectorSegmentCache()
        let processor = makeProcessor(source: source, cache: cache)
        let firstSegment = makeSegment(
            id: 1,
            location: 0,
            target: "Pihak Kedua wajib untuk menyerahkan laporan."
        )
        let secondSegment = makeSegment(
            id: 2,
            location: 90,
            target: firstSegment.targetText
        )

        let first = try await processor.process(
            segment: firstSegment,
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )
        let second = try await processor.process(
            segment: secondSegment,
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertFalse(first.cacheHit)
        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(source.requests.count, 1)
        XCTAssertEqual(second.reviews.first?.segment.sourceLocation, 90)
        XCTAssertEqual(second.reviews.first?.segment.id, 2)
    }

    func testRecoverableParserFailureGetsExactlyOneRepair() async throws {
        let malformed = noSuggestionOutput() + "\nEXTRA"
        let source = CannedModelOutputSource(
            outputs: [result(malformed), noSuggestionResult()]
        )
        let processor = makeProcessor(source: source)

        let output = try await processor.process(
            segment: makeSegment(target: "Kalimat yang tidak memiliki saran."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(source.requests.count, 2)
        XCTAssertTrue(source.requests[1].repairInstruction?.contains("FORMAT REPAIR ONLY") == true)
        XCTAssertTrue(output.repairAttempted)
        XCTAssertEqual(output.modelAttempts, 2)
        XCTAssertEqual(output.reviews.first?.origin, .qwenRepaired)
        XCTAssertTrue(output.rejections.isEmpty)
    }

    func testNoSuggestionShapeIsCanonicalizedWithoutModelRepair() async throws {
        let source = CannedModelOutputSource(outputs: [result("""
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: Kalimat yang tidak memiliki saran.
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah bahasa yang jelas.
        """)])
        let processor = makeProcessor(source: source)

        let output = try await processor.process(
            segment: makeSegment(target: "Kalimat yang tidak memiliki saran."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(source.requests.count, 1)
        XCTAssertFalse(output.repairAttempted)
        XCTAssertTrue(output.firstPassSucceeded)
        XCTAssertEqual(output.reviews.first?.status, .noSuggestion)
        XCTAssertNil(output.reviews.first?.original)
    }

    func testNonMinimalEditGetsOneBoundedRepair() async throws {
        let target = "Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan."
        let broadOutput = """
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: \(target)
        REPLACEMENT: Pihak Kedua wajib menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.
        GLOSSARY_ID: -
        REASON: Menghapus kata yang tidak diperlukan.
        """
        let repairedOutput = """
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: wajib untuk
        REPLACEMENT: wajib
        GLOSSARY_ID: -
        REASON: Menghapus kata yang tidak diperlukan.
        """
        let source = CannedModelOutputSource(
            outputs: [result(broadOutput), result(repairedOutput)]
        )
        let processor = makeProcessor(source: source)

        let output = try await processor.process(
            segment: makeSegment(target: target),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(source.requests.count, 2)
        XCTAssertTrue(source.requests[1].repairInstruction?.contains("span terlalu luas") == true)
        XCTAssertTrue(output.repairAttempted)
        XCTAssertEqual(output.modelAttempts, 2)
        XCTAssertEqual(output.reviews.first?.origin, .qwenRepaired)
        XCTAssertEqual(output.reviews.first?.original, "wajib untuk")
        XCTAssertEqual(output.reviews.first?.replacement, "wajib")
    }

    func testHybridCombinesDeterministicCandidateWithValidModelNoSuggestion() async throws {
        let source = CannedModelOutputSource(outputs: [noSuggestionResult()])
        let processor = makeProcessor(source: source)

        let output = try await processor.process(
            segment: makeSegment(
                target: "Pihak Kedua wajib untuk menyerahkan laporan."
            ),
            documentProtectionContext: .empty,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(source.requests.count, 1)
        XCTAssertTrue(output.firstPassSucceeded)
        XCTAssertFalse(output.usedFallback)
        XCTAssertEqual(output.reviews.count, 1)
        XCTAssertEqual(output.reviews.first?.original, "wajib untuk")
        XCTAssertEqual(output.reviews.first?.replacement, "wajib")
        XCTAssertEqual(output.reviews.first?.origin, .deterministic)
    }

    func testValidatorFailureIsNotRepaired() async throws {
        let invalid = """
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: wajib membayar 30
        REPLACEMENT: wajib membayar 31
        GLOSSARY_ID: -
        REASON: Perbaikan bahasa.
        """
        let source = CannedModelOutputSource(outputs: [result(invalid)])
        let processor = makeProcessor(source: source)

        let output = try await processor.process(
            segment: makeSegment(target: "Pihak Kedua wajib membayar 30."),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(source.requests.count, 1)
        XCTAssertFalse(output.repairAttempted)
        XCTAssertTrue(output.reviews.isEmpty)
        XCTAssertEqual(output.rejections.first?.classification, .validator)
    }

    func testCircuitBreakerUsesDeterministicPathAfterThreeFailuresAmongFirstFour() async {
        let failure = result("<think>internal</think>")
        let source = CannedModelOutputSource(outputs: [failure, failure, failure, failure])
        let processor = makeProcessor(source: source)
        let queue = AIConnectorWorkQueue(processor: processor)
        let text = (1...6).map { "Kalimat aman nomor \($0)." }.joined(separator: "\n\n")
        let segments = LegalTextSegmenter().segment(documentText: text).segments
        let stream = await queue.start(
            runID: UUID(),
            segments: segments,
            mode: .hybrid,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var breakerEvents = 0
        var results: [AIConnectorSegmentResult] = []
        var summary: AIConnectorRunSummary?
        for await event in stream {
            switch event {
            case .circuitBreakerActivated:
                breakerEvents += 1
            case let .result(value):
                results.append(value)
                await queue.acknowledgeResult()
            case let .finished(value):
                summary = value
            default:
                break
            }
        }

        XCTAssertEqual(breakerEvents, 1)
        XCTAssertEqual(source.requests.count, 4)
        XCTAssertEqual(results.count, 6)
        XCTAssertTrue(results.dropFirst(4).allSatisfy { $0.usedFallback })
        XCTAssertTrue(summary?.circuitBreakerActivated ?? false)
    }

    func testBenchmarkRunnerUsesProductionQueueCircuitBreaker() async throws {
        let failure = result("<think>internal</think>")
        let source = CannedModelOutputSource(
            outputs: [failure, failure, failure, failure]
        )
        let samples = (1...6).map { index in
            AIConnectorSample(
                id: "queue-fixture-\(index)",
                title: "Queue fixture \(index)",
                text: "Kalimat aman nomor \(index).",
                expectedSignal: "Tidak membuat perubahan."
            )
        }
        let runner = AIConnectorBenchmarkRunner(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            modelReviewHandler: { @MainActor [source] request in
                try await source.next(request)
            }
        )

        let report = try await runner.run(
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            samples: samples,
            progress: { _, _ in }
        )

        XCTAssertTrue(report.circuitBreakerActivated)
        XCTAssertEqual(source.requests.count, 4)
        XCTAssertEqual(report.records.count, 6)
        XCTAssertTrue(report.records.dropFirst(4).allSatisfy(\.wasFallback))
        XCTAssertTrue(report.qualityGate.safetyContainmentPassed)
        XCTAssertEqual(report.qualityGate.schemaCompliantCount, 0)
        XCTAssertEqual(report.qualityGate.schemaTotal, 4)
        XCTAssertEqual(report.qualityGate.usableValidatedOutputCount, 6)
    }

    func testRulePackHasPositiveAndNegativeFixturesAndProducesMultipleCandidates() {
        let store = AIConnectorRuleStore()
        XCTAssertFalse(store.activeRules.isEmpty)
        XCTAssertTrue(store.activeRules.allSatisfy {
            !$0.positiveFixtures.isEmpty && !$0.negativeFixtures.isEmpty
        })

        let segment = makeSegment(
            target: "Pihak Kedua wajib untuk menyerahkan dokumen yang di simpan dan telah ditanda tangani."
        )
        let reviews = AIConnectorDeterministicSuggestionEngine(ruleStore: store)
            .suggestions(for: segment)

        XCTAssertGreaterThanOrEqual(reviews.count, 3)
        XCTAssertEqual(
            Set(reviews.compactMap(\.ruleID)),
            Set(["grammar-wajib-untuk", "spelling-di-simpan", "spelling-ditanda-tangani"])
        )
        XCTAssertLessThanOrEqual(
            reviews.count,
            AIConnectorSuggestionConflictResolver.maximumSuggestionsPerSegment
        )
    }

    func testRuleEngineIgnoresDisabledAndDeprecatedRules() {
        let rules = [
            makeRule(id: "disabled-rule", status: .disabled),
            makeRule(id: "deprecated-rule", status: .deprecated)
        ]
        let engine = AIConnectorDeterministicSuggestionEngine(
            ruleStore: AIConnectorRuleStore(version: "test-rules", rules: rules)
        )

        XCTAssertTrue(
            engine.suggestions(
                for: makeSegment(target: "Pihak Kedua wajib untuk menyerahkan laporan.")
            ).isEmpty
        )
    }

    func testLocalToolDispatcherIsReadOnlyAndBounded() async throws {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil,
            authority: .legacy,
            corpusVersion: LegalDictionaryCorpusVersion.legacyKamusV1
        )
        let dispatcher = AIConnectorLocalToolDispatcher(
            dictionaryStore: LegalDictionaryStore(entries: [entry]),
            budget: AIConnectorLocalToolBudget(maxCalls: 1, maxResultsPerCall: 2, timeout: 1)
        )

        let response = try await dispatcher.call(
            AIConnectorLocalToolRequest(
                name: .searchLegalConcepts,
                query: "Data Pribadi",
                entryID: nil,
                limit: 1
            )
        )
        XCTAssertEqual(response.corpusVersion, "legacy-kamus-v1")
        XCTAssertFalse(response.isAuthoritative)
        XCTAssertTrue(response.payload.contains("data-pribadi"))

        do {
            _ = try await dispatcher.call(
                AIConnectorLocalToolRequest(
                    name: .searchLegalConcepts,
                    query: "Data",
                    entryID: nil,
                    limit: 1
                )
            )
            XCTFail("The tool budget should stop a second call.")
        } catch let error as AIConnectorLocalToolError {
            XCTAssertEqual(error, .budgetExceeded)
        }
    }

    func testLocalToolDispatcherRejectsNonPositiveTimeout() async throws {
        let dispatcher = AIConnectorLocalToolDispatcher(
            dictionaryStore: LegalDictionaryStore(entries: []),
            budget: AIConnectorLocalToolBudget(
                maxCalls: 1,
                maxResultsPerCall: 5,
                timeout: 0
            )
        )

        do {
            _ = try await dispatcher.call(
                AIConnectorLocalToolRequest(
                    name: .searchLegalConcepts,
                    query: "Data Pribadi",
                    entryID: nil,
                    limit: 1
                )
            )
            XCTFail("A non-positive timeout must reject the tool call.")
        } catch let error as AIConnectorLocalToolError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testProtectionContextCapturesContactAndDocumentIdentifiers() {
        let context = AIConnectorDocumentProtectionContextBuilder().build(
            documentText: "Hubungi legal@example.com melalui https://example.com/uu. Nomor 12/ABC-2026."
        )

        XCTAssertTrue(context.identifiers.contains("legal@example.com"))
        XCTAssertTrue(context.identifiers.contains("https://example.com/uu."))
        XCTAssertTrue(context.identifiers.contains("Nomor 12/ABC-2026"))
    }

    func testValidatorRejectsConditionExceptionAndLegalConsequenceChanges() {
        let cases = [
            (
                original: "Pihak Kedua wajib membayar jika menerima tagihan.",
                replacement: "Pihak Kedua wajib membayar."
            ),
            (
                original: "Pihak Kedua wajib membayar kecuali disepakati lain.",
                replacement: "Pihak Kedua wajib membayar."
            ),
            (
                original: "Pihak Pertama dapat mengakhiri Perjanjian ini.",
                replacement: "Pihak Pertama dapat mengubah Perjanjian ini."
            )
        ]

        for item in cases {
            let parsed = AIParsedReview(
                status: .suggestion,
                category: .clarity,
                original: item.original,
                replacement: item.replacement,
                glossaryID: nil,
                reason: "Perubahan bahasa."
            )

            do {
                _ = try AIConnectorSuggestionValidator().validate(
                    parsed,
                    for: makeSegment(target: item.original),
                    glossaryMatches: []
                )
                XCTFail("The validator must reject a legal-structure change.")
            } catch let error as AIConnectorValidationError {
                XCTAssertEqual(error, .legalStructureChanged)
            } catch {
                XCTFail("Unexpected validation error: \(error)")
            }
        }
    }

    func testQueueSkipsTooLongSegmentWithoutCallingModel() async throws {
        let source = CannedModelOutputSource(outputs: [noSuggestionResult()])
        let processor = makeProcessor(source: source)
        let queue = AIConnectorWorkQueue(processor: processor)
        let segment = LegalTextSegmenter().segment(
            documentText: String(repeating: "kata ", count: 520) + "selesai."
        ).segments[0]

        let stream = await queue.start(
            runID: UUID(),
            segments: [segment],
            mode: .modelOnly,
            modelVariant: .qwen35_2b,
            thinkingEnabled: false,
            documentProtectionContext: .empty,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var result: AIConnectorSegmentResult?
        var summary: AIConnectorRunSummary?
        for await event in stream {
            switch event {
            case let .result(value):
                result = value
                await queue.acknowledgeResult()
            case let .finished(value):
                summary = value
            default:
                break
            }
        }

        XCTAssertEqual(source.requests.count, 0)
        XCTAssertTrue(result?.skipped ?? false)
        XCTAssertEqual(summary?.skippedSegmentCount, 1)
        XCTAssertEqual(summary?.processedSegmentCount, 0)
    }

    func testCacheKeyChangesForPolicyAndProtectedDocumentContext() {
        let segment = makeSegment(target: "Kalimat.")
        let base = AIConnectorCacheKeyComponents(
            segment: segment,
            reviewMode: .modelOnly,
            modelVariant: .qwen35_2b,
            generationProfile: AIConnectorModelVariant.qwen35_2b
                .generationProfile(thinkingEnabled: false),
            promptVersion: "prompt-v1",
            rulePackVersion: "rules-v1",
            corpusVersion: "corpus-v1",
            validatorVersion: "validator-v1",
            outputSchemaVersion: "schema-v1",
            protectionContext: .empty
        )
        let modeChanged = AIConnectorCacheKeyComponents(
            segment: segment,
            reviewMode: .hybrid,
            modelVariant: base.modelVariant,
            generationProfile: base.generationProfile,
            promptVersion: base.promptVersion,
            rulePackVersion: base.rulePackVersion,
            corpusVersion: base.corpusVersion,
            validatorVersion: base.validatorVersion,
            outputSchemaVersion: base.outputSchemaVersion,
            protectionContext: base.protectionContext
        )
        let contextChanged = AIConnectorCacheKeyComponents(
            segment: segment,
            reviewMode: base.reviewMode,
            modelVariant: base.modelVariant,
            generationProfile: base.generationProfile,
            promptVersion: base.promptVersion,
            rulePackVersion: base.rulePackVersion,
            corpusVersion: base.corpusVersion,
            validatorVersion: base.validatorVersion,
            outputSchemaVersion: base.outputSchemaVersion,
            protectionContext: AIConnectorDocumentProtectionContext(
                definedTerms: ["Istilah"],
                partyNames: [],
                acronyms: [],
                quotedTerms: [],
                identifiers: []
            )
        )
        let embeddingSchemaChanged = AIConnectorCacheKeyComponents(
            segment: base.segment,
            reviewMode: base.reviewMode,
            modelVariant: base.modelVariant,
            generationProfile: base.generationProfile,
            promptVersion: base.promptVersion,
            rulePackVersion: base.rulePackVersion,
            corpusVersion: base.corpusVersion,
            semanticEmbeddingSchema: "e5:384:f32:normalized",
            semanticRetrievalProfile: "rrf:60:top100:threshold:0.60",
            validatorVersion: base.validatorVersion,
            outputSchemaVersion: base.outputSchemaVersion,
            protectionContext: base.protectionContext
        )
        let retrievalProfileChanged = AIConnectorCacheKeyComponents(
            segment: base.segment,
            reviewMode: base.reviewMode,
            modelVariant: base.modelVariant,
            generationProfile: base.generationProfile,
            promptVersion: base.promptVersion,
            rulePackVersion: base.rulePackVersion,
            corpusVersion: base.corpusVersion,
            semanticEmbeddingSchema: base.semanticEmbeddingSchema,
            semanticRetrievalProfile: "rrf:60:top100:threshold:0.65",
            validatorVersion: base.validatorVersion,
            outputSchemaVersion: base.outputSchemaVersion,
            protectionContext: base.protectionContext
        )

        XCTAssertNotEqual(
            AIConnectorSegmentCache.key(from: base),
            AIConnectorSegmentCache.key(from: modeChanged)
        )
        XCTAssertNotEqual(
            AIConnectorSegmentCache.key(from: base),
            AIConnectorSegmentCache.key(from: contextChanged)
        )
        XCTAssertNotEqual(
            AIConnectorSegmentCache.key(from: base),
            AIConnectorSegmentCache.key(from: embeddingSchemaChanged)
        )
        XCTAssertNotEqual(
            AIConnectorSegmentCache.key(from: base),
            AIConnectorSegmentCache.key(from: retrievalProfileChanged)
        )
    }

    private func makeProcessor(
        source: CannedModelOutputSource,
        cache: AIConnectorSegmentCache = AIConnectorSegmentCache()
    ) -> AIConnectorSegmentProcessor {
        AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: AIConnectorRuleStore(),
            segmentCache: cache,
            modelReviewHandler: { @MainActor [source] request in
                try await source.next(request)
            }
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
        status: AIConnectorRuleStatus
    ) -> AIConnectorRuleDefinition {
        AIConnectorRuleDefinition(
            id: id,
            revision: 1,
            category: .grammar,
            matcher: .tokenSequence,
            value: "wajib untuk",
            replacement: "wajib",
            reason: "Koreksi grammar.",
            priority: 1,
            exceptions: [],
            status: status,
            sourceNote: "Test rule.",
            owner: "test",
            reviewer: "test",
            changelog: "test",
            positiveFixtures: ["wajib untuk"],
            negativeFixtures: ["wajib"]
        )
    }

    private func noSuggestionOutput() -> String {
        """
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: -
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah bahasa yang jelas.
        """
    }

    private func suggestionOutput() -> String {
        """
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: wajib untuk
        REPLACEMENT: wajib
        GLOSSARY_ID: -
        REASON: Menghapus kata yang tidak diperlukan.
        """
    }

    private func noSuggestionResult() -> QwenReviewResult {
        result(noSuggestionOutput())
    }

    private func suggestionResult() -> QwenReviewResult {
        result(suggestionOutput())
    }

    private func result(
        _ output: String,
        stopReason: AIConnectorGenerationStopReason = .stop
    ) -> QwenReviewResult {
        QwenReviewResult(
            output: output,
            metrics: AIConnectorGenerationMetrics(
                promptTokenCount: 10,
                generationTokenCount: 8,
                promptDuration: 0.01,
                generationDuration: 0.02,
                stopReason: stopReason
            ),
            containsReasoningMarkers: output.contains("<think>")
        )
    }
}

@MainActor
private final class CannedModelOutputSource: Sendable {
    let outputs: [QwenReviewResult]
    let delay: Duration?
    private(set) var requests: [AIConnectorModelReviewRequest] = []
    private(set) var maxActive = 0
    private var active = 0
    private var index = 0

    init(outputs: [QwenReviewResult], delay: Duration? = nil) {
        self.outputs = outputs
        self.delay = delay
    }

    func next(_ request: AIConnectorModelReviewRequest) async throws -> QwenReviewResult {
        requests.append(request)
        active += 1
        maxActive = max(maxActive, active)
        defer { active -= 1 }

        if let delay {
            try await Task.sleep(for: delay)
        }
        guard index < outputs.count else {
            throw QwenSuggestionError.emptyResponse
        }
        let output = outputs[index]
        index += 1
        return output
    }
}
