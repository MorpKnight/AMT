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
                        suggestion.isReadOnlyDiagnostic
                            ? diagnosticTint
                            : suggestion.kind == .definition
                                ? Color.orange
                                : Color.blue
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        suggestion.isReadOnlyDiagnostic
                            ? "\(diagnosticStatus.title) · Read-only"
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

            if suggestion.isReadOnlyDiagnostic {
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
            if !suggestion.isReadOnlyDiagnostic {
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

struct ReviewAnnotationPopoverView: View {
    let annotation: EditorReviewAnnotation
    let isStale: Bool
    let isReviewed: Bool
    let overlappingAnnotations: [EditorReviewAnnotation]
    let resolution: AIConnectorDefinitionResolution?
    let isResolutionLoading: Bool
    let onDismiss: () -> Void
    let onMarkReviewed: () -> Void
    let onReopenReviewed: () -> Void
    let onNavigateToEvidence: (AIConnectorFindingEvidence) -> Void
    let onSelectOverlapping: (UUID) -> Void
    let onRequestResolution: () -> Void
    let onApplyResolution: (AIConnectorDefinitionResolutionOption) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedResolutionOptionID: String?

    init(
        annotation: EditorReviewAnnotation,
        isStale: Bool,
        isReviewed: Bool = false,
        overlappingAnnotations: [EditorReviewAnnotation] = [],
        resolution: AIConnectorDefinitionResolution? = nil,
        isResolutionLoading: Bool = false,
        onDismiss: @escaping () -> Void,
        onMarkReviewed: @escaping () -> Void = {},
        onReopenReviewed: @escaping () -> Void = {},
        onNavigateToEvidence: @escaping (AIConnectorFindingEvidence) -> Void = { _ in },
        onSelectOverlapping: @escaping (UUID) -> Void = { _ in },
        onRequestResolution: @escaping () -> Void = {},
        onApplyResolution: @escaping (AIConnectorDefinitionResolutionOption) -> Void = { _ in }
    ) {
        self.annotation = annotation
        self.isStale = isStale
        self.isReviewed = isReviewed
        self.overlappingAnnotations = overlappingAnnotations
        self.resolution = resolution
        self.isResolutionLoading = isResolutionLoading
        self.onDismiss = onDismiss
        self.onMarkReviewed = onMarkReviewed
        self.onReopenReviewed = onReopenReviewed
        self.onNavigateToEvidence = onNavigateToEvidence
        self.onSelectOverlapping = onSelectOverlapping
        self.onRequestResolution = onRequestResolution
        self.onApplyResolution = onApplyResolution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: annotation.kind.iconName)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(annotation.title ?? annotation.definitionDiagnosticStatus?.title ?? annotation.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    if !annotation.category.displayTitle.isEmpty {
                        Text(annotation.category.displayTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            detailCard(title: "Bagian dokumen", text: annotation.original)

            if let term = annotation.definitionTerm, !term.isEmpty {
                detailCard(title: "Istilah", text: term)
            }

            detailCard(title: "Penjelasan", text: annotation.reason)

            if !annotation.relatedEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Bukti terkait")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(annotation.relatedEvidence) { evidence in
                        Button {
                            onNavigateToEvidence(evidence)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evidence.label)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(evidence.original)
                                        .font(.system(size: 11))
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                        )
                    }
                }
            }

            if !overlappingAnnotations.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Temuan lain pada area ini")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(overlappingAnnotations) { other in
                        Button {
                            onSelectOverlapping(other.id)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: other.kind.iconName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(other.title ?? other.kind.title)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(other.original)
                                        .font(.system(size: 11))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                        )
                    }
                }
            }

            if let reference = annotation.reference {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Referensi definisi")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !reference.regulation.isEmpty {
                        Text(reference.regulation)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if !reference.regulationTitle.isEmpty {
                        Text(reference.regulationTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let definition = reference.definition, !definition.isEmpty {
                        detailCard(title: "Definisi corpus", text: definition)
                    }
                    if let articleLocator = reference.articleLocator, !articleLocator.isEmpty {
                        Text("Pasal: \(articleLocator)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let passageID = reference.sourcePassageID, !passageID.isEmpty {
                        Text("Evidence ID: \(passageID)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let status = reference.applicabilityStatus {
                        Text("Status keberlakuan: \(status.displayTitle)")
                            .font(.system(size: 11))
                            .foregroundStyle(status == .notInForce ? .secondary : .primary)
                    }
                    HStack(spacing: 12) {
                        if let sourceURL = reference.sourceURL {
                            Link(destination: sourceURL) {
                                Label("Sumber detail", systemImage: "link")
                            }
                        }
                        if let officialURL = reference.officialDocumentURL {
                            Link(destination: officialURL) {
                                Label("Dokumen resmi", systemImage: "doc.text")
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
            }

            if annotation.kind == .definition,
               annotation.definitionDiagnosticStatus == .mismatch {
                definitionResolutionSection
            }

            if isStale {
                Label(
                    "Teks sudah berubah. Temuan ini tidak dapat digunakan.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if annotation.kind == .definedTerm || annotation.kind == .legalRisk {
                HStack(spacing: 8) {
                    Button(action: isReviewed ? onReopenReviewed : onMarkReviewed) {
                        Label(
                            isReviewed ? "Buka kembali" : "Tandai sudah diperiksa",
                            systemImage: isReviewed ? "arrow.uturn.backward" : "checkmark"
                        )
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStale)

                    Button(action: onDismiss) {
                        Label("Abaikan", systemImage: "eye.slash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .contain)
            } else {
                Button(action: onDismiss) {
                    Label("Abaikan", systemImage: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Abaikan hasil pemeriksaan")
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(
            colorScheme == .dark
                ? Color(red: 0.15, green: 0.16, blue: 0.18)
                : Color(red: 0.96, green: 0.96, blue: 0.97)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch annotation.definitionDiagnosticStatus {
        case .matches:
            .green
        case .mismatch:
            .red
        case .needsReview, .none:
            .orange
        }
    }

    private func detailCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.9))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
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

    private var definitionResolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pilihan penyelesaian")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if isResolutionLoading {
                Label("Mencari istilah yang sesuai secara lokal…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let resolution {
                if resolution.contractDefined {
                    Label(
                        "Istilah tampak memiliki arti khusus dalam kontrak; perubahan otomatis tidak tersedia.",
                        systemImage: "lock"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                }

                ForEach(resolution.options.filter {
                    $0.action != .rejectRecommendation
                }) { option in
                    resolutionOption(option)
                }

                Button {
                    onRequestResolution()
                } label: {
                    Label("Cari istilah yang sesuai", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isStale || resolution.options.contains(where: {
                    $0.sourceCandidateID?.hasPrefix("R") == true
                }))
            } else {
                Text("Pilihan sumber sedang disiapkan dari evidence pemeriksaan.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button {
                    onRequestResolution()
                } label: {
                    Label("Cari istilah yang sesuai", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isStale)
            }

            Button(role: .destructive, action: onDismiss) {
                Label("Tolak rekomendasi", systemImage: "hand.raised")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isStale)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.orange.opacity(0.08) : Color.orange.opacity(0.06))
        )
    }

    @ViewBuilder
    private func resolutionOption(
        _ option: AIConnectorDefinitionResolutionOption
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                selectedResolutionOptionID = option.id
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selectedResolutionOptionID == option.id
                        ? "checkmark.circle.fill"
                        : "circle")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold))
                        if let reference = option.reference {
                            Text(reference.regulation)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        if let statusMessage = option.statusMessage {
                            Text(statusMessage)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if selectedResolutionOptionID == option.id {
                detailCard(title: "Sebelum", text: option.original)
                if let replacement = option.replacement {
                    detailCard(title: "Sesudah", text: replacement)
                }
                if option.isActionable {
                    Button {
                        onApplyResolution(option)
                    } label: {
                        Label("Terapkan perubahan", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStale)
                } else {
                    Text("Pilihan ini hanya informasional dan belum dapat diterapkan.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
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
