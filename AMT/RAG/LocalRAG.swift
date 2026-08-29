import Foundation
import Accelerate

public struct LocalRAGMetadata: Codable, Sendable {
    public let model: String
    public let dimension: Int
    public let documentCount: Int
    public let normalized: Bool
    public let similarity: String
    public let topK: Int
    public let threshold: Float

    enum CodingKeys: String, CodingKey {
        case model
        case dimension
        case documentCount = "document_count"
        case normalized
        case similarity
        case topK = "top_k"
        case threshold
    }
}

public struct RAGSearchResult: Identifiable, Hashable, Sendable {
    public let document: RAGDocument
    public let score: Float
    public let rank: Int

    public var id: String { "\(rank)-\(document.istilah)" }

    public init(document: RAGDocument, score: Float, rank: Int) {
        self.document = document
        self.score = score
        self.rank = rank
    }
}

public final class LocalRAG: @unchecked Sendable {
    public static let shared = LocalRAG()

    public private(set) var documents: [RAGDocument] = []
    public private(set) var embeddings: [Float] = [] // Row-major: count * dimension
    public private(set) var metadata: LocalRAGMetadata?
    public private(set) var isLoaded: Bool = false

    private let queue = DispatchQueue(label: "com.amt.LocalRAG", qos: .userInitiated)

    public init() {
        loadDataIfNeeded()
    }

    public func loadDataIfNeeded(bundle: Bundle = .main) {
        queue.sync {
            guard !isLoaded else { return }
            loadData(bundle: bundle)
        }
    }

    private func loadData(bundle: Bundle) {
        // 1. Locate rag_export resources
        let jsonURL = findResource(name: "documents", ext: "json", in: bundle)
        let binURL = findResource(name: "embeddings", ext: "bin", in: bundle)
        let metaURL = findResource(name: "metadata", ext: "json", in: bundle)

        // Load metadata
        if let metaURL = metaURL, let metaData = try? Data(contentsOf: metaURL) {
            self.metadata = try? JSONDecoder().decode(LocalRAGMetadata.self, from: metaData)
        }

        // Load documents
        if let jsonURL = jsonURL, let docData = try? Data(contentsOf: jsonURL) {
            self.documents = (try? JSONDecoder().decode([RAGDocument].self, from: docData)) ?? []
        }

        // Load binary embeddings
        if let binURL = binURL, let rawBinData = try? Data(contentsOf: binURL) {
            let floatCount = rawBinData.count / MemoryLayout<Float>.size
            var floats = [Float](repeating: 0, count: floatCount)
            _ = floats.withUnsafeMutableBytes { ptr in
                rawBinData.copyBytes(to: ptr)
            }
            self.embeddings = floats
        }

        if !documents.isEmpty && !embeddings.isEmpty {
            self.isLoaded = true
        }
    }

    private func findResource(name: String, ext: String, in bundle: Bundle) -> URL? {
        let bundleForClass = Bundle(for: LocalRAG.self)
        for b in [bundle, bundleForClass, Bundle.main] {
            if let url = b.url(forResource: name, withExtension: ext, subdirectory: "rag_export") ??
                b.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        // Fallback for file system relative paths in dev/testing environments
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        let possiblePaths = [
            "\(currentDir)/AMT/Resources/rag_export/\(name).\(ext)",
            "\(currentDir)/Resources/rag_export/\(name).\(ext)",
            "\(currentDir)/rag_export/\(name).\(ext)",
            "/Users/bayudf/Documents/GitHub/AMT/AMT/Resources/rag_export/\(name).\(ext)"
        ]
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }


    /// Search the document vector store using a 1024-dimensional query embedding vector (BAAI/bge-m3).
    /// Returns ranked RAGSearchResult matches ordered by similarity score.
    public func search(
        queryEmbedding: [Float],
        topK: Int? = nil,
        minThreshold: Float? = nil
    ) -> [RAGSearchResult] {
        guard isLoaded, !documents.isEmpty, !embeddings.isEmpty else {
            return []
        }

        let dimension = metadata?.dimension ?? 1024
        guard queryEmbedding.count == dimension else {
            return []
        }

        let k = topK ?? metadata?.topK ?? 5
        let threshold = minThreshold ?? metadata?.threshold ?? 0.6
        let docCount = min(documents.count, embeddings.count / dimension)

        var scores = [Float](repeating: 0, count: docCount)

        // Compute inner product (cosine similarity) for each document vector using SIMD vDSP
        queryEmbedding.withUnsafeBufferPointer { queryBuf in
            embeddings.withUnsafeBufferPointer { embBuf in
                guard let qBase = queryBuf.baseAddress, let eBase = embBuf.baseAddress else { return }

                for i in 0..<docCount {
                    let docVecPointer = eBase.advanced(by: i * dimension)
                    var dotProduct: Float = 0
                    vDSP_dotpr(qBase, 1, docVecPointer, 1, &dotProduct, vDSP_Length(dimension))
                    scores[i] = dotProduct
                }
            }
        }

        // Rank documents by score descending
        var candidates: [(index: Int, score: Float)] = []
        candidates.reserveCapacity(docCount)
        for (i, score) in scores.enumerated() {
            if score >= threshold {
                candidates.append((index: i, score: score))
            }
        }

        candidates.sort { $0.score > $1.score }

        let resultCount = min(k, candidates.count)
        var results: [RAGSearchResult] = []
        results.reserveCapacity(resultCount)

        for rankIndex in 0..<resultCount {
            let item = candidates[rankIndex]
            let doc = documents[item.index]
            results.append(RAGSearchResult(document: doc, score: item.score, rank: rankIndex + 1))
        }

        return results
    }

    /// Keyword search fallback when query vector is unavailable or for direct term lookup.
    public func searchByKeyword(
        query: String,
        topK: Int = 5
    ) -> [RAGSearchResult] {
        guard !documents.isEmpty else { return [] }

        let normalizedQuery = query.folding(options: [String.CompareOptions.caseInsensitive, String.CompareOptions.diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else { return [] }

        var candidates: [(doc: RAGDocument, score: Float)] = []

        for doc in documents {
            let termNorm = doc.istilah.folding(options: [String.CompareOptions.caseInsensitive, String.CompareOptions.diacriticInsensitive], locale: .current).lowercased()
            let defNorm = doc.pengertian.folding(options: [String.CompareOptions.caseInsensitive, String.CompareOptions.diacriticInsensitive], locale: .current).lowercased()

            var score: Float = 0.0
            if termNorm == normalizedQuery {
                score = 1.0
            } else if termNorm.hasPrefix(normalizedQuery) {
                score = 0.9
            } else if termNorm.contains(normalizedQuery) {
                score = 0.8
            } else if defNorm.contains(normalizedQuery) {
                score = 0.6
            }

            if score > 0 {
                candidates.append((doc: doc, score: score))
            }
        }

        candidates.sort { $0.score > $1.score }
        let topCount = min(topK, candidates.count)

        return (0..<topCount).map { i in
            RAGSearchResult(document: candidates[i].doc, score: candidates[i].score, rank: i + 1)
        }
    }
}
