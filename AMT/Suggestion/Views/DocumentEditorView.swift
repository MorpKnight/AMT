//
//  DocumentEditorView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import SwiftUI

struct DocumentEditorView: View {
    let documents: [DashboardDocument]
    @Binding var activeDocument: DashboardDocument
    let onBackToDashboard: () -> Void
    let onCreateNewDocument: () -> Void
    let originalURLForDocument: (DashboardDocument) -> URL?
    let onPersistReviewSnapshot: (UUID, DocumentReviewSnapshot) -> Void

    private let suggestionService: QwenSuggestionService

    @State private var selectedDocumentID: UUID?
    @State private var aiConnectorViewModel: AIConnectorViewModel
    @State private var reviewViewModel: DocumentReviewViewModel
    @State private var isDebugPanelPresented = false

    init(
        documents: [DashboardDocument],
        activeDocument: Binding<DashboardDocument>,
        onBackToDashboard: @escaping () -> Void,
        onCreateNewDocument: @escaping () -> Void,
        originalURLForDocument: @escaping (DashboardDocument) -> URL?,
        onPersistReviewSnapshot: @escaping (UUID, DocumentReviewSnapshot) -> Void,
        suggestionService: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore
    ) {
        self.documents = documents
        self._activeDocument = activeDocument
        self.onBackToDashboard = onBackToDashboard
        self.onCreateNewDocument = onCreateNewDocument
        self.originalURLForDocument = originalURLForDocument
        self.onPersistReviewSnapshot = onPersistReviewSnapshot
        self.suggestionService = suggestionService
        self._selectedDocumentID = State(initialValue: activeDocument.wrappedValue.id)

        let aiConnectorViewModel = AIConnectorViewModel(
            service: suggestionService,
            dictionaryStore: dictionaryStore
        )
        self._aiConnectorViewModel = State(initialValue: aiConnectorViewModel)
        self._reviewViewModel = State(
            initialValue: DocumentReviewViewModel(
                document: activeDocument.wrappedValue,
                originalURL: originalURLForDocument(activeDocument.wrappedValue),
                analyzer: AIConnectorDocumentReviewAnalyzer(viewModel: aiConnectorViewModel),
                onSnapshotChanged: onPersistReviewSnapshot
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            EditorSidebar(
                documents: documents,
                selectedDocumentID: $selectedDocumentID,
                onBackToDashboard: onBackToDashboard,
                onCreateNewDocument: onCreateNewDocument
            )
            .navigationTitle("")
        } detail: {
            VStack(spacing: 0) {
                EditorToolbar(
                    documentTitle: $activeDocument.title,
                    onExport: {
                        handleExport()
                    },
                    onShowDebug: {
                        isDebugPanelPresented = true
                    },
                    showsFormattingControls: false,
                    canExport: reviewViewModel.canExport
                        || reviewViewModel.sourceAvailability == .legacyText
                )
                Divider()

                ZStack(alignment: .topTrailing) {
                    DocumentSourceViewer(
                        originalURL: reviewViewModel.sourceURL,
                        isOriginalAvailable: reviewViewModel.sourceAvailability.isOriginal,
                        fallbackText: reviewViewModel.sourceText.isEmpty
                            ? activeDocument.content
                            : reviewViewModel.sourceText,
                        notice: reviewViewModel.sourceViewerNotice,
                        selectedReviewItem: reviewViewModel.selectedReviewItem,
                        selectedSourceContext: reviewViewModel.selectedReviewContext,
                        onClearSelectedReview: {
                            reviewViewModel.selectReviewItem(nil)
                        }
                    )

                    DocumentReviewPopover(
                        documentID: reviewViewModel.documentID,
                        analysisStatus: reviewViewModel.analysisStatus,
                        progress: reviewViewModel.progress,
                        progressDetail: reviewViewModel.progressDetail,
                        canAnalyze: reviewViewModel.canAnalyze,
                        errorMessage: reviewViewModel.errorMessage ?? reviewViewModel.exportErrorMessage,
                        reviewItems: reviewViewModel.reviewItems,
                        acceptedItemCount: reviewViewModel.acceptedItemCount,
                        selectedReviewItemID: reviewViewModel.selectedReviewItemID,
                        selectedSourceContext: reviewViewModel.selectedReviewContext,
                        onSelectReview: { id in
                            reviewViewModel.selectReviewItem(id)
                        },
                        onAnalyze: {
                            reviewViewModel.analyze()
                        },
                        onAccept: { id in
                            _ = reviewViewModel.accept(itemID: id)
                        },
                        onReject: { id in
                            _ = reviewViewModel.reject(itemID: id)
                        },
                        onRetry: {
                            reviewViewModel.retryAnalysis()
                        },
                        onCancel: {
                            reviewViewModel.cancel()
                        }
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationTitle("")
        .onChange(of: selectedDocumentID) { _, newID in
            aiConnectorViewModel.resetInputMetadata()
            isDebugPanelPresented = false
            if let newID,
               let doc = documents.first(where: { $0.id == newID }) {
                activeDocument = doc
                reviewViewModel.load(
                    document: doc,
                    originalURL: originalURLForDocument(doc)
                )
            }
        }
        .onChange(of: activeDocument.id) { _, newID in
            if selectedDocumentID != newID {
                selectedDocumentID = newID
            }
        }
        .task(id: activeDocument.id) {
            reviewViewModel.startAutomaticAnalysisIfNeeded()
        }
        #if DEBUG
        .sheet(isPresented: $isDebugPanelPresented) {
            AIConnectorDebugPanel(
                documentText: reviewViewModel.analysisText,
                viewModel: aiConnectorViewModel
            )
            .frame(minWidth: 760, minHeight: 600)
        }
        #endif
    }

    private func handleExport() {
        switch reviewViewModel.sourceAvailability {
        case .original:
            reviewViewModel.exportReviewedDocument(title: activeDocument.title)
        case .legacyText:
            DocumentExporter.exportAsDocx(
                title: activeDocument.title,
                content: activeDocument.content
            )
        case .missing, .changed, .unreadable:
            reviewViewModel.exportReviewedDocument(title: activeDocument.title)
        }
    }
}

#Preview {
    DocumentEditorView(
        documents: [DashboardDocument(title: "Untitled", content: "Sample")],
        activeDocument: .constant(DashboardDocument(title: "Untitled", content: "Sample")),
        onBackToDashboard: {},
        onCreateNewDocument: {},
        originalURLForDocument: { _ in nil },
        onPersistReviewSnapshot: { _, _ in },
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
