import Foundation

struct DocumentReviewProgress: Equatable, Sendable {
    let fraction: Double
    let detail: String
    let currentSegment: Int?
    let totalSegments: Int?

    init(
        fraction: Double,
        detail: String,
        currentSegment: Int? = nil,
        totalSegments: Int? = nil
    ) {
        self.fraction = min(max(fraction, 0), 1)
        self.detail = detail
        self.currentSegment = currentSegment
        self.totalSegments = totalSegments
    }
}

enum DocumentReviewAnalyzerError: LocalizedError, Equatable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            message
        }
    }
}

@MainActor
protocol DocumentReviewAnalyzer: AnyObject {
    func analyze(
        documentText: String,
        progress: @escaping (DocumentReviewProgress) -> Void
    ) async throws -> [AIValidatedReview]

    func cancel()
}

/// Adapts the existing AI Connector pipeline to the document-review lifecycle.
@MainActor
final class AIConnectorDocumentReviewAnalyzer: DocumentReviewAnalyzer {
    let viewModel: AIConnectorViewModel

    init(viewModel: AIConnectorViewModel) {
        self.viewModel = viewModel
    }

    func analyze(
        documentText: String,
        progress: @escaping (DocumentReviewProgress) -> Void
    ) async throws -> [AIValidatedReview] {
        viewModel.inputSource = .currentDocument
        viewModel.run(documentText: documentText)

        while viewModel.isRunning {
            try Task.checkCancellation()
            progress(currentProgress)
            try await Task.sleep(for: .milliseconds(100))
        }

        progress(currentProgress)

        switch viewModel.state {
        case .completed:
            return viewModel.validatedReviews
        case .cancelled:
            throw CancellationError()
        case let .failed(message):
            throw DocumentReviewAnalyzerError.failed(message)
        default:
            throw DocumentReviewAnalyzerError.failed("Analisis dokumen berhenti sebelum selesai.")
        }
    }

    func cancel() {
        viewModel.cancel()
    }

    private var currentProgress: DocumentReviewProgress {
        let fraction: Double
        let detail: String
        let currentSegment: Int?
        let totalSegments: Int?

        switch viewModel.state {
        case .idle:
            fraction = 0
            detail = "Menyiapkan analisis"
            currentSegment = nil
            totalSegments = nil
        case .segmenting:
            fraction = 0.05
            detail = "Membaca struktur dokumen"
            currentSegment = nil
            totalSegments = nil
        case .loading:
            fraction = 0.15
            detail = "Menyiapkan pemeriksaan"
            currentSegment = nil
            totalSegments = nil
        case let .downloading(value):
            fraction = 0.15 + min(max(value, 0), 1) * 0.25
            detail = "Menyiapkan model lokal"
            currentSegment = nil
            totalSegments = nil
        case let .reviewing(current, total):
            fraction = 0.4 + (Double(current) / Double(max(total, 1))) * 0.55
            let safeTotal = max(total, 1)
            let safeCurrent = min(max(current, 1), safeTotal)
            detail = "Memeriksa segmen \(safeCurrent) dari \(safeTotal)"
            currentSegment = safeCurrent
            totalSegments = safeTotal
        case .completed:
            fraction = 1
            let total = viewModel.segmentationResult?.segments.count
                ?? viewModel.processedSegmentCount
            detail = total > 0 ? "Semua \(total) segmen selesai" : "Analisis selesai"
            currentSegment = total > 0 ? total : nil
            totalSegments = total > 0 ? total : nil
        case .cancelled, .failed:
            fraction = 0
            detail = viewModel.progressStage.title
            currentSegment = nil
            totalSegments = nil
        }

        return DocumentReviewProgress(
            fraction: fraction,
            detail: detail,
            currentSegment: currentSegment,
            totalSegments: totalSegments
        )
    }
}
