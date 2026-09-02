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
    let originalSourceURL: URL?
    
    private let suggestionService: QwenSuggestionService
    
    @State private var selectedDocumentID: UUID?
    @State private var aiConnectorViewModel: AIConnectorViewModel
    @State private var isDebugPanelPresented = false
    @State private var editorViewModel = EditorViewModel()
    @State private var presentationMode: DocumentPresentationMode

    init(
        documents: [DashboardDocument],
        activeDocument: Binding<DashboardDocument>,
        onBackToDashboard: @escaping () -> Void,
        onCreateNewDocument: @escaping () -> Void,
        originalSourceURL: URL?,
        suggestionService: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore,
        aiConnectorViewModel: AIConnectorViewModel? = nil
    ) {
        self.documents = documents
        self._activeDocument = activeDocument
        self.onBackToDashboard = onBackToDashboard
        self.onCreateNewDocument = onCreateNewDocument
        self.originalSourceURL = originalSourceURL
        self.suggestionService = suggestionService
        self._selectedDocumentID = State(initialValue: activeDocument.wrappedValue.id)
        self._aiConnectorViewModel = State(
            initialValue: aiConnectorViewModel ?? AIConnectorViewModel(
                service: suggestionService,
                dictionaryStore: dictionaryStore
            )
        )
        self._presentationMode = State(
            initialValue: .editing
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
                    presentationMode: $presentationMode,
                    viewModel: editorViewModel,
                    canPreviewOriginal: false,
                    onExport: {
                        if let structuredDocument = activeDocument.structuredDocument {
                            DocumentExporter.exportAsDocx(title: activeDocument.title, document: structuredDocument)
                        } else {
                            DocumentExporter.exportAsDocx(title: activeDocument.title, content: activeDocument.content)
                        }
                    }
                )

                GeometryReader { proxy in
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)
                            .ignoresSafeArea()

                        if presentationMode == .preview,
                           let originalSourceURL {
                            WordDocumentPreview(sourceURL: originalSourceURL)
                                .frame(
                                    width: min(max(proxy.size.width - 48, 360), 1120),
                                    height: max(proxy.size.height - 32, 320)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
                        } else {
                            HighlightedDocumentTextEditor(
                                documentID: activeDocument.id,
                                text: $activeDocument.content,
                                richTextData: $activeDocument.richTextData,
                                structuredDocument: $activeDocument.structuredDocument,
                                zoomPercent: $editorViewModel.zoomPercent,
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
                                },
                                formattingViewModel: editorViewModel
                            )
                            .frame(
                                width: min(max(proxy.size.width - 80, 360), 920),
                                height: max(proxy.size.height - 48, 320)
                            )
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
                        }
                    }
                }
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
            presentationMode = .editing
            editorViewModel.resetZoom()
            editorViewModel.resetHistoryState()
        }
        .task(id: activeDocument.id) {
            // Older records may already have semantic blocks but no embedded
            // fidelity payload. Rebuild those once from the native RTF (or
            // Markdown/plain text fallback) and then keep the migrated result.
            guard activeDocument.structuredDocument?.richTextData == nil else { return }
            let payload = DocumentRenderNormalizer.migrate(
                content: activeDocument.content,
                richTextData: activeDocument.richTextData,
                sourceFileName: activeDocument.importedSourceFileName,
                sourceURL: originalSourceURL
            )
            activeDocument.structuredDocument = payload.structuredDocument
            activeDocument.richTextData = payload.richTextData ?? activeDocument.richTextData
            activeDocument.content = payload.plainText
        }
    }
}

#Preview {
    DocumentEditorView(
        documents: [DashboardDocument(title: "Untitled", content: "Sample")],
        activeDocument: .constant(DashboardDocument(title: "Untitled", content: "Samplsdfsafsdafe")),
        onBackToDashboard: {},
        onCreateNewDocument: {},
        originalSourceURL: nil,
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
