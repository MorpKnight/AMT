//
//  DocumentEditorView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import Foundation
import SwiftUI

struct DocumentEditorView: View {
    let documents: [DashboardDocument]
    @Binding var activeDocument: DashboardDocument
    @Binding var selectedDocumentID: UUID?
    let onBackToDashboard: () -> Void
    let onImportDocument: () -> Void
    let onSelectDocument: (DashboardDocument) -> Void
    let originalSourceURL: URL?
    let saveState: DocumentSaveState
    let reviewNeedsRerun: Bool
    let onRetrySave: () -> Void
    let onExport: () -> Void
    let onReviewStateChanged: () -> Void
    let onRerun: () -> Void
    let onRerunSection: () -> Void
    let onRerunFull: () -> Void
    
    let aiConnectorViewModel: AIConnectorViewModel
    @State private var isDebugPanelPresented = false
    @State private var editorViewModel = EditorViewModel()
    @State private var presentationMode: DocumentPresentationMode
    @State private var showDefinitionMatches = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    init(
        documents: [DashboardDocument],
        activeDocument: Binding<DashboardDocument>,
        selectedDocumentID: Binding<UUID?>? = nil,
        onBackToDashboard: @escaping () -> Void,
        onImportDocument: @escaping () -> Void,
        onSelectDocument: @escaping (DashboardDocument) -> Void,
        originalSourceURL: URL?,
        saveState: DocumentSaveState = .saved(Date()),
        reviewNeedsRerun: Bool = false,
        onRetrySave: @escaping () -> Void = {},
        onExport: @escaping () -> Void = {},
        onReviewStateChanged: @escaping () -> Void = {},
        onRerun: @escaping () -> Void = {},
        onRerunSection: @escaping () -> Void = {},
        onRerunFull: @escaping () -> Void = {},
        suggestionService: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore,
        aiConnectorViewModel: AIConnectorViewModel? = nil
    ) {
        self.documents = documents
        self._activeDocument = activeDocument
        self._selectedDocumentID = selectedDocumentID
            ?? .constant(activeDocument.wrappedValue.id)
        self.onBackToDashboard = onBackToDashboard
        self.onImportDocument = onImportDocument
        self.onSelectDocument = onSelectDocument
        self.originalSourceURL = originalSourceURL
        self.saveState = saveState
        self.reviewNeedsRerun = reviewNeedsRerun
        self.onRetrySave = onRetrySave
        self.onExport = onExport
        self.onReviewStateChanged = onReviewStateChanged
        self.onRerun = onRerun
        self.onRerunSection = onRerunSection
        self.onRerunFull = onRerunFull
        self.aiConnectorViewModel = aiConnectorViewModel ?? AIConnectorViewModel(
            service: suggestionService,
            dictionaryStore: dictionaryStore
        )
        self._presentationMode = State(
            initialValue: .editing
        )
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            EditorSidebar(
                documents: documents,
                selectedDocumentID: $selectedDocumentID,
                onBackToDashboard: onBackToDashboard,
                onImportDocument: onImportDocument
            )
            .navigationSplitViewColumnWidth(min: 270, ideal: 270, max: 270)
            .navigationTitle("")
            
        } detail: {
            VStack(spacing: 0) {
                editorToolbar
                Divider()
                    .overlay(Color.borderSubtle)

                GeometryReader { proxy in
                    ZStack {
                        Color.white

                        if presentationMode == .preview,
                           let originalSourceURL {
                            WordDocumentPreview(sourceURL: originalSourceURL)
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                        } else {
                            editorView(for: proxy)
                        }
                    }
//                    .overlay(alignment: .topTrailing) {
//                        if presentationMode == .editing {
//                            VStack(alignment: .trailing, spacing: 10) {
//                                if !reviewItems.isEmpty
//                                    || !aiConnectorViewModel.definitionMatchAnnotations.isEmpty
//                                    || aiConnectorViewModel.reviewedDocumentFindingCount > 0 {
//                                    ReviewNavigatorView(
//                                        items: reviewItems,
//                                        selectedItemID: aiConnectorViewModel.selectedReviewItemID,
//                                        hasDefinitionMatches: !aiConnectorViewModel.definitionMatchAnnotations.isEmpty,
//                                        showDefinitionMatches: $showDefinitionMatches,
//                                        hasReviewedFindings: aiConnectorViewModel.reviewedDocumentFindingCount > 0,
//                                        showReviewedFindings: Binding(
//                                            get: { aiConnectorViewModel.showReviewedFindings },
//                                            set: { aiConnectorViewModel.setShowReviewedFindings($0) }
//                                        ),
//                                        onPrevious: {
//                                            aiConnectorViewModel.selectPreviousReviewItem(
//                                                includeDefinitionMatches: showDefinitionMatches
//                                            )
//                                        },
//                                        onNext: {
//                                            aiConnectorViewModel.selectNextReviewItem(
//                                                includeDefinitionMatches: showDefinitionMatches
//                                            )
//                                        }
//                                    )
//                                } else if aiConnectorViewModel.state == .completed {
//                                    reviewEmptyState
//                                }
//                            }
//                                .padding(.top, 14)
//                                .padding(.trailing, 14)
//                        }
//                    }


                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("")
        .onChange(of: selectedDocumentID) { _, newID in
            isDebugPanelPresented = false
            showDefinitionMatches = false
            if let newID = newID,
               newID != activeDocument.id,
               let doc = documents.first(where: { $0.id == newID }) {
                onSelectDocument(doc)
            }
        }
        .onChange(of: activeDocument.id) { _, newID in
            if selectedDocumentID != newID {
                selectedDocumentID = newID
            }
            presentationMode = .editing
            editorViewModel.resetZoom()
            editorViewModel.resetFontSizeState()
            editorViewModel.resetHistoryState()
        }
        .task(id: activeDocument.id) {
            // Older records may already have semantic blocks but no embedded
            // fidelity payload. Markdown/plain-text records can also carry an
            // older canonical typography scale. Migrate those once while
            // leaving native Word/RTF typography untouched.
            guard DocumentRenderNormalizer.needsMigration(
                structuredDocument: activeDocument.structuredDocument,
                sourceFileName: activeDocument.importedSourceFileName,
                sourceURL: originalSourceURL
            ) else { return }
            let payload = DocumentRenderNormalizer.migrate(
                content: activeDocument.content,
                richTextData: activeDocument.richTextData,
                sourceFileName: activeDocument.importedSourceFileName,
                sourceURL: originalSourceURL,
                structuredDocument: activeDocument.structuredDocument
            )
            activeDocument.structuredDocument = payload.structuredDocument
            activeDocument.richTextData = payload.richTextData ?? activeDocument.richTextData
            activeDocument.content = payload.plainText
        }
        .onChange(of: showDefinitionMatches) { _, _ in
            aiConnectorViewModel.selectReviewItem(nil)
        }
        .sheet(isPresented: $isDebugPanelPresented) {
            AIConnectorDebugPanel(
                documentText: activeDocument.content,
                viewModel: aiConnectorViewModel
            )
            .frame(minWidth: 760, minHeight: 620)
        }
        .focusedSceneValue(\.showAIConnectorDebugPanel) {
            isDebugPanelPresented = true
        }
        .focusedSceneValue(\.showAIConnectorDefinitionDiagnostics, $showDefinitionMatches)
    }

    private var editorToolbar: some View {
        EditorToolbar(
            documentTitle: $activeDocument.title,
            presentationMode: $presentationMode,
            viewModel: editorViewModel,
            canPreviewOriginal: originalSourceURL != nil,
            saveState: saveState,
            reviewNeedsRerun: reviewNeedsRerun,
            canAdjustFontSize: editorSourceKind.usesCanonicalTypography,
            onRetrySave: onRetrySave,
            onExport: onExport,
            aiConnectorViewModel: aiConnectorViewModel,
            onRerun: onRerun,
            onRerunSection: onRerunSection,
            onRerunFull: onRerunFull
        )
    }

    private var reviewItems: [EditorReviewItem] {
        aiConnectorViewModel.reviewItems(
            includeDefinitionMatches: showDefinitionMatches
        )
    }

    private var displayedReviewAnnotations: [EditorReviewAnnotation] {
        aiConnectorViewModel.visibleReviewAnnotations(
            includeDefinitionMatches: showDefinitionMatches
        )
    }

    private var reviewEmptyState: some View {
        let allItemsIgnored = aiConnectorViewModel.allReviewItemsIgnored
        let hasReviewedItems = aiConnectorViewModel.reviewedDocumentFindingCount > 0
        let baseMessage = allItemsIgnored
            ? "Semua hasil pada pemeriksaan ini telah diabaikan"
            : hasReviewedItems
                ? "Semua temuan aktif sudah diperiksa. Gunakan ‘Tampilkan yang sudah diperiksa’ untuk membukanya kembali."
            : "Tidak ditemukan isu pada pemeriksaan ini. Hasil ini bukan jaminan ketepatan hukum dan tetap memerlukan review profesional."
        let limitationCount = aiConnectorViewModel.skippedSegmentCount
            + aiConnectorViewModel.rejectedReviews.count

        return VStack(alignment: .leading, spacing: 4) {
            Text(baseMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            if limitationCount > 0 {
                Text("\(limitationCount) bagian tidak dapat disimpulkan.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: 360, alignment: .trailing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func editorView(for proxy: GeometryProxy) -> some View {
        HighlightedDocumentTextEditor(
            documentID: activeDocument.id,
            text: $activeDocument.content,
            richTextData: $activeDocument.richTextData,
            structuredDocument: $activeDocument.structuredDocument,
            zoomPercent: $editorViewModel.zoomPercent,
            fontSizePoints: editorViewModel.fontSizePoints,
            sourceKind: editorSourceKind,
            suggestions: aiConnectorViewModel.editorSuggestions,
            annotations: displayedReviewAnnotations,
            definitionResolutions: aiConnectorViewModel.definitionResolutions,
            definitionResolutionLoadingIDs: aiConnectorViewModel.definitionResolutionLoadingIDs,
            reviewedReviewItemIDs: aiConnectorViewModel.reviewedReviewItemIDs,
            selectedReviewItemID: aiConnectorViewModel.selectedReviewItemID,
            onSelect: { id in
                aiConnectorViewModel.selectReviewItem(id)
            },
            onCaretLocationChanged: { location in
                aiConnectorViewModel.updateCaretLocation(location)
            },
            onTextEdited: {
                aiConnectorViewModel.markDocumentEdited(
                    documentText: activeDocument.content,
                    structuredDocument: activeDocument.structuredDocument
                )
            },
            onSuggestionAccepted: { suggestion, previousText, updatedText in
                if !aiConnectorViewModel.reconcileAfterAccept(
                    suggestion,
                    previousText: previousText,
                    updatedText: updatedText
                ) {
                    aiConnectorViewModel.resetInputMetadata()
                }
                onReviewStateChanged()
            },
            onDismiss: { id in
                aiConnectorViewModel.dismissReviewItem(id)
                onReviewStateChanged()
            },
            onMarkReviewed: { id in
                aiConnectorViewModel.markReviewItemReviewed(id)
                onReviewStateChanged()
            },
            onReopenReviewed: { id in
                aiConnectorViewModel.reopenReviewItem(id)
                onReviewStateChanged()
            },
            onRequestDefinitionResolution: { id in
                aiConnectorViewModel.requestDefinitionResolution(for: id)
            },
            onDefinitionResolutionApplied: { option, previousText, updatedText in
                if !aiConnectorViewModel.reconcileAfterDefinitionResolution(
                    option,
                    previousText: previousText,
                    updatedText: updatedText
                ) {
                    aiConnectorViewModel.resetInputMetadata()
                }
                onReviewStateChanged()
            },
            formattingViewModel: editorViewModel
        )
        .frame(
            width: proxy.size.width,
            height: proxy.size.height
        )
        .background(Color.white)
    }

    private var editorSourceKind: StructuredDocument.SourceKind {
        if let sourceKind = activeDocument.structuredDocument?.sourceKind,
           sourceKind != .unknown {
            return sourceKind
        }

        let extensionName = activeDocument.importedSourceFileName
            .map { ($0 as NSString).pathExtension.lowercased() }
        switch extensionName {
        case "docx", "doc", "rtf", "html", "htm":
            return .native
        case "md", "markdown":
            return .markdown
        default:
            return .plainText
        }
    }
}

private struct ReviewNavigatorView: View {
    let items: [EditorReviewItem]
    let selectedItemID: UUID?
    let hasDefinitionMatches: Bool
    @Binding var showDefinitionMatches: Bool
    let hasReviewedFindings: Bool
    @Binding var showReviewedFindings: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == selectedItemID })
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .disabled(items.isEmpty || selectedIndex == 0)
            .accessibilityLabel("Temuan sebelumnya")
            .help("Temuan sebelumnya")

            Text(positionTitle)
                .font(.caption.weight(.medium).monospacedDigit())
                .frame(minWidth: 58)
                .accessibilityLabel("Posisi temuan")

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(items.isEmpty || selectedIndex == items.count - 1)
            .accessibilityLabel("Temuan berikutnya")
            .help("Temuan berikutnya")

            if hasDefinitionMatches {
                Divider()
                    .frame(height: 16)
                Toggle("Definisi selaras", isOn: $showDefinitionMatches)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .help("Tampilkan definisi selaras")
                    .accessibilityLabel("Tampilkan definisi selaras")
            }
            if hasReviewedFindings {
                Divider()
                    .frame(height: 16)
                Toggle("Sudah diperiksa", isOn: $showReviewedFindings)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .help("Tampilkan yang sudah diperiksa")
                    .accessibilityLabel("Tampilkan yang sudah diperiksa")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var positionTitle: String {
        guard let selectedIndex else { return "— dari \(items.count)" }
        return "\(selectedIndex + 1) dari \(items.count)"
    }
}

#Preview {
    DocumentEditorView(
        documents: [DashboardDocument(title: "Untitled", content: "Sample")],
        activeDocument: .constant(DashboardDocument(title: "Untitled", content: "Samplsdfsafsdafe")),
        selectedDocumentID: .constant(nil),
        onBackToDashboard: {},
        onImportDocument: {},
        onSelectDocument: { _ in },
        originalSourceURL: nil,
        saveState: .saved(Date()),
        onRetrySave: {},
        onExport: {},
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
