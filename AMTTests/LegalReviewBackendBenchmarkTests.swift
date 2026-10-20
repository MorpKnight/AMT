import Darwin
import Foundation
import MLX
import XCTest
@testable import AMT

/// Measures the application ViewModel itself, including integrated mapping and final review.
@MainActor
final class LegalReviewBackendBenchmarkTests: XCTestCase {
    struct Fixture: Decodable { let id: String; let text: String; let group: String; let split: String }
    struct Observed: Codable {
        let id: String; let category: String; let original: String; let replacement: String?
        let location: Int; let length: Int; let readOnly: Bool; let reason: String; let evidenceIDs: [String]
    }
    struct Record: Codable {
        let fixtureID: String; let group: String; let split: String; let arm: String
        let phase: String; let iteration: Int; let total: Double; let baseSeconds: Double; let contextualSeconds: Double
        let firstVisible: Double?; let firstActionable: Double?
        let findings: [Observed]; let contextualStatus: String; let contextualFailures: [String]; let toolTrace: [String]
        let modelCalls: Int; let contextualCacheHit: Bool; let contextualCacheEvictions: Int
        let rssPeak: UInt64?; let mlxActivePeak: Int; let mlxCachePeak: Int
        let partialRun: Bool; let invalidAnchors: Int; let invalidActionableSources: Int
        let observation: AIConnectorObservationReport?
    }
    func testIntegratedBackendMatrix() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_INTEGRATED_REVIEW"] == "1" else { throw XCTSkip("Opt-in integrated model benchmark.") }
        let fixturePath = try XCTUnwrap(env["AMT_INTEGRATED_REVIEW_FIXTURES"])
        let outputPath = try XCTUnwrap(env["AMT_INTEGRATED_REVIEW_OUTPUT"])
        guard fixturePath.hasPrefix("/private/tmp/"), outputPath.hasPrefix("/private/tmp/") else { throw XCTSkip("External synthetic fixtures/artifacts required.") }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        let phase = env["AMT_INTEGRATED_REVIEW_PHASE"] ?? "warm"
        let repeats = max(1, Int(env["AMT_INTEGRATED_REVIEW_REPEATS"] ?? "3") ?? 3)
        let folder = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let service = QwenSuggestionService()
        let store = LegalDictionaryStore(inferenceScheduler: service.inferenceScheduler)
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        vm.reviewMode = .hybrid; vm.modelVariant = .qwen35Base4B
        vm.thinkingEnabled = false; vm.generationProfilePreset = .greedy
        let prep = ContinuousClock.now
        try await vm.flowBenchmarkPrepareResources()
        try encoder.encode(["seconds": seconds(prep)]).write(to: folder.appendingPathComponent("preparation-\(phase).json"))
        for fixture in fixtures {
            await vm.flowBenchmarkClearCaches()
            if phase == "cached" {
                vm.run(documentText: fixture.text, scope: .fullFresh)
                await vm.flowBenchmarkAwaitCompletion()
            }
            for iteration in 1...repeats {
                let stem = "\(fixture.id)-\(phase)-\(iteration)"
                let destination = folder.appendingPathComponent(stem + ".json")
                if FileManager.default.fileExists(atPath: destination.path) { continue }
                if phase == "warm" { await vm.flowBenchmarkClearCaches() }
                let start = ContinuousClock.now
                var visible: Double?; var actionable: Double?
                var rss = residentBytes(); var active = Memory.activeMemory; var cache = Memory.cacheMemory
                if phase == "cached" { vm.rerunIncrementally(documentText: fixture.text) }
                else { vm.run(documentText: fixture.text, scope: .fullFresh) }
                while vm.isRunning {
                    if visible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty || !vm.documentFindings.isEmpty) { visible = seconds(start) }
                    if actionable == nil && !vm.editorSuggestions.isEmpty { actionable = seconds(start) }
                    rss = max(rss ?? 0, residentBytes() ?? 0)
                    active = max(active, Memory.activeMemory); cache = max(cache, Memory.cacheMemory)
                    try await Task.sleep(for: .milliseconds(10))
                }
                await vm.flowBenchmarkAwaitCompletion()
                let total = seconds(start)
                if visible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty) { visible = total }
                if actionable == nil && !vm.editorSuggestions.isEmpty { actionable = total }
                let observed = vm.accuracyMatrixObservedFindings(in: fixture.text).enumerated().compactMap { index, value -> Observed? in
                    guard let original = value.original, let location = occurrenceRange(original, occurrence: value.occurrence, text: fixture.text) else { return nil }
                    let supplemental = vm.legalReviewResult?.findings.first { $0.range == location && $0.original == original }
                    let annotation = vm.reviewAnnotations.first { $0.sourceRange == location && $0.original == original }
                    let suggestion = vm.editorSuggestions.first { $0.sourceRange == location && $0.original == original }
                    return .init(id: supplemental?.id ?? "base-\(index)", category: supplemental?.category ?? value.category.rawValue,
                        original: original, replacement: value.replacement, location: location.location, length: location.length,
                        readOnly: value.readOnly, reason: supplemental?.reason ?? suggestion?.reason ?? annotation?.reason ?? "production",
                        evidenceIDs: supplemental?.evidenceIDs ?? annotation?.relatedEvidence.map(\.id) ?? [])
                }
                let result = vm.legalReviewResult
                let contextDuration = vm.observationReport?.stageMetrics.first { $0.stage == .documentConsistencyReview }?.totalDuration ?? 0
                var trace = result?.toolTrace ?? []
                if let route = vm.legalReviewRouting { trace += ["baseRoute:\(route.mode.rawValue)", "baseRouteReason:\(route.reason)"] }
                let record = Record(fixtureID: fixture.id, group: fixture.group, split: fixture.split, arm: "integrated",
                    phase: phase, iteration: iteration, total: total, baseSeconds: max(0, total-contextDuration), contextualSeconds: contextDuration,
                    firstVisible: visible, firstActionable: actionable, findings: observed,
                    contextualStatus: result?.status ?? "missing", contextualFailures: result?.failures ?? ["missing"], toolTrace: trace,
                    modelCalls: result?.modelCalls ?? 0, contextualCacheHit: result?.cacheHit ?? false, contextualCacheEvictions: result?.cacheEvictions ?? 0,
                    rssPeak: rss, mlxActivePeak: active, mlxCachePeak: cache, partialRun: vm.runSummary?.wasPartial ?? true,
                    invalidAnchors: vm.editorSuggestions.filter { !$0.isAnchored(to: fixture.text) }.count + vm.reviewAnnotations.filter { !$0.isAnchored(to: fixture.text) }.count,
                    invalidActionableSources: vm.flowBenchmarkInvalidSourceCount(), observation: vm.observationReport)
                try encoder.encode(record).write(to: destination, options: .atomic)
                let metadata = folder.appendingPathComponent("full-metadata")
                try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
                try encoder.encode(vm.editorSuggestions).write(to: metadata.appendingPathComponent(stem+"-suggestions.json"))
                try encoder.encode(vm.reviewAnnotations).write(to: metadata.appendingPathComponent(stem+"-annotations.json"))
                try encoder.encode(vm.documentFindings).write(to: metadata.appendingPathComponent(stem+"-findings.json"))
                XCTAssertEqual(record.invalidAnchors, 0); XCTAssertEqual(record.invalidActionableSources, 0)
                print("INTEGRATED_REVIEW \(stem) \(total)")
            }
        }
    }
    func testIntegratedIncrementalFreshPairs() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_INTEGRATED_INCREMENTAL"] == "1" else { throw XCTSkip("Opt-in integrated incremental/fresh model comparison.") }
        let output = try XCTUnwrap(env["AMT_INTEGRATED_REVIEW_OUTPUT"])
        guard output.hasPrefix("/private/tmp/") else { throw XCTSkip("External output required") }
        let folder = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let service = QwenSuggestionService(), store = LegalDictionaryStore()
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        try await vm.flowBenchmarkPrepareResources()
        let workloads: [(String, String, String)] = [
            ("local", "Penyedia menjaga menjaga bukti.", "Pengantar 📝.\nPenyedia menjaga bukti.\nPihak menerima menerima salinan."),
            ("definitions", "Yang dimaksud dengan Hari adalah hari kalender.\nHari berarti hari kerja.", "Pasal 1\nYang dimaksud dengan Hari adalah hari kalender.\nPasal 2\nHari berarti hari kerja."),
            ("long", "Penyedia wajib wajib hadir.\n" + String(repeating: "Penyedia menyimpan catatan. ", count: 75),
             "Penyedia wajib hadir.\n" + String(repeating: "Penyedia menyimpan catatan. ", count: 75))
        ]
        struct PairResult: Codable {
            let workload: String; let iteration: Int; let equivalent: Bool
            let incrementalSeconds: Double; let freshSeconds: Double
            let incrementalPartial: Bool; let freshPartial: Bool
            let incremental: [String]; let fresh: [String]
        }
        for (name, initial, final) in workloads {
            for iteration in 1...3 {
                vm.run(documentText: initial, scope: .fullFresh); await vm.flowBenchmarkAwaitCompletion()
                vm.markDocumentEdited(documentText: final)
                let start = ContinuousClock.now
                vm.rerunIncrementally(documentText: final); await vm.flowBenchmarkAwaitCompletion()
                let elapsed = seconds(start), incremental = projection(vm), partial = vm.runSummary?.wasPartial ?? true
                let freshStart = ContinuousClock.now
                vm.run(documentText: final, scope: .fullFresh); await vm.flowBenchmarkAwaitCompletion()
                let freshElapsed = seconds(freshStart), fresh = projection(vm)
                let result = PairResult(workload: name, iteration: iteration, equivalent: incremental == fresh,
                    incrementalSeconds: elapsed, freshSeconds: freshElapsed, incrementalPartial: partial,
                    freshPartial: vm.runSummary?.wasPartial ?? true, incremental: incremental, fresh: fresh)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: folder.appendingPathComponent("\(name)-\(iteration).json"))
                XCTAssertEqual(incremental, fresh, name)
                XCTAssertEqual(partial, vm.runSummary?.wasPartial ?? true)
            }
        }
    }
    private func projection(_ vm: AIConnectorViewModel) -> [String] {
        (vm.editorSuggestions.map { "\($0.sourceRange)|\($0.original)|\($0.replacement)|\($0.reason)" }
         + vm.reviewAnnotations.map { "\($0.sourceRange)|\($0.original)|\($0.reason)|\($0.relatedEvidence.map { "\($0.sourceRange):\($0.original)" })" }).sorted()
    }
    private func occurrenceRange(_ original: String, occurrence: Int, text: String) -> NSRange? {
        let ns = text as NSString; var start = 0
        for index in 0...max(0, occurrence) {
            let range = ns.range(of: original, range: NSRange(location: start, length: ns.length-start))
            guard range.location != NSNotFound else { return nil }
            if index == occurrence { return range }
            start = NSMaxRange(range)
        }
        return nil
    }
    private func seconds(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds)/1e18
    }
    private func residentBytes() -> UInt64? {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
}
