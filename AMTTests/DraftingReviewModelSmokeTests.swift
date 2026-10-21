import Foundation
import XCTest
@testable import AMT

/// Opt-in integration evidence, not a legal quality gate. Ordinary tests do not
/// load/download Qwen. Every input below is synthetic and all output is read-only.
@MainActor
final class DraftingReviewModelSmokeTests: XCTestCase {
    func testProductionDraftingRoutesWithResidentModel() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AMT_RUN_DRAFTING_INTEGRATION_SMOKE"] == "1",
              let reportPath = environment["AMT_DRAFTING_INTEGRATION_REPORT"] else {
            throw XCTSkip("Set AMT_RUN_DRAFTING_INTEGRATION_SMOKE=1 explicitly.")
        }
        let qwen = QwenSuggestionService()
        let service = DraftingReviewService(service: qwen)
        let preparationStart = ContinuousClock.now
        try await qwen.prepareModel(for: .qwen35Base4B)
        let preparation = seconds(preparationStart)
        let cases: [(String, DraftingReview.Request)] = [
            ("literal-payment", request("Penyedia membayar dalam 5 hari setelah tagihan diterima.", brief: "Ubah tenggat pembayaran menjadi 10 hari.", scope: .rewriteTarget)),
            ("literal-frequency", request("Penyedia mengirim laporan bulanan.", brief: "Ubah frekuensi laporan menjadi mingguan.", scope: .rewriteTarget)),
            ("no-change", request("Jasa diberikan jarak jauh.", brief: "Pastikan jasa diberikan jarak jauh.", scope: .verifyDocument)),
            ("missing-location", request("Penyerahan dilakukan di lokasi pilihan Pelanggan.", brief: "Cantumkan lokasi penyerahan; lokasinya belum diberikan.", scope: .rewriteTarget)),
            ("missing-report-choice", request("Penyedia mengirim laporan teknis atau laporan keuangan.", brief: "Pastikan laporan yang diminta disebutkan, tetapi jenis laporannya belum dipilih.", scope: .verifyDocument)),
            ("oversized-evidence", request(String(repeating: "Penyedia wajib mempertahankan informasi dan pengecualiannya. ", count: 1500), brief: "Periksa seluruh klausul.", scope: .verifyDocument))
        ]
        var records: [[String: Any]] = []
        for (id, input) in cases {
            service.clearCache()
            let start = ContinuousClock.now
            let warm = await service.review(input)
            let warmSeconds = seconds(start)
            let cachedStart = ContinuousClock.now
            let cached = await service.review(input, fullFresh: false)
            records.append(record(id: id, phase: "warm", result: warm, duration: warmSeconds))
            records.append(record(id: id, phase: "cached", result: cached, duration: seconds(cachedStart)))
            XCTAssertTrue(warm.isReadOnly)
            if id.hasPrefix("literal-") {
                XCTAssertTrue(warm.isComplete)
                XCTAssertEqual(warm.modelCallCount, 0)
                XCTAssertTrue(cached.cacheHit)
            } else if id == "oversized-evidence" {
                XCTAssertEqual(warm.failures, ["requiredEvidenceTooLong"])
                XCTAssertFalse(cached.cacheHit)
                XCTAssertNil(warm.response)
            } else {
                XCTAssertEqual(warm.modelCallCount, 1)
                XCTAssertNotNil(warm.generationMetrics)
                XCTAssertEqual(cached.cacheHit, warm.isComplete)
                XCTAssertEqual(warm.response, cached.response)
            }
        }
        let report: [String: Any] = [
            "purpose": "Production integration smoke; synthetic pending labels; no legal quality claim",
            "policy": DraftingReview.policyVersion,
            "model": AIConnectorModelVariant.qwen35Base4B.modelID,
            "revision": AIConnectorModelVariant.qwen35Base4B.revision,
            "preparationSeconds": preparation,
            "records": records
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
    }

    private func request(_ text: String, brief: String, scope: DraftingReview.Scope) -> DraftingReview.Request {
        .init(documentText: text, documentRevision: DocumentFingerprinting.contentSHA256(text), brief: brief,
              scope: scope, clauses: [.init(id: "c1", text: text, sourceRange: NSRange(location: 0, length: text.utf16.count))], targetClauseIDs: ["c1"])
    }

    private func seconds(_ start: ContinuousClock.Instant) -> Double { AIConnectorObservationTiming.seconds(start.duration(to: .now)) }

    private func record(id: String, phase: String, result: DraftingReview.Result, duration: Double) -> [String: Any] {
        var record: [String: Any] = ["id": id, "phase": phase, "seconds": duration, "status": result.status.rawValue,
            "route": result.route.rawValue, "modelCalls": result.modelCallCount, "cacheHit": result.cacheHit,
            "failures": result.failures, "readOnly": result.isReadOnly]
        if let response = result.response, let data = try? JSONEncoder().encode(response),
           let object = try? JSONSerialization.jsonObject(with: data) { record["response"] = object }
        if let metrics = result.generationMetrics { record["promptTokens"] = metrics.promptTokenCount; record["outputTokens"] = metrics.generationTokenCount }
        return record
    }
}
