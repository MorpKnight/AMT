import CryptoKit
import Foundation
import XCTest
@testable import AMT

/// Frozen, opt-in replay without retrieval or model inference.
@MainActor
final class AIConnectorMappingBenchmarkTests: XCTestCase {
    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_" + key]
    }

    func testFrozenMappingReplay() async throws {
        guard env("AMT_RUN_MAPPING_BENCHMARK") == "1" else { throw XCTSkip("Opt-in mapping benchmark.") }
        let directory = env("AMT_MAPPING_OUTPUT") ?? "/private/tmp/amt-mapping-task/reports/before"
        guard directory.hasPrefix("/private/tmp/") else { throw XCTSkip("External artifacts only.") }
        var records: [MappingRecord] = []
        for count in [180, 360, 720] {
            var text = ""
            var segments: [AIReviewSegment] = []
            for id in 1...count {
                let target = "Bagian \(id) 😀 memasukan arsip. "
                segments.append(AIReviewSegment(id: id, sourceLocation: text.utf16.count, sourceLength: target.utf16.count, targetText: target, previousContext: nil, nextContext: nil))
                text += target
            }
            for iteration in 1...3 {
                let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
                vm.mappingBenchmarkReset(documentText: text)
                let start = ContinuousClock.now
                for segment in segments {
                    let local = review(segment: segment, reason: "Lokal")
                    vm.mappingBenchmarkApplyLocal(AIConnectorSegmentResult(segment: segment, reviews: [local]))
                }
                let localIDs = vm.editorSuggestions.map(\.id)
                for segment in segments {
                    let final = review(segment: segment, reason: "Final")
                    await vm.mappingBenchmarkApplyFinal(AIConnectorSegmentResult(segment: segment, reviews: [final]))
                }
                let duration = AIConnectorObservationTiming.seconds(start.duration(to: .now))
                let metrics = vm.mappingBenchmarkMetrics
                // Reference comparison is outside the timed event replay.
                XCTAssertEqual(vm.editorSuggestions, EditorSuggestionMapper.make(reviews: vm.validatedReviews, definitionAssessments: vm.definitionAssessments, documentText: text))
                XCTAssertEqual(vm.editorSuggestions.count, count)
                XCTAssertEqual(vm.editorSuggestions.map(\.id), localIDs)
                XCTAssertEqual(vm.processedSegmentCount, count)
                XCTAssertTrue(vm.editorSuggestions.allSatisfy { $0.isAnchored(to: text) && $0.reason == "Final" })
                records.append(MappingRecord(segmentCount: count, iteration: iteration, fixtureSHA256: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(), total: duration, metrics: metrics))
            }
        }
        let output = MappingEnvelope(buildIdentity: env("AMT_FLOW_BUILD") ?? "unrecorded", records: records)
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(output).write(to: url.appendingPathComponent("mapping.json"), options: .atomic)
    }

    private func review(segment: AIReviewSegment, reason: String) -> AIValidatedReview {
        AIValidatedReview(segment: segment, status: .suggestion, category: .spelling, original: "memasukan", replacement: "memasukkan", reason: reason, glossaryMatch: nil, origin: .deterministic)
    }
}

private struct MappingEnvelope: Codable { let buildIdentity: String; let records: [MappingRecord] }
private struct MappingRecord: Codable {
    let segmentCount: Int
    let iteration: Int
    let fixtureSHA256: String
    let total: Double
    let metrics: AIConnectorMappingBenchmarkMetrics
}
