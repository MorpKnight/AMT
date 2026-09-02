//
//  EditorToolbar.swift
//  AMT
//

import AppKit
import SwiftUI

enum TextStyle: String, CaseIterable, Identifiable {
    case body = "T"
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
        case .preview: "Dokumen"
        case .editing: "Edit & Suggestion"
        }
    }
}

struct EditorToolbar: View {
    @Binding var documentTitle: String
    @Binding var presentationMode: DocumentPresentationMode
    let viewModel: EditorViewModel
    let canPreviewOriginal: Bool
    var onExport: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            documentTitleField
            Spacer()
            if canPreviewOriginal {
                Picker("Mode", selection: $presentationMode) {
                    ForEach(DocumentPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            if presentationMode == .editing {
                formattingControls
            }
            Spacer()
            exportButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var documentTitleField: some View {
        TextField("Untitled", text: $documentTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 100, maxWidth: 220)
    }

    private var formattingControls: some View {
        HStack(spacing: 8) {
            textStyleGroup
            inlineStyleGroup
            listStyleGroup
        }
    }

    private var textStyleGroup: some View {
        HStack(spacing: 2) {
            ForEach(TextStyle.allCases) { style in
                let isActive = viewModel.activeState.textStyle == style
                GlassPillButton(isActive: isActive) {
                    viewModel.pendingAction = .textStyle(style)
                } label: {
                    Text(style.rawValue)
                        .font(.system(size: 12, weight: isActive ? .bold : .medium))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
        }
        .toolbarGroupStyle()
    }

    private var inlineStyleGroup: some View {
        HStack(spacing: 2) {
            inlineButton("B", action: .bold, isActive: viewModel.activeState.isBold) {
                $0.font(.system(size: 13, weight: .bold))
            }
            inlineButton("I", action: .italic, isActive: viewModel.activeState.isItalic) {
                $0.font(.system(size: 13, weight: .bold)).italic()
            }
            inlineButton("U", action: .underline, isActive: viewModel.activeState.isUnderline) {
                $0.font(.system(size: 13, weight: .semibold)).underline()
            }
            inlineButton("S", action: .strikethrough, isActive: viewModel.activeState.isStrikethrough) {
                $0.font(.system(size: 13, weight: .semibold)).strikethrough()
            }
        }
        .toolbarGroupStyle()
    }

    private var listStyleGroup: some View {
        HStack(spacing: 2) {
            ForEach(ListStyle.allCases) { style in
                let isActive = viewModel.activeState.listStyle == style
                GlassPillButton(isActive: isActive) {
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

    private var exportButton: some View {
        Button {
            onExport?()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 10)
        .help("Ekspor Dokumen (.docx)")
    }
}

private struct GlassPillButton<Label: View>: View {
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 26, height: 24)
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
        .onHover { isHovered = $0 }
    }
}

private struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.70))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.85),
                                        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.35)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.06),
                        radius: 6,
                        x: 0,
                        y: 2
                    )
            }
    }
}

private extension View {
    func toolbarGroupStyle() -> some View {
        padding(.horizontal, 4)
            .padding(.vertical, 3)
            .liquidGlass(cornerRadius: 16)
    }

    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
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
            canPreviewOriginal: true
        )
    }
    .frame(width: 850, height: 100)
}
