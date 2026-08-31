import Foundation
import XCTest
@testable import AMT

final class RAGTests: XCTestCase {
    func testLocalRAGLoadsValidatedLexicalSnapshot() async throws {
        let status = try await LocalRAG.shared.loadDataIfNeeded()

        XCTAssertEqual(status.documentCount, 3_146)
        XCTAssertEqual(status.metadata.documentCount, 3_146)
        XCTAssertEqual(status.metadata.model, "BAAI/bge-m3")
        XCTAssertEqual(status.metadata.dimension, 1_024)
        XCTAssertEqual(status.retrievalMode, .lexicalBM25)
    }

    func testBGEEmbeddingNormalization() {
        let rawVector: [Float] = [3, 4, 0]
        let normalized = BGEEmbedding.shared.normalize(rawVector)
        let length = sqrt(normalized.reduce(0) { $0 + $1 * $1 })

        XCTAssertEqual(normalized[0], 0.6, accuracy: 1e-4)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 1e-4)
        XCTAssertEqual(length, 1, accuracy: 1e-4)
    }

    func testSemanticEmbeddingFailsClosedWithoutVerifiedTokenizer() async {
        XCTAssertFalse(BGEEmbedding.shared.isSemanticSearchAvailable)

        do {
            _ = try await BGEEmbedding.shared.generateEmbedding(for: "Data Pribadi")
            XCTFail("Semantic embedding must remain disabled")
        } catch let error as BGEEmbeddingError {
            guard case .verifiedModelAndTokenizerUnavailable = error else {
                return XCTFail("Unexpected semantic capability error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLexicalRAGSearchFindsExactTerm() async throws {
        let results = try await LocalRAG.shared.searchByKeyword(
            query: "Abrasi",
            topK: 3
        )

        XCTAssertEqual(results.first?.document.istilah, "Abrasi")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0)
    }

    func testLegalDictionarySearchPrefersPrimaryCorpusForDuplicateTerm() async {
        let store = LegalDictionaryStore()
        let results = await store.searchRAG("Data Pribadi", limit: 5)

        XCTAssertEqual(results.first?.term, "Data Pribadi")
        XCTAssertEqual(
            results.first?.corpusVersion,
            "hukumonline-kamus@78a2ab626c092662b0441c95904c353b2487b216"
        )
        XCTAssertEqual(results.first?.authority, .verified)
    }

    func testLexicalDefinitionQueryFindsDataPribadi() async {
        let store = LegalDictionaryStore()
        let results = store.search(
            "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi",
            limit: 5
        )

        XCTAssertEqual(results.first?.term, "Data Pribadi")
    }

    func testLexicalSearchReturnsNoResultForUnrelatedTokens() async {
        let store = LegalDictionaryStore()
        let results = store.search(
            "nebula kuantum xenolit fotonik",
            limit: 5
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testVerifiedEntryWinsDuplicateLegacyTerm() async {
        let verifiedEntry = LegalDictionaryEntry(
            id: "verified-data-pribadi",
            term: "Data Pribadi",
            definition: "Definisi yang telah melalui review corpus test.",
            regulation: "Test Regulation",
            regulationTitle: "Verified fixture",
            sourceURL: nil,
            authority: .verified,
            corpusVersion: "verified-test-v1"
        )
        let store = LegalDictionaryStore(entries: [verifiedEntry])
        let results = await store.searchRAG("Data Pribadi", limit: 5)

        XCTAssertEqual(results.first?.id, verifiedEntry.id)
        XCTAssertEqual(results.first?.authority, .verified)
    }

    func testEntryDefaultsFailClosedAsLegacy() {
        let entry = LegalDictionaryEntry(
            id: "unspecified",
            term: "Istilah",
            definition: "Pengertian",
            regulation: "",
            regulationTitle: "",
            sourceURL: nil
        )

        XCTAssertEqual(entry.authority, .legacy)
        XCTAssertEqual(
            entry.corpusVersion,
            LegalDictionaryCorpusVersion.unspecifiedLegacy
        )
    }
}
