import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorDummyDocumentTests: XCTestCase {
    func testBuiltInCatalogContainsFourDistinctLongFormDocuments() {
        let documents = AIConnectorDummyDocument.builtInDocuments

        XCTAssertEqual(documents.count, 4)
        XCTAssertEqual(Set(documents.map(\.id)).count, documents.count)
        XCTAssertEqual(Set(documents.map(\.title)).count, documents.count)
        XCTAssertEqual(documents.first?.id, AIConnectorDummyDocument.id)
        XCTAssertEqual(documents.first?.content, AIConnectorDummyDocument.initialContent)

        for document in documents {
            let wordCount = document.content.split(whereSeparator: \.isWhitespace).count
            XCTAssertGreaterThan(
                wordCount,
                300,
                "Fixture \(document.title) harus cukup panjang untuk review dokumen nyata."
            )
            XCTAssertTrue(AIConnectorDummyDocument.isBuiltIn(document))
        }
    }

    func testBuiltInCatalogContainsDistinctLegalDomainsAndIntentSensitiveSignals() {
        let documents = AIConnectorDummyDocument.builtInDocuments

        let requiredSignals: [[String]] = [
            ["Data Pribadi", "Korporasi", "Keadaan Kahar", "ditanda tangani"],
            ["Subprosesor", "Transfer Internasional", "Insiden Keamanan", "di lakukan", "72 (tujuh puluh dua)"],
            ["Borrower", "Lender", "Facility", "Collateral", "Event of Default", "Rp25.750.000.000", "10,75%"],
            ["HPS", "SLA", "BAST", "Addendum", "Keadaan Kahar", "1/1000", "Rp8.375.000.000"]
        ]

        XCTAssertEqual(requiredSignals.count, documents.count)
        for (document, signals) in zip(documents, requiredSignals) {
            for signal in signals {
                XCTAssertTrue(
                    document.content.contains(signal),
                    "Fixture \(document.title) tidak memuat sinyal \(signal)."
                )
            }
        }
    }

    func testBuiltInDocumentsAreDocumentWideSegmentsWithoutOmission() {
        let segmenter = LegalTextSegmenter()

        for document in AIConnectorDummyDocument.builtInDocuments {
            let segmentation = segmenter.segment(documentText: document.content)

            XCTAssertGreaterThan(
                segmentation.segments.count,
                LegalTextSegmenter.batchSize,
                "Fixture \(document.title) harus melewati satu batch queue."
            )
            XCTAssertEqual(segmentation.queuedSegmentCount, segmentation.segments.count)
            XCTAssertEqual(segmentation.omittedSegmentCount, 0)
        }
    }

    func testViewModelProcessesEveryBuiltInDocumentInDeterministicModeWithoutModel() async {
        let segmenter = LegalTextSegmenter()

        for document in AIConnectorDummyDocument.builtInDocuments {
            let viewModel = AIConnectorViewModel(
                service: QwenSuggestionService(),
                dictionaryStore: LegalDictionaryStore(entries: [])
            )
            viewModel.inputSource = .currentDocument
            viewModel.reviewMode = .deterministic
            viewModel.run(documentText: document.content)

            let finished = await waitForCompletion(of: viewModel)
            XCTAssertTrue(finished, "ViewModel gagal menyelesaikan fixture \(document.title).")
            guard finished else { continue }

            let segmentation = segmenter.segment(documentText: document.content)
            XCTAssertEqual(viewModel.state, .completed)
            XCTAssertEqual(viewModel.runSummary?.reviewMode, .deterministic)
            XCTAssertEqual(viewModel.runSummary?.totalSegmentCount, segmentation.segments.count)
            XCTAssertEqual(
                viewModel.processedSegmentCount + viewModel.skippedSegmentCount,
                segmentation.segments.count
            )
            XCTAssertEqual(viewModel.modelCallCount, 0)
            XCTAssertEqual(viewModel.runSummary?.modelCallCount, 0)
            XCTAssertGreaterThan(viewModel.processedSegmentCount, 0)
        }
    }

    func testAllCatalogIDsAreProtectedAsBuiltInDocuments() {
        for document in AIConnectorDummyDocument.builtInDocuments {
            var editedDocument = document
            editedDocument.content += "\nPerubahan lokal untuk test."
            XCTAssertTrue(AIConnectorDummyDocument.isBuiltIn(editedDocument))
        }

        let userDocument = DashboardDocument(
            id: UUID(),
            title: "Dokumen pengguna",
            content: "Isi dokumen pengguna"
        )
        XCTAssertFalse(AIConnectorDummyDocument.isBuiltIn(userDocument))
    }

    private func waitForCompletion(of viewModel: AIConnectorViewModel) async -> Bool {
        for _ in 0..<600 {
            if !viewModel.isRunning {
                return viewModel.state == .completed
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        viewModel.cancel()
        return false
    }
}
