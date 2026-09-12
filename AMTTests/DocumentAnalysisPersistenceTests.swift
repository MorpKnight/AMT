import Foundation
import XCTest
@testable import AMT

@MainActor
final class DocumentAnalysisPersistenceTests: XCTestCase {
    func testMatchingSnapshotRestoresSuggestionsWithoutStartingAnalysis() {
        let documentText = "Pihak Kedua wajib untuk membayar."
        let service = QwenSuggestionService()
        let dictionaryStore = LegalDictionaryStore(entries: [])
        let viewModel = AIConnectorViewModel(
            service: service,
            dictionaryStore: dictionaryStore
        )
        let suggestionRange = (documentText as NSString).range(of: "wajib untuk")
        let suggestion = EditorSuggestion(
            id: UUID(),
            sourceRange: suggestionRange,
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            reason: "Perbaikan tata bahasa.",
            origin: .deterministic
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(documentText),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(timeIntervalSince1970: 123),
            editorSuggestions: [suggestion]
        )

        XCTAssertTrue(
            viewModel.restoreAnalysisSnapshot(
                snapshot,
                documentText: documentText
            )
        )
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.state, .completed)
        XCTAssertEqual(viewModel.editorSuggestions, [suggestion])
    }

    func testSnapshotWithDifferentPipelineProfileIsNotRestored() {
        let documentText = "Pihak Kedua wajib untuk membayar."
        let service = QwenSuggestionService()
        let dictionaryStore = LegalDictionaryStore(entries: [])
        let viewModel = AIConnectorViewModel(
            service: service,
            dictionaryStore: dictionaryStore
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(documentText),
            analysisProfile: AIConnectorAnalysisProfile(
                pipelineVersion: "obsolete-pipeline",
                reviewMode: .hybrid,
                modelVariant: .qwen35Base4B,
                thinkingEnabled: false,
                generationProfilePreset: .greedy,
                corpusVersion: "test-corpus",
                semanticModelRevision: "test-revision",
                semanticEmbeddingSchema: "test-schema",
                semanticRetrievalProfile: "test-profile"
            ),
            completedAt: Date(timeIntervalSince1970: 456),
            editorSuggestions: []
        )

        XCTAssertFalse(
            viewModel.restoreAnalysisSnapshot(
                snapshot,
                documentText: documentText
            )
        )
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertTrue(viewModel.editorSuggestions.isEmpty)
    }

    func testDocumentLifecycleAnalyzeSaveLeaveAndReopen() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AMTTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageManager = DocumentStorageManager(storageDirectoryURL: tempDir)
        let fileURL = tempDir.appendingPathComponent("test.txt")
        let docText = "Pihak Kedua wajib untuk membayar dan kata kedua adalah adalah salah."
        try Data(docText.utf8).write(to: fileURL)

        let imported = await storageManager.importDocument(at: fileURL)
        let docID: UUID
        switch imported {
        case let .imported(doc): docID = doc.id
        default: XCTFail("Import failed"); return
        }

        let service = QwenSuggestionService()
        let dictionaryStore = LegalDictionaryStore(entries: [])
        let viewModel = AIConnectorViewModel(service: service, dictionaryStore: dictionaryStore)

        let firstLoc = (docText as NSString).range(of: "wajib untuk").location
        let secondLoc = (docText as NSString).range(of: "adalah adalah").location
        let sug1 = EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: firstLoc, length: 11),
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            reason: "r",
            origin: .deterministic
        )
        let sug2 = EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: secondLoc, length: 13),
            original: "adalah adalah",
            replacement: "adalah",
            category: .grammar,
            reason: "r",
            origin: .deterministic
        )

        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(docText),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(),
            editorSuggestions: [sug1, sug2]
        )

        let currentDoc = storageManager.documents.first { $0.id == docID }!
        let saveResult = await storageManager.saveAnalysisSnapshot(snapshot, for: currentDoc)
        guard case let .success(savedDoc) = saveResult else {
            XCTFail("saveAnalysisSnapshot failed")
            return
        }
        XCTAssertNotNil(savedDoc.analysisSnapshot)

        // Simulate leave document editor: flush pending save
        _ = await storageManager.flushPendingSave(for: docID)

        // Simulate reopen document:
        let reloadedDoc = storageManager.documents.first { $0.id == docID }!
        XCTAssertNotNil(reloadedDoc.analysisSnapshot, "Document snapshot should not be nil after reload")

        let reopenVM = AIConnectorViewModel(service: service, dictionaryStore: dictionaryStore)
        let restored = reopenVM.restoreAnalysisSnapshot(reloadedDoc.analysisSnapshot!, documentText: reloadedDoc.content)
        XCTAssertTrue(restored, "restoreAnalysisSnapshot should succeed on reloaded document")
        XCTAssertEqual(reopenVM.editorSuggestions.count, 2)
    }

    func testDocumentLifecycleAcceptSuggestionLeaveAndReopen() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AMTTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageManager = DocumentStorageManager(storageDirectoryURL: tempDir)
        let fileURL = tempDir.appendingPathComponent("test.txt")
        let docText = "Pihak Kedua wajib untuk membayar dan kata kedua adalah adalah salah."
        try Data(docText.utf8).write(to: fileURL)

        let imported = await storageManager.importDocument(at: fileURL)
        let docID: UUID
        switch imported {
        case let .imported(doc): docID = doc.id
        default: XCTFail("Import failed"); return
        }

        let service = QwenSuggestionService()
        let dictionaryStore = LegalDictionaryStore(entries: [])
        let viewModel = AIConnectorViewModel(service: service, dictionaryStore: dictionaryStore)

        let firstLoc = (docText as NSString).range(of: "wajib untuk").location
        let secondLoc = (docText as NSString).range(of: "adalah adalah").location
        let sug1 = EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: firstLoc, length: 11),
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            reason: "r",
            origin: .deterministic
        )
        let sug2 = EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: secondLoc, length: 13),
            original: "adalah adalah",
            replacement: "adalah",
            category: .grammar,
            reason: "r",
            origin: .deterministic
        )

        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(docText),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(),
            editorSuggestions: [sug1, sug2]
        )

        var currentDoc = storageManager.documents.first { $0.id == docID }!
        let saveResult = await storageManager.saveAnalysisSnapshot(snapshot, for: currentDoc)
        guard case let .success(savedDoc) = saveResult else {
            XCTFail("saveAnalysisSnapshot failed")
            return
        }
        currentDoc = savedDoc
        XCTAssertTrue(viewModel.restoreAnalysisSnapshot(snapshot, documentText: docText))

        // Step 1: User accepts sug1
        let updatedText = (docText as NSString).replacingCharacters(
            in: sug1.sourceRange,
            with: sug1.replacement
        )
        currentDoc.content = updatedText

        // In DashboardView: activeDocument = storageManager.updateDraft(updatedDocument)
        currentDoc = storageManager.updateDraft(currentDoc)

        // In HighlightedDocumentTextEditor: onSuggestionAccepted -> reconcileAfterAccept
        XCTAssertTrue(
            viewModel.reconcileAfterAccept(
                sug1,
                previousText: docText,
                updatedText: updatedText
            )
        )

        // In DashboardView: persistReviewState(for: currentDoc)
        let newSnapshot = try XCTUnwrap(viewModel.makeAnalysisSnapshot(documentText: currentDoc.content))
        let persistResult = await storageManager.saveAnalysisSnapshot(newSnapshot, for: currentDoc)
        guard case let .success(persistedDoc) = persistResult else {
            XCTFail("persistReviewState saveAnalysisSnapshot failed: \(persistResult)")
            return
        }
        currentDoc = persistedDoc

        // Step 2: User leaves document editor (flush pending save)
        _ = await storageManager.flushPendingSave(for: docID)

        // Step 3: User reopens document
        let reloadedDoc = storageManager.documents.first { $0.id == docID }!
        XCTAssertNotNil(reloadedDoc.analysisSnapshot, "Document snapshot should not be nil after accept + reload")

        let reopenVM = AIConnectorViewModel(service: service, dictionaryStore: dictionaryStore)
        let restored = reopenVM.restoreAnalysisSnapshot(reloadedDoc.analysisSnapshot!, documentText: reloadedDoc.content)
        XCTAssertTrue(restored, "restoreAnalysisSnapshot should succeed on reloaded document after accept")
        XCTAssertEqual(reopenVM.editorSuggestions.count, 1)
        XCTAssertEqual(reopenVM.editorSuggestions[0].id, sug2.id)
    }
}
