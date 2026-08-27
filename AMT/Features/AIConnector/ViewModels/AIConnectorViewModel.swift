import Foundation
import Observation

@MainActor
@Observable
final class AIConnectorViewModel {
    private static let previewCharacters = 2_000

    var inputSource: AIConnectorInputSource = .currentDocument
    var selectedSampleID = "redundant-wajib-untuk"
    var thinkingEnabled = false

    private(set) var state: AIConnectorRunState = .idle
    private(set) var output = ""
    private(set) var errorMessage: String?
    private(set) var downloadProgress = 0.0
    private(set) var inputTokenCount: Int?
    private(set) var inputWasTruncated = false

    private let service: QwenSuggestionService
    private var task: Task<Void, Never>?
    private var activeOperationID: UUID?

    init(service: QwenSuggestionService) {
        self.service = service
    }

    var isRunning: Bool {
        state.isRunning
    }

    var selectedSample: AIConnectorSample {
        AIConnectorSample.samples.first(where: { $0.id == selectedSampleID })
            ?? AIConnectorSample.samples[0]
    }

    func inputPreview(documentText: String) -> String {
        let preview = String(sourceText(documentText: documentText).prefix(Self.previewCharacters))
        return sourceText(documentText: documentText).count > Self.previewCharacters
            ? preview + "…"
            : preview
    }

    private func sourceText(documentText: String) -> String {
        switch inputSource {
        case .currentDocument:
            documentText
        case .dummy:
            selectedSample.text
        }
    }

    func canRun(documentText: String) -> Bool {
        guard !isRunning else { return false }
        return !sourceText(documentText: documentText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func run(documentText: String) {
        resetInputMetadata()

        guard canRun(documentText: documentText) else {
            errorMessage = "Pilih atau masukkan teks sebelum menjalankan model."
            state = .failed(errorMessage ?? "Input tidak tersedia.")
            return
        }

        let sourceText = sourceText(documentText: documentText)
        let operationID = UUID()

        task?.cancel()
        activeOperationID = operationID
        output = ""
        errorMessage = nil
        downloadProgress = 0
        state = service.hasLoadedModel ? .generating : .loading

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await service.review(
                    text: sourceText,
                    thinkingEnabled: thinkingEnabled,
                    downloadProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeOperationID == operationID else { return }
                            self.downloadProgress = progress
                            self.state = .downloading(progress)
                        }
                    },
                    onInputPrepared: { [weak self] tokenCount, wasTruncated in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.inputTokenCount = tokenCount
                        self.inputWasTruncated = wasTruncated
                    },
                    onVisibleChunk: { [weak self] chunk in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.state = .generating
                        self.output += chunk
                    }
                )

                guard activeOperationID == operationID, !Task.isCancelled else { return }
                output = result
                state = .completed
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                errorMessage = error.localizedDescription
                state = .failed(errorMessage ?? "Model gagal dijalankan.")
                task = nil
            }
        }
    }

    func resetInputMetadata() {
        inputTokenCount = nil
        inputWasTruncated = false
    }

    func cancel() {
        activeOperationID = nil
        task?.cancel()
        task = nil
        service.cancelLoading()
        state = .cancelled
    }
}
