import SwiftUI

struct DocumentReviewPanel: View {
    let analysisStatus: DocumentReviewAnalysisStatus
    let progress: Double
    let progressDetail: String
    let errorMessage: String?
    let reviewItems: [DocumentReviewItem]
    let acceptedItemCount: Int
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()

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

            Divider()
            HStack {
                Text("Diterima: \(acceptedItemCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if analysisStatus == .cancelled || analysisStatus == .failed {
                    Button("Coba lagi", action: onRetry)
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var panelHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review dokumen")
                    .font(.headline)
                Text(analysisStatus.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if analysisStatus == .analyzing {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Batalkan analisis")
            }
        }
        .padding(14)
    }

    private var analysisProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: progress)
            HStack {
                Text(progressDetail.isEmpty ? "Menganalisis dokumen..." : progressDetail)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06))
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
        .padding(12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: analysisStatus == .completed ? "checkmark.circle" : "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private var emptyTitle: String {
        switch analysisStatus {
        case .completed:
            "Tidak ada perubahan yang dapat ditinjau"
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
            "Tidak ada saran yang berhasil dipetakan dengan aman ke teks asli."
        case .failed:
            "Periksa pesan di atas, lalu jalankan analisis kembali."
        case .cancelled:
            "Jalankan kembali analisis jika ingin melanjutkan."
        case .analyzing:
            "Hasil akan muncul di sini setelah analisis selesai."
        case .idle:
            "Analisis otomatis akan dimulai saat dokumen DOCX baru dibuka."
        }
    }

    private var reviewList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(reviewItems) { item in
                    DocumentReviewItemCard(
                        item: item,
                        onAccept: { onAccept(item.id) },
                        onReject: { onReject(item.id) }
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct DocumentReviewItemCard: View {
    let item: DocumentReviewItem
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Segmen \(item.segmentID)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !item.category.displayTitle.isEmpty {
                    Text(item.category.displayTitle)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                Text(item.decision.displayTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(decisionColor)
            }

            labeledText("Kutipan asli", item.original)
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

            if let mappingIssue = item.mappingIssue {
                Label(
                    "\(mappingIssue.displayTitle). Perubahan ini tidak actionable.",
                    systemImage: "lock"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if item.decision == .pending {
                HStack {
                    Button("Tolak", role: .destructive, action: onReject)
                        .buttonStyle(.bordered)
                    Button("Terima", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .disabled(!item.isActionable)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
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

    private var decisionColor: Color {
        switch item.decision {
        case .accepted:
            .green
        case .rejected:
            .secondary
        case .unavailable:
            .orange
        case .pending:
            .primary
        }
    }
}
