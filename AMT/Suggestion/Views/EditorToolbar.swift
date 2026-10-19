//
//  EditorToolbar.swift
//  AMT
//

import AppKit
import SwiftUI

enum TextStyle: String, CaseIterable, Identifiable {
    case body = "Paragraph"
    case heading1 = "H1"
    case heading2 = "H2"
    case heading3 = "H3"

    var id: String { rawValue }
}

enum ListStyle: String, CaseIterable, Identifiable {
    case bulleted = "list.bullet"
    case numbered = "list.number"

    var id: String { rawValue }
}

enum DocumentPresentationMode: String, CaseIterable, Identifiable {
    case preview
    case editing

    var id: Self { self }
    var title: String {
        switch self {
        case .preview: "Dokumen Asli"
        case .editing: "Review & Edit"
        }
    }
}

// MARK: - Floating Controls (Font Size & Zoom Pills)

struct EditorFloatingControls: View {
    let viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Font Size Pill: [ A  18pt  A ]
            HStack(spacing: 8) {
                Button {
                    viewModel.decreaseFontSize()
                } label: {
                    Text("A")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.fontSizePoints > EditorViewModel.minimumFontSize ? Color.textPrimary : Color.textSecondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.fontSizePoints <= EditorViewModel.minimumFontSize)
                .help("Perkecil ukuran font")

                Text("\(Int(viewModel.fontSizePoints))pt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(minWidth: 32)

                Button {
                    viewModel.increaseFontSize()
                } label: {
                    Text("A")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(viewModel.fontSizePoints < EditorViewModel.maximumFontSize ? Color.textPrimary : Color.textSecondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.fontSizePoints >= EditorViewModel.maximumFontSize)
                .help("Perbesar ukuran font")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Zoom Pill: [ (-)  10%  (+) ]
            HStack(spacing: 8) {
                Button {
                    viewModel.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.zoomPercent > EditorZoom.minimumPercent ? Color.textPrimary : Color.textSecondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.zoomPercent <= EditorZoom.minimumPercent)
                .help("Zoom out (⌘−)")
                .keyboardShortcut("-", modifiers: .command)

                Button {
                    viewModel.resetZoom()
                } label: {
                    Text("\(viewModel.zoomPercent)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .frame(minWidth: 36)
                }
                .buttonStyle(.plain)
                .help("Reset zoom (⌘0)")
                .keyboardShortcut("0", modifiers: .command)

                Button {
                    viewModel.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.zoomPercent < EditorZoom.maximumPercent ? Color.textPrimary : Color.textSecondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.zoomPercent >= EditorZoom.maximumPercent)
                .help("Zoom in (⌘+)")
                .keyboardShortcut("=", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    @Binding var documentTitle: String
    @Binding var presentationMode: DocumentPresentationMode
    let viewModel: EditorViewModel
    let canPreviewOriginal: Bool
    let saveState: DocumentSaveState
    let reviewNeedsRerun: Bool
    let aiConnectorViewModel: AIConnectorViewModel?
    var isRightSidebarVisible: Bool = true
    var onToggleRightSidebar: () -> Void = {}
    var onRetrySave: () -> Void = {}
    var onExport: (() -> Void)?
    var onRerun: () -> Void = {}
    var onRerunSection: () -> Void = {}
    var onRerunFull: () -> Void = {}

    init(
        documentTitle: Binding<String>,
        presentationMode: Binding<DocumentPresentationMode>,
        viewModel: EditorViewModel,
        canPreviewOriginal: Bool,
        saveState: DocumentSaveState,
        reviewNeedsRerun: Bool,
        isRightSidebarVisible: Bool = true,
        onToggleRightSidebar: @escaping () -> Void = {},
        onRetrySave: @escaping () -> Void = {},
        onExport: (() -> Void)? = nil,
        aiConnectorViewModel: AIConnectorViewModel? = nil,
        onRerun: @escaping () -> Void = {},
        onRerunSection: @escaping () -> Void = {},
        onRerunFull: @escaping () -> Void = {}
    ) {
        self._documentTitle = documentTitle
        self._presentationMode = presentationMode
        self.viewModel = viewModel
        self.canPreviewOriginal = canPreviewOriginal
        self.saveState = saveState
        self.reviewNeedsRerun = reviewNeedsRerun
        self.isRightSidebarVisible = isRightSidebarVisible
        self.onToggleRightSidebar = onToggleRightSidebar
        self.onRetrySave = onRetrySave
        self.onExport = onExport
        self.aiConnectorViewModel = aiConnectorViewModel
        self.onRerun = onRerun
        self.onRerunSection = onRerunSection
        self.onRerunFull = onRerunFull
    }

    var body: some View {
        HStack(spacing: 16) {
            documentTitleField

            Spacer()

            if presentationMode == .editing, let aiConnectorViewModel {
                analysisButton(for: aiConnectorViewModel)
            }

            exportButton

            if presentationMode == .editing {
                toggleRightSidebarButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var documentTitleField: some View {
        TextField("Untitled", text: $documentTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textPrimary)
            .frame(minWidth: 160, maxWidth: 460, alignment: .leading)
    }

    @ViewBuilder
    private func analysisButton(for viewModel: AIConnectorViewModel) -> some View {
        Menu {
            Button("Periksa ulang") { onRerun() }
                .disabled(!viewModel.canRerunAnalysis)
            Button("Periksa bagian ini") { onRerunSection() }
                .disabled(!viewModel.canRerunSelectedSection)
            Divider()
            Button("Periksa seluruh dokumen dari awal") { onRerunFull() }
        } label: {
            HStack(spacing: 5) {
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                Text("Analisis")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.textPrimary)
        } primaryAction: {
            if viewModel.isRunning {
                viewModel.cancel()
            } else {
                onRerun()
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Analisis Dokumen")
    }

    private var exportButton: some View {
        Button {
            onExport?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                Text("Export")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.textPrimary)
        }
        .buttonStyle(.plain)
        .help("Ekspor Dokumen (.docx)")
    }

    private var toggleRightSidebarButton: some View {
        Button {
            onToggleRightSidebar()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14))
                .foregroundStyle(isRightSidebarVisible ? Color.textPrimary : Color.textSecondary)
        }
        .buttonStyle(.plain)
        .help(isRightSidebarVisible ? "Sembunyikan Panel Saran" : "Tampilkan Panel Saran")
    }
}

#Preview {
    ZStack {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            EditorToolbar(
                documentTitle: .constant("PERJANJIAN KERAHASIAAN BERSAMA"),
                presentationMode: .constant(.editing),
                viewModel: EditorViewModel(),
                canPreviewOriginal: true,
                saveState: .saved(Date()),
                reviewNeedsRerun: false
            )

            EditorFloatingControls(viewModel: EditorViewModel())
        }
    }
    .frame(width: 850, height: 160)
}
