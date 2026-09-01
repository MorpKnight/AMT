//
//  DocumentAnalysisLoadingView.swift
//  AMT
//
//  Created by Antigravity on 2026/09/01.
//

import SwiftUI

struct DocumentAnalysisLoadingView: View {
    var progressStage: AIConnectorProgressStage = .idle
    var downloadProgress: Double = 0
    var generationProgress: Int = 0

    @State private var isAnimating: Bool = false

    private var blueAccent: Color {
        Color(red: 0.08, green: 0.38, blue: 0.85)
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Logo Image from Assets
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 120)

            // MARK: - Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(blueAccent.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(blueAccent)
                        .frame(width: max(16, geo.size.width * effectiveProgress), height: 6)
                        .animation(.easeInOut(duration: 0.35), value: effectiveProgress)
                }
            }
            .frame(width: 180, height: 6)

            // MARK: - Status Label
            Text("Dokumenmu sedang dianalisis...")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(blueAccent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private var effectiveProgress: Double {
        if downloadProgress > 0 {
            return downloadProgress
        }
        switch progressStage {
        case .segmenting:
            return 0.15
        case .semanticModelDownload, .modelDownload:
            return max(0.2, downloadProgress)
        case .semanticRetrieval, .modelLoading:
            return 0.45
        case .generation:
            return min(0.92, 0.50 + Double(generationProgress) / 400.0)
        case .completed:
            return 1.0
        default:
            return isAnimating ? 0.70 : 0.30
        }
    }
}

#Preview {
    DocumentAnalysisLoadingView(
        progressStage: .generation,
        downloadProgress: 0.5,
        generationProgress: 120
    )
}
