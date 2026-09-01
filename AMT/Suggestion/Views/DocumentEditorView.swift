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

    private let suggestionService: QwenSuggestionService

    @State private var selectedDocumentID: UUID?
    @State private var aiConnectorViewModel: AIConnectorViewModel
    @State private var isDebugPanelPresented = false

    init(
        documents: [DashboardDocument],
        activeDocument: Binding<DashboardDocument>,
        onBackToDashboard: @escaping () -> Void,
        onCreateNewDocument: @escaping () -> Void,
        suggestionService: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore
    ) {
        self.documents = documents
        self._activeDocument = activeDocument
        self.onBackToDashboard = onBackToDashboard
        self.onCreateNewDocument = onCreateNewDocument
        self.suggestionService = suggestionService
        self._selectedDocumentID = State(initialValue: activeDocument.wrappedValue.id)
        self._aiConnectorViewModel = State(
            initialValue: AIConnectorViewModel(
                service: suggestionService,
                dictionaryStore: dictionaryStore
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
                        DocumentExporter.exportAsDocx(
                            title: activeDocument.title,
                            content: activeDocument.content
                        )
                    },
                    onAnalyze: {
                        aiConnectorViewModel.run(documentText: activeDocument.content)
                    },
                    onCancelAnalysis: {
                        aiConnectorViewModel.cancel()
                    },
                    onShowDebug: {
                        isDebugPanelPresented = true
                    },
                    canAnalyze: aiConnectorViewModel.canRun(
                        documentText: activeDocument.content
                    ),
                    isAnalyzing: aiConnectorViewModel.isRunning,
                    analysisState: aiConnectorViewModel.state,
                    analysisProgressStage: aiConnectorViewModel.progressStage,
                    analysisDownloadProgress: aiConnectorViewModel.downloadProgress,
                    analysisGenerationProgress: aiConnectorViewModel.generationProgress,
                    analysisSummary: aiConnectorViewModel.runSummary,
                    analysisErrorMessage: aiConnectorViewModel.errorMessage
                )
                Divider()

                HighlightedDocumentTextEditor(
                    text: $activeDocument.content,
                    suggestions: aiConnectorViewModel.editorSuggestions,
                    selectedSuggestionID: aiConnectorViewModel.selectedSuggestionID,
                    onSelect: { id in
                        aiConnectorViewModel.selectSuggestion(id)
                    },
                    onTextEdited: {
                        aiConnectorViewModel.resetInputMetadata()
                    },
                    onAccept: { suggestion in
                        let delta = suggestion.replacement.utf16.count
                            - suggestion.original.utf16.count
                        aiConnectorViewModel.reconcileAfterAccept(
                            suggestion.id,
                            replacementDelta: delta
                        )
                    },
                    onDismiss: { id in
                        aiConnectorViewModel.dismissSuggestion(id)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationTitle("")
        .onChange(of: selectedDocumentID) { _, newID in
            aiConnectorViewModel.resetInputMetadata()
            isDebugPanelPresented = false
            if let newID = newID,
               let doc = documents.first(where: { $0.id == newID }) {
                activeDocument = doc
            }
        }
        .onChange(of: activeDocument.id) { _, newID in
            if selectedDocumentID != newID {
                selectedDocumentID = newID
            }
        }
        #if DEBUG
        .sheet(isPresented: $isDebugPanelPresented) {
            AIConnectorDebugPanel(
                documentText: activeDocument.content,
                viewModel: aiConnectorViewModel
            )
            .frame(minWidth: 760, minHeight: 600)
        }
        #endif
    }
}

#Preview {
    DocumentEditorView(
        documents: [DashboardDocument(title: "Untitled", content: "Sample")],
        activeDocument: .constant(DashboardDocument(title: "Untitled", content: "Sample")),
        onBackToDashboard: {},
        onCreateNewDocument: {},
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
