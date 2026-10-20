import AppKit
import SwiftUI
import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorFlowFixTests: XCTestCase {
    func testDefinitionHeadingChangeInvalidatesCacheAndMatchesFresh() async throws {
        let store = LegalDictionaryStore(entries: [LegalDictionaryEntry(id: "data", term: "Data", definition: "informasi yang tidak dapat dipublikasikan", regulation: "Uji", regulationTitle: "Uji", sourceURL: nil, authority: .verified, corpusVersion: "heading-test", applicabilityStatus: .inForce)])
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: store, ruleStore: AIConnectorRuleStore(version: "empty", rules: []))
        let text = #""Data" adalah informasi yang tidak dapat dipublikasikan."#
        func run(_ heading: String) async throws -> AIConnectorSegmentResult {
            let context = AIConnectorSegmentContext(sectionID: "s", headingPath: [heading], parentClause: nil, relevantDefinedTerms: [], relevantParties: [], sectionRegulationReferences: [], documentTypeCandidates: [], legalDomainCandidates: [], profileFingerprint: "p", structureFingerprint: heading)
            let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil, context: context)
            return try await processor.process(segment: segment, documentProtectionContext: .empty, mode: .deterministic, modelVariant: .qwen35Base4B, thinkingEnabled: false, forceDeterministic: false, downloadProgress: { _ in }, generationProgress: { _ in })
        }
        _ = try await run("Pendahuluan")
        let cached = try await run("Pendahuluan")
        XCTAssertTrue(cached.cacheHit)
        let changed = try await run("Definisi")
        XCTAssertFalse(changed.cacheHit)
        XCTAssertFalse(changed.definitionCacheHit)
        await processor.clearCache()
        let fresh = try await run("Definisi")
        XCTAssertEqual(changed.definitionAssessment, fresh.definitionAssessment)
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: store)
        XCTAssertTrue(vm.currentAnalysisProfile.pipelineVersion.contains(AIConnectorDefinitionAnalyzer.policyVersion))
    }

    func testCacheSeparatesThinkingAndRematerializesMovedDefinitions() async throws {
        let entry = LegalDictionaryEntry(id: "data", term: "Data", definition: "informasi mengenai orang yang teridentifikasi", regulation: "Uji", regulationTitle: "Uji", sourceURL: nil, authority: .verified, corpusVersion: "test", applicabilityStatus: .inForce, isActionable: true)
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: [entry]), ruleStore: AIConnectorRuleStore())
        let profile = AIConnectorGenerationProfilePreset.greedy.profile(for: .qwen35Base4B, thinkingEnabled: false)
        let text = "Data adalah informasi mengenai orang yang teridentifikasi."
        func run(location: Int, thinking: Bool, profile: AIConnectorGenerationProfile) async throws -> AIConnectorSegmentResult {
            let segment = AIReviewSegment(id: 1, sourceLocation: location, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
            return try await processor.process(segment: segment, documentProtectionContext: .empty, mode: .deterministic, modelVariant: .qwen35Base4B, thinkingEnabled: thinking, forceDeterministic: false, downloadProgress: { _ in }, generationProgress: { _ in }, generationProfile: profile)
        }
        let first = try await run(location: 0, thinking: false, profile: profile)
        let cached = try await run(location: 0, thinking: false, profile: profile)
        let thinkingChanged = try await run(location: 0, thinking: true, profile: profile)
        let moved = try await run(location: 100, thinking: false, profile: profile)
        let penaltyProfile = AIConnectorGenerationProfile(maxTokens: profile.maxTokens, temperature: profile.temperature, topP: profile.topP, topK: profile.topK, presencePenalty: 1, seed: profile.seed)
        let penaltyChanged = try await run(location: 0, thinking: false, profile: penaltyProfile)
        XCTAssertNotNil(first.definitionAssessment)
        XCTAssertTrue(cached.cacheHit)
        XCTAssertFalse(thinkingChanged.cacheHit)
        XCTAssertFalse(moved.definitionCacheHit)
        XCTAssertEqual(moved.definitionAssessment?.segment.sourceLocation, 100)
        XCTAssertFalse(penaltyChanged.definitionCacheHit)
    }

    func testLocalResultsAreAcknowledgedBeforeDelayedClassification() async throws {
        let service = QwenSuggestionService()
        let processor = AIConnectorSegmentProcessor(service: service, dictionaryStore: LegalDictionaryStore(entries: []), ruleStore: AIConnectorRuleStore(), enablePhaseTwo: true)
        let queue = AIConnectorWorkQueue(processor: processor)
        var localReviews: [AIValidatedReview] = []
        var classificationSawLocalResults = false
        let coordinator = AIConnectorDocumentContextCoordinator(service: service, classifier: { _, _, _ in
            classificationSawLocalResults = !localReviews.isEmpty
            try await Task.sleep(for: .milliseconds(50))
            throw FlowTestError.deliberatelyUnavailable
        })
        let text = "Dokumen memasukan arsip yang ditanda tangani dan di simpan."
        _ = try await coordinator.prepare(documentText: text, structuredDocument: nil, mode: .hybrid, modelVariant: .qwen35Base4B, generationProfile: .init(maxTokens: 384, temperature: 0, topP: 1, topK: 0, presencePenalty: nil, seed: 42), localPreparation: { preparation in
            let events = await queue.startLocalPass(runID: UUID(), segments: preparation.segmentation.segments, protectionContext: processor.protectionContext(for: text))
            for await event in events {
                guard case let .localResult(result) = event else { continue }
                localReviews.append(contentsOf: result.reviews.filter { $0.status == .suggestion })
                await queue.acknowledgeResult()
            }
        })
        XCTAssertTrue(classificationSawLocalResults)
        XCTAssertEqual(localReviews.count, 3)
        XCTAssertEqual(Set(localReviews.compactMap { $0.sourceAnchor?.sourceLocation }).count, 3)
    }

    func testViewModelPublishesLocalFindingsBeforeClassificationAndCancellationIsOwned() async throws {
        let service = QwenSuggestionService()
        let store = LegalDictionaryStore(entries: [])
        let classifier: AIConnectorDocumentContextClassificationHandler = { _, _, _ in
            try await Task.sleep(for: .milliseconds(500))
            throw FlowTestError.deliberatelyUnavailable
        }
        // This test exercises the delayed classifier path explicitly; ordinary
        // rule-only text is now admitted to the local base by the router.
        let route: LegalReviewRoutingHandler = { _, _, _ in
            .init(needsHybrid: true, reason: "delayed classifier test", lexicalQueries: 0, cacheHit: false)
        }
        let first = AIConnectorViewModel(service: service, dictionaryStore: store, contextClassifier: classifier, legalReviewRoute: route)
        let second = AIConnectorViewModel(service: service, dictionaryStore: store, contextClassifier: classifier, legalReviewRoute: route)
        let text = "memasukan ditanda tangani di simpan."
        first.reviewMode = .hybrid
        second.reviewMode = .hybrid
        first.run(documentText: text)
        second.run(documentText: text)
        try await waitUntil { first.editorSuggestions.count == 3 && second.editorSuggestions.count == 3 }
        XCTAssertTrue(first.isRunning)
        XCTAssertTrue(second.isRunning)
        XCTAssertEqual(second.processedSegmentCount, 0)
        let localIDs = Set(second.editorSuggestions.map(\.id))
        first.cancel()
        try await waitUntil { !second.isRunning }
        await second.flowBenchmarkAwaitCompletion()
        XCTAssertEqual(second.processedSegmentCount, 1)
        XCTAssertEqual(Set(second.editorSuggestions.map(\.id)), localIDs)
        XCTAssertEqual(second.editorSuggestions.count, 3)
        XCTAssertEqual(second.segmentCoverage[1]?["localReview"], .completed)
        first.run(documentText: text, scope: .incrementalDocument)
        try await waitUntil { !first.isRunning }
        await first.flowBenchmarkAwaitCompletion()
        XCTAssertEqual(first.processedSegmentCount, 1)
        XCTAssertEqual(normalizedFindings(first), normalizedFindings(second))
    }

    func testFinalResultsUpsertLocalFindingsAndCountEachSegmentOnce() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        vm.reviewMode = .deterministic
        let text = "Dokumen memasukan arsip yang ditanda tangani dan di simpan."
        vm.run(documentText: text)
        try await waitUntil { !vm.isRunning }
        XCTAssertEqual(vm.processedSegmentCount, 1)
        XCTAssertEqual(vm.editorSuggestions.count, 3)
        XCTAssertEqual(Set(vm.editorSuggestions.map(\.sourceRange.location)).count, 3)
        XCTAssertEqual(vm.segmentCoverage[1]?["semanticRetrieval"], .notApplicable)
        let suggestion = try XCTUnwrap(vm.editorSuggestions.first)
        XCTAssertTrue(vm.canApplySuggestion(suggestion, to: text))
        XCTAssertFalse(vm.canApplySuggestion(suggestion, to: text + " Tambahan."))
        vm.generationProfilePreset = .lowVariance
        XCTAssertFalse(vm.canApplySuggestion(suggestion, to: text))
    }

    func testUnknownSourceIsReferenceOnlyAndAdditionalCandidatesAreProcessed() async throws {
        let source = LegalDictionaryEntry(id: "unknown", term: "Data", definition: "informasi mengenai orang yang teridentifikasi", regulation: "Uji", regulationTitle: "Uji", sourceURL: nil, authority: .verified, corpusVersion: "test", applicabilityStatus: .unknown, isActionable: true)
        let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: source.definition.utf16.count, targetText: source.definition, previousContext: nil, nextContext: nil)
        let match = LegalDictionaryMatch(entry: source, score: 1, rank: 1, matchedDefinitionTokenCount: 6, isDirectTermMatch: false)
        XCTAssertTrue(AIConnectorCandidateBuilder(ruleStore: AIConnectorRuleStore(version: "empty", rules: [])).build(for: segment, glossaryMatches: [match]).isEmpty)
        let parsed = AIParsedReview(status: .suggestion, category: .terminology, original: source.definition, replacement: source.term, glossaryID: "G1", reason: "Uji")
        XCTAssertThrowsError(try AIConnectorSuggestionValidator().validate(parsed, for: segment, glossaryMatches: [match], origin: .deterministic))
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        vm.reviewMode = .deterministic
        vm.run(documentText: "Dokumen memasukan arsip yang ditanda tangani dan di simpan karena wajib untuk tersedia.")
        try await waitUntil { !vm.isRunning }
        XCTAssertEqual(vm.candidateCount, 4)
        XCTAssertEqual(vm.currentCandidateDecisions.count, 4)
    }

    func testCancellationOfOldQueueRunDoesNotCancelReplacementRun() async throws {
        let processor = AIConnectorSegmentProcessor(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []), ruleStore: AIConnectorRuleStore(), enablePhaseTwo: true)
        let queue = AIConnectorWorkQueue(processor: processor)
        let text = "memasukan ditanda tangani di simpan."
        let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
        let oldID = UUID()
        _ = await queue.startLocalPass(runID: oldID, segments: [segment], protectionContext: processor.protectionContext(for: text))
        let events = await queue.startLocalPass(runID: UUID(), segments: [segment], protectionContext: processor.protectionContext(for: text))
        await queue.cancel(runID: oldID)
        var results = 0
        for await event in events {
            if case .localResult = event {
                results += 1
                await queue.acknowledgeResult()
            }
        }
        XCTAssertEqual(results, 1)
    }

    func testIncrementalMatchesFreshAfterLocalDefinitionReferenceAndConfigurationChanges() async throws {
        let original = "Pasal 1\nData adalah informasi yang tidak dapat dibuka.\nPihak Kedua memasukan arsip.\nLihat Pasal 1."
        let variants = [
            original.replacingOccurrences(of: "memasukan", with: "memasukkan"),
            original.replacingOccurrences(of: "tidak dapat", with: "dapat"),
            original.replacingOccurrences(of: "Lihat Pasal 1", with: "Lihat Pasal 99"),
            original
        ]
        for (index, text) in variants.enumerated() {
            let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
            vm.reviewMode = .deterministic
            vm.run(documentText: original)
            try await waitUntil { !vm.isRunning }
            await vm.flowBenchmarkAwaitCompletion()
            if index == 3 { vm.generationProfilePreset = .lowVariance }
            vm.markDocumentEdited(documentText: text)
            vm.run(documentText: text, scope: .incrementalDocument)
            try await waitUntil { !vm.isRunning }
            await vm.flowBenchmarkAwaitCompletion()
            let incremental = normalizedFindings(vm)
            vm.run(documentText: text, scope: .fullFresh)
            try await waitUntil { !vm.isRunning }
            await vm.flowBenchmarkAwaitCompletion()
            XCTAssertEqual(incremental, normalizedFindings(vm), "Variant \(index)")
        }
    }

    private func normalizedFindings(_ vm: AIConnectorViewModel) -> [String] {
        let reviews = vm.validatedReviews.filter { $0.status != .noSuggestion }.map {
            "\($0.segment.sourceLocation + ($0.sourceAnchor?.sourceLocation ?? 0))|\($0.status.rawValue)|\($0.category.rawValue)|\($0.original ?? "")|\($0.replacement ?? "")"
        }
        let definitions = vm.definitionAssessments.map { "\($0.segment.sourceLocation)|\($0.classification)|\($0.alignment)|\($0.segment.targetText)" }
        let findings = vm.documentFindings.map { "\($0.kind)|\($0.sourceRange.location)|\($0.sourceRange.length)" }
        return (reviews + definitions + findings).sorted()
    }

    func testFreshRunsBypassCachesButBenchmarkCachedRerunsReuseResults() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        vm.reviewMode = .deterministic
        let text = "Dokumen memasukan arsip yang ditanda tangani."
        vm.flowBenchmarkReuseCaches = true
        vm.run(documentText: text)
        try await waitUntil { !vm.isRunning }
        vm.run(documentText: text)
        try await waitUntil { !vm.isRunning }
        XCTAssertEqual(vm.cacheHitCount, 1)
        vm.flowBenchmarkReuseCaches = false
        vm.run(documentText: text)
        try await waitUntil { !vm.isRunning }
        XCTAssertEqual(vm.cacheHitCount, 0)
        XCTAssertFalse(vm.contextPreparationCacheHit)
    }

    func testEditorRejectsInvalidResolutionAndValidEditSupportsUndoRedo() async throws {
        let state = EditorState()
        let text = "Dokumen memasukan arsip."
        state.text = text
        let suggestion = EditorSuggestion(id: UUID(), sourceRange: (text as NSString).range(of: "memasukan"), original: "memasukan", replacement: "memasukkan", category: .spelling, reason: "Ejaan", origin: .deterministic)
        let parent = HighlightedDocumentTextEditor(
            documentID: UUID(),
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            richTextData: Binding(get: { state.richText }, set: { state.richText = $0 }),
            structuredDocument: Binding(get: { state.structured }, set: { state.structured = $0 }),
            zoomPercent: .constant(100), suggestions: [suggestion], annotations: [], reviewedReviewItemIDs: [], selectedReviewItemID: nil,
            onSelect: { _ in }, onTextEdited: {}, validateSuggestion: { item, source in item == suggestion && source == text }, validateDefinitionResolution: { _, _ in false },
            onSuggestionAccepted: { _, _, _ in state.accepted += 1 }, onDismiss: { _ in }, onMarkReviewed: { _ in }, onReopenReviewed: { _ in }
        )
        let coordinator = parent.makeCoordinator()
        let storage = NSTextStorage(string: text)
        let layout = SuggestionLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 1000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = SuggestionTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        view.allowsUndo = true
        let scroll = NSScrollView(frame: view.frame)
        scroll.documentView = view
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.makeFirstResponder(view)
        coordinator.connect(scrollView: scroll, textView: view, layoutManager: layout, textContainer: container, documentID: parent.documentID, text: text, richTextData: nil, structuredDocument: nil, zoomPercent: 100)
        let invalid = AIConnectorDefinitionResolutionOption(id: "forged", action: .replaceTerm, title: "Ganti", targetRange: suggestion.sourceRange, original: suggestion.original, replacement: suggestion.replacement, status: .actionable)
        coordinator.applyDefinitionResolution(invalid)
        XCTAssertEqual(view.string, text)
        XCTAssertNil(state.richText)
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        coordinator.accept(suggestion)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "Dokumen memasukkan arsip.")
        XCTAssertEqual(state.text, view.string)
        XCTAssertNotNil(state.richText)
        XCTAssertNotNil(state.structured)
        XCTAssertEqual(state.accepted, 1)
        undo.undo()
        XCTAssertEqual(view.string, text)
        XCTAssertEqual(state.text, text)
        undo.redo()
        XCTAssertEqual(state.text, "Dokumen memasukkan arsip.")
        window.orderOut(nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AMT-FlowEdit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var document = DashboardDocument(content: text)
        try JSONEncoder().encode(document).write(to: directory.appendingPathComponent("\(document.id.uuidString).json"))
        let documentStorage = DocumentStorageManager(storageDirectoryURL: directory)
        document.content = state.text
        document.richTextData = state.richText
        document.structuredDocument = state.structured
        _ = documentStorage.updateDraft(document)
        await documentStorage.flushAllPendingSaves()
        let reloaded = DocumentStorageManager(storageDirectoryURL: directory)
        let saved = try XCTUnwrap(reloaded.documents.first { $0.id == document.id })
        XCTAssertEqual(saved.content, state.text)
        XCTAssertEqual(saved.richTextData, state.richText)
        XCTAssertEqual(saved.structuredDocument, state.structured)
    }

    func testQueuedCancellationLeavesOtherOwnersAliveAndInteractiveRequestHasPriority() async throws {
        let scheduler = AIConnectorInferenceScheduler()
        let holder = try await scheduler.acquire()
        let background = Task { try await scheduler.acquire(priority: .background) }
        try await waitUntil { await scheduler.queuedRequestCount == 1 }
        let cancelled = Task { try await scheduler.acquire(priority: .background) }
        try await waitUntil { await scheduler.queuedRequestCount == 2 }
        let interactive = Task { try await scheduler.acquire(priority: .interactive) }
        try await waitUntil { await scheduler.queuedRequestCount == 3 }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled owner must not acquire a lease") }
        catch is CancellationError { }
        await scheduler.release(holder)
        let interactiveLease = try await interactive.value
        let pendingCount = await scheduler.queuedRequestCount
        XCTAssertEqual(pendingCount, 1)
        await scheduler.release(interactiveLease)
        let backgroundLease = try await background.value
        await scheduler.release(backgroundLease)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for deterministic test state")
        throw FlowTestError.timeout
    }
}

private enum FlowTestError: Error {
    case deliberatelyUnavailable, timeout
}

@MainActor private final class EditorState {
    var text = ""
    var richText: Data?
    var structured: StructuredDocument?
    var accepted = 0
}
