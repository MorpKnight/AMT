import Accelerate
import Foundation

/// Capability boundary for the future BGE-M3 semantic retriever.
///
/// AMT intentionally keeps semantic generation disabled until a verified
/// BGE-M3 model and its matching tokenizer are shipped together. Returning a
/// synthetic vector would make unrelated legal definitions look relevant, so
/// callers must fall back to the lexical corpus retriever instead.
public struct BGEEmbedding: Sendable {
    public static let shared = BGEEmbedding()

    public let dimension = 1024
    public let isSemanticSearchAvailable = false

    public init() {}

    public func generateEmbedding(for text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BGEEmbeddingError.emptyInput
        }

        throw BGEEmbeddingError.verifiedModelAndTokenizerUnavailable
    }

    /// L2 normalization remains available for validating a future embedding
    /// implementation without enabling semantic retrieval prematurely.
    public func normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }

        var result = vector
        var sumSquares: Float = 0
        vDSP_svesq(result, 1, &sumSquares, vDSP_Length(result.count))

        let norm = sqrt(sumSquares)
        guard norm > 1e-6 else { return result }

        var divisor = norm
        vDSP_vsdiv(result, 1, &divisor, &result, 1, vDSP_Length(result.count))
        return result
    }
}

public enum BGEEmbeddingError: LocalizedError, Sendable {
    case emptyInput
    case verifiedModelAndTokenizerUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Teks query embedding kosong."
        case .verifiedModelAndTokenizerUnavailable:
            "Semantic retrieval dinonaktifkan sampai model dan tokenizer BGE-M3 yang terverifikasi tersedia."
        }
    }
}
