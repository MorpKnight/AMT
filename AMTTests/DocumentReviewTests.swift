import AppKit
import Foundation
import XCTest
@testable import AMT

@MainActor
final class DocumentReviewTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("amt-document-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testLegacyJSONDecodesWithoutNewReviewMetadata() throws {
        let id = UUID()
        let data = Data("""
        {
          "id": "\(id.uuidString)",
          "title": "Dokumen lama",
          "content": "Isi lama",
          "createdAt": 0,
          "updatedAt": 0
        }
        """.utf8)

        let document = try JSONDecoder().decode(DashboardDocument.self, from: data)

        XCTAssertEqual(document.id, id)
        XCTAssertEqual(document.title, "Dokumen lama")
        XCTAssertNil(document.originalFileName)
        XCTAssertNil(document.originalSidecarRelativePath)
        XCTAssertNil(document.originalFingerprint)
        XCTAssertNil(document.reviewSnapshot)
    }

    func testImportStoresOriginalSidecarAndMetadata() throws {
        let sourceURL = try writeDocx(named: "Kontrak Sumber.docx", text: "Pihak Kedua wajib untuk menyerahkan laporan.")
        let storage = DocumentStorageManager(storageDirectory: temporaryDirectory)

        let imported = try storage.importWordDocument(from: sourceURL)
        let sidecarURL = try XCTUnwrap(storage.originalFileURL(for: imported))

        XCTAssertEqual(imported.originalFileName, "Kontrak Sumber.docx")
        XCTAssertEqual(
            imported.originalSidecarRelativePath,
            "AMT_Documents/\(imported.id.uuidString).original.docx"
        )
        XCTAssertEqual(
            imported.originalFingerprint,
            try DocumentFingerprint.sha256(fileURL: sourceURL)
        )
        XCTAssertEqual(try Data(contentsOf: sidecarURL), try Data(contentsOf: sourceURL))
        XCTAssertEqual(imported.content, "Pihak Kedua wajib untuk menyerahkan laporan.")
    }

    func testDeletingDocumentRemovesOnlyItsRelatedSidecar() throws {
        let sourceURL = try writeDocx(named: "Kontrak Sumber.docx", text: "Isi kontrak.")
        let storage = DocumentStorageManager(storageDirectory: temporaryDirectory)
        let imported = try storage.importWordDocument(from: sourceURL)
        let sidecarURL = try XCTUnwrap(storage.originalFileURL(for: imported))
        let unrelatedURL = temporaryDirectory.appendingPathComponent("unrelated.original.docx")
        try Data("unrelated".utf8).write(to: unrelatedURL)

        storage.deleteDocument(imported)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
        XCTAssertFalse(storage.documents.contains { $0.id == imported.id })
    }

    func testReviewSnapshotRoundTripsThroughDocumentStorage() throws {
        let sourceText = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceURL = try writeDocx(named: "Persisted Review.docx", text: sourceText)
        let storage = DocumentStorageManager(storageDirectory: temporaryDirectory)
        let imported = try storage.importWordDocument(from: sourceURL)
        let reviewItem = makeReviewItem(
            segmentID: 1,
            original: "wajib untuk",
            replacement: "wajib",
            sourceRange: (sourceText as NSString).range(of: "wajib untuk"),
            decision: .accepted
        )
        let snapshot = DocumentReviewSnapshot(
            sourceFingerprint: try XCTUnwrap(imported.originalFingerprint),
            analysisStatus: .completed,
            reviewItems: [reviewItem]
        )
        var updated = imported
        updated.reviewSnapshot = snapshot
        _ = storage.saveDocument(updated)

        let reopenedStorage = DocumentStorageManager(storageDirectory: temporaryDirectory)
        let reopened = try XCTUnwrap(
            reopenedStorage.documents.first(where: { $0.id == imported.id })
        )

        XCTAssertEqual(reopened.reviewSnapshot, snapshot)
        XCTAssertEqual(
            reopenedStorage.originalFileURL(for: reopened)?.lastPathComponent,
            imported.originalSidecarRelativePath?.split(separator: "/").last.map(String.init)
        )
    }

    func testExtractionKeepsSourceTextAndMarkdownAnalysisText() throws {
        let sourceURL = try writeDocx(
            named: "Extraction.docx",
            text: "PASAL 1\nPihak Kedua wajib untuk menyerahkan laporan."
        )

        let extraction = try DocxToMarkdownConverter.extract(fileURL: sourceURL)

        XCTAssertEqual(
            extraction.sourceText.trimmingCharacters(in: .newlines),
            "PASAL 1\nPihak Kedua wajib untuk menyerahkan laporan."
        )
        XCTAssertTrue(extraction.analysisText.contains("### PASAL 1"))
        XCTAssertTrue(extraction.analysisText.contains("wajib untuk"))
    }

    func testMapperUsesUTF16OffsetsAndFailsClosedForAmbiguityAndMissingText() {
        let prefix = "Pembukaan 😀.\n"
        let target = "Pihak Kedua wajib untuk menyerahkan laporan."
        let source = prefix + target
        let mapped = DocumentReviewMapper.make(
            reviews: [makeReview(segmentText: target, original: "wajib untuk", replacement: "wajib")],
            sourceText: source
        )

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].decision, .pending)
        XCTAssertEqual(
            mapped[0].sourceRange?.location,
            prefix.utf16.count + (target as NSString).range(of: "wajib untuk").location
        )
        XCTAssertEqual(mapped[0].sourceRange?.length, "wajib untuk".utf16.count)

        let duplicate = DocumentReviewMapper.make(
            reviews: [makeReview(segmentText: "wajib", original: "wajib", replacement: "harus")],
            sourceText: "wajib dan wajib"
        )
        XCTAssertEqual(duplicate.first?.decision, .unavailable)
        XCTAssertEqual(duplicate.first?.mappingIssue, .ambiguousInSource)
        XCTAssertNil(duplicate.first?.sourceRange)

        let overlappingDuplicate = DocumentReviewMapper.make(
            reviews: [makeReview(segmentText: "aaa", original: "aa", replacement: "AA")],
            sourceText: "aaa"
        )
        XCTAssertEqual(overlappingDuplicate.first?.decision, .unavailable)
        XCTAssertEqual(overlappingDuplicate.first?.mappingIssue, .ambiguousInAnalysis)

        let missing = DocumentReviewMapper.make(
            reviews: [makeReview(segmentText: "wajib", original: "wajib", replacement: "harus")],
            sourceText: "Tidak ada kutipan ini."
        )
        XCTAssertEqual(missing.first?.decision, .unavailable)
        XCTAssertEqual(missing.first?.mappingIssue, .missingFromSource)
    }

    func testMapperMarksOverlappingChangesUnavailable() {
        let reviews = [
            makeReview(segmentID: 1, segmentText: "abc", original: "abc", replacement: "ABC"),
            makeReview(segmentID: 2, segmentText: "bc", original: "bc", replacement: "BC")
        ]

        let items = DocumentReviewMapper.make(reviews: reviews, sourceText: "abc")

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.decision == .unavailable })
        XCTAssertTrue(items.allSatisfy { $0.mappingIssue == .overlapsAnotherChange })
    }

    func testAutomaticAnalysisRunsOnceAndAcceptDoesNotMutateSource() async throws {
        let sourceText = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceURL = try writeDocx(named: "Review.docx", text: sourceText)
        let fingerprint = try DocumentFingerprint.sha256(fileURL: sourceURL)
        let document = DashboardDocument(
            title: "Review",
            content: "**Pihak Kedua wajib untuk menyerahkan laporan.**",
            originalFileName: "Review.docx",
            originalSidecarRelativePath: "AMT_Documents/review.original.docx",
            originalFingerprint: fingerprint
        )
        let analyzer = StubDocumentReviewAnalyzer(reviews: [
            makeReview(segmentText: sourceText, original: "wajib untuk", replacement: "wajib")
        ])
        var snapshots: [DocumentReviewSnapshot] = []
        let viewModel = DocumentReviewViewModel(
            document: document,
            originalURL: sourceURL,
            analyzer: analyzer,
            onSnapshotChanged: { _, snapshot in
                snapshots.append(snapshot)
            }
        )
        let originalBytes = try Data(contentsOf: sourceURL)

        viewModel.startAutomaticAnalysisIfNeeded()
        viewModel.startAutomaticAnalysisIfNeeded()
        await waitForAnalysis(viewModel)

        XCTAssertEqual(analyzer.analysisCallCount, 1)
        let item = try XCTUnwrap(viewModel.reviewItems.first)
        XCTAssertTrue(viewModel.accept(itemID: item.id))
        XCTAssertEqual(viewModel.reviewItems.first?.decision, .accepted)
        XCTAssertEqual(document.content, "**Pihak Kedua wajib untuk menyerahkan laporan.**")
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
        XCTAssertEqual(snapshots.last?.reviewItems.first?.decision, .accepted)
    }

    func testRejectOnlyChangesReviewDraft() async throws {
        let sourceText = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceURL = try writeDocx(named: "Reject.docx", text: sourceText)
        let fingerprint = try DocumentFingerprint.sha256(fileURL: sourceURL)
        let document = DashboardDocument(
            title: "Reject",
            content: sourceText,
            originalSidecarRelativePath: "AMT_Documents/reject.original.docx",
            originalFingerprint: fingerprint
        )
        let analyzer = StubDocumentReviewAnalyzer(reviews: [
            makeReview(segmentText: sourceText, original: "wajib untuk", replacement: "wajib")
        ])
        let viewModel = DocumentReviewViewModel(
            document: document,
            originalURL: sourceURL,
            analyzer: analyzer
        )
        let originalBytes = try Data(contentsOf: sourceURL)

        viewModel.analyze()
        await waitForAnalysis(viewModel)

        let item = try XCTUnwrap(viewModel.reviewItems.first)
        XCTAssertTrue(viewModel.reject(itemID: item.id))
        XCTAssertEqual(viewModel.reviewItems.first?.decision, .rejected)
        XCTAssertEqual(viewModel.sourceText.trimmingCharacters(in: .newlines), sourceText)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
    }

    func testValidSnapshotRestoresAndStaleSnapshotIsRejected() throws {
        let sourceText = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceURL = try writeDocx(named: "Restore.docx", text: sourceText)
        let fingerprint = try DocumentFingerprint.sha256(fileURL: sourceURL)
        let item = makeReviewItem(
            segmentID: 1,
            original: "wajib untuk",
            replacement: "wajib",
            sourceRange: (sourceText as NSString).range(of: "wajib untuk"),
            decision: .accepted
        )
        let snapshot = DocumentReviewSnapshot(
            sourceFingerprint: fingerprint,
            analysisStatus: .completed,
            reviewItems: [item]
        )
        let restoredDocument = DashboardDocument(
            title: "Restore",
            content: sourceText,
            originalSidecarRelativePath: "AMT_Documents/restore.original.docx",
            originalFingerprint: fingerprint,
            reviewSnapshot: snapshot
        )
        let restoredAnalyzer = StubDocumentReviewAnalyzer(reviews: [])
        let restored = DocumentReviewViewModel(
            document: restoredDocument,
            originalURL: sourceURL,
            analyzer: restoredAnalyzer
        )

        XCTAssertTrue(restored.didRestoreSnapshot)
        XCTAssertEqual(restored.reviewItems.first?.decision, .accepted)
        restored.startAutomaticAnalysisIfNeeded()
        XCTAssertEqual(restoredAnalyzer.analysisCallCount, 0)

        let staleDocument = DashboardDocument(
            title: "Stale",
            content: sourceText,
            originalSidecarRelativePath: "AMT_Documents/stale.original.docx",
            originalFingerprint: fingerprint,
            reviewSnapshot: DocumentReviewSnapshot(
                sourceFingerprint: "stale-fingerprint",
                analysisStatus: .completed,
                reviewItems: [item]
            )
        )
        let stale = DocumentReviewViewModel(
            document: staleDocument,
            originalURL: sourceURL,
            analyzer: StubDocumentReviewAnalyzer(reviews: [])
        )

        XCTAssertTrue(stale.didRejectStaleSnapshot)
        XCTAssertTrue(stale.reviewItems.isEmpty)
        XCTAssertFalse(stale.didRestoreSnapshot)
    }

    func testExportReopensWithReplacementAndLeavesOriginalByteIdentical() throws {
        let sourceText = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceURL = try writeFormattedDocx(
            named: "Original.docx",
            text: sourceText,
            boldRange: (sourceText as NSString).range(of: "wajib untuk")
        )
        let originalBytes = try Data(contentsOf: sourceURL)
        let range = (sourceText as NSString).range(of: "wajib untuk")
        let item = makeReviewItem(
            segmentID: 1,
            original: "wajib untuk",
            replacement: "wajib",
            sourceRange: range,
            decision: .accepted
        )

        let exportedData = try DocumentExporter.makeReviewedDocxData(
            originalURL: sourceURL,
            expectedFingerprint: DocumentFingerprint.sha256(data: originalBytes),
            acceptedItems: [item]
        )
        let outputURL = temporaryDirectory.appendingPathComponent("Original - Reviewed.docx")
        try exportedData.write(to: outputURL)
        let reviewed = try DocxToMarkdownConverter.loadAttributedString(fileURL: outputURL)

        XCTAssertTrue(reviewed.string.contains("Pihak Kedua wajib menyerahkan laporan."))
        XCTAssertFalse(reviewed.string.contains("wajib untuk"))
        let replacementRange = (reviewed.string as NSString).range(of: "wajib")
        XCTAssertNotEqual(replacementRange.location, NSNotFound)
        guard replacementRange.location != NSNotFound else { return }
        let replacementFont = reviewed.attribute(
            .font,
            at: replacementRange.location,
            effectiveRange: nil
        ) as? NSFont
        XCTAssertTrue(replacementFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
    }

    func testExportRejectsOverlappingAcceptedRanges() throws {
        let sourceText = "abc"
        let sourceURL = try writeDocx(named: "Overlap.docx", text: sourceText)
        let items = [
            makeReviewItem(
                segmentID: 1,
                original: "abc",
                replacement: "ABC",
                sourceRange: NSRange(location: 0, length: 3),
                decision: .accepted
            ),
            makeReviewItem(
                segmentID: 2,
                original: "bc",
                replacement: "BC",
                sourceRange: NSRange(location: 1, length: 2),
                decision: .accepted
            )
        ]

        XCTAssertThrowsError(
            try DocumentExporter.makeReviewedDocxData(
                originalURL: sourceURL,
                expectedFingerprint: try DocumentFingerprint.sha256(fileURL: sourceURL),
                acceptedItems: items
            )
        ) { error in
            XCTAssertEqual(error as? DocumentExportError, .overlappingChanges)
        }
    }

    private func writeDocx(named name: String, text: String) throws -> URL {
        let attributedString = NSAttributedString(string: text)
        return try writeDocx(named: name, attributedString: attributedString)
    }

    private func writeFormattedDocx(
        named name: String,
        text: String,
        boldRange: NSRange
    ) throws -> URL {
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 12),
            range: boldRange
        )
        return try writeDocx(named: name, attributedString: attributedString)
    }

    private func writeDocx(
        named name: String,
        attributedString: NSAttributedString
    ) throws -> URL {
        let data = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        let url = temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeReview(
        segmentID: Int = 1,
        segmentText: String,
        original: String,
        replacement: String
    ) -> AIValidatedReview {
        AIValidatedReview(
            segment: AIReviewSegment(
                id: segmentID,
                sourceLocation: 0,
                sourceLength: segmentText.utf16.count,
                targetText: segmentText,
                previousContext: nil,
                nextContext: nil
            ),
            status: .suggestion,
            category: .grammar,
            original: original,
            replacement: replacement,
            reason: "Perbaikan bahasa.",
            glossaryMatch: nil,
            origin: .deterministic
        )
    }

    private func makeReviewItem(
        segmentID: Int,
        original: String,
        replacement: String,
        sourceRange: NSRange,
        decision: DocumentReviewDecision
    ) -> DocumentReviewItem {
        DocumentReviewItem(
            segmentID: segmentID,
            original: original,
            replacement: replacement,
            category: .grammar,
            reason: "Perbaikan bahasa.",
            origin: .deterministic,
            sourceRange: DocumentTextRange(sourceRange),
            decision: decision
        )
    }

    private func waitForAnalysis(_ viewModel: DocumentReviewViewModel) async {
        for _ in 0..<100 {
            if !viewModel.isAnalyzing { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class StubDocumentReviewAnalyzer: DocumentReviewAnalyzer {
    let reviews: [AIValidatedReview]
    private(set) var analysisCallCount = 0

    init(reviews: [AIValidatedReview]) {
        self.reviews = reviews
    }

    func analyze(
        documentText: String,
        progress: @escaping (DocumentReviewProgress) -> Void
    ) async throws -> [AIValidatedReview] {
        analysisCallCount += 1
        progress(DocumentReviewProgress(fraction: 1, detail: "Stub selesai"))
        return reviews
    }

    func cancel() {}
}
