import Foundation

struct DocumentReviewProgress: Equatable, Sendable {
    let fraction: Double
    let detail: String

    init(fraction: Double, detail: String) {
        self.fraction = min(max(fraction, 0), 1)
        self.detail = detail
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
        switch viewModel.state {
        case .idle:
            fraction = 0
        case .segmenting:
            fraction = 0.05
        case .loading:
            fraction = 0.15
        case let .downloading(value):
            fraction = 0.15 + min(max(value, 0), 1) * 0.25
        case let .reviewing(current, total):
            fraction = 0.4 + (Double(current) / Double(max(total, 1))) * 0.55
        case .completed:
            fraction = 1
        case .cancelled, .failed:
            fraction = 0
        }

        return DocumentReviewProgress(
            fraction: fraction,
            detail: viewModel.progressStage.title
        )
    }
}
