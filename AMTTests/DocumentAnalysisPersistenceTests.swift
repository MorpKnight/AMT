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
}
