import AppKit
import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import AMT

/// Opt-in, whole-document benchmark. Fixture and runner bytes are identical in
/// the baseline and changed tree. No user documents or storage manager are used.
@MainActor
final class AIConnectorFlowBenchmarkTests: XCTestCase {
    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_" + key]
    }

    func testFrozenProductionFlow() async throws {
        guard env("AMT_RUN_FLOW_BENCHMARK") == "1" else {
            throw XCTSkip("Opt-in model benchmark; regular tests remain offline.")
        }
        let phase = env("AMT_FLOW_PHASE") ?? "warm"
        let fixtureID = env("AMT_FLOW_FIXTURE") ?? "local-12"
        let directory = env("AMT_FLOW_OUTPUT") ?? "/private/tmp/amt-flow-fix-task/reports/before"
        guard directory.hasPrefix("/private/tmp/") else { throw XCTSkip("Reports require /private/tmp/.") }
        let fixture = try XCTUnwrap(Self.fixtures.first { $0.id == fixtureID })
        let store = LegalDictionaryStore()
        XCTAssertNotNil(store.corpusStore, "Must use the production corpus, never preview fallback.")
        let service = QwenSuggestionService()
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        vm.reviewMode = phase == "control" ? .deterministic : .hybrid
        vm.modelVariant = .qwen35Base4B
        vm.generationProfilePreset = .greedy
        vm.thinkingEnabled = false
        vm.flowBenchmarkReuseCaches = true
        var records: [FlowMeasurement] = []
        var preparation: Double?
        if phase == "prepare" || phase == "warm" || phase == "cached" || phase == "incremental" {
            let start = ContinuousClock.now
            try await vm.flowBenchmarkPrepareResources()
            preparation = seconds(start.duration(to: .now))
        }
        if phase != "prepare" {
            let repetitions = ["warm", "cached", "incremental"].contains(phase) ? 3 : 1
            if phase == "cached" { _ = try await measure(vm, fixture: fixture, iteration: 0) }
            for iteration in 1...repetitions {
                if phase == "warm" || phase == "incremental" { await vm.flowBenchmarkClearCaches() }
                if phase == "incremental" {
                    _ = try await measure(vm, fixture: fixture, iteration: 0)
                    let edited = fixture.id == "definitions"
                        ? fixture.text.replacingOccurrences(of: "informasi yang tidak dapat dipublikasikan", with: "informasi yang dapat dipublikasikan")
                        : fixture.text.replacingOccurrences(of: "memasukan", with: "memasukkan")
                    vm.markDocumentEdited(documentText: edited)
                    let editedFixture = FlowFixture(id: fixture.id + "-edited", text: edited, expected: [])
                    var incremental = try await measure(vm, fixture: editedFixture, iteration: iteration, incremental: true)
                    let expected = normalized(vm)
                    await vm.flowBenchmarkClearCaches()
                    _ = try await measure(vm, fixture: editedFixture, iteration: 0)
                    incremental.incrementalEquivalentToFresh = expected == normalized(vm)
                    records.append(incremental)
                } else {
                    records.append(try await measure(vm, fixture: fixture, iteration: iteration))
                }
            }
        }
        let envelope = FlowEnvelope(
            fixtureID: fixture.id,
            fixtureSHA256: sha(fixture.text),
            runnerSHA256: env("AMT_FLOW_RUNNER_SHA") ?? "unrecorded",
            buildIdentity: env("AMT_FLOW_BUILD") ?? "unrecorded",
            phase: phase,
            modelID: vm.modelVariant.modelID,
            modelRevision: vm.modelVariant.revision,
            corpusVersion: store.activeCorpusVersion,
            hardwareMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            preparationDuration: preparation,
            records: records
        )
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: url.appendingPathComponent("\(fixture.id)-\(phase).json"), options: .atomic)
        XCTAssertTrue(records.allSatisfy { $0.observation != nil }, "Each measured run must retain its completed stage report.")
        XCTAssertTrue(records.allSatisfy(\.complete), "Incomplete runs are recorded, never presented as successful benchmarks.")
    }

    private func measure(_ vm: AIConnectorViewModel, fixture: FlowFixture, iteration: Int, incremental: Bool = false) async throws -> FlowMeasurement {
        let clock = ContinuousClock()
        let start = clock.now
        var firstVisible: Double?
        var firstActionable: Double?
        var peakMemory = residentBytes()
        if incremental { vm.rerunIncrementally(documentText: fixture.text) }
        else { vm.run(documentText: fixture.text) }
        while vm.isRunning {
            if firstVisible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty || !vm.documentFindings.isEmpty) {
                firstVisible = seconds(start.duration(to: clock.now))
            }
            if firstActionable == nil && vm.editorSuggestions.contains(where: { $0.category == .spelling || $0.category == .grammar }) {
                firstActionable = seconds(start.duration(to: clock.now))
            }
            if let bytes = residentBytes() { peakMemory = max(peakMemory ?? 0, bytes) }
            if seconds(start.duration(to: clock.now)) > 900 {
                vm.cancel()
                throw FlowBenchmarkError.timeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let duration = seconds(start.duration(to: clock.now))
        await vm.flowBenchmarkAwaitCompletion()
        if firstVisible == nil && (!vm.editorSuggestions.isEmpty || !vm.reviewAnnotations.isEmpty || !vm.documentFindings.isEmpty) { firstVisible = duration }
        if firstActionable == nil && vm.editorSuggestions.contains(where: { $0.category == .spelling || $0.category == .grammar }) { firstActionable = duration }
        if let bytes = residentBytes() { peakMemory = max(peakMemory ?? 0, bytes) }
        let output = normalized(vm)
        let observed = vm.validatedReviews.compactMap { review -> String? in
            guard review.status == .suggestion, let original = review.original, let replacement = review.replacement else { return nil }
            return "\(review.category.rawValue)|\(original)|\(replacement)"
        }
        var remaining = observed
        var tp = 0
        for wanted in fixture.expected {
            if let index = remaining.firstIndex(of: wanted) { tp += 1; remaining.remove(at: index) }
        }
        let invalidMappedAnchors = vm.editorSuggestions.filter { !$0.isAnchored(to: fixture.text) }.count
            + vm.reviewAnnotations.filter { !$0.isAnchored(to: fixture.text) }.count
        let invalidAnchors = invalidMappedAnchors + vm.validatedReviews.filter { review in
            guard let original = review.original, let anchor = review.sourceAnchor else { return false }
            let range = NSRange(location: review.segment.sourceLocation + anchor.sourceLocation, length: anchor.sourceLength)
            return !anchor.isValid(for: review.segment, original: original) || range.location < 0 || NSMaxRange(range) > fixture.text.utf16.count || (fixture.text as NSString).substring(with: range) != original
        }.count
        return FlowMeasurement(iteration: iteration, complete: { if case .completed = vm.state { return true }; return false }(), firstVisible: firstVisible, firstLocalActionable: firstActionable, total: duration, peakResidentBytes: peakMemory, segmentCount: vm.segmentationResult?.segments.count ?? 0, processedSegments: vm.processedSegmentCount, skippedSegments: vm.skippedSegmentCount, truePositives: tp, falsePositives: remaining.count, falseNegatives: fixture.expected.count - tp, invalidAnchors: invalidAnchors, invalidSources: vm.flowBenchmarkInvalidSourceCount(), normalizedFindings: output, observation: vm.observationReport, contextModelCalls: vm.contextPreparationCacheHit ? 0 : (vm.documentContextProfile?.modelCallCount ?? 0), incrementalEquivalentToFresh: nil)
    }

    private func normalized(_ vm: AIConnectorViewModel) -> [String] {
        let reviews = vm.validatedReviews.filter { $0.status != .noSuggestion }.map {
            "review|\($0.segment.sourceLocation + ($0.sourceAnchor?.sourceLocation ?? 0))|\($0.status.rawValue)|\($0.category.rawValue)|\($0.original ?? "")|\($0.replacement ?? "")|\($0.glossaryMatch?.entry.id ?? "")"
        }
        let definitions = vm.definitionAssessments.map { String(describing: $0.classification) + "|" + String(describing: $0.alignment) + "|" + $0.segment.targetText }
        let findings = vm.documentFindings.map { "finding|\($0.kind)|\($0.sourceRange.location)|\($0.sourceRange.length)" }
        return (reviews + definitions + findings).sorted()
    }

    private func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
    private func seconds(_ duration: Duration) -> Double { AIConnectorObservationTiming.seconds(duration) }
    private func sha(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    private static let fixtures: [FlowFixture] = {
        var fixtures = [12,60,180].map { count in
            let texts = (1...count).map { "Pihak Kedua memasukan dokumen nomor \($0) yang telah ditanda tangani dan di simpan oleh Pihak Pertama." }
            let expectations = (1...count).flatMap { _ in ["SPELLING|memasukan|memasukkan", "SPELLING|ditanda tangani|ditandatangani", "SPELLING|di simpan|disimpan"] }
            return FlowFixture(id: "local-\(count)", text: texts.joined(separator: "\n"), expected: expectations)
        }
        fixtures.append(FlowFixture(id: "terminology", text: "PERJANJIAN PENGOLAHAN DATA\nData Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.\nPihak Kedua memproses informasi mengenai individu yang identitasnya dapat diketahui melalui sistem elektronik.\nKorporasi adalah kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum.", expected: []))
        fixtures.append(FlowFixture(id: "definitions", text: "BAB I\n\"Data\" adalah informasi yang tidak dapat dipublikasikan.\n\"Data Pribadi\" adalah data mengenai pelanggan korporat.\nBAB II\nPihak Kedua wajib menjaga Data.\nPihak Pertama tidak dapat membuka Data kecuali mendapatkan persetujuan tertulis.\nPihak Kedua wajib memenuhi Pasal 99.\nPihak Pertama dapat menyampaikan pemberitahuan.", expected: []))
        let mixed = (1...60).map { i in "\(i). Pihak Kedua wajib untuk memastikan dokumen nomor \(i) di simpan, ditanda tangani, dan memasukan tanggal sebelum diserahkan." }.joined(separator: "\n")
        fixtures.append(FlowFixture(id: "mixed", text: "PERJANJIAN\n\"Data\" adalah informasi umum.\n" + mixed + "\nLampiran A\nNama | Kewajiban\nPihak Kedua | menjaga Data\nPihak Pertama | tidak mengubah Data\n" + Array(repeating: "dokumen pendukung harus tersedia untuk pemeriksaan", count: 150).joined(separator: " ") + ".", expected: []))
        return fixtures
    }()
}

private enum FlowBenchmarkError: Error { case timeout }
private struct FlowFixture { let id: String; let text: String; let expected: [String] }
private struct FlowMeasurement: Codable {
    let iteration: Int
    let complete: Bool
    let firstVisible: Double?
    let firstLocalActionable: Double?
    let total: Double
    let peakResidentBytes: UInt64?
    let segmentCount: Int
    let processedSegments: Int
    let skippedSegments: Int
    let truePositives: Int
    let falsePositives: Int
    let falseNegatives: Int
    let invalidAnchors: Int
    let invalidSources: Int
    let normalizedFindings: [String]
    let observation: AIConnectorObservationReport?
    let contextModelCalls: Int
    var incrementalEquivalentToFresh: Bool?
}
private struct FlowEnvelope: Codable {
    let fixtureID: String
    let fixtureSHA256: String
    let runnerSHA256: String
    let buildIdentity: String
    let phase: String
    let modelID: String
    let modelRevision: String
    let corpusVersion: String
    let hardwareMemoryBytes: UInt64
    let os: String
    let preparationDuration: Double?
    let records: [FlowMeasurement]
}
