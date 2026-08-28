import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorP09OfflineTests: XCTestCase {
    func testLegalModelMetadataIsPinned() {
        let model = AIConnectorModelVariant.qwen35Legal4B

        XCTAssertEqual(model.modelID, "morpknight/qwen3.5-4b-indonesian-legal-mlx-4bit")
        XCTAssertEqual(model.revision, "2517cc7962517b85d97aff8988785cdb02c8fea1")
        XCTAssertEqual(model.shortRevision, "2517cc796251")
        XCTAssertEqual(model.downloadEstimate, "sekitar 2,39 GB")
    }

    func testLegalModelUsesGreedyNonThinkingProfileAndBaselineRemainsHistorical() {
        let legalModel = AIConnectorModelVariant.qwen35Legal4B
        let legal = legalModel
            .generationProfile(thinkingEnabled: false)
        let baseline = AIConnectorModelVariant.qwen35_2b
            .generationProfile(thinkingEnabled: false)
        let thinking = legalModel.generationProfile(thinkingEnabled: true)

        XCTAssertEqual(legal.maxTokens, 256)
        XCTAssertEqual(legal.temperature, 0)
        XCTAssertEqual(legal.topP, 1)
        XCTAssertEqual(legal.topK, 0)
        XCTAssertNil(legal.presencePenalty)
        XCTAssertTrue(legal.isGreedy)

        XCTAssertEqual(baseline.maxTokens, 256)
        XCTAssertEqual(baseline.temperature, 0.2)
        XCTAssertEqual(baseline.topP, 0.9)
        XCTAssertEqual(baseline.topK, 20)
        XCTAssertEqual(baseline.presencePenalty, 0)
        XCTAssertFalse(baseline.isGreedy)

        XCTAssertEqual(thinking.maxTokens, 768)
        XCTAssertEqual(thinking.temperature, 0.6)
        XCTAssertEqual(thinking.topP, 0.95)
        XCTAssertEqual(thinking.topK, 20)
    }

    func testViewModelDefaultsToHybridLegalModel() {
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )

        XCTAssertEqual(viewModel.reviewMode, .hybrid)
        XCTAssertEqual(viewModel.modelVariant, .qwen35Legal4B)
        XCTAssertFalse(viewModel.thinkingEnabled)
    }

    func testGenerationStopReasonsRoundTripThroughReportEncoding() throws {
        let metrics = AIConnectorGenerationMetrics(
            promptTokenCount: 12,
            generationTokenCount: 256,
            promptDuration: 0.1,
            generationDuration: 1.2,
            stopReason: .length
        )

        let encoded = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(
            AIConnectorGenerationMetrics.self,
            from: encoded
        )

        XCTAssertEqual(decoded.stopReason, .length)
        XCTAssertEqual(decoded.generationTokenCount, 256)
    }

    func testRepeatedSixGramDiagnosticUsesThreshold() {
        let repeated = Array(repeating: "satu dua tiga empat lima enam", count: 4)
            .joined(separator: " ")
        let ratio = AIConnectorGenerationDiagnostics.repeatedSixGramRatio(in: repeated)

        XCTAssertGreaterThanOrEqual(ratio, AIConnectorGenerationDiagnostics.repetitionThreshold)
        XCTAssertLessThan(
            AIConnectorGenerationDiagnostics.repeatedSixGramRatio(in: "satu dua tiga"),
            AIConnectorGenerationDiagnostics.repetitionThreshold
        )
    }

    func testReasoningDiagnosticIsRedactedBeforeStorage() {
        let raw = "<think>jawaban internal</think>\nSTATUS: NO_SUGGESTION"

        XCTAssertTrue(AIConnectorGenerationDiagnostics.containsReasoningMarkers(in: raw))
        XCTAssertEqual(
            AIConnectorGenerationDiagnostics.sanitizedDiagnosticOutput(raw),
            "[REDACTED: reasoning atau token template terdeteksi]"
        )
    }

    func testDeterministicRunnerProducesEncodableReportAndQualityGateCanBeCalculated() async throws {
        let dataEntry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        )
        let fillerEntries = (0..<100).map { index in
            LegalDictionaryEntry(
                id: "p09-filler-\(index)",
                term: "P09 Filler \(index)",
                definition: "kata unik p09 filler \(index)",
                regulation: "",
                regulationTitle: "",
                sourceURL: nil
            )
        }
        let runner = AIConnectorBenchmarkRunner(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [dataEntry] + fillerEntries)
        )

        let report = try await runner.run(
            mode: .deterministic,
            modelVariant: .qwen35Legal4B,
            thinkingEnabled: false,
            progress: { _, _ in }
        )

        XCTAssertEqual(report.records.count, AIConnectorSample.samples.count)
        XCTAssertEqual(report.evaluations.count, AIConnectorSample.samples.count)
        let evaluationDetails = report.evaluations.map { evaluation in
            "\(evaluation.sample.id)=\(evaluation.passed):\(evaluation.detail)"
        }.joined(separator: " | ")
        XCTAssertEqual(report.passedCount, report.totalCount, evaluationDetails)

        let modelGate = AIConnectorQualityGate(
            records: report.records,
            mode: .modelOnly
        )
        XCTAssertTrue(modelGate.passed)

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(AIConnectorBenchmarkReport.self, from: encoded)
        XCTAssertEqual(decoded.records.count, report.records.count)
        XCTAssertEqual(decoded.qualityGate, report.qualityGate)
    }
}
