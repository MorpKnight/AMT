//
//  EditorToolbar.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import Foundation
import SwiftUI
import AppKit

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

enum TextAlignment: String, CaseIterable, Identifiable {
    case leading = "text.alignleft"
    case center = "text.aligncenter"
    case trailing = "text.alignright"

    var id: String { rawValue }
}

struct EditorToolbar: View {
    @Binding var documentTitle: String
//    var onToggleSidebar: (() -> Void)? = nil
    var onExport: (() -> Void)? = nil

    @State private var selectedTextStyle: TextStyle = .body
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var selectedListStyle: ListStyle?
    @State private var selectedAlignment: TextAlignment = .leading

    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Section (Sidebar Toggle & Document Title)
            leadingControls

            Spacer()

            // MARK: - Center Section (4 Liquid Glass Capsule Groups)
            centerControls

            Spacer()

            // MARK: - Right Section (Export Button)
            trailingControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Left Section

    private var leadingControls: some View {
        HStack(spacing: 12) {
            // Document Title Text Field
            TextField("Untitled", text: $documentTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 100, maxWidth: 220)
        }
    }

    // MARK: - Center Section (4 Distinct Liquid Glass Groups)

    private var centerControls: some View {
        HStack(spacing: 8) {
            // 1. Text Style Group (T, H1, H2, H3)
            textStyleGroup

            // 2. Formatting Group (B, I, U, S)
            formattingGroup

            // 3. List Style Group (Bullets, Numbered)
            listGroup

            // 4. Alignment Group (Left, Center, Right)
            alignmentGroup
        }
    }

    // 1. Text Style Capsule
    private var textStyleGroup: some View {
        HStack(spacing: 2) {
            ForEach(TextStyle.allCases) { style in
                GlassPillButton(
                    isActive: selectedTextStyle == style,
                    action: { selectedTextStyle = style }
                ) {
                    Text(style.rawValue)
                        .font(.system(size: 12, weight: selectedTextStyle == style ? .bold : .medium))
                        .foregroundStyle(selectedTextStyle == style ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .liquidGlass(cornerRadius: 16)
    }

    // 2. Formatting Capsule (B, I, U, S)
    private var formattingGroup: some View {
        HStack(spacing: 2) {
            // Bold
            GlassPillButton(
                isActive: isBold,
                action: { isBold.toggle() }
            ) {
                Text("B")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isBold ? .primary : .secondary)
            }

            // Italic
            GlassPillButton(
                isActive: isItalic,
                action: { isItalic.toggle() }
            ) {
                Text("I")
                    .font(.system(size: 13, weight: .bold))
                    .italic()
                    .foregroundStyle(isItalic ? .primary : .secondary)
            }

            // Underline
            GlassPillButton(
                isActive: isUnderline,
                action: { isUnderline.toggle() }
            ) {
                Text("U")
                    .font(.system(size: 13, weight: .semibold))
                    .underline()
                    .foregroundStyle(isUnderline ? .primary : .secondary)
            }

            // Strikethrough
            GlassPillButton(
                isActive: isStrikethrough,
                action: { isStrikethrough.toggle() }
            ) {
                Text("S")
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough()
                    .foregroundStyle(isStrikethrough ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .liquidGlass(cornerRadius: 16)
    }

    // 3. List Style Capsule
    private var listGroup: some View {
        HStack(spacing: 2) {
            ForEach(ListStyle.allCases) { style in
                GlassPillButton(
                    isActive: selectedListStyle == style,
                    action: {
                        selectedListStyle = (selectedListStyle == style) ? nil : style
                    }
                ) {
                    Image(systemName: style.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedListStyle == style ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .liquidGlass(cornerRadius: 16)
    }

    // 4. Alignment Capsule
    private var alignmentGroup: some View {
        HStack(spacing: 2) {
            ForEach(TextAlignment.allCases) { alignment in
                GlassPillButton(
                    isActive: selectedAlignment == alignment,
                    action: { selectedAlignment = alignment }
                ) {
                    Image(systemName: alignment.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedAlignment == alignment ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Right Section (Export Glass Button)

    private var trailingControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                onExport?()
            }) {
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
}

// MARK: - Glass Pill Button Component

private struct GlassPillButton<Content: View>: View {
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
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
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Liquid Glass View Modifier

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
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.05)
                                    : Color.white.opacity(0.70)
                            )
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
                        color: colorScheme == .dark
                            ? Color.black.opacity(0.4)
                            : Color.black.opacity(0.06),
                        radius: 6,
                        x: 0,
                        y: 2
                    )
            }
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    ZStack {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

        EditorToolbar(documentTitle: .constant("Untitled"))
    }
    .frame(width: 850, height: 100)
}
