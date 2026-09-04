//
//  AIConnectorToolbarStatusView.swift
//  AMT
//

import SwiftUI

struct AIConnectorToolbarStatusView: View {
    let state: AIConnectorRunState
    let progressStage: AIConnectorProgressStage
    let downloadProgress: Double
    let generationProgress: Int
    let summary: AIConnectorRunSummary?
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestion")
                        .font(.headline)
                    Text(state.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if case .downloading = state {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: clampedDownloadProgress)
                    Text(progressStage.title + " • " + String(Int(clampedDownloadProgress * 100)) + "%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if case .reviewing = state {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressStage.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if progressStage == .generation {
                        Text("Karakter keluaran: " + String(generationProgress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if case .loading = state {
                Label(
                    progressStage.title + ".",
                    systemImage: "cpu"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if case .segmenting = state {
                Label(progressStage.title + ".", systemImage: "text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary {
                summaryView(summary)
            }

            if case let .failed(message) = state {
                Text(errorMessage ?? message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private func summaryView(_ summary: AIConnectorRunSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ringkasan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                SummaryPill(value: summary.suggestionCount, label: "saran", tint: .green)
                SummaryPill(value: summary.needsReviewCount, label: "review", tint: .orange)
                SummaryPill(value: summary.rejectedCount, label: "ditahan", tint: .red)
            }

            HStack(spacing: 6) {
                SummaryPill(value: summary.cacheHitCount, label: "cache", tint: .blue)
                SummaryPill(value: summary.repairAttemptCount, label: "repair", tint: .purple)
                SummaryPill(value: summary.fallbackCount, label: "fallback", tint: .orange)
            }

            if summary.suggestionCount == 0 {
                Label(
                    "Tidak ada saran yang siap ditampilkan.",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Klik bagian yang disorot untuk melihat detail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if summary.wasPartial {
                Label(
                    "Ringkasan sementara; hasil parsial dipertahankan.",
                    systemImage: "pause.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if summary.circuitBreakerActivated {
                Label(
                    "Model dilewati untuk sisa dokumen; pemulihan deterministik digunakan.",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private var clampedDownloadProgress: Double {
        min(max(downloadProgress, 0), 1)
    }

    private var stateIcon: String {
        switch state {
        case .idle:
            "wand.and.sparkles"
        case .segmenting:
            "text.magnifyingglass"
        case .loading:
            "cpu"
        case .downloading:
            "arrow.down.circle.fill"
        case .reviewing:
            "sparkles"
        case .completed:
            "checkmark.circle.fill"
        case .cancelled:
            "pause.circle"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    private var stateTint: Color {
        switch state {
        case .idle, .cancelled:
            .secondary
        case .segmenting, .loading, .downloading, .reviewing:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

private struct SummaryPill: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

#Preview("Completed") {
    AIConnectorToolbarStatusView(
        state: .completed,
        progressStage: .completed,
        downloadProgress: 1,
        generationProgress: 0,
        summary: AIConnectorRunSummary(
            reviewMode: .deterministic,
            modelVariant: .qwen35_2b,
            processedSegmentCount: 4,
            suggestionCount: 2,
            needsReviewCount: 1,
            noSuggestionCount: 1,
            recoveredCount: 0,
            rejectedCount: 0,
            skippedSegmentCount: 0
        ),
        errorMessage: nil,
        onRetry: {}
    )
}
