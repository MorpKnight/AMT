//
//  DocumentAnalysisLoadingView.swift
//  AMT
//
//  Created by Antigravity on 2026/09/01.
//

import SwiftUI
import Combine

struct DocumentAnalysisLoadingView: View {
    var progressStage: AIConnectorProgressStage = .idle
    var downloadProgress: Double = 0
    var generationProgress: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    @State private var displayedProgress: Double = 0.08
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var logoImageName: String {
        isDarkMode ? "logo_white" : "logo_black"
    }

    private var primaryColor: Color {
        isDarkMode ? .white : .black
    }

    private var trackColor: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Logo Image from Assets
            Image(logoImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 120)

            // MARK: - Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                        .frame(height: 6)

                    Capsule()
                        .fill(primaryColor)
                        .frame(width: max(16, min(geo.size.width, geo.size.width * displayedProgress)), height: 6)
                        .animation(.linear(duration: 0.05), value: displayedProgress)
                }
            }
            .frame(width: 180, height: 6)

            // MARK: - Status Label
            Text("Dokumenmu sedang dianalisis...")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(primaryColor)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            advanceProgress()
        }
        .onChange(of: progressStage) { _, newStage in
            if newStage == .completed {
                withAnimation(.easeOut(duration: 0.25)) {
                    displayedProgress = 1.0
                }
            }
        }
    }

    private var stageTarget: Double {
        if downloadProgress > 0 {
            return max(0.20, min(0.70, downloadProgress))
        }
        switch progressStage {
        case .idle:
            return 0.12
        case .segmenting:
            return 0.25
        case .semanticModelDownload, .modelDownload:
            return max(0.25, downloadProgress)
        case .semanticRetrieval, .modelLoading:
            return 0.50
        case .generation:
            let genOffset = min(0.42, Double(generationProgress) / 400.0)
            return min(0.95, 0.50 + genOffset)
        case .completed:
            return 1.0
        default:
            return 0.85
        }
    }

    private func advanceProgress() {
        guard progressStage != .completed else {
            if displayedProgress < 1.0 {
                displayedProgress = 1.0
            }
            return
        }

        let target = max(stageTarget, displayedProgress)
        if target > displayedProgress {
            // Smoothly catch up towards stage target
            let step = max(0.003, (target - displayedProgress) * 0.1)
            displayedProgress = min(target, displayedProgress + step)
        } else if displayedProgress < 0.95 {
            // Slowly crawl forward even while waiting on long tasks
            displayedProgress = min(0.95, displayedProgress + 0.001)
        }
    }
}

#Preview("Light Mode") {
    DocumentAnalysisLoadingView(
        progressStage: .generation,
        downloadProgress: 0.5,
        generationProgress: 120
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    DocumentAnalysisLoadingView(
        progressStage: .generation,
        downloadProgress: 0.5,
        generationProgress: 120
    )
    .preferredColorScheme(.dark)
}
