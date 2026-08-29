import Foundation
import XCTest
@testable import AMT

/// Opt-in only: this test downloads/loads the selected pinned model and can
/// take several minutes. Base 4B is the current default. Normal unit-test
/// runs skip it before touching MLX.
@MainActor
final class AIConnectorModelBenchmarkTests: XCTestCase {
    func testP010SelectedModelBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["AMT_RUN_P09_MODEL_BENCHMARK"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_AMT_RUN_P09_MODEL_BENCHMARK=1 to run the model benchmark.")
        }

        let reportPath = ProcessInfo.processInfo.environment["AMT_P09_REPORT_PATH"]
            ?? "/private/tmp/amt-p010-base-4b.json"
        guard reportPath.hasPrefix("/private/tmp/") else {
            throw XCTSkip("AMT_P09_REPORT_PATH must be under /private/tmp.")
        }

        let service = QwenSuggestionService()
        let runner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: LegalDictionaryStore()
        )
        let model: AIConnectorModelVariant
        if let rawModelVariant = ProcessInfo.processInfo.environment["AMT_P09_MODEL_VARIANT"] {
            guard let selectedModel = AIConnectorModelVariant(rawValue: rawModelVariant) else {
                XCTFail("Unknown AMT_P09_MODEL_VARIANT: \(rawModelVariant)")
                return
            }
            model = selectedModel
        } else {
            model = .qwen35Base4B
        }

        let baseline = try await runner.run(
            mode: .deterministic,
            modelVariant: model,
            thinkingEnabled: false,
            progress: { _, _ in }
        )
        let qwenOnly = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            progress: { _, _ in }
        )
        let cachedQwenOnly = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            resetCache: false,
            progress: { _, _ in }
        )
        let hybrid = try await runner.run(
            mode: .hybrid,
            modelVariant: model,
            thinkingEnabled: false,
            progress: { _, _ in }
        )

        var thinkingReport: AIConnectorBenchmarkReport?
        var thinkingError: String?
        do {
            thinkingReport = try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: true,
                samples: [AIConnectorSample.samples[0]],
                progress: { _, _ in }
            )
        } catch {
            thinkingError = error.localizedDescription
        }

        var cancellationProgressCount = 0
        var cancellationPassed = false
        let cancellationTask = Task { @MainActor in
            try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: false,
                samples: AIConnectorSample.samples,
                progress: { _, _ in
                    cancellationProgressCount += 1
                }
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            XCTFail("Cancelled benchmark unexpectedly completed.")
        } catch is CancellationError {
            // Expected: the runner must not start the next fixture.
            cancellationPassed = true
        } catch let error as QwenSuggestionError {
            XCTFail("Cancellation surfaced as a model error: \(error.localizedDescription)")
        }
        XCTAssertTrue(cancellationPassed)
        XCTAssertLessThanOrEqual(
            cancellationProgressCount,
            1,
            "Cancellation must not start a second fixture."
        )

        let envelope = AIConnectorP09BenchmarkEnvelope(
            generatedAt: Date(),
            modelID: model.modelID,
            revision: model.revision,
            baseline: baseline,
            qwenOnly: qwenOnly,
            cachedQwenOnly: cachedQwenOnly,
            hybrid: hybrid,
            thinking: thinkingReport,
            thinkingError: thinkingError,
            cancellationPassed: cancellationPassed
        )
        let data = try JSONEncoder.prettySorted.encode(envelope)
        try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)

        XCTAssertEqual(baseline.passedCount, baseline.totalCount)
        XCTAssertEqual(qwenOnly.records.count, AIConnectorSample.samples.count)
        XCTAssertTrue(cachedQwenOnly.records.allSatisfy(\.cacheHit))
        XCTAssertEqual(hybrid.records.count, AIConnectorSample.samples.count)
        XCTAssertTrue(qwenOnly.records.allSatisfy { !$0.diagnosticOutput.orEmpty.contains("<think>") })
    }
}

private struct AIConnectorP09BenchmarkEnvelope: Codable {
    let generatedAt: Date
    let modelID: String
    let revision: String
    let baseline: AIConnectorBenchmarkReport
    let qwenOnly: AIConnectorBenchmarkReport
    let cachedQwenOnly: AIConnectorBenchmarkReport
    let hybrid: AIConnectorBenchmarkReport
    let thinking: AIConnectorBenchmarkReport?
    let thinkingError: String?
    let cancellationPassed: Bool
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
