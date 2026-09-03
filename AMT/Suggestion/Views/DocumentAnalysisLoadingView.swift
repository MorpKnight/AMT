//
//  DocumentAnalysisLoadingView.swift
//  AMT
//
//  Created by Antigravity on 2026/09/01.
//

import Foundation
import SwiftUI

struct DocumentAnalysisLoadingView: View {
    let progress: AIConnectorProgressSnapshot
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

            VStack(alignment: .center, spacing: 14) {
                VStack(alignment: .center, spacing: 5) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .accessibilityLabel("Analisis sedang berjalan")

                        Text("Dokumen sedang dianalisis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(primaryColor)
                    }

                    Text(progress.stage.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.2), value: progress.stage)
                }
                .frame(maxWidth: .infinity)

                overallProgress

                if isStalled(at: currentDate) {
                    VStack(alignment: .center, spacing: 10) {
                        Label {
                            Text("Belum ada aktivitas selama 60 detik. Proses mungkin masih berjalan.")
                                .multilineTextAlignment(.center)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)

                        Button("Hentikan dan buka dokumen", action: onCancel)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var overallProgress: some View {
        if let fraction = progress.overallFraction {
            ProgressView(value: fraction)
                .frame(maxWidth: .infinity)
                .tint(primaryColor)
                .animation(.easeOut(duration: 0.2), value: fraction)
                .accessibilityLabel("Kemajuan analisis dokumen")
                .accessibilityValue("\(Int(fraction * 100)) persen")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .tint(primaryColor)
                .accessibilityLabel("Kemajuan analisis dokumen sedang disiapkan")
        }
    }

    private func isStalled(at date: Date) -> Bool {
        switch progress.stage {
        case .completed, .cancelled, .failed:
            return false
        default:
            return date.timeIntervalSince(progress.lastActivityAt)
                >= Self.stalledThreshold
        }
    }
}

#Preview("Definition Review · Light") {
    DocumentAnalysisLoadingView(
        progress: AIConnectorProgressSnapshot(
            stage: .definitionReview,
            overallFraction: 0.25,
            phaseFraction: nil,
            completedSegmentCount: 2,
            totalSegmentCount: 8,
            currentSegmentID: 3,
            generationCharacters: 120,
            startedAt: Date().addingTimeInterval(-18),
            lastActivityAt: Date().addingTimeInterval(-2)
        )
    )
    .preferredColorScheme(.light)
}

#Preview("Stalled · Light") {
    DocumentAnalysisLoadingView(
        progress: AIConnectorProgressSnapshot(
            stage: .generation,
            overallFraction: 0.25,
            phaseFraction: nil,
            completedSegmentCount: 2,
            totalSegmentCount: 8,
            currentSegmentID: 3,
            generationCharacters: 120,
            startedAt: Date().addingTimeInterval(-78),
            lastActivityAt: Date().addingTimeInterval(-60)
        )
    )
    .preferredColorScheme(.light)
}

#Preview("Semantic Download · Dark") {
    DocumentAnalysisLoadingView(
        progress: AIConnectorProgressSnapshot(
            stage: .semanticModelDownload,
            overallFraction: 0,
            phaseFraction: 0.42,
            completedSegmentCount: 0,
            totalSegmentCount: 8,
            currentSegmentID: 1,
            generationCharacters: 0,
            startedAt: Date().addingTimeInterval(-18),
            lastActivityAt: Date().addingTimeInterval(-2)
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Deterministic · Dark") {
    DocumentAnalysisLoadingView(
        progress: AIConnectorProgressSnapshot(
            stage: .deterministicReview,
            overallFraction: 0.5,
            phaseFraction: nil,
            completedSegmentCount: 4,
            totalSegmentCount: 8,
            currentSegmentID: 5,
            generationCharacters: 0,
            startedAt: Date().addingTimeInterval(-18),
            lastActivityAt: Date().addingTimeInterval(-2)
        )
    )
    .preferredColorScheme(.dark)
}
