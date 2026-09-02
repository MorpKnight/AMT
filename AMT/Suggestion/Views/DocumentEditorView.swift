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
                    HighlightedDocumentTextEditor(
                        text: $activeDocument.content,
                        suggestions: editorSuggestions,
                        selectedSuggestionID: selectedEditorSuggestionID,
                        onSelect: { id in
                            handleReviewSelection(id)
                        },
                        onTextEdited: { text in
                            aiConnectorViewModel.resetInputMetadata()
                            reviewViewModel.updateDraftText(text)
                        },
                        onAccept: { suggestion in
                            handleInlineAccept(suggestion)
                        },
                        onDismiss: { id in
                            handleInlineDismiss(id)
                        }
                    )
                    .accessibilityLabel("Isi dokumen")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let selectedReviewItem = reviewViewModel.selectedReviewItem,
                       let selectedSourceContext = reviewViewModel.selectedReviewContext {
                        DocumentReviewPreviewHighlight(
                            item: selectedReviewItem,
                            context: selectedSourceContext,
                            onDismiss: {
                                handleReviewSelection(nil)
                            }
                        )
                        .padding(16)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                    }

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
                            handleReviewSelection(id)
                        },
                        onAnalyze: {
                            reviewViewModel.analyze()
                        },
                        onAccept: { id in
                            handleReviewAccept(id)
                        },
                        onReject: { id in
                            handleReviewReject(id)
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

    private var editorSuggestions: [EditorSuggestion] {
        let pendingActionableIDs = Set(
            reviewViewModel.reviewItems.compactMap { item in
                item.decision == .pending && item.isActionable ? item.id : nil
            }
        )

        return aiConnectorViewModel.editorSuggestions.filter {
            pendingActionableIDs.contains($0.id)
        }
    }

    private var selectedEditorSuggestionID: UUID? {
        guard let selectedSuggestionID = aiConnectorViewModel.selectedSuggestionID,
              editorSuggestions.contains(where: { $0.id == selectedSuggestionID })
        else {
            return nil
        }
        return selectedSuggestionID
    }

    private func handleReviewSelection(_ id: UUID?) {
        reviewViewModel.selectReviewItem(id)
        aiConnectorViewModel.selectSuggestion(id)
    }

    private func handleReviewAccept(_ id: UUID) {
        guard reviewViewModel.accept(itemID: id) else { return }
        aiConnectorViewModel.dismissSuggestion(id)
    }

    private func handleReviewReject(_ id: UUID) {
        guard reviewViewModel.reject(itemID: id) else { return }
        aiConnectorViewModel.dismissSuggestion(id)
    }

    private func handleInlineAccept(_ suggestion: EditorSuggestion) {
        let delta = suggestion.replacement.utf16.count
            - suggestion.original.utf16.count
        aiConnectorViewModel.reconcileAfterAccept(
            suggestion.id,
            replacementDelta: delta
        )
        _ = reviewViewModel.accept(itemID: suggestion.id)
    }

    private func handleInlineDismiss(_ id: UUID) {
        aiConnectorViewModel.dismissSuggestion(id)
        _ = reviewViewModel.reject(itemID: id)
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
