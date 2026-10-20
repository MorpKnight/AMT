import AppKit
import Foundation
import MLXLMCommon
import SwiftUI
import XCTest
@testable import AMT

@MainActor
final class LegalReviewIntegrationTests: XCTestCase {
    private let paired = "Penyedia wajib wajib membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari."

    func testLocalPublishesBeforeDelayedContextAndFinalDoesNotDuplicateOrAdvanceSegments() async throws {
        var started = false
        let vm = makeVM { messages, _ in
            started = true
            try await Task.sleep(for: .milliseconds(150))
            return try self.turn(messages, verdict: "conflict")
        }
        vm.run(documentText: paired)
        try await until { started }
        let item = try XCTUnwrap(vm.editorSuggestions.first { $0.original == "wajib wajib" })
        XCTAssertTrue(vm.isRunning)
        XCTAssertTrue(vm.canApplySuggestion(item, to: paired))
        XCTAssertNil(vm.makeAnalysisSnapshot(documentText: paired))
        let count = vm.processedSegmentCount
        try await finish(vm)
        XCTAssertEqual(vm.editorSuggestions.filter { $0.original == "wajib wajib" }.count, 1)
        XCTAssertEqual(vm.editorSuggestions.first { $0.original == "wajib wajib" }?.id, item.id)
        XCTAssertEqual(vm.processedSegmentCount, count)
        XCTAssertEqual(vm.completedSegmentCount, vm.totalSegmentCount)
        XCTAssertEqual(vm.analysisProgress, 1)
        let conflict = try XCTUnwrap(vm.reviewAnnotations.first { $0.relatedEvidence.count == 2 })
        XCTAssertTrue(conflict.relatedEvidence.allSatisfy { $0.isAnchored(to: paired) })
        XCTAssertEqual(vm.legalReviewResult?.modelCalls, 1)
    }

    func testInvalidInferencePreservesLocalAndPreventsCompleteSnapshot() async throws {
        let vm = makeVM { _, _ in throw LegalReviewAgent.Failure.invalidSubmission }
        vm.run(documentText: paired)
        try await finish(vm)
        XCTAssertEqual(vm.legalReviewResult?.status, "partial")
        XCTAssertTrue(vm.runSummary?.wasPartial == true)
        XCTAssertNil(vm.makeAnalysisSnapshot(documentText: paired))
        XCTAssertTrue(vm.editorSuggestions.contains { $0.original == "wajib wajib" })
    }

    func testDeterministicModeNeverLoadsReviewModelAndLongInputRemainsPartial() async throws {
        var calls = 0
        let vm = makeVM { _, _ in calls += 1; throw LegalReviewAgent.Failure.invalidCall }
        vm.reviewMode = .deterministic
        vm.run(documentText: paired)
        try await finish(vm)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(vm.legalReviewResult?.toolTrace.contains("policySkipped:contextual:deterministicMode") == true)
        let long = "Penyedia wajib wajib hadir.\n" + (0..<75).map { "Catatan nomor \($0) diterima." }.joined(separator: "\n")
        vm.run(documentText: long)
        try await finish(vm)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(vm.legalReviewResult?.status, "partial")
        XCTAssertTrue(vm.editorSuggestions.contains { $0.original == "wajib wajib" })
        XCTAssertNil(vm.makeAnalysisSnapshot(documentText: long))
        XCTAssertEqual(vm.completedSegmentCount, vm.totalSegmentCount)
    }

    func testFullFreshBypassesSupplementalCacheAndIncrementalEqualsFresh() async throws {
        var calls = 0
        let vm = makeVM { messages, _ in calls += 1; return try self.turn(messages, verdict: "conflict") }
        vm.run(documentText: paired)
        try await finish(vm)
        let original = projection(vm)
        vm.rerunIncrementally(documentText: paired)
        try await finish(vm)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(vm.legalReviewResult?.cacheHit == true)
        XCTAssertEqual(original, projection(vm))
        vm.run(documentText: paired, scope: .fullFresh)
        try await finish(vm)
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(vm.legalReviewResult?.cacheHit ?? true)
        XCTAssertEqual(original, projection(vm))
        let edited = "Pasal 1\nPengantar 🧑🏽‍⚖️.\n" + paired
        vm.markDocumentEdited(documentText: edited)
        XCTAssertNil(vm.legalReviewResult)
        vm.rerunIncrementally(documentText: edited)
        try await finish(vm)
        let incremental = projection(vm)
        vm.run(documentText: edited, scope: .fullFresh)
        try await finish(vm)
        XCTAssertEqual(incremental, projection(vm))
    }

    func testTwoDocumentsCancellationAndNewRunCannotPublishOldContext() async throws {
        var entered = false
        let first = makeVM { messages, _ in
            entered = true
            try await Task.sleep(for: .seconds(2))
            return try self.turn(messages, verdict: "conflict")
        }
        let second = makeVM { messages, _ in try self.turn(messages, verdict: "compatible") }
        first.run(documentText: paired)
        try await until { entered }
        first.cancel()
        second.run(documentText: paired)
        try await finish(second)
        XCTAssertEqual(second.legalReviewResult?.status, "completePairs")
        XCTAssertEqual(first.legalReviewResult?.status, "cancelled")
        first.run(documentText: "Penyedia menjaga menjaga bukti.")
        try await finish(first)
        XCTAssertEqual(first.editorSuggestions.map(\.original), ["menjaga menjaga"])
        XCTAssertFalse(first.reviewAnnotations.contains { $0.relatedEvidence.count == 2 })
        XCTAssertNil(first.makeAnalysisSnapshot(documentText: paired))
    }

    func testSnapshotRestoresLocalAuthorizationAndRejectsStaleOrForgedEdit() async throws {
        let text = "📝 Penyedia menjaga menjaga bukti."
        let vm = makeVM { _, _ in XCTFail("Local path must not call model"); throw LegalReviewAgent.Failure.invalidCall }
        vm.reviewMode = .deterministic
        vm.run(documentText: text)
        try await finish(vm)
        let snapshot = try XCTUnwrap(vm.makeAnalysisSnapshot(documentText: text))
        let item = try XCTUnwrap(vm.editorSuggestions.first)
        let restored = makeVM { _, _ in XCTFail("Restore must not call model"); throw LegalReviewAgent.Failure.invalidCall }
        restored.reviewMode = .deterministic
        XCTAssertTrue(restored.restoreAnalysisSnapshot(snapshot, documentText: text))
        XCTAssertTrue(restored.canApplySuggestion(item, to: text))
        XCTAssertFalse(restored.canApplySuggestion(item, to: "Prefix " + text))
        let forged = EditorSuggestion(id: item.id, sourceRange: item.sourceRange, original: item.original,
            replacement: "menghapus", category: item.category, reason: item.reason, origin: item.origin)
        XCTAssertFalse(restored.canApplySuggestion(forged, to: text))
        restored.markDocumentEdited(documentText: "Prefix " + text)
        XCTAssertFalse(restored.canApplySuggestion(item, to: text))
        restored.resetInputMetadata()
        XCTAssertTrue(restored.editorSuggestions.isEmpty)
        XCTAssertNil(restored.legalReviewResult)
    }

    func testMergedEditorAcceptUndoRedoAndPersist() async throws {
        let text = "Penyedia menjaga menjaga bukti."
        let vm = makeVM { _, _ in throw LegalReviewAgent.Failure.invalidCall }
        vm.reviewMode = .deterministic
        vm.run(documentText: text)
        try await finish(vm)
        let suggestion = try XCTUnwrap(vm.editorSuggestions.first)
        let state = ReviewIntegrationEditorState(text)
        let editor = HighlightedDocumentTextEditor(documentID: UUID(),
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            richTextData: Binding(get: { state.rich }, set: { state.rich = $0 }),
            structuredDocument: Binding(get: { state.structured }, set: { state.structured = $0 }),
            zoomPercent: .constant(100), suggestions: vm.editorSuggestions, annotations: vm.reviewAnnotations,
            reviewedReviewItemIDs: [], selectedReviewItemID: nil, onSelect: { _ in }, onTextEdited: {},
            validateSuggestion: { vm.canApplySuggestion($0, to: $1) }, validateDefinitionResolution: { _, _ in false },
            onSuggestionAccepted: { item, before, after in
                XCTAssertTrue(vm.reconcileAfterAccept(item, previousText: before, updatedText: after))
            }, onDismiss: { _ in }, onMarkReviewed: { _ in }, onReopenReviewed: { _ in })
        let coordinator = editor.makeCoordinator()
        let storage = NSTextStorage(string: text), layout = SuggestionLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 1000))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let view = SuggestionTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        view.allowsUndo = true
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll; window.makeFirstResponder(view)
        defer { window.orderOut(nil) }
        coordinator.connect(scrollView: scroll, textView: view, layoutManager: layout, textContainer: container,
            documentID: editor.documentID, text: text, richTextData: nil, structuredDocument: nil, zoomPercent: 100)
        let undo = try XCTUnwrap(view.undoManager); undo.groupsByEvent = false; undo.beginUndoGrouping()
        coordinator.accept(suggestion); undo.endUndoGrouping()
        XCTAssertEqual(state.text, "Penyedia menjaga bukti.")
        XCTAssertFalse(vm.canApplySuggestion(suggestion, to: text))
        undo.undo(); XCTAssertEqual(state.text, text)
        undo.redo(); XCTAssertEqual(state.text, "Penyedia menjaga bukti.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var document = DashboardDocument(content: text)
        try JSONEncoder().encode(document).write(to: dir.appendingPathComponent(document.id.uuidString + ".json"))
        let store = DocumentStorageManager(storageDirectoryURL: dir)
        document.content = state.text; document.richTextData = state.rich; document.structuredDocument = state.structured
        _ = store.updateDraft(document); await store.flushAllPendingSaves()
        let saved = try XCTUnwrap(DocumentStorageManager(storageDirectoryURL: dir).documents.first)
        XCTAssertEqual(saved.content, state.text); XCTAssertEqual(saved.richTextData, state.rich)
    }

    func testRoutingModeChangeDoesNotReuseLocallyReviewedSegmentsAsHybridResults() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            contextClassifier: { _, _, _ in throw LegalReviewAgent.Failure.invalidCall },
            legalReviewGenerator: { _, _ in throw LegalReviewAgent.Failure.invalidCall },
            legalReviewRoute: { text, _, _ in
                .init(needsHybrid: text.contains("Berita"), reason: "routing invalidation test", lexicalQueries: 0, cacheHit: false)
            })
        vm.run(documentText: "Dokumen disimpan.")
        try await finish(vm)
        let changed = "Dokumen disimpan.\nBerita diterima."
        vm.markDocumentEdited(documentText: changed)
        vm.rerunIncrementally(documentText: changed)
        try await finish(vm)
        XCTAssertEqual(vm.reusedSegmentCount, 0)
        XCTAssertEqual(vm.reprocessedSegmentCount, vm.totalSegmentCount)
    }

    func testDismissedSupplementalItemsStayDismissedOnUnchangedIncrementalRun() async throws {
        let text = "Penyedia menjaga menjaga bukti. Barang diberikan kepada [NAMA PEMESAN]."
        let vm = makeVM { _, _ in XCTFail("Pure local findings"); throw LegalReviewAgent.Failure.invalidCall }
        vm.reviewMode = .deterministic
        vm.run(documentText: text)
        try await finish(vm)
        let suggestion = try XCTUnwrap(vm.editorSuggestions.first)
        let parameter = try XCTUnwrap(vm.reviewAnnotations.first { $0.title == "Parameter terbuka" })
        vm.dismissReviewItem(suggestion.id); vm.dismissReviewItem(parameter.id)
        vm.rerunIncrementally(documentText: text)
        try await finish(vm)
        XCTAssertTrue(vm.ignoredReviewItemIDs.contains(suggestion.id))
        XCTAssertTrue(vm.ignoredReviewItemIDs.contains(parameter.id))
        XCTAssertFalse(vm.editorSuggestions.contains { $0.id == suggestion.id })
        XCTAssertFalse(vm.reviewAnnotations.contains { $0.id == parameter.id })
        vm.run(documentText: text, scope: .fullFresh)
        try await finish(vm)
        XCTAssertTrue(vm.editorSuggestions.contains { $0.original == "menjaga menjaga" })
        let contextual = makeVM { messages, _ in try self.turn(messages, verdict: "conflict") }
        contextual.run(documentText: paired)
        try await finish(contextual)
        let conflict = try XCTUnwrap(contextual.reviewAnnotations.first { $0.relatedEvidence.count == 2 })
        contextual.dismissReviewItem(conflict.id)
        contextual.rerunIncrementally(documentText: paired)
        try await finish(contextual)
        XCTAssertTrue(contextual.ignoredReviewItemIDs.contains(conflict.id))
        XCTAssertFalse(contextual.reviewAnnotations.contains { $0.id == conflict.id })
        XCTAssertTrue(contextual.legalReviewResult?.cacheHit == true)
    }

    func testQuoteAndCodeGuardAppliedAtDiscoveryNotOnlyMutation() {
        for text in ["Kutipan 'menjaga menjaga bukti'.", "Kutipan «wajib wajib hadir».",
                     "`Penyedia menjaga menjaga bukti.`", "```\nPenyedia wajib wajib hadir.\n```",
                     "```\nPenyedia wajib wajib hadir.", "Kutipan ‘akan ditentukan’." ] {
            XCTAssertTrue(LegalReviewSignalPlanner().build(text).local.isEmpty, text)
        }
    }

    private func makeVM(generator: @escaping LegalReviewAgent.Generator) -> AIConnectorViewModel {
        AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            legalReviewGenerator: generator, legalReviewRoute: { _, _, _ in
                .init(needsHybrid: false, reason: "offline integration test", lexicalQueries: 0, cacheHit: false)
            })
    }
    private func turn(_ messages: [Chat.Message], verdict: String) throws -> LegalReviewAgent.Turn {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(messages.dropFirst().first?.content).utf8)) as? [String: Any])
        let pairs = try XCTUnwrap(payload["pairs"] as? [[String: String]])
        let decisions: [[String: Any]] = pairs.map {
            ["pair_id": $0["id"] ?? "", "verdict": verdict, "evidence_ids": [$0["first_id"] ?? "", $0["second_id"] ?? ""]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["function": ["name": "submit_review", "arguments": ["decisions": decisions]]])
        let call = try JSONDecoder().decode(ToolCall.self, from: data)
        return .init(text: "", calls: [call], stopReason: "stop", promptTokens: 200, outputTokens: 80)
    }
    private func projection(_ vm: AIConnectorViewModel) -> [String] {
        (vm.editorSuggestions.map { "\($0.sourceRange)|\($0.original)|\($0.replacement)|\($0.reason)" }
         + vm.reviewAnnotations.map { "\($0.sourceRange)|\($0.original)|\($0.reason)|\($0.relatedEvidence.map(\.original))" }).sorted()
    }
    private func finish(_ vm: AIConnectorViewModel) async throws { try await until { !vm.isRunning }; await vm.flowBenchmarkAwaitCompletion() }
    private func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<1500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out waiting for integrated review"); throw LegalReviewAgent.Failure.timeBudget
    }
}

@MainActor private final class ReviewIntegrationEditorState {
    var text: String; var rich: Data?; var structured: StructuredDocument?
    init(_ text: String) { self.text = text }
}
