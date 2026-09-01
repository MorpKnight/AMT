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
    var onAnalyze: (() -> Void)? = nil
    var onCancelAnalysis: (() -> Void)? = nil
    var onShowDebug: (() -> Void)? = nil
    var canAnalyze = false
    var isAnalyzing = false
    var analysisState: AIConnectorRunState = .idle
    var analysisProgressStage: AIConnectorProgressStage = .idle
    var analysisDownloadProgress = 0.0
    var analysisGenerationProgress = 0
    var analysisSummary: AIConnectorRunSummary?
    var analysisErrorMessage: String?
    var showsFormattingControls = true
    var canExport = true

    @State private var selectedTextStyle: TextStyle = .body
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var selectedListStyle: ListStyle?
    @State private var selectedAlignment: TextAlignment = .leading
    @State private var isAnalysisStatusPresented = false

    var body: some View {
        HStack(spacing: 0) {
            leadingControls
            Spacer()
            if showsFormattingControls {
                centerControls
            }
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
            .disabled(!canExport)
            .opacity(canExport ? 1 : 0.45)
            .help("Ekspor Dokumen (.docx)")

            if onAnalyze != nil {
                Button {
                    if isAnalyzing {
                        onCancelAnalysis?()
                    } else if canAnalyze {
                        onAnalyze?()
                        isAnalysisStatusPresented = true
                    }
                } label: {
                    if isAnalyzing {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.small)
                            Image(systemName: "stop.fill")
                        }
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isAnalyzing ? .red : .secondary)
                .opacity(canAnalyze || isAnalyzing ? 1 : 0.45)
                .disabled(!canAnalyze && !isAnalyzing)
                .help(isAnalyzing ? "Batalkan analisis" : "Analisis dokumen")
                .popover(isPresented: $isAnalysisStatusPresented, arrowEdge: .bottom) {
                    AIConnectorToolbarStatusView(
                        state: analysisState,
                        progressStage: analysisProgressStage,
                        downloadProgress: analysisDownloadProgress,
                        generationProgress: analysisGenerationProgress,
                        summary: analysisSummary,
                        errorMessage: analysisErrorMessage,
                        onRetry: {
                            onAnalyze?()
                            isAnalysisStatusPresented = true
                        }
                    )
                }
            }

            #if DEBUG
            Menu {
                Button {
                    onShowDebug?()
                } label: {
                    Label("Buka panel Debug", systemImage: "ladybug")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("Opsi lainnya")
            #else
            Button(action: {}) {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("More Options")
            #endif
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
