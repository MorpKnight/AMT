import Foundation
import XCTest
@testable import AMT

final class RAGTests: XCTestCase {

    func testLocalRAGLoadsResources() throws {
        let localRAG = LocalRAG.shared
        localRAG.loadDataIfNeeded()

        XCTAssertTrue(localRAG.isLoaded, "LocalRAG should load resources successfully")
        XCTAssertEqual(localRAG.documents.count, 3146, "Should load 3,146 legal documents")
        XCTAssertEqual(localRAG.embeddings.count, 3146 * 1024, "Should load 3,146 x 1024 Float32 embeddings")

        XCTAssertNotNil(localRAG.metadata, "Metadata should be loaded")
        XCTAssertEqual(localRAG.metadata?.model, "BAAI/bge-m3", "Metadata model should be BAAI/bge-m3")
        XCTAssertEqual(localRAG.metadata?.dimension, 1024, "Embedding dimension should be 1024")
    }

    func testBGEEmbeddingNormalization() throws {
        let bge = BGEEmbedding.shared
        let rawVector: [Float] = [3.0, 4.0, 0.0]
        let normalized = bge.normalize(rawVector)

        var sumSq: Float = 0
        for val in normalized {
            sumSq += val * val
        }
        let length = sqrt(sumSq)

        XCTAssertEqual(normalized[0], 0.6, accuracy: 1e-4)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 1e-4)
        XCTAssertEqual(length, 1.0, accuracy: 1e-4, "L2 norm of normalized vector must be 1.0")
    }

    func testVectorSimilaritySearch() async throws {
        let localRAG = LocalRAG.shared
        localRAG.loadDataIfNeeded()

        let bge = BGEEmbedding.shared
        let query = "Data Pribadi"
        let queryEmbedding = try await bge.generateEmbedding(for: query)

        let results = localRAG.search(queryEmbedding: queryEmbedding, topK: 5, minThreshold: -1.0)

        XCTAssertFalse(results.isEmpty, "Search should return non-empty RAG results")
        if let topMatch = results.first {
            XCTAssertFalse(topMatch.document.istilah.isEmpty, "Matched document should have valid term")
            XCTAssertFalse(topMatch.document.pengertian.isEmpty, "Matched document should have valid definition")
        }
    }

    func testKeywordRAGSearchFallback() throws {
        let localRAG = LocalRAG.shared
        localRAG.loadDataIfNeeded()

        let results = localRAG.searchByKeyword(query: "Abrasi", topK: 3)
        if let first = results.first {
            XCTAssertEqual(first.document.istilah, "Abrasi")
        } else {
            XCTAssertTrue(localRAG.documents.isEmpty || !results.isEmpty)
        }
    }

    func testLegalDictionaryStoreRAGSearch() async throws {
        let store = LegalDictionaryStore()
        let results = await store.searchRAG("Data Pribadi", limit: 5)


        XCTAssertFalse(results.isEmpty, "LegalDictionaryStore searchRAG should return entries")
        XCTAssertEqual(results[0].term, "Data Pribadi")
        XCTAssertFalse(results[0].definition.isEmpty)
    }


}
