import Foundation
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import HuggingFace
import Tokenizers

nonisolated enum LegalSemanticRetrieverError: Error, Equatable, LocalizedError, Sendable {
    case emptyQuery
    case invalidEmbeddingDimension
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Query semantik kosong."
        case .invalidEmbeddingDimension:
            "Dimensi embedding query tidak sesuai dengan corpus."
        case let .modelUnavailable(detail):
            "Model pencarian semantik tidak tersedia: \(detail)."
        }
    }
}

/// Lazy multilingual E5 runtime. The model is loaded once, on first semantic
/// query, and its container serializes all MLX access for the application.
actor LegalSemanticRetriever {
    let corpus: LegalCorpusStore

    private var modelContainer: EmbedderModelContainer?
    private var loadingTask: Task<EmbedderModelContainer, Error>?

    init(corpus: LegalCorpusStore) {
        self.corpus = corpus
    }

    var isLoaded: Bool {
        modelContainer != nil
    }

    func load(
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        _ = try await resolvedContainer(progress: progress)
    }

    func search(
        _ query: String,
        limit: Int,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> [LegalRetrievalMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw LegalSemanticRetrieverError.emptyQuery
        }
        guard limit > 0 else { return [] }

        let container = try await resolvedContainer(progress: progress)
        let vector = try await embed(
            "\(corpus.manifest.embedding.queryPrefix)\(trimmedQuery)",
            with: container
        )
        guard vector.count == corpus.manifest.embedding.dimension else {
            throw LegalSemanticRetrieverError.invalidEmbeddingDimension
        }
        return corpus.semanticMatches(for: vector, limit: limit)
    }

    private func resolvedContainer(
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EmbedderModelContainer {
        if let modelContainer {
            progress(1)
            return modelContainer
        }
        if let loadingTask {
            return try await loadingTask.value
        }

        let modelID = corpus.manifest.embedding.model
        let revision = corpus.manifest.embedding.revision
        let configuration = ModelConfiguration(id: modelID, revision: revision)
        let task = Task<EmbedderModelContainer, Error> {
            try await EmbedderModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration,
                progressHandler: { downloadProgress in
                    progress(downloadProgress.fractionCompleted)
                }
            )
        }
        loadingTask = task

        do {
            let loaded = try await task.value
            modelContainer = loaded
            loadingTask = nil
            progress(1)
            return loaded
        } catch {
            loadingTask = nil
            throw LegalSemanticRetrieverError.modelUnavailable(error.localizedDescription)
        }
    }

    private func embed(
        _ text: String,
        with container: EmbedderModelContainer
    ) async throws -> [Float] {
        try await container.perform { context in
            let tokenIDs = context.tokenizer.encode(text: text, addSpecialTokens: true)
            guard !tokenIDs.isEmpty else {
                throw LegalSemanticRetrieverError.emptyQuery
            }

            let input = stacked([MLXArray(tokenIDs)])
            let eosTokenID = context.tokenizer.eosTokenId ?? 0
            let mask = input .!= eosTokenID
            let tokenTypes = MLXArray.zeros(like: input)
            let output = context.model(
                input,
                positionIds: nil,
                tokenTypeIds: tokenTypes,
                attentionMask: mask
            )
            let pooled = context.pooling(
                output,
                mask: mask,
                normalize: true,
                applyLayerNorm: true
            )
            pooled.eval()
            return pooled.map { $0.asArray(Float.self) }.first ?? []
        }
    }
}
