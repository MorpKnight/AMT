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
                    },
                    onCreateNewDocument: {
                        storageManager.importWordDocumentFromFinder { importedDoc in
                            if let doc = importedDoc {
                                activeDocument = doc
                            }
                        }
                    }
                )
            } else {
                // Main Dashboard Split View
                NavigationSplitView {
                    DashboardSidebar(selectedTab: $selectedTab)
                        .navigationTitle("")
                } detail: {
                    switch selectedTab {
                    case .document, .none:
                        documentDashboardContent
                    case .dictionary:
                        DictionaryView()
                    }
                }
                .navigationTitle("")
            }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 600)
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    // Import Word Document Button Card (+)
                    NewDocumentCardView {
                        storageManager.importWordDocumentFromFinder { importedDoc in
                            if let doc = importedDoc {
                                activeDocument = doc
                            }
                        }
                    }

                    // Existing Document Cards
                    ForEach(filteredDocuments) { doc in
                        DocumentCardView(
                            document: doc,
                            onSelect: {
                                activeDocument = doc
                            },
                            onDelete: {
                                storageManager.deleteDocument(doc)
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    DashboardView()
}
