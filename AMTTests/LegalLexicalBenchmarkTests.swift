import Foundation
import XCTest
@testable import AMT

/// Identical, opt-in measurement overlay for both revisions; never loads E5 or Qwen.
@MainActor
final class LegalLexicalBenchmarkTests: XCTestCase {
    func testFrozenLexicalQueries() async throws {
        let environment = ProcessInfo.processInfo.environment
        func value(_ key: String) -> String? {
            environment[key] ?? environment["TEST_RUNNER_" + key]
        }
        guard value("AMT_RUN_LEXICAL_BENCHMARK") == "1" else {
            throw XCTSkip("Opt-in lexical benchmark.")
        }
        let directory = try XCTUnwrap(value("AMT_LEXICAL_OUTPUT"))
        guard directory.hasPrefix("/private/tmp/") else { throw XCTSkip("External reports required.") }
        let queries = [
            "Data Pribadi", "Advokat", "pidana", "informasi", "per", "prib", "27", "2022",
            "  DATA\n PRIBADI  ", "dáta pribadi", "justifikasi", "", "dan", "yang",
            "informasi yang tidak dapat dipublikasikan", "Pihak Pertama wajib memberikan informasi.",
            "Data adalah informasi yang tidak dapat dipublikasikan.",
            "Pengguna dapat memasukan data, kecuali jika izin dicabut.",
            "perlindungan terhadap orang perseorangan yang dapat diidentifikasi",
            "yang dimaksud dengan Data Pribadi adalah data tentang orang perseorangan"
        ]
        var initialization: [Double] = []
        var store = LegalDictionaryStore()
        for _ in 0..<3 {
            let start = ContinuousClock.now
            store = LegalDictionaryStore()
            initialization.append(seconds(start.duration(to: .now)))
        }
        XCTAssertNotNil(store.corpusStore)
        var runs: [[String: Any]] = []
        for iteration in 1...3 {
            let start = ContinuousClock.now
            var outputs: [[String: Any]] = []
            for query in queries {
                let matches = try await store.retrieve(
                    LegalRetrievalRequest(query: query, intent: .exactTerm, limit: 30)
                )
                outputs.append([
                    "query": query,
                    "ids": matches.map { $0.concept.recordID },
                    "scores": matches.map { $0.lexicalScore ?? 0 },
                    "ranks": matches.map(\.rank),
                    "actionable": matches.map(\.isActionable),
                    "evidence": matches.map { $0.evidence?.passageID ?? "" },
                    "exactIDs": store.entries(forTerm: query).map(\.id)
                ])
            }
            runs.append(["iteration": iteration, "duration": seconds(start.duration(to: .now)), "outputs": outputs])
        }
        let report: [String: Any] = [
            "buildIdentity": value("AMT_FLOW_BUILD") ?? "unrecorded",
            "corpusVersion": store.activeCorpusVersion,
            "initializationDurations": initialization,
            "queryCount": queries.count,
            "runs": runs
        ]
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.appendingPathComponent("lexical.json"), options: .atomic)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
