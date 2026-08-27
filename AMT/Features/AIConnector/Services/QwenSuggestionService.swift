import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import HuggingFace
import Tokenizers

enum QwenSuggestionError: LocalizedError {
    case emptyInput
    case incompleteThinking
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Tidak ada teks untuk ditinjau."
        case .incompleteThinking:
            "Thinking mode berhenti sebelum jawaban final terbentuk. Coba matikan thinking mode."
        case .emptyResponse:
            "Model tidak menghasilkan jawaban yang dapat ditampilkan."
        }
    }
}

@MainActor
final class QwenSuggestionService {
    private static let modelConfiguration = ModelConfiguration(
        id: "mlx-community/Qwen3.5-2B-4bit",
        revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207",
        extraEOSTokens: ["<|im_end|>"]
    )

    private static let systemPrompt = """
    Anda adalah peninjau bahasa dokumen hukum Indonesia yang berhati-hati.
    Fokus hanya pada ejaan, tata bahasa, kejelasan, dan konsistensi istilah.
    Pertahankan makna hukum, nama, angka, tanggal, istilah terdefinisi, hak, dan kewajiban.
    Jangan membuat aturan, sumber, kutipan, atau kesimpulan hukum.
    Jika perubahan dapat memengaruhi makna hukum, tulis \"Perlu review manusia\" dan jangan menulis ulang klausul.

    Jawab ringkas dalam bahasa Indonesia dengan format:
    Status:
    Temuan:
    Usulan:
    Alasan:

    Jika tidak ada masalah yang jelas, gunakan \"Status: Tidak ada saran\".
    """

    private var modelContainer: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?

    var hasLoadedModel: Bool {
        modelContainer != nil
    }

    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    func review(
        text: String,
        thinkingEnabled: Bool,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        onVisibleChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwenSuggestionError.emptyInput
        }

        let container = try await loadModel(downloadProgress: downloadProgress)
        try Task.checkCancellation()

        let session = ChatSession(
            container,
            instructions: Self.systemPrompt,
            generateParameters: generationParameters(thinkingEnabled: thinkingEnabled),
            additionalContext: ["enable_thinking": thinkingEnabled]
        )

        var rawOutput = ""
        var emittedCharacterCount = 0
        let prompt = """
        Tinjau teks berikut:
        ---
        \(text)
        ---
        """

        for try await chunk in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            rawOutput += chunk

            let visibleOutput = Self.visibleResponse(from: rawOutput)
            guard visibleOutput.count > emittedCharacterCount else { continue }

            let newCharacters = String(visibleOutput.dropFirst(emittedCharacterCount))
            emittedCharacterCount = visibleOutput.count
            onVisibleChunk(newCharacters)
        }

        if thinkingEnabled && !rawOutput.contains("</think>") {
            throw QwenSuggestionError.incompleteThinking
        }

        let finalResponse = Self.visibleResponse(from: rawOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !finalResponse.isEmpty else {
            throw QwenSuggestionError.emptyResponse
        }

        return finalResponse
    }

    private func loadModel(
        downloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ModelContainer {
        if let modelContainer {
            return modelContainer
        }

        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task { @Sendable in
            try await #huggingFaceLoadModelContainer(
                configuration: Self.modelConfiguration,
                progressHandler: { progress in
                    downloadProgress(progress.fractionCompleted)
                }
            )
        }
        loadingTask = task

        do {
            let container = try await task.value
            try Task.checkCancellation()
            modelContainer = container
            loadingTask = nil
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private func generationParameters(thinkingEnabled: Bool) -> GenerateParameters {
        if thinkingEnabled {
            return GenerateParameters(
                maxTokens: 2_048,
                temperature: 1.0,
                topP: 0.95,
                topK: 20,
                presencePenalty: 1.5,
                seed: 42
            )
        }

        return GenerateParameters(
            maxTokens: 512,
            temperature: 1.0,
            topP: 1.0,
            topK: 20,
            presencePenalty: 2.0,
            seed: 42
        )
    }

    private static func visibleResponse(from rawOutput: String) -> String {
        var response = rawOutput

        if let closingThinkTag = response.range(of: "</think>") {
            response = String(response[closingThinkTag.upperBound...])
        } else if response.contains("<think>") {
            return ""
        }

        response = response.replacingOccurrences(of: "<think>", with: "")
        response = response.replacingOccurrences(of: "</think>", with: "")
        response = response.replacingOccurrences(of: "<|im_end|>", with: "")
        return response
    }
}
