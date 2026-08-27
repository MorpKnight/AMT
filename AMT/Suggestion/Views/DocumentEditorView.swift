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

    init(
        documents: [DashboardDocument],
        activeDocument: Binding<DashboardDocument>,
        onBackToDashboard: @escaping () -> Void,
        onCreateNewDocument: @escaping () -> Void,
        suggestionService: QwenSuggestionService
    ) {
        self.documents = documents
        self._activeDocument = activeDocument
        self.onBackToDashboard = onBackToDashboard
        self.onCreateNewDocument = onCreateNewDocument
        self.suggestionService = suggestionService
        self._selectedDocumentID = State(initialValue: activeDocument.wrappedValue.id)
        self._aiConnectorViewModel = State(
            initialValue: AIConnectorViewModel(service: suggestionService)
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
                EditorToolbar(documentTitle: $activeDocument.title)
                Divider()

                TextEditor(text: $activeDocument.content)
                    .font(.body)
                    .padding(16)
                    .scrollContentBackground(.visible)

                #if DEBUG
                Divider()
                AIConnectorDebugPanel(
                    documentText: activeDocument.content,
                    viewModel: aiConnectorViewModel
                )
                #endif
            }
            .navigationTitle("")
        }
        .navigationTitle("")
        .onChange(of: selectedDocumentID) { _, newID in
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
    }
}

#Preview {
    DocumentEditorView(
        documents: [DashboardDocument(title: "Untitled", content: "Sample")],
        activeDocument: .constant(DashboardDocument(title: "Untitled", content: "Sample")),
        onBackToDashboard: {},
        onCreateNewDocument: {},
        suggestionService: QwenSuggestionService()
    )
}
