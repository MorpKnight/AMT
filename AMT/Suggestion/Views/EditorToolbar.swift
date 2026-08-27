//
//  EditorToolbar.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

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

enum TextAlignment: String, CaseIterable, Identifiable {
    case leading = "text.alignleft"
    case center = "text.aligncenter"
    case trailing = "text.alignright"

    var id: String { rawValue }
}

struct EditorToolbar: View {
    @Binding var documentTitle: String
    var onExport: (() -> Void)? = nil

    @State private var selectedTextStyle: TextStyle = .body
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var selectedListStyle: ListStyle?
    @State private var selectedAlignment: TextAlignment = .leading

    var body: some View {
        HStack(spacing: 0) {
            leadingControls
            Spacer()
            centerControls
            Spacer()
            trailingControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar, ignoresSafeAreaEdges: .all)
    }

    // MARK: - Left Section

    private var leadingControls: some View {
        HStack(spacing: 8) {
            TextField("Document Title", text: $documentTitle)
                .textFieldStyle(.plain)
                .font(.headline)
                .frame(minWidth: 120, maxWidth: 200)
        }
    }

    // MARK: - Center Section

    private var centerControls: some View {
        HStack(spacing: 2) {
            textStyleGroup
            formattingGroup
            listGroup
            alignmentGroup
        }
    }

    private var textStyleGroup: some View {
        HStack(spacing: 0) {
            ForEach(TextStyle.allCases) { style in
                Button(action: { selectedTextStyle = style }) {
                    Text(style.rawValue)
                        .font(style == .body ? .body : .caption)
                        .fontWeight(.semibold)
                        .frame(width: 32, height: 24)
                        .background(
                            selectedTextStyle == style
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var formattingGroup: some View {
        HStack(spacing: 0) {
            FormatButton(
                symbolName: "bold",
                isActive: isBold,
                action: { isBold.toggle() }
            )
            FormatButton(
                symbolName: "italic",
                isActive: isItalic,
                action: { isItalic.toggle() }
            )
            FormatButton(
                symbolName: "underline",
                isActive: isUnderline,
                action: { isUnderline.toggle() }
            )
            FormatButton(
                symbolName: "strikethrough",
                isActive: isStrikethrough,
                action: { isStrikethrough.toggle() }
            )
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var listGroup: some View {
        HStack(spacing: 0) {
            ForEach(ListStyle.allCases) { style in
                Button(action: {
                    selectedListStyle = selectedListStyle == style ? nil : style
                }) {
                    Image(systemName: style.rawValue)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 24)
                        .background(
                            selectedListStyle == style
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var alignmentGroup: some View {
        HStack(spacing: 0) {
            ForEach(TextAlignment.allCases) { alignment in
                Button(action: { selectedAlignment = alignment }) {
                    Image(systemName: alignment.rawValue)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 24)
                        .background(
                            selectedAlignment == alignment
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Right Section

    private var trailingControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                onExport?()
            }) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Ekspor Dokumen (.docx)")

            Button(action: {}) {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("More Options")
        }
    }
}

// MARK: - Format Button

private struct FormatButton: View {
    let symbolName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EditorToolbar(documentTitle: .constant("Untitled"))
}
