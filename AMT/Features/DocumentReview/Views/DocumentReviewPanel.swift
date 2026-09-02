import SwiftUI

struct DocumentReviewPanel: View {
    let analysisStatus: DocumentReviewAnalysisStatus
    let progress: Double
    let progressDetail: String
    let canAnalyze: Bool
    let errorMessage: String?
    let reviewItems: [DocumentReviewItem]
    let acceptedItemCount: Int
    let selectedReviewItemID: UUID?
    let selectedSourceContext: DocumentReviewSourceContext?
    let onSelectReview: (UUID?) -> Void
    let onAnalyze: () -> Void
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            if analysisStatus == .analyzing {
                analysisProgress
            }

            if let errorMessage {
                errorCard(message: errorMessage)
            }

            if reviewItems.isEmpty {
                emptyState
            } else {
                reviewList
            }

            panelFooter
        }
        .frame(width: 340, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel review dokumen")
    }

    private var panelHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Review dokumen")
                    .font(.headline)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if analysisStatus == .analyzing {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Batalkan analisis")
                .accessibilityLabel("Batalkan analisis")
            }
        }
        .padding(14)
    }

    private var statusDescription: String {
        switch analysisStatus {
        case .analyzing:
            progressDetail.isEmpty ? "Menganalisis dokumen" : progressDetail
        case .completed:
            reviewItems.isEmpty
                ? "Tidak ada temuan"
                : "\(reviewItems.count) temuan · \(acceptedItemCount) diterima"
        default:
            analysisStatus.displayTitle
        }
    }

    private var analysisProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: progress)
                .tint(.accentColor)

            Text(progressDetail.isEmpty ? "Menyiapkan analisis" : progressDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func errorCard(message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: emptySymbol)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))

            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if analysisStatus == .idle, canAnalyze {
                Button("Analisis dokumen", action: onAnalyze)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if (analysisStatus == .failed || analysisStatus == .cancelled), canAnalyze {
                Button("Coba lagi", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var emptySymbol: String {
        switch analysisStatus {
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "pause.circle"
        default:
            "doc.text.magnifyingglass"
        }
    }

    private var emptyTitle: String {
        switch analysisStatus {
        case .completed:
            "Tidak ada temuan"
        case .failed:
            "Analisis belum selesai"
        case .cancelled:
            "Analisis dibatalkan"
        case .analyzing:
            "Menyiapkan hasil review"
        case .idle:
            "Review belum dimulai"
        }
    }

    private var emptyMessage: String {
        switch analysisStatus {
        case .completed:
            "Tidak ada saran yang dapat dipetakan dengan aman ke teks asli."
        case .failed:
            "Periksa pesan di atas sebelum mencoba kembali."
        case .cancelled:
            "Analisis dapat dijalankan kembali kapan saja."
        case .analyzing:
            "Temuan akan muncul setelah analisis selesai."
        case .idle:
            "Analisis dokumen untuk menemukan bagian yang perlu ditinjau."
        }
    }

    private var reviewList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(reviewItems) { item in
                    DocumentReviewItemCard(
                        item: item,
                        isSelected: selectedReviewItemID == item.id,
                        sourceContext: selectedReviewItemID == item.id
                            ? selectedSourceContext
                            : nil,
                        onSelect: { onSelectReview(item.id) },
                        onAccept: { onAccept(item.id) },
                        onReject: { onReject(item.id) }
                    )
                }
            }
            .padding(10)
        }
    }

    private var panelFooter: some View {
        HStack(spacing: 6) {
            Text("\(acceptedItemCount) diterima")
            Text("·")
            Text("\(reviewItems.count) temuan")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct DocumentReviewItemCard: View {
    let item: DocumentReviewItem
    let isSelected: Bool
    let sourceContext: DocumentReviewSourceContext?
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                compactHeader
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Temuan segmen \(item.segmentID)")
            .accessibilityValue(item.decision.displayTitle)

            if isSelected {
                detailContent
            }
        }
        .padding(10)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.09)
                : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.65) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private var compactHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Segmen \(item.segmentID)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !item.category.displayTitle.isEmpty {
                        Text(item.category.displayTitle)
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(item.original)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let sourceContext {
                DocumentReviewSourceContextView(context: sourceContext)
            } else if let mappingIssue = item.mappingIssue {
                Label(
                    "\(mappingIssue.displayTitle). Perubahan ini tidak dapat diterapkan.",
                    systemImage: "lock"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            labeledText("Usulan perubahan", item.replacement)
            labeledText("Alasan", item.reason)

            if let reference = item.reference {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Referensi kamus")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(reference.term)
                        .font(.caption)
                    if !reference.regulation.isEmpty {
                        Text(reference.regulation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if item.decision == .pending {
                HStack(spacing: 8) {
                    Button("Tolak", role: .destructive, action: onReject)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Terima", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!item.isActionable)
                }
            }
        }
    }

    private func labeledText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DocumentReviewSourceContextView: View {
    let context: DocumentReviewSourceContext

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Bagian yang ditinjau")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            DocumentReviewHighlightedSourceText(context: context)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            Text("Posisi halaman tidak dipetakan oleh Quick Look.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct DocumentReviewHighlightedSourceText: View {
    let context: DocumentReviewSourceContext
    var maximumSideCharacters: Int? = nil

    var body: some View {
        Text(highlightedText)
    }

    private var highlightedText: AttributedString {
        var result = AttributedString()
        let visiblePrefix = visiblePrefix
        let visibleSuffix = visibleSuffix
        if context.hasPreviousText || visiblePrefix.count < context.prefix.count {
            result.append(AttributedString("…"))
        }
        result.append(AttributedString(visiblePrefix))

        let matchStart = result.endIndex
        result.append(AttributedString(context.original))
        let matchEnd = result.endIndex
        result[matchStart..<matchEnd].backgroundColor = Color.accentColor.opacity(0.28)
        result[matchStart..<matchEnd].foregroundColor = .primary

        result.append(AttributedString(visibleSuffix))
        if context.hasNextText || visibleSuffix.count < context.suffix.count {
            result.append(AttributedString("…"))
        }
        return result
    }

    private var visiblePrefix: String {
        guard let maximumSideCharacters,
              maximumSideCharacters >= 0,
              context.prefix.count > maximumSideCharacters
        else {
            return context.prefix
        }
        return String(context.prefix.suffix(maximumSideCharacters))
    }

    private var visibleSuffix: String {
        guard let maximumSideCharacters,
              maximumSideCharacters >= 0,
              context.suffix.count > maximumSideCharacters
        else {
            return context.suffix
        }
        return String(context.suffix.prefix(maximumSideCharacters))
    }
}
