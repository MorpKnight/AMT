import Foundation
import XCTest
@testable import AMT

@MainActor
final class LegalLexicalSearchTests: XCTestCase {
    func testIndexedSearchMatchesFrozenFullScanForSyntheticEdges() {
        let entries = [
            entry("z", "Data", "Data adalah informasi pribadi", .verified),
            entry("a", "Data", "Data adalah informasi pribadi", .verified),
            entry("legacy", "Data", "informasi pribadi", .legacy, "legacy-kamus-v1"),
            entry("personal", "Data Pribadi", "data orang yang dapat diidentifikasi", .verified),
            entry("number", "Nomor 27", "Undang-undang tahun 2022", .verified),
            entry("accent", "Dáta Ársip", "informasi mengenai arsip", .verified),
            entry("prefix", "Perusahaan", "peraturan perusahaan", .legacy, "preview-v1"),
            entry("empty", "", "informasi tambahan", .verified)
        ]
        let queries = ["Data", "data pribadi", "DATA\n PRIBADI", "dáta ár", "per", "usaha", "rmasi", "27", "2022", "dan", "!!!", "", "informasi pribadi", "informasi tambahan", "tidak ada istilah ini"]
        assertEquivalent(entries: entries, queries: queries)
        let store = LegalDictionaryStore(entries: entries)
        XCTAssertEqual(store.entries(forTerm: " DATA ").map(\.id), ["z", "a", "legacy"])
        XCTAssertTrue(store.entries(forTerm: "").isEmpty)
    }

    func testPostingIndexAvoidsScoringUnrelatedEntries() {
        let entries = [entry("one", "Data", "informasi tambahan", .verified), entry("two", "Advokat", "orang yang berprofesi", .verified)]
        XCTAssertEqual(LegalDictionaryStore(entries: entries).debugLexicalSearch("tambahan", limit: 30).evaluatedCandidateCount, 1)
    }

    func testGateReusePreservesResultsAndLimitsWithOfflineSemanticProvider() async throws {
        let store = LegalDictionaryStore()
        let text = "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi, Data Pribadi berarti data tentang orang perseorangan"
        for limit in [1, 3, 120] {
            let reused = await store.debugSuggestionCandidateResultAsync(for: text, limit: limit, semanticSearch: { _, _, _ in [] })
            let repeated = await store.debugSuggestionCandidateResultAsync(for: text, limit: limit, reuseLexicalGate: false, semanticSearch: { _, _, _ in [] })
            XCTAssertEqual(reused.matches.map(\.id), repeated.matches.map(\.id))
            for (left, right) in zip(reused.matches, repeated.matches) {
                XCTAssertEqual(left.score, right.score, accuracy: 1e-9)
                XCTAssertEqual(left.rank, right.rank)
                XCTAssertEqual(left.entry, right.entry)
                XCTAssertEqual(left.retrievalOrigin, right.retrievalOrigin)
            }
            XCTAssertEqual(reused.queryCount, repeated.queryCount)
            XCTAssertEqual(reused.semanticQueryCount, repeated.semanticQueryCount)
            XCTAssertEqual(reused.lexicalDiagnostics.reuseCount, 1)
            XCTAssertEqual(reused.lexicalDiagnostics.searchCount + 1, repeated.lexicalDiagnostics.searchCount)
            XCTAssertLessThanOrEqual(reused.matches.count, limit)
        }
    }

    func testSemanticFailureRetainsLexicalGateAndCancellationStaysLocal() async throws {
        let store = LegalDictionaryStore()
        let text = "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        let lexical = await store.suggestionCandidateResultAsync(for: text, limit: 3, allowSemantic: false)
        let failed = await store.debugSuggestionCandidateResultAsync(for: text, limit: 3, semanticSearch: { _, _, _ in throw LexicalTestError.unavailable })
        XCTAssertTrue(failed.semanticFailed)
        XCTAssertEqual(failed.matches, lexical.matches)
        XCTAssertEqual(failed.lexicalDiagnostics.searchCount, 1)
        XCTAssertEqual(failed.lexicalDiagnostics.reuseCount, 1)
        let cancelled = Task {
            await store.debugSuggestionCandidateResultAsync(for: text, limit: 3, semanticSearch: { _, _, _ in
                try Task.checkCancellation()
                try await Task.sleep(for: .seconds(1))
                return []
            })
        }
        cancelled.cancel()
        let result = await cancelled.value
        XCTAssertTrue(result.matches.isEmpty)
        let independent = await store.debugSuggestionCandidateResultAsync(for: text, limit: 3, semanticSearch: { _, _, _ in [] })
        XCTAssertFalse(independent.semanticFailed)
        XCTAssertEqual(independent.semanticQueryCount, 1)
    }

    func testIndexedSearchMatchesFrozenFullScanOnProductionCorpus() {
        let store = LegalDictionaryStore()
        XCTAssertNotNil(store.corpusStore)
        let terms = stride(from: 0, to: store.entries.count, by: 173).map { store.entries[$0].term }
        let queries = terms + ["Data Pribadi", "Advokat", "pidana", "per", "prib", "27", "informasi", "yang", "yang dimaksud dengan Data adalah informasi yang tidak dapat dipublikasikan."]
        assertEquivalent(entries: store.entries, queries: queries)
    }

    private func assertEquivalent(entries: [LegalDictionaryEntry], queries: [String], file: StaticString = #filePath, line: UInt = #line) {
        let store = LegalDictionaryStore(entries: entries)
        let reference = FrozenLexicalFullScan(entries: entries)
        for query in queries {
            for limit in [-1, 0, 1, 3, 30, 100] {
                let expected = reference.search(query, limit: limit)
                let actual = store.debugLexicalSearch(query, limit: limit).matches
                XCTAssertEqual(actual.map { $0.entry.id }, expected.map { $0.entry.id }, "query=\(query), limit=\(limit)", file: file, line: line)
                for (left, right) in zip(actual, expected) {
                    XCTAssertEqual(left.score, right.score, accuracy: 1e-9, file: file, line: line)
                    XCTAssertEqual(left.entry.sourcePassageID, right.entry.sourcePassageID, file: file, line: line)
                    XCTAssertEqual(left.entry.isActionable, right.entry.isActionable, file: file, line: line)
                }
            }
        }
    }

    private func entry(_ id: String, _ term: String, _ definition: String, _ authority: LegalDictionaryEntryAuthority, _ corpus: String = "official-test") -> LegalDictionaryEntry {
        LegalDictionaryEntry(id: id, term: term, definition: definition, regulation: "Nomor 27 Tahun 2022", regulationTitle: "Pengelolaan", sourceURL: nil, authority: authority, corpusVersion: corpus, sourcePassageID: "passage-" + id)
    }
}

private enum LexicalTestError: Error { case unavailable }

/// Frozen scoring/ranking from cff94f6, deliberately scanning every entry.
/// Normalized corpus data is prepared once here to keep differential tests inexpensive.
@MainActor
private struct FrozenLexicalFullScan {
    let entries: [LegalDictionaryEntry]
    let terms: [String]
    let definitions: [String]
    let frequencies: [[String: Int]]
    let lengths: [Int]
    let idf: [String: Double]
    let averageLength: Double

    init(entries: [LegalDictionaryEntry]) {
        self.entries = entries
        terms = entries.map { Self.normalize($0.term) }
        definitions = entries.map { Self.normalize($0.definition) }
        let tokens = entries.map { entry -> [String] in
            let term = Self.normalize(entry.term)
            var definition = Self.normalize(entry.definition)
            for connector in ["adalah", "ialah", "merupakan"] {
                let prefix = term + " " + connector + " "
                if definition.hasPrefix(prefix) { definition = String(definition.dropFirst(prefix.count)); break }
            }
            return Self.tokenize([entry.term, definition, entry.regulation, entry.regulationTitle].joined(separator: " "))
        }
        frequencies = tokens.map { $0.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        lengths = tokens.map(\.count)
        var documentFrequency: [String: Int] = [:]
        for frequency in frequencies {
            for token in frequency.keys { documentFrequency[token, default: 0] += 1 }
        }
        let count = Double(entries.count)
        idf = documentFrequency.mapValues { log(1 + (count - Double($0) + 0.5) / (Double($0) + 0.5)) }
        averageLength = count > 0 ? Double(lengths.reduce(0, +)) / count : 0
    }

    func search(_ query: String, limit: Int) -> [(entry: LegalDictionaryEntry, score: Double)] {
        let normalized = Self.normalize(query)
        let tokens = Array(Set(Self.tokenize(query)))
        guard limit > 0, !normalized.isEmpty, !tokens.isEmpty else { return [] }
        let scored = entries.indices.compactMap { index -> (Int, Double)? in
            var score = 0.0
            if averageLength > 0 {
                let normalization = 1 - 0.75 + 0.75 * Double(lengths[index]) / averageLength
                for token in tokens {
                    let frequency = Double(frequencies[index][token] ?? 0)
                    if frequency > 0 { score += (idf[token] ?? 0) * frequency * 2.5 / (frequency + 1.5 * normalization) }
                }
            }
            if terms[index] == normalized { score += 1_000 }
            else if terms[index].hasPrefix(normalized) { score += 300 }
            else if terms[index].contains(normalized) { score += 150 }
            if definitions[index].contains(normalized) { score += 100 }
            return score > 0 ? (index, score) : nil
        }
        return scored.sorted { lhs, rhs in
            let left = entries[lhs.0], right = entries[rhs.0]
            let leftExact = terms[lhs.0] == normalized, rightExact = terms[rhs.0] == normalized
            if leftExact != rightExact { return leftExact }
            if leftExact && rightExact && left.authority != right.authority { return left.authority == .verified }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if left.authority != right.authority { return left.authority == .verified }
            if priority(left.corpusVersion) != priority(right.corpusVersion) { return priority(left.corpusVersion) > priority(right.corpusVersion) }
            return left.term.localizedCaseInsensitiveCompare(right.term) == .orderedAscending
        }.prefix(limit).map { (entries[$0.0], $0.1) }
    }

    private func priority(_ corpus: String) -> Int {
        switch corpus {
        case "legacy-kamus-v1": 3
        case "legacy-rag-export-v1": 2
        case "preview-v1": 1
        default: 0
        }
    }
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func tokenize(_ text: String) -> [String] {
        normalize(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
