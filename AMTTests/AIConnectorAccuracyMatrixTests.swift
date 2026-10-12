import AppKit
import Darwin
import Foundation
import MLX
import XCTest
@testable import AMT

/// Identical opt-in measurement overlay for the archived baseline and changed build.
@MainActor
final class AIConnectorAccuracyMatrixTests: XCTestCase {
    func testFrozenAccuracyMatrix() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_ACCURACY_MATRIX"] == "1" else { throw XCTSkip("Opt-in complete accuracy matrix.") }
        let output = try XCTUnwrap(env["AMT_ACCURACY_MATRIX_OUTPUT"])
        let fixturePath = try XCTUnwrap(env["AMT_ACCURACY_MATRIX_FIXTURES"])
        guard output.hasPrefix("/private/tmp/"), fixturePath.hasPrefix("/private/tmp/") else { throw XCTSkip("External synthetic artifacts required.") }
        let fixtures = try JSONDecoder().decode([AIConnectorQualityFixture].self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        XCTAssertEqual(fixtures.count, 181)
        let folder = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let service = QwenSuggestionService()
        let store = LegalDictionaryStore(inferenceScheduler: service.inferenceScheduler)
        XCTAssertNotNil(store.corpusStore)
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        vm.modelVariant = .qwen35Base4B; vm.generationProfilePreset = .greedy; vm.thinkingEnabled = false
        vm.inputSource = .currentDocument; vm.flowBenchmarkReuseCaches = false
        let start = ContinuousClock.now
        try await vm.flowBenchmarkPrepareResources()
        try encoder.encode(["preparationSeconds": seconds(start.duration(to: .now))]).write(to: folder.appendingPathComponent("preparation.json"))
        let modes = AIConnectorReviewMode.allCases.filter { env["AMT_ACCURACY_MATRIX_MODE"] == nil || $0.rawValue == env["AMT_ACCURACY_MATRIX_MODE"] }
        for mode in modes {
            vm.reviewMode = mode
            for fixture in fixtures {
                for phase in ["warm", "cached"] {
                    // Explicit priming is outside measured cached reruns.
                    await vm.flowBenchmarkClearCaches()
                    if phase == "cached" { _ = try await measure(vm, fixture: fixture, mode: mode, phase: "priming", iteration: 0, incremental: false) }
                    for iteration in 1...3 {
                        let name = "\(fixture.id)-\(mode.rawValue)-\(phase)-\(iteration).json"
                        // Resumability never uses previous analysis snapshots as model evidence.
                        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) { continue }
                        if phase == "warm" { await vm.flowBenchmarkClearCaches() }
                        let record = try await measure(vm, fixture: fixture, mode: mode, phase: phase, iteration: iteration, incremental: phase == "cached")
                        try encoder.encode(record).write(to: folder.appendingPathComponent(name), options: .atomic)
                        print("ACCURACY_MATRIX \(mode.rawValue) \(fixture.id) \(phase) \(iteration)")
                    }
                }
            }
        }
    }

    private func measure(_ vm: AIConnectorViewModel, fixture: AIConnectorQualityFixture, mode: AIConnectorReviewMode, phase: String, iteration: Int, incremental: Bool) async throws -> Record {
        let start = ContinuousClock.now
        var firstVisible: Double?; var firstActionable: Double?
        var rss = residentBytes(); var active = Memory.activeMemory; var cache = Memory.cacheMemory
        let before = await vm.flowBenchmarkCacheCounts()
        if incremental { vm.rerunIncrementally(documentText: fixture.text) }
        else { vm.run(documentText: fixture.text, scope: .fullFresh) }
        while vm.isRunning {
            if firstVisible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty || !vm.documentFindings.isEmpty) { firstVisible = seconds(start.duration(to: .now)) }
            if firstActionable == nil && !vm.editorSuggestions.isEmpty { firstActionable = seconds(start.duration(to: .now)) }
            rss = max(rss ?? 0, residentBytes() ?? 0)
            active = max(active, Memory.activeMemory); cache = max(cache, Memory.cacheMemory)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await vm.flowBenchmarkAwaitCompletion()
        let elapsed = seconds(start.duration(to: .now))
        if firstVisible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty || !vm.documentFindings.isEmpty) { firstVisible = elapsed }
        if firstActionable == nil && !vm.editorSuggestions.isEmpty { firstActionable = elapsed }
        let definitions = vm.definitionAssessments.map {
            Definition(term: $0.term, classification: $0.classification.rawValue, alignment: $0.alignment.rawValue, reason: $0.reason, sourceID: $0.candidate?.match.entry.id, sourceTerm: $0.candidate?.term, sourceVerified: $0.candidate?.match.entry.authority == .verified, sourceActionable: $0.candidate?.match.entry.isActionable == true, modelReviewed: $0.modelReviewed)
        }
        let candidates = vm.currentCandidates.map { candidate in
            let decision = vm.currentCandidateDecisions.first { $0.candidateID == candidate.id }
            return Candidate(original: candidate.original, replacement: candidate.replacement, location: candidate.evidence.sourceLocation, delta: candidate.languageScoreEvidence?.delta, route: decision?.route?.rawValue, reason: decision?.routeReason?.rawValue, decision: decision?.decision?.rawValue, rejection: decision?.rejectionClass?.rawValue)
        }
        return Record(fixtureID: fixture.id, mode: mode, phase: phase, iteration: iteration, findings: vm.accuracyMatrixObservedFindings(in: fixture.text), definitions: definitions, candidates: candidates, observation: vm.observationReport, benchmark: vm.benchmarkReport, total: elapsed, firstVisible: firstVisible, firstActionable: firstActionable, rssPeak: rss, mlxActivePeak: active, mlxCachePeak: cache, mlxRuntimePeak: Memory.peakMemory, partialRun: vm.runSummary?.wasPartial ?? true, skippedSegments: vm.skippedSegmentCount, invalidMappedAnchors: vm.editorSuggestions.filter { !$0.isAnchored(to: fixture.text) }.count + vm.reviewAnnotations.filter { !$0.isAnchored(to: fixture.text) }.count, invalidActionableSources: vm.flowBenchmarkInvalidSourceCount(), reusedSegments: vm.reusedSegmentCount, reprocessedSegments: vm.reprocessedSegmentCount, cacheBefore: before, cacheAfter: await vm.flowBenchmarkCacheCounts())
    }
    private func seconds(_ duration: Duration) -> Double { AIConnectorObservationTiming.seconds(duration) }
    private func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
    private struct Record: Codable {
        let fixtureID: String; let mode: AIConnectorReviewMode; let phase: String; let iteration: Int
        let findings: [AIConnectorQualityObservedFinding]; let definitions: [Definition]; let candidates: [Candidate]
        let observation: AIConnectorObservationReport?; let benchmark: AIConnectorBenchmarkReport?
        let total: Double; let firstVisible: Double?; let firstActionable: Double?
        let rssPeak: UInt64?; let mlxActivePeak: Int; let mlxCachePeak: Int; let mlxRuntimePeak: Int
        let partialRun: Bool; let skippedSegments: Int; let invalidMappedAnchors: Int; let invalidActionableSources: Int
        let reusedSegments: Int; let reprocessedSegments: Int; let cacheBefore: [String: Int]; let cacheAfter: [String: Int]
    }
    private struct Definition: Codable {
        let term: String?; let classification: String; let alignment: String; let reason: String
        let sourceID: String?; let sourceTerm: String?; let sourceVerified: Bool; let sourceActionable: Bool; let modelReviewed: Bool
    }
    private struct Candidate: Codable {
        let original: String; let replacement: String; let location: Int; let delta: Double?
        let route: String?; let reason: String?; let decision: String?; let rejection: String?
    }
}
