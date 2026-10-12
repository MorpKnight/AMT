import Foundation
import MLX
import XCTest
@testable import AMT

/// Fixed candidates isolate TataKata from the OS spell-checker dictionary.
@MainActor
final class AIConnectorResourceScoringBenchmarkTests: XCTestCase {
    func testFrozenTataKataScores() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_RESOURCE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in resource benchmark.") }
        let directory = try XCTUnwrap(env["AMT_FLOW_OUTPUT"])
        let phase = env["AMT_FLOW_PHASE"] ?? "warm"
        let service = QwenSuggestionService()
        let scorer = service.languageScorer
        let preparationStart = ContinuousClock.now
        try await scorer.prepare()
        let preparation = AIConnectorObservationTiming.seconds(preparationStart.duration(to: .now))
        var records: [[String: Double]] = []
        for iteration in 0..<3 {
            if phase == "warm" { await scorer.clearCachedScores() }
            let start = ContinuousClock.now
            var scored = 0
            var improvement = 0.0
            for (index, fixture) in AIConnectorBackendEvaluationFixtures.fixtures.filter({ $0.category == .spelling }).enumerated() {
                let finding = try XCTUnwrap(fixture.expected.findings.first)
                let original = try XCTUnwrap(finding.original)
                let replacement = try XCTUnwrap(finding.replacement)
                for suffix in ["", " Pihak Kedua menyimpan salinan."] {
                    let text = fixture.text + suffix
                    let segment = AIReviewSegment(id: index + 1, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
                    let range = (text as NSString).range(of: original)
                    let values = try await scorer.scoreForDiagnostics(segment: segment, candidates: [.init(original: original, replacement: replacement, sourceLocation: range.location, sourceLength: range.length)])
                    scored += values.count
                    improvement += values.first?.evidence?.delta ?? 0
                }
            }
            records.append(["iteration": Double(iteration + 1), "total": AIConnectorObservationTiming.seconds(start.duration(to: .now)), "scored": Double(scored), "deltaSum": improvement, "mlxActive": Double(Memory.activeMemory), "mlxCache": Double(Memory.cacheMemory)])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = Report(phase: phase, buildIdentity: env["AMT_FLOW_BUILD"] ?? "unknown", preparation: preparation, records: records)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try encoder.encode(report).write(to: URL(fileURLWithPath: directory).appendingPathComponent("fixed-scoring-\(phase).json"))
        XCTAssertTrue(records.allSatisfy { $0["scored"] == 12 })
    }
    private struct Report: Codable {
        let phase: String
        let buildIdentity: String
        let preparation: Double
        let records: [[String: Double]]
    }
}
