//
//  DocumentAnalysisLoadingView.swift
//  AMT
//
//  Created by Antigravity on 2026/09/01.
//

import Foundation
import SwiftUI

struct DocumentAnalysisLoadingView: View {
    var progressStage: AIConnectorProgressStage = .idle
    var downloadProgress: Double = 0
    var generationProgress: Int = 0
    var analysisProgress: Double = 0
    var completedSegmentCount: Int = 0
    var totalSegmentCount: Int = 0
    var analysisStartedAt: Date = Date()
    var lastActivityAt: Date = Date()
    var onCancel: () -> Void = {}

    private static let stalledThreshold: TimeInterval = 60

    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var logoImageName: String {
        isDarkMode ? "logo_white" : "logo_black"
    }

    private var primaryColor: Color {
        isDarkMode ? .white : .black
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(currentDate: context.date)
        }
    }

    @ViewBuilder
    private func content(currentDate: Date) -> some View {
        VStack(spacing: 24) {
            Image(logoImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 120)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .accessibilityLabel("Analisis sedang berjalan")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dokumen sedang dianalisis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(primaryColor)

                        Text(progressStage.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                ProgressView(value: clamped(analysisProgress))
                    .tint(primaryColor)
                    .animation(.easeInOut(duration: 0.25), value: analysisProgress)
                    .accessibilityValue("\(Int(clamped(analysisProgress) * 100)) persen")

                HStack(spacing: 8) {
                    Text("Berjalan")
                    Spacer()
                    Text(formattedDuration(analysisDuration(at: currentDate)))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let progressDetail {
                    Text(progressDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isStalled(at: currentDate) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Belum ada aktivitas selama 60 detik. Proses mungkin masih berjalan.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)

                        Button("Hentikan dan buka dokumen", action: onCancel)
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progressDetail: String? {
        switch progressStage {
        case .semanticModelDownload, .modelDownload:
            return "Unduhan \(Int(clamped(downloadProgress) * 100))%"
        case .generation:
            if totalSegmentCount > 0 {
                return "\(min(max(completedSegmentCount, 0), totalSegmentCount)) dari \(totalSegmentCount) segmen selesai · \(generationProgress) karakter keluaran"
            }
            return "\(generationProgress) karakter keluaran"
        default:
            guard totalSegmentCount > 0 else { return nil }
            return "\(min(max(completedSegmentCount, 0), totalSegmentCount)) dari \(totalSegmentCount) segmen selesai"
        }
    }

    private func analysisDuration(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(analysisStartedAt))
    }

    private func isStalled(at date: Date) -> Bool {
        date.timeIntervalSince(lastActivityAt) >= Self.stalledThreshold
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview("Normal · Light") {
    DocumentAnalysisLoadingView(
        progressStage: .generation,
        generationProgress: 120,
        analysisProgress: 0.66,
        completedSegmentCount: 2,
        totalSegmentCount: 8,
        analysisStartedAt: Date().addingTimeInterval(-18),
        lastActivityAt: Date().addingTimeInterval(-2)
    )
    .preferredColorScheme(.light)
}

#Preview("Stalled · Light") {
    DocumentAnalysisLoadingView(
        progressStage: .generation,
        generationProgress: 120,
        analysisProgress: 0.66,
        completedSegmentCount: 2,
        totalSegmentCount: 8,
        analysisStartedAt: Date().addingTimeInterval(-78),
        lastActivityAt: Date().addingTimeInterval(-60)
    )
    .preferredColorScheme(.light)
}

#Preview("Normal · Dark") {
    DocumentAnalysisLoadingView(
        progressStage: .semanticRetrieval,
        analysisProgress: 0.32,
        completedSegmentCount: 1,
        totalSegmentCount: 8,
        analysisStartedAt: Date().addingTimeInterval(-18),
        lastActivityAt: Date().addingTimeInterval(-2)
    )
    .preferredColorScheme(.dark)
}

#Preview("Stalled · Dark") {
    DocumentAnalysisLoadingView(
        progressStage: .modelLoading,
        analysisProgress: 0.55,
        completedSegmentCount: 1,
        totalSegmentCount: 8,
        analysisStartedAt: Date().addingTimeInterval(-78),
        lastActivityAt: Date().addingTimeInterval(-60)
    )
    .preferredColorScheme(.dark)
}
