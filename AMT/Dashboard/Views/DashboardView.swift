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
    @State private var selectedDocumentID: UUID?

    let suggestionService: QwenSuggestionService
    let dictionaryStore: LegalDictionaryStore

    @State private var documentViewModels: [UUID: AIConnectorViewModel] = [:]
    @State private var analyzingDocument: DashboardDocument?
    @State private var aiConnectorViewModel: AIConnectorViewModel?
    @State private var documentNotice: DocumentNotice?
    @State private var pendingDeletionDocument: DashboardDocument?
    @Environment(\.scenePhase) private var scenePhase

    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

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
                DocumentEditorView(
                    documents: storageManager.documents,
                    activeDocument: Binding(
                        get: { document },
                        set: { updatedDocument in
                            guard updatedDocument.id == document.id else {
                                openDocument(updatedDocument)
                                return
                            }
                            activeDocument = storageManager.updateDraft(updatedDocument)
                        }
                    ),
                    selectedDocumentID: $selectedDocumentID,
                    onBackToDashboard: leaveDocumentEditor,
                    onImportDocument: importDocumentFromFinder,
                    onSelectDocument: openDocument,
                    originalSourceURL: storageManager.importedSourceURL(for: document),
                    saveState: storageManager.saveState(for: document),
                    reviewNeedsRerun: document.analysisSnapshot == nil,
                    onRetrySave: {
                        storageManager.retrySave(for: document.id)
                    },
                    onExport: {
                        requestExport(for: document)
                    },
                    onReviewStateChanged: {
                        persistReviewState(for: document)
                    },
                    onRerun: {
                        aiConnectorViewModel?.rerunIncrementally(
                            documentText: activeDocument?.content ?? document.content,
                            structuredDocument: activeDocument?.structuredDocument ?? document.structuredDocument
                        )
                    },
                    onRerunSection: {
                        aiConnectorViewModel?.rerunSelectedSection(
                            documentText: activeDocument?.content ?? document.content,
                            structuredDocument: activeDocument?.structuredDocument ?? document.structuredDocument
                        )
                    },
                    onRerunFull: {
                        aiConnectorViewModel?.rerunFullFresh(
                            documentText: activeDocument?.content ?? document.content,
                            structuredDocument: activeDocument?.structuredDocument ?? document.structuredDocument
                        )
                    },
                    suggestionService: suggestionService,
                    dictionaryStore: dictionaryStore,
                    aiConnectorViewModel: aiConnectorViewModel
                )
            } else {
                NavigationSplitView(columnVisibility: $sidebarVisibility) {
                    DashboardSidebar(selectedTab: $selectedTab)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
                        .navigationTitle("")
                } detail: {
                    switch selectedTab {
                    case .document, .none:
                        if let vm = aiConnectorViewModel,
                           analyzingDocument != nil,
                           vm.isRunning {
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
                .navigationSplitViewStyle(.prominentDetail)
                .navigationTitle("")
            }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 600)
        .alert(item: $documentNotice) { notice in
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

            if let retryDocumentID = notice.retryDocumentID {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Coba Lagi")) {
                        storageManager.retrySave(for: retryDocumentID)
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
        .confirmationDialog(
            "Hapus Dokumen?",
            isPresented: Binding(
                get: { pendingDeletionDocument != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletionDocument = nil }
                }
            )
        ) {
            Button("Hapus Permanen", role: .destructive) {
                guard let document = pendingDeletionDocument else { return }
                pendingDeletionDocument = nil
                deleteDocument(document)
            }
            Button("Batal", role: .cancel) {
                pendingDeletionDocument = nil
            }
        } message: {
            Text("Yang dihapus hanya workspace AMT dan salinan sumber lokal. File asli di lokasi awal tetap ada.")
        }
        .onChange(of: aiConnectorViewModel?.isRunning) { _, isRunning in
            guard isRunning == false,
                  let viewModel = aiConnectorViewModel,
                  viewModel.state == .completed,
                  let document = activeDocument ?? analyzingDocument else { return }
            finishAnalysis(for: document, with: viewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { @MainActor in
                await storageManager.flushAllPendingSaves()
            }
        }
    }

    private func startAnalyzingDocument(_ document: DashboardDocument) {
        let viewModel = AIConnectorViewModel(
            service: suggestionService,
            dictionaryStore: dictionaryStore
        )
        documentViewModels[document.id] = viewModel
        aiConnectorViewModel = viewModel
        analyzingDocument = document
        selectedDocumentID = document.id
        withAnimation(.easeInOut(duration: 0.22)) {
            activeDocument = document
        }
        viewModel.run(
            documentText: document.content,
            structuredDocument: document.structuredDocument
        )
    }

    private func finishAnalysis(
        for document: DashboardDocument,
        with viewModel: AIConnectorViewModel
    ) {
        Task { @MainActor in
            var analyzedDocument = storageManager.documents.first {
                $0.id == document.id
            } ?? activeDocument ?? document

            if let snapshot = viewModel.makeAnalysisSnapshot(documentText: analyzedDocument.content) {
                switch await storageManager.saveAnalysisSnapshot(snapshot, for: analyzedDocument) {
                case let .success(persistedDocument):
                    analyzedDocument = persistedDocument
                case let .failure(error) where error != .cancelled:
                    presentStorageError(error, retryDocumentID: document.id)
                case .failure:
                    break
                }
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                activeDocument = analyzedDocument
                analyzingDocument = nil
            }
        }
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
            documentNotice = DocumentNotice(
                title: title,
                message: message,
                existingDocument: existing
            )
        case .cancelled:
            break
        case let .failed(message):
            documentNotice = DocumentNotice(
                title: "Impor dokumen gagal",
                message: message,
                existingDocument: nil
            )
        }
    }

    private func openDocument(_ document: DashboardDocument) {
        if let currentDocument = activeDocument,
           currentDocument.id != document.id {
            let previousViewModel = aiConnectorViewModel
            previousViewModel?.cancel()
            Task { @MainActor in
                if let previousViewModel,
                   let snapshot = previousViewModel.makeAnalysisSnapshot(documentText: currentDocument.content) {
                    _ = await storageManager.saveAnalysisSnapshot(snapshot, for: currentDocument)
                }
                let result = await storageManager.flushPendingSave(for: currentDocument.id)
                if case let .failure(error) = result, error != .cancelled {
                    presentStorageError(error, retryDocumentID: currentDocument.id)
                }
                documentViewModels.removeValue(forKey: currentDocument.id)
                openDocumentImmediately(document)
            }
        } else {
            openDocumentImmediately(document)
        }
    }

    private func openDocumentImmediately(_ requestedDocument: DashboardDocument) {
        let document = storageManager.documents.first {
            $0.id == requestedDocument.id
        } ?? requestedDocument
        let viewModel = documentViewModels[document.id]
            ?? AIConnectorViewModel(
                service: suggestionService,
                dictionaryStore: dictionaryStore
            )

        if let snapshot = document.analysisSnapshot,
           !viewModel.restoreAnalysisSnapshot(snapshot, documentText: document.content) {
            viewModel.resetInputMetadata()
        } else if document.analysisSnapshot == nil {
            viewModel.resetInputMetadata()
        }

        documentViewModels[document.id] = viewModel
        aiConnectorViewModel = viewModel
        analyzingDocument = nil
        selectedDocumentID = document.id
        withAnimation(.easeInOut(duration: 0.22)) {
            activeDocument = document
        }
    }

    private func leaveDocumentEditor() {
        guard let currentDocument = activeDocument else {
            activeDocument = nil
            analyzingDocument = nil
            aiConnectorViewModel = nil
            return
        }

        let currentViewModel = aiConnectorViewModel
        currentViewModel?.cancel()
        Task { @MainActor in
            if let currentViewModel,
               let snapshot = currentViewModel.makeAnalysisSnapshot(documentText: currentDocument.content) {
                _ = await storageManager.saveAnalysisSnapshot(snapshot, for: currentDocument)
            }
            let result = await storageManager.flushPendingSave(for: currentDocument.id)
            if case let .failure(error) = result, error != .cancelled {
                presentStorageError(error, retryDocumentID: currentDocument.id)
            }
            documentViewModels.removeValue(forKey: currentDocument.id)
            withAnimation(.easeInOut(duration: 0.22)) {
                activeDocument = nil
                analyzingDocument = nil
                aiConnectorViewModel = nil
                selectedDocumentID = nil
            }
        }
    }

    private func persistReviewState(for document: DashboardDocument) {
        guard let viewModel = aiConnectorViewModel,
              let currentDocument = activeDocument,
              currentDocument.id == document.id,
              let snapshot = viewModel.makeAnalysisSnapshot(
                  documentText: currentDocument.content
              ) else {
            return
        }

        Task { @MainActor in
            switch await storageManager.saveAnalysisSnapshot(snapshot, for: currentDocument) {
            case let .success(persistedDocument):
                activeDocument = persistedDocument
            case let .failure(error) where error != .cancelled:
                presentStorageError(error, retryDocumentID: document.id)
            case .failure:
                break
            }
        }
    }

    private func deleteDocument(_ document: DashboardDocument) {
        Task { @MainActor in
            switch await storageManager.deleteDocument(document) {
            case .success:
                if activeDocument?.id == document.id {
                    activeDocument = nil
                    aiConnectorViewModel = nil
                    selectedDocumentID = nil
                }
                documentViewModels.removeValue(forKey: document.id)
            case let .failure(error):
                presentStorageError(error)
            }
        }
    }

    private func requestExport(for document: DashboardDocument) {
        Task { @MainActor in
            switch await storageManager.flushPendingSave(for: document.id) {
            case let .success(savedDocument):
                let currentDocument = storageManager.documents.first {
                    $0.id == savedDocument.id
                } ?? savedDocument
                export(currentDocument)
            case let .failure(error) where error != .cancelled:
                presentStorageError(error, retryDocumentID: document.id)
            case .failure:
                break
            }
        }
    }

    private func export(_ document: DashboardDocument) {
        let completion: (Result<URL, DocumentExportError>) -> Void = { result in
            switch result {
            case let .success(url):
                documentNotice = DocumentNotice(
                    title: "Ekspor berhasil",
                    message: "Hasil review disimpan di:\n\(url.path)",
                    existingDocument: nil
                )
            case .failure(.cancelled):
                break
            case let .failure(error):
                documentNotice = DocumentNotice(
                    title: "Ekspor gagal",
                    message: error.localizedDescription,
                    existingDocument: nil
                )
            }
        }

        if let structuredDocument = document.structuredDocument {
            DocumentExporter.exportAsDocx(
                title: document.title,
                document: structuredDocument,
                completion: completion
            )
        } else {
            DocumentExporter.exportAsDocx(
                title: document.title,
                content: document.content,
                completion: completion
            )
        }
    }

    private func presentStorageError(
        _ error: DocumentStorageError,
        retryDocumentID: UUID? = nil
    ) {
        guard error != .cancelled else { return }
        documentNotice = DocumentNotice(
            title: "Penyimpanan lokal gagal",
            message: error.localizedDescription,
            existingDocument: nil,
            retryDocumentID: retryDocumentID
        )
    }

    // MARK: - Document Grid Dashboard View

    private var documentDashboardContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Document")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

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

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ImportDocumentCardView {
                        importDocumentFromFinder()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    ForEach(filteredDocuments) { document in
                        DocumentCardView(
                            document: document,
                            onSelect: {
                                openDocument(document)
                            },
                            onExport: {
                                requestExport(for: document)
                            },
                            onDelete: {
                                pendingDeletionDocument = document
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

private struct DocumentNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let existingDocument: DashboardDocument?
    let retryDocumentID: UUID?

    init(
        title: String,
        message: String,
        existingDocument: DashboardDocument?,
        retryDocumentID: UUID? = nil
    ) {
        self.title = title
        self.message = message
        self.existingDocument = existingDocument
        self.retryDocumentID = retryDocumentID
    }
}

#Preview {
    DashboardView(
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
