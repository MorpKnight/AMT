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
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: suggestion.kind.iconName)
                    .foregroundStyle(
                        suggestion.isDebugOnly
                            ? diagnosticTint
                            : suggestion.kind == .definition
                                ? Color.orange
                                : Color.blue
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        suggestion.isDebugOnly
                            ? "\(diagnosticStatus.title) (Debug)"
                            : suggestion.kind.title
                    )
                        .font(.system(size: 13, weight: .semibold))
                    if !suggestion.category.displayTitle.isEmpty {
                        Text(suggestion.category.displayTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            if suggestion.isDebugOnly {
                detailCard(title: "Bagian dokumen", text: suggestion.original)

                if let term = suggestion.definitionTerm ?? suggestion.reference?.term,
                   !term.isEmpty {
                    detailCard(title: "Istilah", text: term)
                }
                if let definition = suggestion.reference?.definition,
                   !definition.isEmpty {
                    detailCard(title: "Definisi terverifikasi", text: definition)
                } else {
                    detailCard(
                        title: "Definisi terverifikasi",
                        text: "Belum tersedia evidence definisi yang dapat dibandingkan."
                    )
                }
                detailCard(title: "Penilaian", text: suggestion.reason)
                Label(
                    diagnosticMessage,
                    systemImage: diagnosticStatus.iconName
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(diagnosticTint)
            } else {
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

                detailCard(title: "Alasan", text: suggestion.reason)

                if suggestion.kind == .definition,
                   let definition = suggestion.reference?.definition,
                   !definition.isEmpty {
                    detailCard(title: "Acuan pengertian", text: definition)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("References")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if let reference = suggestion.reference {
                    if !reference.regulation.isEmpty {
                        Text(reference.regulation)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    if !reference.regulationTitle.isEmpty {
                        Text(reference.regulationTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let articleLocator = reference.articleLocator,
                       !articleLocator.isEmpty {
                        Text(articleLocator)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let passageID = reference.sourcePassageID,
                       !passageID.isEmpty {
                        Text("Evidence: \(passageID)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if let sourceURL = reference.sourceURL {
                            Link(destination: sourceURL) {
                                Label("Sumber detail", systemImage: "link")
                            }
                        }
                        if let officialDocumentURL = reference.officialDocumentURL {
                            Link(destination: officialDocumentURL) {
                                Label("Dokumen resmi", systemImage: "doc.text")
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
            }

            if isStale {
                Label("Teks sudah berubah. Jalankan analisis ulang.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            // MARK: - Bottom Action Buttons (Accept / Dismiss)
            if !suggestion.isDebugOnly {
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
        }
        .padding(16)
        .frame(width: 400)
        .background(colorScheme == .dark ? Color(red: 0.15, green: 0.16, blue: 0.18) : Color(red: 0.96, green: 0.96, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var diagnosticStatus: EditorDefinitionDiagnosticStatus {
        suggestion.definitionDiagnosticStatus ?? .matches
    }

    private var diagnosticTint: Color {
        switch diagnosticStatus {
        case .matches:
            .green
        case .mismatch:
            .red
        case .needsReview:
            .orange
        }
    }

    private var diagnosticMessage: String {
        switch diagnosticStatus {
        case .matches:
            "Makna dinilai selaras dengan evidence terverifikasi."
        case .mismatch:
            "Makna dinilai tidak selaras dengan evidence terverifikasi."
        case .needsReview:
            "Kesetaraan makna belum dapat dipastikan; verifikasi diperlukan."
        }
    }

    private func detailCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(text)
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
