import SwiftUI

struct DocumentReviewPopover: View {
    let documentID: UUID?
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPinned = false
    @State private var isHoveringRegion = false

    private var isVisible: Bool {
        isPinned || isHoveringRegion
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            triggerButton

            if isVisible {
                DocumentReviewPanel(
                    analysisStatus: analysisStatus,
                    progress: progress,
                    progressDetail: progressDetail,
                    canAnalyze: canAnalyze,
                    errorMessage: errorMessage,
                    reviewItems: reviewItems,
                    acceptedItemCount: acceptedItemCount,
                    selectedReviewItemID: selectedReviewItemID,
                    selectedSourceContext: selectedSourceContext,
                    onSelectReview: onSelectReview,
                    onAnalyze: onAnalyze,
                    onAccept: onAccept,
                    onReject: onReject,
                    onRetry: onRetry,
                    onCancel: onCancel
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                )
            }
        }
        .onHover { isHoveringRegion = $0 }
        .animation(
            reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.16),
            value: isVisible
        )
        .onChange(of: documentID) { _, _ in
            isPinned = false
            isHoveringRegion = false
        }
    }

    private var triggerButton: some View {
        Button {
            isPinned.toggle()
        } label: {
            HStack(spacing: 6) {
                if analysisStatus == .analyzing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checklist")
                }

                Text("Review")
                    .font(.caption.weight(.semibold))

                if reviewItems.isEmpty == false {
                    Text("\(reviewItems.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Tutup panel review" : "Buka panel review")
        .accessibilityLabel(isPinned ? "Tutup panel review" : "Buka panel review")
        .accessibilityValue(triggerStatus)
        .accessibilityHint(
            isPinned
                ? "Klik untuk melepas pin panel."
                : "Klik untuk tetap membuka panel review."
        )
    }

    private var triggerStatus: String {
        switch analysisStatus {
        case .analyzing:
            "Analisis sedang berjalan"
        case .completed:
            "\(reviewItems.count) temuan"
        default:
            analysisStatus.displayTitle
        }
    }
}
