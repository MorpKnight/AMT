import Foundation

nonisolated public struct LocalRAGMetadata: Codable, Sendable {
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

nonisolated public enum LocalRAGRetrievalMode: String, Codable, Hashable, Sendable {
    case lexicalBM25 = "lexical-bm25"
}

nonisolated public struct LocalRAGStatus: Sendable {
    public let documentCount: Int
    public let metadata: LocalRAGMetadata
    public let retrievalMode: LocalRAGRetrievalMode
}

nonisolated public struct RAGSearchResult: Identifiable, Hashable, Sendable {
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

/// Actor-isolated access to the bundled legacy legal corpus.
///
/// The current product intentionally uses lexical BM25 retrieval. Bundled
/// vectors are not loaded because AMT does not yet ship the matching BGE-M3
/// tokenizer required to create a trustworthy query embedding.
public actor LocalRAG {
    public static let shared = LocalRAG()

    private var snapshot: LocalRAGSnapshot?
    private var loadingTask: Task<LocalRAGSnapshot, Error>?

    public init() {}

    @discardableResult
    public func loadDataIfNeeded(bundle: Bundle = .main) async throws -> LocalRAGStatus {
        if let snapshot {
            return snapshot.status
        }

        if let loadingTask {
            let loadedSnapshot = try await loadingTask.value
            return loadedSnapshot.status
        }

        guard let documentsURL = Self.findResource(
            name: "documents",
            extension: "json",
            in: bundle
        ), let metadataURL = Self.findResource(
            name: "metadata",
            extension: "json",
            in: bundle
        ) else {
            throw LocalRAGError.resourcesUnavailable
        }

        let task = Task.detached(priority: .userInitiated) {
            try LocalRAGSnapshot.load(
                documentsURL: documentsURL,
                metadataURL: metadataURL
            )
        }
        loadingTask = task

        do {
            let loadedSnapshot = try await task.value
            snapshot = loadedSnapshot
            loadingTask = nil
            return loadedSnapshot.status
        } catch {
            loadingTask = nil
            throw error
        }
    }

    public func currentStatus() -> LocalRAGStatus? {
        snapshot?.status
    }

    /// Lexical retrieval over term and definition text. This method executes on
    /// the LocalRAG actor rather than the MainActor.
    public func searchByKeyword(
        query: String,
        topK: Int = 5,
        bundle: Bundle = .main
    ) async throws -> [RAGSearchResult] {
        guard topK > 0 else { return [] }
        _ = try await loadDataIfNeeded(bundle: bundle)
        return snapshot?.search(query: query, topK: topK) ?? []
    }

    private nonisolated static func findResource(
        name: String,
        extension fileExtension: String,
        in bundle: Bundle
    ) -> URL? {
        let candidateBundles = [bundle, Bundle(for: LocalRAG.self), Bundle.main]
        for candidateBundle in candidateBundles {
            if let URL = candidateBundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "rag_export"
            ) ?? candidateBundle.url(
                forResource: name,
                withExtension: fileExtension
            ) {
                return URL
            }
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        let relativePaths = [
            "\(currentDirectory)/AMT/Resources/rag_export/\(name).\(fileExtension)",
            "\(currentDirectory)/Resources/rag_export/\(name).\(fileExtension)",
            "\(currentDirectory)/rag_export/\(name).\(fileExtension)"
        ]

        return relativePaths
            .first(where: FileManager.default.fileExists(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}

public enum LocalRAGError: LocalizedError, Sendable {
    case resourcesUnavailable
    case malformedMetadata
    case malformedDocuments
    case documentCountMismatch(expected: Int, actual: Int)
    case emptyDocument(index: Int)

    public var errorDescription: String? {
        switch self {
        case .resourcesUnavailable:
            "Resource corpus RAG lokal tidak ditemukan."
        case .malformedMetadata:
            "Metadata corpus RAG lokal tidak dapat dibaca."
        case .malformedDocuments:
            "Dokumen corpus RAG lokal tidak dapat dibaca."
        case let .documentCountMismatch(expected, actual):
            "Jumlah dokumen corpus tidak sesuai metadata (\(actual) dari \(expected))."
        case let .emptyDocument(index):
            "Corpus RAG memuat dokumen tanpa istilah atau pengertian pada indeks \(index)."
        }
    }
}

private nonisolated struct LocalRAGSnapshot: Sendable {
    private struct IndexedDocument: Sendable {
        let normalizedTerm: String
        let termTokens: [String]
        let termFrequencies: [String: Int]
        let tokenCount: Int
    }

    let documents: [RAGDocument]
    let metadata: LocalRAGMetadata
    private let index: [IndexedDocument]
    let inverseDocumentFrequencies: [String: Double]
    let averageDocumentLength: Double

    var status: LocalRAGStatus {
        LocalRAGStatus(
            documentCount: documents.count,
            metadata: metadata,
            retrievalMode: .lexicalBM25
        )
    }

    static func load(
        documentsURL: URL,
        metadataURL: URL
    ) throws -> LocalRAGSnapshot {
        let decoder = JSONDecoder()

        guard let metadata = try? decoder.decode(
            LocalRAGMetadata.self,
            from: Data(contentsOf: metadataURL)
        ) else {
            throw LocalRAGError.malformedMetadata
        }

        guard let documents = try? decoder.decode(
            [RAGDocument].self,
            from: Data(contentsOf: documentsURL)
        ) else {
            throw LocalRAGError.malformedDocuments
        }

        guard metadata.documentCount == documents.count else {
            throw LocalRAGError.documentCountMismatch(
                expected: metadata.documentCount,
                actual: documents.count
            )
        }

        for (index, document) in documents.enumerated() {
            guard !normalize(document.istilah).isEmpty,
                  !normalize(document.pengertian).isEmpty else {
                throw LocalRAGError.emptyDocument(index: index)
            }
        }

        let indexedDocuments = documents.map { document in
            let normalizedTerm = normalize(document.istilah)
            let tokens = tokenize("\(document.istilah) \(document.pengertian)")
            return IndexedDocument(
                normalizedTerm: normalizedTerm,
                termTokens: tokenize(document.istilah),
                termFrequencies: termFrequencies(for: tokens),
                tokenCount: tokens.count
            )
        }

        var documentFrequencies: [String: Int] = [:]
        for document in indexedDocuments {
            for token in document.termFrequencies.keys {
                documentFrequencies[token, default: 0] += 1
            }
        }

        let documentCount = Double(indexedDocuments.count)
        let inverseDocumentFrequencies = Dictionary(
            uniqueKeysWithValues: documentFrequencies.map { token, frequency in
                let frequency = Double(frequency)
                return (
                    token,
                    log(1 + (documentCount - frequency + 0.5) / (frequency + 0.5))
                )
            }
        )
        let averageDocumentLength = indexedDocuments.isEmpty
            ? 0
            : Double(indexedDocuments.reduce(0) { $0 + $1.tokenCount }) / documentCount

        return LocalRAGSnapshot(
            documents: documents,
            metadata: metadata,
            index: indexedDocuments,
            inverseDocumentFrequencies: inverseDocumentFrequencies,
            averageDocumentLength: averageDocumentLength
        )
    }

    func search(query: String, topK: Int) -> [RAGSearchResult] {
        let normalizedQuery = Self.normalize(query)
        let orderedQueryTokens = Self.tokenize(query)
        let queryTokens = Array(Set(orderedQueryTokens))
        guard !normalizedQuery.isEmpty, !queryTokens.isEmpty else { return [] }

        let scored = index.indices.compactMap { index -> (Int, Double)? in
            let document = self.index[index]
            var score = bm25Score(queryTokens: queryTokens, document: document)

            if document.normalizedTerm == normalizedQuery {
                score += 1_000
            } else if document.normalizedTerm.hasPrefix(normalizedQuery) {
                score += 300
            } else if document.normalizedTerm.contains(normalizedQuery) {
                score += 150
            } else if Self.containsTokenSequence(orderedQueryTokens, document.termTokens) {
                score += 40
            }

            return score > 0 ? (index, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return documents[lhs.0].istilah.localizedCaseInsensitiveCompare(
                documents[rhs.0].istilah
            ) == .orderedAscending
        }
        .prefix(topK)

        return scored.enumerated().map { rank, item in
            RAGSearchResult(
                document: documents[item.0],
                score: Float(item.1),
                rank: rank + 1
            )
        }
    }

    private func bm25Score(
        queryTokens: [String],
        document: IndexedDocument
    ) -> Double {
        guard averageDocumentLength > 0 else { return 0 }

        let k1 = 1.5
        let b = 0.75
        let documentLength = Double(document.tokenCount)
        let normalization = 1 - b + b * documentLength / averageDocumentLength

        return queryTokens.reduce(into: 0.0) { score, token in
            let frequency = Double(document.termFrequencies[token] ?? 0)
            guard frequency > 0 else { return }
            score += (inverseDocumentFrequencies[token] ?? 0)
                * frequency * (k1 + 1)
                / (frequency + k1 * normalization)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func tokenize(_ value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func termFrequencies(for tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
    }

    private static func containsTokenSequence(
        _ queryTokens: [String],
        _ termTokens: [String]
    ) -> Bool {
        guard !termTokens.isEmpty, termTokens.count <= queryTokens.count else {
            return false
        }

        for start in 0...(queryTokens.count - termTokens.count) {
            if Array(queryTokens[start..<(start + termTokens.count)]) == termTokens {
                return true
            }
        }
        return false
    }
}
