import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorResourcePolicyTests: XCTestCase {
    func testLRUEnforcesCountAndKeepsRecentlyReadValues() {
        var cache = AIConnectorBoundedLRUCache<String, String>(capacity: 2, maximumCost: 100, payloadCost: { _, value in value.utf8.count })
        cache["a"] = "one"; cache["b"] = "two"
        XCTAssertEqual(cache["a"], "one")
        cache["c"] = "three"
        XCTAssertNil(cache["b"]); XCTAssertEqual(cache["a"], "one")
        XCTAssertEqual(cache.count, 2); XCTAssertEqual(cache.statistics.evictions, 1)
    }
    func testCostReplacementOversizedAndClear() {
        var cache = AIConnectorBoundedLRUCache<Int, String>(capacity: 20, maximumCost: 8, payloadCost: { _, value in value.utf8.count })
        cache[1] = "1234"; cache[2] = "5678"; cache[1] = "abcdef"
        XCTAssertEqual(cache.totalCost, 6); XCTAssertNil(cache[2]); XCTAssertEqual(cache.count, 1)
        cache[3] = "0123456789"
        XCTAssertNil(cache[3]); XCTAssertEqual(cache.statistics.oversizedEntries, 1)
        cache.removeAll(); XCTAssertEqual(cache.totalCost, 0); XCTAssertEqual(cache.count, 0)
    }
    func testAllConfiguredCapacitiesEvictIncrementally() {
        for capacity in [256,512,2048] {
            var cache = AIConnectorBoundedLRUCache<Int, Int>(capacity: capacity, maximumCost: 100_000, payloadCost: { _, _ in 1 })
            for i in 0..<(capacity+10) { cache[i] = i }
            XCTAssertEqual(cache.count, capacity); XCTAssertEqual(cache.statistics.evictions, 10)
            XCTAssertEqual(cache[capacity+9], capacity+9); XCTAssertNil(cache[0])
        }
    }
    func testMaintenanceWaitsForActiveInferenceAndDoesNotCancelInteractiveOwner() async throws {
        let scheduler = AIConnectorInferenceScheduler()
        let active = try await scheduler.acquire()
        let maintenance = Task { try await scheduler.acquire(priority: .maintenance) }
        let interactive = Task { try await scheduler.acquire(priority: .interactive) }
        for _ in 0..<10 { await Task.yield() }
        let queued = await awaitCount(scheduler)
        XCTAssertEqual(queued, 2)
        await scheduler.release(active)
        let lease = try await maintenance.value
        await scheduler.release(lease)
        let next = try await interactive.value
        await scheduler.release(next)
    }
    func testPressureCoalescesAndPreservesActiveOwner() async throws {
        let service = QwenSuggestionService()
        let scheduler = service.inferenceScheduler
        let lifecycle = service.resourceLifecycle
        var trims = 0
        lifecycle.registerDocument(owner: UUID()) { trims += 1; return true }
        let active = try await scheduler.acquire()
        let first = Task { await lifecycle.handle(.critical) }
        for _ in 0..<20 { await Task.yield() }
        let repeated = Task { await lifecycle.handle(.critical) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(lifecycle.modelReleaseCount, 0)
        await scheduler.release(active)
        await first.value; await repeated.value
        XCTAssertEqual(lifecycle.maintenanceCount, 1)
        XCTAssertEqual(lifecycle.modelReleaseCount, 1)
        XCTAssertEqual(trims, 1)
        await lifecycle.handle(.critical)
        XCTAssertEqual(lifecycle.maintenanceCount, 1)
        await lifecycle.handle(.normal)
        await lifecycle.handle(.warning)
        XCTAssertEqual(lifecycle.maintenanceCount, 2)
        await lifecycle.handle(.normal)
    }
    func testRestoringSegmentCacheKeepsBoundsAndDocumentsAreIsolated() async {
        let first = AIConnectorSegmentCache(), second = AIConnectorSegmentCache()
        let value = AIConnectorCachedSegmentResult(reviews: [], rejectionReasons: [], modelAttempts: 0,
            repairAttempted: false, usedFallback: false, firstPassSucceeded: true)
        let values = Dictionary(uniqueKeysWithValues: (0..<300).map { ("key-\($0)", value) })
        await first.restore(values)
        let restored = await first.snapshot(), other = await second.snapshot()
        XCTAssertEqual(restored.count, 256); XCTAssertTrue(other.isEmpty)
        await first.removeAll()
        let empty = await first.snapshot()
        XCTAssertTrue(empty.isEmpty)
    }

    func testBudgetRefusalIsNonActionableUncachedAndNotCountedAsInference() async throws {
        var calls = 0
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: AIConnectorRuleStore(), candidateDecisionHandler: { request, _, _ in
                calls += 1
                throw AIConnectorInputBudgetError(coverage: .init(windowRanges: [], omittedRanges: [NSRange(location: 0, length: request.segment.targetText.utf16.count)], tokenCounts: [5_000], reason: "Evidence wajib terlalu panjang."))
            })
        let text = "Pihak Kedua wajib untuk menyerahkan laporan."
        let segment = AIReviewSegment(id: 1, sourceLocation: 20, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
        for _ in 0..<2 {
            let result = try await processor.process(segment: segment, documentProtectionContext: .empty, mode: .modelOnly,
                modelVariant: .qwen35Base4B, thinkingEnabled: false, forceDeterministic: false,
                downloadProgress: { _ in }, generationProgress: { _ in })
            XCTAssertFalse(result.cacheHit); XCTAssertFalse(result.usedFallback)
            XCTAssertEqual(result.modelCallCount, 0)
            XCTAssertTrue(result.stageCoverage.values.contains(.tooLong))
            XCTAssertTrue(result.reviews.allSatisfy { $0.status == .needsReview })
            XCTAssertTrue(result.rejections.contains { $0.classification == .segmentTooLong })
        }
        XCTAssertGreaterThanOrEqual(calls, 2)
    }
    func testLongSegmentStillReceivesAnchoredLocalCorrections() {
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []), ruleStore: AIConnectorRuleStore())
        let text = String(repeating: "arsip disimpan ", count: 600) + "memasukan laporan."
        let segment = AIReviewSegment(id: 1, sourceLocation: 10, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil, isTooLong: true)
        XCTAssertTrue(segment.isTooLong)
        let result = processor.localResult(for: segment, protectionContext: .empty)
        XCTAssertTrue(result.reviews.contains { $0.original == "memasukan" && $0.status == .suggestion })
        XCTAssertTrue(result.reviews.allSatisfy { $0.sourceAnchor?.isValid(for: segment, original: $0.original ?? "") == true })
    }

    func testDefinitionBudgetRefusalRetainsFullSourceAndNeedsReview() async throws {
        let definition = String(repeating: "dokumen pendukung ", count: 300) + "kecuali informasi rahasia."
        let entry = LegalDictionaryEntry(id: "synthetic", term: "Arsip", definition: definition, regulation: "Uji",
            regulationTitle: "Uji", sourceURL: nil, authority: .verified, corpusVersion: "test", applicabilityStatus: .inForce, isActionable: true)
        let analyzer = AIConnectorDefinitionAnalyzer(dictionaryStore: LegalDictionaryStore(entries: [entry]), reviewHandler: { request, _, _ in
            XCTAssertEqual(request.candidate.sourceDefinition, definition)
            XCTAssertTrue(request.candidate.sourceDefinition.hasSuffix("kecuali informasi rahasia."))
            throw AIConnectorInputBudgetError(coverage: .init(windowRanges: [], omittedRanges: [NSRange(location: 0, length: definition.utf16.count)], tokenCounts: [6_000], reason: "Evidence lengkap tidak muat."))
        })
        let text = "\"Arsip\" adalah dokumen pendukung."
        let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
        let result = try await analyzer.analyze(segment: segment, glossaryMatches: [], mode: .hybrid, modelVariant: .qwen35Base4B,
            thinkingEnabled: false, forceDeterministic: false, generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(for: .qwen35Base4B, thinkingEnabled: false),
            downloadProgress: { _ in }, generationProgress: { _ in }, semanticProgress: { _ in }, progressStage: { _ in })
        XCTAssertFalse(result.isComplete); XCTAssertEqual(result.modelCallCount, 0)
        XCTAssertEqual(result.assessment?.classification, .needsReview); XCTAssertEqual(result.assessment?.alignment, .needsReview)
        XCTAssertFalse(result.assessment?.modelReviewed ?? true)
        XCTAssertFalse(result.inputCoverage?.isComplete ?? true)
    }

    func testBudgetRefusalsDoNotTripCircuitBreakerForLaterSegments() async throws {
        var calls = 0
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []), ruleStore: AIConnectorRuleStore(), candidateDecisionHandler: { request, _, _ in
            calls += 1
            throw AIConnectorInputBudgetError(coverage: .init(windowRanges: [], omittedRanges: [NSRange(location: 0, length: request.segment.sourceLength)], tokenCounts: [5_000], reason: "Input wajib tidak muat."))
        })
        let queue = AIConnectorWorkQueue(processor: processor)
        let text = "Pihak Kedua wajib untuk menyerahkan laporan."
        let segments = (1...5).map { AIReviewSegment(id: $0, sourceLocation: $0 * 100, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil) }
        let stream = await queue.start(runID: UUID(), segments: segments, mode: .modelOnly, modelVariant: .qwen35Base4B,
            thinkingEnabled: false, documentProtectionContext: .empty, downloadProgress: { _ in }, generationProgress: { _ in })
        var completed = 0, breaker = false
        for await event in stream {
            switch event {
            case .circuitBreakerActivated: breaker = true
            case let .result(result):
                completed += 1
                XCTAssertEqual(result.stageCoverage["candidateInput"], .tooLong)
                await queue.acknowledgeResult()
            default: break
            }
        }
        XCTAssertFalse(breaker); XCTAssertEqual(completed, 5); XCTAssertEqual(calls, 5)
    }

    private func awaitCount(_ scheduler: AIConnectorInferenceScheduler) async -> Int { await scheduler.queuedRequestCount }

    func testWindowPlannerPreservesIndependentClausesAndUTF16Anchors() async throws {
        let unit = "😀 Pihak Pertama menyimpan arsip;"
        let text = Array(repeating: unit, count: 80).joined(separator: " ")
        let plan = try await AIConnectorInferenceWindowPlanner.plan(text) { $0.utf16.count }
        XCTAssertTrue(plan.isComplete); XCTAssertGreaterThan(plan.windowRanges.count, 1)
        XCTAssertLessThanOrEqual(plan.windowRanges.count, 16)
        XCTAssertTrue(plan.tokenCounts.allSatisfy { $0 <= 512 })
        XCTAssertEqual(plan.windowRanges.map { (text as NSString).substring(with: $0) }.joined(), text)
    }
    func testSentenceWindowsKeepNumbersAndAbbreviationsIntact() async throws {
        let unit = "Pihak Pertama membayar 1.500 rupiah kepada PT. Perusahaan Uji. "
        let text = String(repeating: unit, count: 30)
        let plan = try await AIConnectorInferenceWindowPlanner.plan(text) { $0.utf16.count }
        XCTAssertTrue(plan.isComplete)
        XCTAssertGreaterThan(plan.windowRanges.count, 1)
        XCTAssertEqual(plan.windowRanges.map { (text as NSString).substring(with: $0) }.joined(), text)
        for range in plan.windowRanges {
            let window = (text as NSString).substring(with: range)
            XCTAssertFalse(window.trimmingCharacters(in: .whitespaces).hasPrefix("Perusahaan Uji"))
            XCTAssertFalse(window.trimmingCharacters(in: .whitespaces).hasPrefix("500"))
        }
    }

    func testConditionScopeAndIrreducibleTargetsRemainIncomplete() async throws {
        for text in [String(repeating: "dokumen ", count: 100)+"kecuali disetujui.", String(repeating: "x", count: 600)] {
            let plan = try await AIConnectorInferenceWindowPlanner.plan(text) { $0.utf16.count }
            XCTAssertFalse(plan.isComplete); XCTAssertTrue(plan.windowRanges.isEmpty); XCTAssertNotNil(plan.reason)
        }
    }
    func testWindowCapAndQuotedCandidateAreNotCut() async throws {
        let text = Array(repeating: "Pihak Pertama menyimpan "+String(repeating: "x", count: 300)+";", count: 20).joined()
        let plan = try await AIConnectorInferenceWindowPlanner.plan(text) { $0.utf16.count }
        XCTAssertEqual(plan.windowRanges.count, 16); XCTAssertFalse(plan.isComplete)
        let quoted = "Pihak Pertama menyebut \""+String(repeating: "arsip;", count: 100)+"\"."
        let quotePlan = try await AIConnectorInferenceWindowPlanner.plan(quoted) { $0.utf16.count }
        XCTAssertTrue(quotePlan.windowRanges.isEmpty)
    }
    func testFrozenFixtureSplitsStayPendingAndDisjoint() throws {
        let fixtures = AIConnectorBackendEvaluationFixtures.fixtures
        XCTAssertEqual(fixtures.count, 48); XCTAssertEqual(Set(fixtures.map(\.scenarioID)).count, 48)
        XCTAssertEqual(fixtures.filter { $0.split == .regression }.count, 24)
        XCTAssertEqual(fixtures.filter { $0.split == .holdout }.count, 24)
        XCTAssertTrue(fixtures.allSatisfy { $0.reviewStatus == .pending && $0.provenance == .synthetic })
        XCTAssertTrue(fixtures.contains { $0.expected.noChange })
        let policy = AIConnectorQualityPolicy.uncalibrated
        let manifest = AIConnectorQualityCandidateManifestFactory.make(fixtures: fixtures, policy: policy,
            corpusVersion: "test-corpus", modelVariants: [.qwen35Base4B], sourceRevision: "b5af420")
        let report = AIConnectorQualityEvaluator().evaluate(fixtures: fixtures, reviews: [], policy: policy,
            candidateManifest: manifest, outputsByMode: [:])
        XCTAssertEqual(report.overallStatus, .insufficientEvidence)
        XCTAssertTrue(report.statusReasons.contains("no-approved-fixtures"))
        if let path = ProcessInfo.processInfo.environment["AMT_PENDING_QUALITY_REPORT_PATH"] {
            try JSONEncoder().encode(report).write(to: URL(fileURLWithPath: path))
        }

    }
}
