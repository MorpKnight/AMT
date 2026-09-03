import CryptoKit
import Foundation
import HuggingFace
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import MLXNN
import Tokenizers

nonisolated enum AIConnectorLanguageScorerConfiguration {
    static let modelID = "citylighxts/TataKata"
    static let revision = "4b90902f013ea22096f47f99f3a7c8aac508e3c7"
    static let expectedModelSHA256 = "9e52c5e4334ce4428bf980aded27300617bec7a663b32600f5ab439211844883"
    static let configuredVocabularyCount = 50_000
    static let tokenizerVocabularyCount = 30_521
    static let maximumWordPieceWindow = 64
    static let minimumImprovementInNats = 0.25

    /// Bumping this value invalidates cached analysis when the scoring policy
    /// or the pinned TataKata artifact changes.
    static let pipelineVersion = "tatakata-pilot-v1-mean-pll-64wp-delta-025"
    static let cacheKey = "\(modelID)@\(revision):\(pipelineVersion)"
}

/// Keeps the hand-off into candidate-first processing closed over the pinned
/// TataKata artifact and its calibrated score threshold. A scorer failure or a
/// malformed mock must never turn an arbitrary replacement into a Qwen input.
nonisolated enum AIConnectorLanguageScorePolicy {
    static func isEligible(_ evidence: AIConnectorLanguageScoreEvidence) -> Bool {
        evidence.modelID == AIConnectorLanguageScorerConfiguration.modelID
            && evidence.revision == AIConnectorLanguageScorerConfiguration.revision
            && evidence.tokenizerVocabularyCount
                == AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount
            && evidence.configuredVocabularyCount
                == AIConnectorLanguageScorerConfiguration.configuredVocabularyCount
            && evidence.originalScore.isFinite
            && evidence.replacementScore.isFinite
            && evidence.delta.isFinite
            && evidence.delta >= AIConnectorLanguageScorerConfiguration.minimumImprovementInNats
            && !evidence.sourceWindow.isEmpty
    }
}

nonisolated enum TataKataLanguageScorerError: Error, Equatable, LocalizedError, Sendable {
    case modelUnavailable(String)
    case checksumMismatch
    case invalidConfiguration(String)
    case invalidWeights(String)
    case invalidTokenizer(String)
    case invalidTokenization
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case let .modelUnavailable(detail):
            "Model TataKata tidak tersedia: \(detail)."
        case .checksumMismatch:
            "Checksum model TataKata tidak sesuai dengan revision yang dipatok."
        case let .invalidConfiguration(detail):
            "Konfigurasi TataKata tidak didukung: \(detail)."
        case let .invalidWeights(detail):
            "Tensor TataKata tidak sesuai: \(detail)."
        case let .invalidTokenizer(detail):
            "Tokenizer TataKata tidak sesuai: \(detail)."
        case .invalidTokenization:
            "Teks kandidat tidak dapat ditokenisasi dengan aman."
        case .inferenceFailed:
            "Inference TataKata gagal."
        }
    }
}

/// Stable key for a mean-PLL score. The source window is already bounded by
/// the runtime, while the revision prevents scores from different artifacts
/// from being reused.
nonisolated struct AIConnectorLanguageScoreCacheKey: Hashable, Sendable {
    let revision: String
    let sourceWindow: String
    let replacement: String
    let replacementSourceLocation: Int?
    let replacementSourceLength: Int?

    init(
        revision: String,
        sourceWindow: String,
        replacement: String,
        replacementSourceLocation: Int? = nil,
        replacementSourceLength: Int? = nil
    ) {
        self.revision = revision
        self.sourceWindow = sourceWindow
        self.replacement = replacement
        self.replacementSourceLocation = replacementSourceLocation
        self.replacementSourceLength = replacementSourceLength
    }
}

/// TataKata's checkpoint follows the BERT MLM transform, but the bundled
/// MLX BERT implementation uses SiLU in its private head. Keep the backbone
/// and the head explicit so this pilot matches the checkpoint's GELU head and
/// tied word embeddings.
private nonisolated final class TataKataMLMTransform: Module {
    @ModuleInfo(key: "dense") var dense: Linear
    @ModuleInfo(key: "ln") var layerNorm: LayerNorm

    init(hiddenSize: Int, layerNormEps: Float) {
        _dense.wrappedValue = Linear(hiddenSize, hiddenSize, bias: true)
        _layerNorm.wrappedValue = LayerNorm(
            dimensions: hiddenSize,
            eps: layerNormEps
        )
    }

    func callAsFunction(_ inputs: MLXArray) -> MLXArray {
        layerNorm(gelu(dense(inputs)))
    }
}

/// Bridges Hugging Face's synchronous `@Sendable` callback to the main-actor
/// progress callback while preserving callback order. The relay is drained
/// before the scorer publishes the loading stage, so a late download update
/// cannot move the UI backwards into an earlier phase.
private nonisolated final class TataKataDownloadProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @MainActor @Sendable (AIConnectorLanguageScoringProgress) -> Void
    private var pendingDelivery: Task<Void, Never>?

    init(
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void
    ) {
        self.progress = progress
    }

    func enqueue(fraction: Double) {
        lock.lock()
        let previous = pendingDelivery
        let next = Task { @MainActor [progress, previous] in
            if let previous {
                await previous.value
            }
            progress(.downloading(fraction))
        }
        pendingDelivery = next
        lock.unlock()
    }

    func drain() async {
        await pendingTask()?.value
    }

    private func pendingTask() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return pendingDelivery
    }
}

/// A lazy, actor-isolated TataKata scorer. The actor owns all MLX objects and
/// therefore serializes model access without exposing them to the UI layer.
actor TataKataLanguageScorer: AIConnectorLanguageCandidateScoring {
    static let modelID = AIConnectorLanguageScorerConfiguration.modelID
    static let revision = AIConnectorLanguageScorerConfiguration.revision
    static let expectedModelSHA256 = AIConnectorLanguageScorerConfiguration.expectedModelSHA256

    nonisolated static let pipelineVersion = AIConnectorLanguageScorerConfiguration.pipelineVersion

    private let modelDirectory: URL?
    private var runtime: TataKataRuntime?
    private var loadingTask: Task<TataKataRuntime, Error>?

    init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory
    }

    var isLoaded: Bool {
        runtime != nil
    }

    func load(
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void = { _ in }
    ) async throws {
        _ = try await resolvedRuntime(progress: progress)
    }

    func score(
        segment: AIReviewSegment,
        candidates: [AIConnectorSpellingCandidate],
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void = { _ in }
    ) async throws -> [AIConnectorSpellingCandidate] {
        guard !candidates.isEmpty else { return [] }
        let runtime = try await resolvedRuntime(progress: progress)
        await progress(.scoring(0))
        return try await runtime.score(
            segment: segment,
            candidates: candidates,
            progress: progress,
            minimumImprovement: AIConnectorLanguageScorerConfiguration.minimumImprovementInNats
        )
    }

    /// Returns the best scored candidate per source span, including candidates
    /// below the production threshold. This is intentionally a diagnostics
    /// boundary for opt-in benchmark tests; candidate-first production flow
    /// uses `score`, which returns only threshold-qualified candidates.
    func scoreForDiagnostics(
        segment: AIReviewSegment,
        candidates: [AIConnectorSpellingCandidate],
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void = { _ in }
    ) async throws -> [AIConnectorSpellingCandidate] {
        guard !candidates.isEmpty else { return [] }
        let runtime = try await resolvedRuntime(progress: progress)
        await progress(.scoring(0))
        return try await runtime.score(
            segment: segment,
            candidates: candidates,
            progress: progress,
            minimumImprovement: nil
        )
    }

    private func resolvedRuntime(
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void
    ) async throws -> TataKataRuntime {
        if let runtime {
            return runtime
        }
        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task<TataKataRuntime, Error> {
            let directory: URL
            if let modelDirectory {
                directory = modelDirectory
            } else {
                let configuration = ModelConfiguration(
                    id: AIConnectorLanguageScorerConfiguration.modelID,
                    revision: AIConnectorLanguageScorerConfiguration.revision
                )
                let progressRelay = TataKataDownloadProgressRelay(progress: progress)
                let resolved: ResolvedModelConfiguration
                do {
                    resolved = try await resolve(
                        configuration: configuration,
                        from: #hubDownloader(),
                        useLatest: false,
                        progressHandler: { downloadProgress in
                            progressRelay.enqueue(
                                fraction: downloadProgress.fractionCompleted
                            )
                        }
                    )
                } catch {
                    await progressRelay.drain()
                    throw error
                }
                await progressRelay.drain()
                directory = resolved.modelDirectory
            }
            await progress(.loading)
            return try await TataKataRuntime.load(from: directory)
        }
        loadingTask = task

        do {
            let loaded = try await task.value
            runtime = loaded
            loadingTask = nil
            return loaded
        } catch is CancellationError {
            loadingTask = nil
            throw CancellationError()
        } catch let error as TataKataLanguageScorerError {
            loadingTask = nil
            throw error
        } catch {
            loadingTask = nil
            throw TataKataLanguageScorerError.modelUnavailable(error.localizedDescription)
        }
    }
}

private actor TataKataRuntime {
    private let tokenizer: any Tokenizers.Tokenizer
    private let backbone: BertModel
    private let transform: TataKataMLMTransform
    private let wordEmbeddingProjection: MLXArray
    private let vocabularyBias: MLXArray
    private let maskTokenID: Int
    private let unknownTokenID: Int?
    private let specialTokenIDs: Set<Int>
    private let revision: String
    private var scoreCache: [AIConnectorLanguageScoreCacheKey: Double] = [:]

    private init(
        tokenizer: any Tokenizers.Tokenizer,
        backbone: BertModel,
        transform: TataKataMLMTransform,
        wordEmbeddingProjection: MLXArray,
        vocabularyBias: MLXArray,
        maskTokenID: Int,
        unknownTokenID: Int?,
        specialTokenIDs: Set<Int>,
        revision: String
    ) {
        self.tokenizer = tokenizer
        self.backbone = backbone
        self.transform = transform
        self.wordEmbeddingProjection = wordEmbeddingProjection
        self.vocabularyBias = vocabularyBias
        self.maskTokenID = maskTokenID
        self.unknownTokenID = unknownTokenID
        self.specialTokenIDs = specialTokenIDs
        self.revision = revision
    }

    static func load(from directory: URL) async throws -> TataKataRuntime {
        let decoder = JSONDecoder()
        let configURL = directory.appendingPathComponent("config.json")
        let configData: Data
        do {
            configData = try Data(contentsOf: configURL)
        } catch {
            throw TataKataLanguageScorerError.modelUnavailable(error.localizedDescription)
        }

        let config = try decoder.decode(LocalBertConfiguration.self, from: configData)
        guard config.modelType == "bert",
              config.architectures.contains("BertForMaskedLM"),
              config.hiddenAct.lowercased() == "gelu",
              config.vocabSize == AIConnectorLanguageScorerConfiguration.configuredVocabularyCount,
              config.hiddenSize == 768,
              config.intermediateSize == 3072,
              config.numHiddenLayers == 12,
              config.numAttentionHeads == 12,
              config.maxPositionEmbeddings == 512,
              config.typeVocabSize == 2 else {
            throw TataKataLanguageScorerError.invalidConfiguration(
                "arsitektur BERT/GELU atau ukuran tensor tidak cocok"
            )
        }

        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        let tokenizerVocabularyCount = try validateTokenizerVocabulary(tokenizer)
        guard tokenizerVocabularyCount == AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount else {
            throw TataKataLanguageScorerError.invalidTokenizer(
                "tokenizer memiliki \(tokenizerVocabularyCount) token"
            )
        }

        let requiredSpecialTokens = ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]"]
        let specialTokenIDs = Set(requiredSpecialTokens.compactMap {
            tokenizer.convertTokenToId($0)
        })
        guard specialTokenIDs.count == requiredSpecialTokens.count,
              specialTokenIDs == Set(0 ..< requiredSpecialTokens.count),
              tokenizer.convertTokenToId("[MASK]") == 4 else {
            throw TataKataLanguageScorerError.invalidTokenizer(
                "ID special token BERT tidak sesuai"
            )
        }

        let modelURL = directory.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TataKataLanguageScorerError.modelUnavailable(
                "model.safetensors tidak ditemukan"
            )
        }
        guard try sha256(of: modelURL) == AIConnectorLanguageScorerConfiguration.expectedModelSHA256 else {
            throw TataKataLanguageScorerError.checksumMismatch
        }

        let bertConfiguration: BertConfiguration
        do {
            bertConfiguration = try decoder.decode(BertConfiguration.self, from: configData)
        } catch {
            throw TataKataLanguageScorerError.invalidConfiguration(error.localizedDescription)
        }

        let rawWeights: [String: MLXArray]
        do {
            rawWeights = try loadArrays(url: modelURL)
        } catch {
            throw TataKataLanguageScorerError.invalidWeights(error.localizedDescription)
        }

        let backbone = BertModel(bertConfiguration, lmHead: false)
        let sanitizedWeights = backbone.sanitize(weights: rawWeights)
        let backboneWeights = sanitizedWeights.filter { key, _ in
            key.hasPrefix("embeddings.") || key.hasPrefix("encoder.")
        }
        do {
            try backbone.update(
                parameters: ModuleParameters.unflattened(backboneWeights),
                verify: [.noUnusedKeys, .shapeMismatch]
            )
        } catch {
            throw TataKataLanguageScorerError.invalidWeights(
                "backbone: \(error.localizedDescription)"
            )
        }

        let transform = TataKataMLMTransform(
            hiddenSize: config.hiddenSize,
            layerNormEps: Float(config.layerNormEps)
        )
        let transformWeights: [String: MLXArray] = [
            "dense.weight": try requiredWeight(
                sanitizedWeights,
                key: "lm_head.dense.weight"
            ),
            "dense.bias": try requiredWeight(
                sanitizedWeights,
                key: "lm_head.dense.bias"
            ),
            "ln.weight": try requiredWeight(
                sanitizedWeights,
                key: "lm_head.ln.weight"
            ),
            "ln.bias": try requiredWeight(
                sanitizedWeights,
                key: "lm_head.ln.bias"
            )
        ]
        do {
            try transform.update(
                parameters: ModuleParameters.unflattened(transformWeights),
                verify: [.noUnusedKeys, .shapeMismatch]
            )
        } catch {
            throw TataKataLanguageScorerError.invalidWeights(
                "GELU MLM head: \(error.localizedDescription)"
            )
        }

        guard let wordEmbeddings = rawWeights["bert.embeddings.word_embeddings.weight"],
              wordEmbeddings.shape == [config.vocabSize, config.hiddenSize],
              let bias = rawWeights["cls.predictions.bias"],
              bias.shape == [config.vocabSize] else {
            throw TataKataLanguageScorerError.invalidWeights(
                "embedding tied atau bias tidak berukuran 50000"
            )
        }

        let validVocabularyRange = 0 ..< AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount
        let projection = wordEmbeddings[validVocabularyRange].transposed()
        let vocabularyBias = bias[validVocabularyRange]

        return TataKataRuntime(
            tokenizer: tokenizer,
            backbone: backbone,
            transform: transform,
            wordEmbeddingProjection: projection,
            vocabularyBias: vocabularyBias,
            maskTokenID: 4,
            unknownTokenID: tokenizer.convertTokenToId("[UNK]"),
            specialTokenIDs: specialTokenIDs,
            revision: AIConnectorLanguageScorerConfiguration.revision
        )
    }

    func score(
        segment: AIReviewSegment,
        candidates: [AIConnectorSpellingCandidate],
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void,
        minimumImprovement: Double?
    ) async throws -> [AIConnectorSpellingCandidate] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            "\(candidate.sourceLocation):\(candidate.sourceLength):\(candidate.original)"
        }
        let groups = grouped.values.sorted {
            ($0.first?.sourceLocation ?? 0) < ($1.first?.sourceLocation ?? 0)
        }
        var selected: [AIConnectorSpellingCandidate] = []

        for (index, group) in groups.enumerated() {
            try Task.checkCancellation()
            guard let first = group.first else { continue }
            let window = try makeWindow(for: first, in: segment.targetText)
            let originalScore = try scoreVariant(
                window: window.text,
                replacement: nil
            )

            var best: (candidate: AIConnectorSpellingCandidate, score: Double)?
            for candidate in group.sorted(by: { lhs, rhs in
                if lhs.sourceRank != rhs.sourceRank {
                    return lhs.sourceRank < rhs.sourceRank
                }
                return lhs.replacement < rhs.replacement
            }) {
                try Task.checkCancellation()
                let score = try scoreVariant(
                    window: window.text,
                    replacement: candidate.replacement,
                    sourceRange: window.range
                )
                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }

            if let best,
               minimumImprovement == nil
                || best.score >= originalScore + (minimumImprovement ?? 0) {
                let evidence = AIConnectorLanguageScoreEvidence(
                    modelID: AIConnectorLanguageScorerConfiguration.modelID,
                    revision: revision,
                    sourceWindow: window.text,
                    originalScore: originalScore,
                    replacementScore: best.score,
                    delta: best.score - originalScore,
                    tokenizerVocabularyCount: AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount,
                    configuredVocabularyCount: AIConnectorLanguageScorerConfiguration.configuredVocabularyCount
                )
                selected.append(
                    AIConnectorSpellingCandidate(
                        original: best.candidate.original,
                        replacement: best.candidate.replacement,
                        sourceLocation: best.candidate.sourceLocation,
                        sourceLength: best.candidate.sourceLength,
                        sourceRank: best.candidate.sourceRank,
                        evidence: evidence
                    )
                )
            }
            await progress(.scoring(Double(index + 1) / Double(max(groups.count, 1))))
        }

        return selected.sorted { lhs, rhs in
            let lhsDelta = lhs.evidence?.delta ?? -.greatestFiniteMagnitude
            let rhsDelta = rhs.evidence?.delta ?? -.greatestFiniteMagnitude
            if lhsDelta != rhsDelta { return lhsDelta > rhsDelta }
            return lhs.sourceLocation < rhs.sourceLocation
        }.prefix(1).map { $0 }
    }

    private func scoreVariant(
        window: String,
        replacement: String?,
        sourceRange: NSRange? = nil
    ) throws -> Double {
        let cacheReplacement = replacement ?? "<ORIGINAL>"
        let cacheKey = AIConnectorLanguageScoreCacheKey(
            revision: revision,
            sourceWindow: window,
            replacement: cacheReplacement,
            replacementSourceLocation: sourceRange?.location,
            replacementSourceLength: sourceRange?.length
        )
        if let cached = scoreCache[cacheKey] {
            return cached
        }

        let scoredText: String
        if let replacement, let sourceRange {
            scoredText = (window as NSString).replacingCharacters(
                in: sourceRange,
                with: replacement
            )
        } else {
            scoredText = window
        }
        let score = try pseudoLogLikelihood(of: scoredText)
        scoreCache[cacheKey] = score
        return score
    }

    private func pseudoLogLikelihood(of text: String) throws -> Double {
        let tokenIDs = tokenizer.encode(text: text, addSpecialTokens: true)
        guard !tokenIDs.isEmpty,
              tokenIDs.count <= AIConnectorLanguageScorerConfiguration.maximumWordPieceWindow,
              tokenIDs.allSatisfy({ (0 ..< AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount).contains($0) }),
              !(unknownTokenID.map { tokenIDs.contains($0) } ?? false) else {
            throw TataKataLanguageScorerError.invalidTokenization
        }

        let contentPositions = tokenIDs.indices.filter {
            !specialTokenIDs.contains(tokenIDs[$0])
        }
        guard !contentPositions.isEmpty else {
            throw TataKataLanguageScorerError.invalidTokenization
        }

        var totalLogProbability = 0.0
        for position in contentPositions {
            var maskedIDs = tokenIDs
            let targetID = maskedIDs[position]
            maskedIDs[position] = maskTokenID
            // BertModel accepts one-dimensional input IDs by reshaping them
            // internally, but it does not reshape the optional token-type and
            // attention masks. Keep all three inputs batched so the mask
            // expansion remains [batch, heads, sequence, sequence].
            let input = MLXArray(maskedIDs).reshaped(1, -1)
            let tokenTypes = MLXArray.zeros(like: input)
            let attentionMask = MLXArray.ones(like: input)
            let output = backbone(
                input,
                positionIds: nil,
                tokenTypeIds: tokenTypes,
                attentionMask: attentionMask
            )
            guard let hiddenStates = output.hiddenStates else {
                throw TataKataLanguageScorerError.inferenceFailed
            }
            let transformed = transform(hiddenStates)
            let logits = transformed.matmul(wordEmbeddingProjection) + vocabularyBias
            let logProbabilities = logSoftmax(logits, axis: -1)
            let value = Double(
                logProbabilities[0, position, targetID].item(Float.self)
            )
            guard value.isFinite else {
                throw TataKataLanguageScorerError.inferenceFailed
            }
            totalLogProbability += value
        }

        return totalLogProbability / Double(contentPositions.count)
    }

    private func makeWindow(
        for candidate: AIConnectorSpellingCandidate,
        in text: String
    ) throws -> TextWindow {
        let sourceRange = NSRange(
            location: candidate.sourceLocation,
            length: candidate.sourceLength
        )
        let nsText = text as NSString
        guard sourceRange.location >= 0,
              sourceRange.length == candidate.original.utf16.count,
              NSMaxRange(sourceRange) <= nsText.length,
              nsText.substring(with: sourceRange) == candidate.original else {
            throw TataKataLanguageScorerError.invalidTokenization
        }

        if tokenizer.encode(text: text, addSpecialTokens: true).count
            <= AIConnectorLanguageScorerConfiguration.maximumWordPieceWindow {
            return TextWindow(text: text, range: sourceRange)
        }

        var wordRanges: [NSRange] = []
        text.enumerateSubstrings(
            in: text.startIndex ..< text.endIndex,
            options: .byWords
        ) { _, substringRange, _, _ in
            wordRanges.append(NSRange(substringRange, in: text))
        }
        guard let wordIndex = wordRanges.firstIndex(where: { wordRange in
            wordRange.location <= sourceRange.location
                && NSMaxRange(wordRange) >= NSMaxRange(sourceRange)
        }) else {
            throw TataKataLanguageScorerError.invalidTokenization
        }

        var start = max(0, wordIndex - 32)
        var end = min(wordRanges.count, wordIndex + 33)
        while start < end {
            let windowRange = NSRange(
                location: wordRanges[start].location,
                length: NSMaxRange(wordRanges[end - 1]) - wordRanges[start].location
            )
            let windowText = nsText.substring(with: windowRange)
            if tokenizer.encode(text: windowText, addSpecialTokens: true).count
                <= AIConnectorLanguageScorerConfiguration.maximumWordPieceWindow {
                return TextWindow(
                    text: windowText,
                    range: NSRange(
                        location: sourceRange.location - windowRange.location,
                        length: sourceRange.length
                    )
                )
            }

            let wordsBefore = wordIndex - start
            let wordsAfter = end - wordIndex - 1
            if wordsAfter >= wordsBefore, end > wordIndex + 1 {
                end -= 1
            } else if start < wordIndex {
                start += 1
            } else if end > wordIndex + 1 {
                end -= 1
            } else {
                throw TataKataLanguageScorerError.invalidTokenization
            }
        }

        throw TataKataLanguageScorerError.invalidTokenization
    }

    private struct TextWindow: Sendable {
        let text: String
        let range: NSRange
    }

    private struct LocalBertConfiguration: Decodable {
        let modelType: String
        let architectures: [String]
        let hiddenAct: String
        let vocabSize: Int
        let hiddenSize: Int
        let intermediateSize: Int
        let numHiddenLayers: Int
        let numAttentionHeads: Int
        let maxPositionEmbeddings: Int
        let typeVocabSize: Int
        let layerNormEps: Double

        enum CodingKeys: String, CodingKey {
            case modelType = "model_type"
            case architectures
            case hiddenAct = "hidden_act"
            case vocabSize = "vocab_size"
            case hiddenSize = "hidden_size"
            case intermediateSize = "intermediate_size"
            case numHiddenLayers = "num_hidden_layers"
            case numAttentionHeads = "num_attention_heads"
            case maxPositionEmbeddings = "max_position_embeddings"
            case typeVocabSize = "type_vocab_size"
            case layerNormEps = "layer_norm_eps"
        }
    }

    private static func requiredWeight(
        _ weights: [String: MLXArray],
        key: String
    ) throws -> MLXArray {
        guard let weight = weights[key] else {
            throw TataKataLanguageScorerError.invalidWeights("missing \(key)")
        }
        return weight
    }

    private static func validateTokenizerVocabulary(
        _ tokenizer: any Tokenizers.Tokenizer
    ) throws -> Int {
        let expectedCount = AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount
        guard (0 ..< expectedCount).allSatisfy({
            tokenizer.convertIdToToken($0) != nil
        }), tokenizer.convertIdToToken(expectedCount) == nil else {
            throw TataKataLanguageScorerError.invalidTokenizer(
                "ID tokenizer tidak membentuk vocabulary 0..<\(expectedCount)"
            )
        }
        return expectedCount
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
