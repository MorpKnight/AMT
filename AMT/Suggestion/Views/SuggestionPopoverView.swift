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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header (Correctness Suggestion)
            HStack(spacing: 4) {
                Text("Correctness")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Suggestion")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            // MARK: - Diff Preview (e.g. Kedua wajib untuk wajib memproses...)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let prefix = suggestion.prefixContext, !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Text(suggestion.original)
                    .font(.system(size: 13, weight: .bold))
                    .strikethrough(true, color: .primary.opacity(0.7))
                    .foregroundStyle(.primary)

                Text(suggestion.replacement)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.65, blue: 0.28))

                if let suffix = suggestion.suffixContext, !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Example Box Card
            VStack(alignment: .leading, spacing: 6) {
                Text("Example")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(exampleSentence)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // MARK: - References Section
            VStack(alignment: .leading, spacing: 8) {
                Text("References")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)

                        Text(referenceLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)

                        Text(referenceLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }
                }
            }

            if isStale {
                Label("Teks sudah berubah. Jalankan analisis ulang.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            // MARK: - Bottom Action Buttons (Accept / Dismiss)
            HStack(spacing: 16) {
                Button(action: onAccept) {
                    Text("Accept")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(isStale)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 360)
        .background(colorScheme == .dark ? Color(red: 0.15, green: 0.16, blue: 0.18) : Color(red: 0.96, green: 0.96, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exampleSentence: String {
        if !suggestion.reason.isEmpty {
            return suggestion.reason
        }
        return "Perusahaan logistik itu melakukan wanprestasi karena terlambat mengirimkan barang pesanan hingga melewati batas waktu di kontrak."
    }

    private var referenceLabel: String {
        if let ref = suggestion.reference {
            return "\(ref.regulation)"
        }
        return "Pasal 1234 KUH Perdata"
    }
}

#Preview("Suggestion Popover") {
    SuggestionPopoverView(
        suggestion: EditorSuggestion(
            id: UUID(),
            sourceRange: NSRange(location: 0, length: 14),
            original: "di luar kontrak",
            replacement: "Wanprestasi",
            category: .terminology,
            reason: "Perusahaan logistik itu melakukan wanprestasi karena terlambat mengirimkan barang pesanan hingga melewati batas waktu di kontrak.",
            origin: .deterministic,
            reference: EditorSuggestionReference(
                term: "Wanprestasi",
                regulation: "Pasal 1234 KUH Perdata",
                regulationTitle: "",
                sourceURL: nil
            )
        ),
        isStale: false,
        onAccept: {},
        onDismiss: {}
    )
    .padding()
}
