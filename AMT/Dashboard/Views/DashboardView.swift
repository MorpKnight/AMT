//
//  DashboardView.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var storageManager = DocumentStorageManager()
    @State private var selectedTab: DashboardTab? = .document
    @State private var searchText = ""
    @State private var activeDocument: DashboardDocument?

    let suggestionService: QwenSuggestionService
    let dictionaryStore: LegalDictionaryStore

    @State private var documentViewModels: [UUID: AIConnectorViewModel] = [:]
    @State private var analyzingDocument: DashboardDocument?
    @State private var aiConnectorViewModel: AIConnectorViewModel?
    @State private var importNotice: DocumentImportNotice?

    private var filteredDocuments: [DashboardDocument] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storageManager.documents
        } else {
            return storageManager.documents.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 24)
    ]

    var body: some View {
        Group {
            if let document = activeDocument {
                // Detail Document Editor View with Document List Sidebar
                DocumentEditorView(
                    documents: storageManager.documents,
                    activeDocument: Binding(
                        get: { document },
                        set: { updatedDoc in
                            activeDocument = updatedDoc
                            storageManager.saveDocument(updatedDoc)
                        }
                    ),
                    onBackToDashboard: {
                        if let currentDoc = activeDocument {
                            storageManager.saveDocument(currentDoc)
                        }
                        activeDocument = nil
                        analyzingDocument = nil
                        aiConnectorViewModel = nil
                    },
                    onCreateNewDocument: {
                        importDocumentFromFinder()
                    },
                    suggestionService: suggestionService,
                    dictionaryStore: dictionaryStore,
                    aiConnectorViewModel: aiConnectorViewModel
                )
            } else {
                // Main Dashboard Split View
                NavigationSplitView {
                    DashboardSidebar(selectedTab: $selectedTab)
                        .navigationTitle("")
                } detail: {
                    switch selectedTab {
                    case .document, .none:
                        if let vm = aiConnectorViewModel, analyzingDocument != nil, vm.isRunning {
                            DocumentAnalysisLoadingView(
                                progress: vm.progressSnapshot,
                                onCancel: {
                                    vm.cancel()
                                }
                            )
                            .transition(.opacity)
                        } else {
                            documentDashboardContent
                        }
                    case .dictionary:
                        DictionaryView(dictionaryStore: dictionaryStore)
                    }
                }
                .navigationTitle("")
            }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 600)
        .alert(item: $importNotice) { notice in
            if let existingDocument = notice.existingDocument {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Buka Dokumen")) {
                        openDocument(existingDocument)
                    },
                    secondaryButton: .cancel(Text("Tutup"))
                )
            }

            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("Tutup"))
            )
        }
        .onChange(of: aiConnectorViewModel?.isRunning) { _, isRunning in
            if isRunning == false, let doc = analyzingDocument {
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.activeDocument = doc
                    self.analyzingDocument = nil
                }
            }
        }
    }

    private func startAnalyzingDocument(_ doc: DashboardDocument) {
        let vm = AIConnectorViewModel(service: suggestionService, dictionaryStore: dictionaryStore)
        self.documentViewModels[doc.id] = vm
        self.aiConnectorViewModel = vm
        self.analyzingDocument = doc
        vm.run(documentText: doc.content)
    }

    private func importDocumentFromFinder() {
        storageManager.importWordDocumentFromFinder { result in
            handleImportResult(result)
        }
    }

    private func handleImportResult(_ result: DocumentImportResult) {
        switch result {
        case let .imported(document):
            startAnalyzingDocument(document)
        case let .duplicate(existing, matchKind):
            let title: String
            let message: String
            switch matchKind {
            case .sourceFile:
                title = "Dokumen sudah diimpor"
                message = "File yang sama sudah tersedia sebagai \(existing.title)."
            case .normalizedContent:
                title = "Konten dokumen sudah tersedia"
                message = "Dokumen dengan konten yang sama sudah tersedia sebagai \(existing.title)."
            }
            importNotice = DocumentImportNotice(
                title: title,
                message: message,
                existingDocument: existing
            )
        case .cancelled:
            break
        case let .failed(message):
            importNotice = DocumentImportNotice(
                title: "Impor dokumen gagal",
                message: message,
                existingDocument: nil
            )
        }
    }

    private func openDocument(_ document: DashboardDocument) {
        let vm = documentViewModels[document.id]
            ?? AIConnectorViewModel(
                service: suggestionService,
                dictionaryStore: dictionaryStore
            )
        documentViewModels[document.id] = vm
        aiConnectorViewModel = vm
        analyzingDocument = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            activeDocument = document
        }
    }

    // MARK: - Document Grid Dashboard View

    private var documentDashboardContent: some View {
        VStack(spacing: 0) {
            // Header Bar (Title & Search)
            HStack {
                Text("Document")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 180)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Documents Grid Section
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    // Import Word Document Button Card (+)
                    NewDocumentCardView {
                        importDocumentFromFinder()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Existing Document Cards
                    ForEach(filteredDocuments) { doc in
                        DocumentCardView(
                            document: doc,
                            onSelect: {
                                openDocument(doc)
                            },
                            onDelete: {
                                storageManager.deleteDocument(doc)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("")
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DocumentImportNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let existingDocument: DashboardDocument?
}

#Preview {
    DashboardView(
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
