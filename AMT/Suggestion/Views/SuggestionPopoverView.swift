//
//  SuggestionPopoverView.swift
//  AMT
//

import Foundation
import SwiftUI

struct SuggestionPopoverView: View {
    let suggestion: EditorSuggestion
    let isStale: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .padding(.vertical, 12)

            changePreview
            detailSection(title: "Alasan", systemImage: "text.alignleft") {
                Text(suggestion.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let reference = suggestion.reference {
                referenceSection(reference)
            }

            if isStale {
                Label(
                    "Teks sudah berubah. Jalankan analisis ulang sebelum menerima saran.",
                    systemImage: "arrow.clockwise"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }

            Divider()
                .padding(.top, 16)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)

                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .disabled(isStale)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 22, height: 22)
                .background(.red.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Correctness Suggestion")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(suggestion.category.displayTitle)
                    .font(.headline)
            }

            Spacer(minLength: 0)

            Text(suggestion.origin.displayTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var changePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Rekomendasi")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            changeText
                .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var changeText: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(suggestion.original)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(suggestion.replacement)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.original)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(suggestion.replacement)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.top, 14)
    }

    private func referenceSection(_ reference: EditorSuggestionReference) -> some View {
        detailSection(title: "Referensi", systemImage: "link") {
            VStack(alignment: .leading, spacing: 4) {
                Text(reference.term)
                    .font(.callout.weight(.semibold))

                Text(reference.regulation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !reference.regulationTitle.isEmpty {
                    Text(reference.regulationTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let sourceURL = reference.sourceURL {
                    Link(destination: sourceURL) {
                        Label("Buka sumber", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconName: String {
        switch suggestion.category {
        case .spelling:
            "textformat.abc"
        case .grammar:
            "text.quote"
        case .clarity:
            "text.magnifyingglass"
        case .terminology:
            "books.vertical"
        case .none:
            "lightbulb"
        }
    }
}

#Preview("Terminology with reference") {
    SuggestionPopoverView(
        suggestion: EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: 0, length: 17),
            original: "data tentang orang",
            replacement: "Data Pribadi",
            category: .terminology,
            reason: "Istilah ini tersedia pada glossary lokal dan lebih ringkas.",
            origin: .deterministic,
            reference: EditorSuggestionReference(
                term: "Data Pribadi",
                regulation: "Undang-Undang Nomor 27 Tahun 2022",
                regulationTitle: "Pelindungan Data Pribadi",
                sourceURL: URL(string: "https://peraturan.bpk.go.id")
            )
        ),
        isStale: false,
        onAccept: {},
        onDismiss: {}
    )
    .padding()
}

#Preview("Spelling without reference") {
    SuggestionPopoverView(
        suggestion: EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: 0, length: 16),
            original: "ditanda tangani",
            replacement: "ditandatangani",
            category: .spelling,
            reason: "Bentuk baku ditulis sebagai satu kata.",
            origin: .deterministic,
            reference: nil
        ),
        isStale: false,
        onAccept: {},
        onDismiss: {}
    )
    .padding()
}
