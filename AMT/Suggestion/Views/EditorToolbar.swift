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

struct EditorToolbar: View {
    @Binding var documentTitle: String
    @Binding var presentationMode: DocumentPresentationMode
    let viewModel: EditorViewModel
    let canPreviewOriginal: Bool
    let saveState: DocumentSaveState
    let reviewNeedsRerun: Bool
    let canAdjustFontSize: Bool
    let aiConnectorViewModel: AIConnectorViewModel?
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
        canAdjustFontSize: Bool = true,
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
        self.canAdjustFontSize = canAdjustFontSize
        self.aiConnectorViewModel = aiConnectorViewModel
        self.onRetrySave = onRetrySave
        self.onExport = onExport
        self.onRerun = onRerun
        self.onRerunSection = onRerunSection
        self.onRerunFull = onRerunFull
    }

    @State private var linkURLText = ""
    @State private var isLinkPopoverPresented = false

    var body: some View {
        HStack(spacing: 12) {
            documentTitleField
            Spacer()
            fontSizeGroup
            // zoomGroup is intentionally disabled while font-size controls
            // are the only supported enlargement mechanism.
            // zoomGroup
            Spacer()
            if presentationMode == .editing, reviewNeedsRerun {
                Label("Review perlu diulang", systemImage: "arrow.clockwise.circle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .help("Dokumen berubah setelah analisis terakhir.")
                    .accessibilityLabel("Review perlu diulang")
            }
            if presentationMode == .editing, let aiConnectorViewModel {
                incrementalAnalysisControls(for: aiConnectorViewModel)
            }
            exportButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var documentTitleField: some View {
        TextField("Untitled", text: $documentTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 100, maxWidth: 360, alignment: .leading)
    }

    private var formattingControls: some View {
        HStack(spacing: 8) {
            historyGroup
            // Formatting commands are temporarily hidden while the command
            // surface is being reviewed. Keep the implementations below so
            // they can be re-enabled without losing their wiring.
            // textStyleGroup
            // inlineStyleGroup
            // listStyleGroup
            // paragraphAlignmentGroup
            // indentGroup
            // linkGroup
            // clearFormattingButton
            // zoomGroup
        }
    }

    private var historyGroup: some View {
        HStack(spacing: 2) {
            toolbarIconButton(
                systemName: "arrow.uturn.backward",
                help: "Undo (⌘Z)",
                isEnabled: viewModel.canUndo
            ) {
                viewModel.pendingAction = .undo
            }
            .keyboardShortcut("z", modifiers: .command)
            toolbarIconButton(
                systemName: "arrow.uturn.forward",
                help: "Redo (⇧⌘Z)",
                isEnabled: viewModel.canRedo
            ) {
                viewModel.pendingAction = .redo
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .toolbarGroupStyle()
    }

    private var textStyleGroup: some View {
        HStack(spacing: 2) {
            ForEach(TextStyle.allCases) { style in
                let isActive = viewModel.activeState.textStyle == style
                GlassPillButton(isActive: isActive, width: style == .body ? 76 : 26) {
                    viewModel.pendingAction = .textStyle(style)
                } label: {
                    Text(style.rawValue)
                        .font(.system(size: style == .body ? 11 : 12, weight: isActive ? .bold : .medium))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
        }
        .toolbarGroupStyle()
    }

    private var zoomGroup: some View {
        HStack(spacing: 2) {
            toolbarIconButton(
                systemName: "minus.magnifyingglass",
                help: "Zoom out (⌘−)",
                isEnabled: viewModel.zoomPercent > EditorZoom.minimumPercent
            ) {
                viewModel.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button {
                viewModel.resetZoom()
            } label: {
                Text("\(viewModel.zoomPercent)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reset zoom (⌘0)")
            .keyboardShortcut("0", modifiers: .command)

            toolbarIconButton(
                systemName: "plus.magnifyingglass",
                help: "Zoom in (⌘+)",
                isEnabled: viewModel.zoomPercent < EditorZoom.maximumPercent
            ) {
                viewModel.zoomIn()
            }
            .keyboardShortcut("=", modifiers: [.command, .shift])
        }
        .toolbarGroupStyle()
    }

    private var fontSizeGroup: some View {
        HStack(spacing: 2) {
            toolbarIconButton(
                systemName: "textformat.size.smaller",
                help: "Perkecil ukuran font",
                isEnabled: canAdjustFontSize
                    && viewModel.fontSizePoints > EditorViewModel.minimumFontSize
            ) {
                viewModel.decreaseFontSize()
            }

            Button {
                viewModel.resetFontSize()
            } label: {
                Text("\(Int(viewModel.fontSizePoints))pt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(canAdjustFontSize ? .secondary : .tertiary)
                    .frame(width: 36, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!canAdjustFontSize)
            .help(
                canAdjustFontSize
                    ? "Reset ukuran font"
                    : "Ukuran font native dokumen dipertahankan"
            )

            toolbarIconButton(
                systemName: "textformat.size.larger",
                help: "Perbesar ukuran font",
                isEnabled: canAdjustFontSize
                    && viewModel.fontSizePoints < EditorViewModel.maximumFontSize
            ) {
                viewModel.increaseFontSize()
            }
        }
        .toolbarGroupStyle()
    }

    private var listStyleGroup: some View {
        HStack(spacing: 2) {
            ForEach(ListStyle.allCases) { style in
                let isActive = viewModel.activeState.listStyle == style
                GlassPillButton(
                    isActive: isActive,
                    help: style == .bulleted ? "Bulleted list" : "Numbered list"
                ) {
                    viewModel.pendingAction = .listStyle(style)
                } label: {
                    Image(systemName: style.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
        }
        .toolbarGroupStyle()
    }

    private var paragraphAlignmentGroup: some View {
        HStack(spacing: 2) {
            ForEach(EditorParagraphAlignment.allCases) { alignment in
                GlassPillButton(
                    isActive: viewModel.activeState.alignment == alignment,
                    help: alignment.label
                ) {
                    viewModel.pendingAction = .alignment(alignment)
                } label: {
                    Image(systemName: alignment.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            viewModel.activeState.alignment == alignment ? .primary : .secondary
                        )
                }
            }
        }
        .toolbarGroupStyle()
    }

    private var indentGroup: some View {
        HStack(spacing: 2) {
            ForEach(IndentDirection.allCases) { direction in
                GlassPillButton(isActive: false, help: direction.label) {
                    viewModel.pendingAction = .indent(direction)
                } label: {
                    Image(systemName: direction.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbarGroupStyle()
    }

    private var linkGroup: some View {
        HStack(spacing: 2) {
            GlassPillButton(
                isActive: viewModel.activeState.isLink,
                isEnabled: viewModel.activeState.hasSelection,
                help: "Add or edit link"
            ) {
                linkURLText = viewModel.activeState.linkURL?.absoluteString ?? ""
                isLinkPopoverPresented = true
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        viewModel.activeState.hasSelection ? .secondary : .tertiary
                    )
            }

            GlassPillButton(
                isActive: false,
                isEnabled: viewModel.activeState.isLink && viewModel.activeState.hasSelection,
                help: "Remove link"
            ) {
                viewModel.pendingAction = .link(nil)
            } label: {
                Image(systemName: "link.badge.minus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        viewModel.activeState.isLink ? .secondary : .tertiary
                    )
            }
        }
        .toolbarGroupStyle()
        .popover(isPresented: $isLinkPopoverPresented, arrowEdge: .bottom) {
            LinkPopoverView(
                urlText: $linkURLText,
                hasExistingLink: viewModel.activeState.isLink,
                onApply: { url in
                    viewModel.pendingAction = .link(url)
                    isLinkPopoverPresented = false
                },
                onRemove: {
                    viewModel.pendingAction = .link(nil)
                    isLinkPopoverPresented = false
                },
                onCancel: {
                    isLinkPopoverPresented = false
                }
            )
        }
    }

    private var clearFormattingButton: some View {
        HStack(spacing: 2) {
            GlassPillButton(
                isActive: false,
                isEnabled: true,
                help: "Clear formatting"
            ) {
                viewModel.pendingAction = .clearFormatting
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .toolbarGroupStyle()
    }

    private func inlineButton(
        _ title: String,
        action: FormattingAction,
        isActive: Bool,
        textStyle: @escaping (Text) -> Text
    ) -> some View {
        GlassPillButton(isActive: isActive) {
            viewModel.pendingAction = action
        } label: {
            textStyle(Text(title))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private func toolbarIconButton(
        systemName: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassPillButton(isActive: false, isEnabled: isEnabled, help: help, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if case let .failed(message) = saveState {
            Button(action: onRetrySave) {
                Label(saveState.title, systemImage: saveState.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("\(message) Klik untuk mencoba lagi.")
            .accessibilityLabel("\(saveState.title). Coba lagi")
        } else {
            Label(saveState.title, systemImage: saveState.systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(saveStatusColor)
                .accessibilityLabel(saveState.title)
        }
    }

    private var saveStatusColor: Color {
        switch saveState {
        case .dirty:
            .secondary
        case .saving:
            .secondary
        case .saved:
            .secondary
        case .failed:
            .orange
        }
    }

    private var exportButton: some View {
        Button {
            onExport?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 18)
                Text("Ekspor")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .toolbarGroupStyle(cornerRadius: 10)
        .help("Ekspor Dokumen (.docx)")
    }

    @ViewBuilder
    private func incrementalAnalysisControls(
        for aiConnectorViewModel: AIConnectorViewModel
    ) -> some View {
        if aiConnectorViewModel.isRunning {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(analysisProgressTitle(aiConnectorViewModel))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Batal") {
                    aiConnectorViewModel.cancel()
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .help("Batalkan pemeriksaan; hasil yang sudah valid tetap dipertahankan.")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(analysisProgressTitle(aiConnectorViewModel))
        } else {
            Menu {
                Button("Periksa ulang") { onRerun() }
                    .disabled(!aiConnectorViewModel.canRerunAnalysis)
                Button("Periksa bagian ini") { onRerunSection() }
                    .disabled(!aiConnectorViewModel.canRerunSelectedSection)
                Divider()
                Button("Periksa seluruh dokumen dari awal") { onRerunFull() }
            } label: {
                Label(
                    aiConnectorViewModel.hasPendingAnalysisChanges
                        ? "Periksa ulang"
                        : "Periksa",
                    systemImage: "arrow.clockwise"
                )
                .font(.caption2.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pilih bagian dokumen yang ingin diperiksa ulang.")
            .accessibilityLabel("Pilihan pemeriksaan ulang")
        }
    }

    private func analysisProgressTitle(_ viewModel: AIConnectorViewModel) -> String {
        let progress = viewModel.progressSnapshot
        let reused = progress.reusedSegmentCount
        let reprocessed = progress.reprocessedSegmentCount
        let completed = progress.completedSegmentCount
        let total = progress.totalSegmentCount
        if reused > 0 {
            return "Memeriksa \(completed) dari \(total) · \(reused) dipakai ulang · \(reprocessed) dihitung ulang"
        }
        return "Memeriksa \(completed) dari \(total)"
    }
}

private struct GlassPillButton<Label: View>: View {
    let isActive: Bool
    var isEnabled = true
    var width: CGFloat = 26
    var help: String?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: width, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isActive
                                ? Color.primary.opacity(0.12)
                                : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help ?? "")
        .onHover { isHovered = $0 }
    }
}

private struct FlatToolbarGroupModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension View {
    func toolbarGroupStyle(cornerRadius: CGFloat = 16) -> some View {
        padding(.horizontal, 4)
            .padding(.vertical, 3)
            .modifier(FlatToolbarGroupModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    ZStack {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

        EditorToolbar(
            documentTitle: .constant("Untitled"),
            presentationMode: .constant(.editing),
            viewModel: EditorViewModel(),
            canPreviewOriginal: true,
            saveState: .saved(Date()),
            reviewNeedsRerun: false
        )
    }
    .frame(width: 850, height: 100)
}

private struct LinkPopoverView: View {
    @Binding var urlText: String
    let hasExistingLink: Bool
    let onApply: (URL) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    private var parsedURL: URL? {
        let value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(value)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link")
                .font(.headline)

            TextField("https://example.com", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit {
                    if let parsedURL { onApply(parsedURL) }
                }

            HStack {
                if hasExistingLink {
                    Button("Remove") { onRemove() }
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Apply") {
                    if let parsedURL { onApply(parsedURL) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedURL == nil)
            }
        }
        .padding(14)
    }
}
