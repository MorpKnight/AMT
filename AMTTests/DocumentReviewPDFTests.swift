import AppKit
import Foundation
import PDFKit
import XCTest
@testable import AMT

final class DocumentReviewPDFTests: XCTestCase {
    func testRendererCreatesMultipleReadablePages() throws {
        let text = Array(repeating: "Paragraf kontrak untuk pengujian pagination.", count: 140)
            .joined(separator: "\n\n")
        let configuration = DocumentReviewPDFConfiguration(
            paperSize: NSSize(width: 320, height: 420),
            margins: NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
            font: NSFont.systemFont(ofSize: 11)
        )

        let data = try DocumentReviewPDFRenderer.render(
            attributedString: NSAttributedString(string: text),
            configuration: configuration
        )
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Paragraf kontrak") == true)
        XCTAssertTrue(document.page(at: document.pageCount - 1)?.string?.contains("pagination") == true)
    }

    func testPageAnchorMapsUniqueReviewToRenderedPage() throws {
        let prefix = Array(repeating: "Isi pendahuluan dokumen hukum.", count: 100)
            .joined(separator: "\n\n")
        let target = "Pihak Kedua wajib untuk menyerahkan laporan."
        let sourceText = prefix + "\n\n" + target
        let configuration = DocumentReviewPDFConfiguration(
            paperSize: NSSize(width: 320, height: 420),
            margins: NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
            font: NSFont.systemFont(ofSize: 11)
        )
        let data = try DocumentReviewPDFRenderer.render(
            attributedString: NSAttributedString(string: sourceText),
            configuration: configuration
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let original = "wajib untuk"
        let item = DocumentReviewItem(
            segmentID: 1,
            original: original,
            replacement: "wajib",
            category: .grammar,
            reason: "Perbaikan bahasa.",
            origin: .deterministic,
            sourceRange: DocumentTextRange((sourceText as NSString).range(of: original))
        )

        let anchors = DocumentReviewPageAnchorMapper.make(
            items: [item],
            in: document
        )
        let anchor = try XCTUnwrap(anchors[item.id])

        XCTAssertGreaterThan(anchor.pageIndex, 0)
        XCTAssertEqual(anchor.pageLabel, String(anchor.pageIndex + 1))
        XCTAssertFalse(anchor.rects.isEmpty)
        XCTAssertTrue(anchor.rects.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    func testPageAnchorFailsClosedWhenReviewQuoteIsAmbiguous() throws {
        let repeated = Array(repeating: "Pihak Kedua wajib untuk menyerahkan laporan.", count: 2)
            .joined(separator: "\n\n")
        let configuration = DocumentReviewPDFConfiguration(
            paperSize: NSSize(width: 320, height: 420),
            margins: NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
            font: NSFont.systemFont(ofSize: 11)
        )
        let data = try DocumentReviewPDFRenderer.render(
            attributedString: NSAttributedString(string: repeated),
            configuration: configuration
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let original = "wajib untuk"
        let item = DocumentReviewItem(
            segmentID: 1,
            original: original,
            replacement: "wajib",
            category: .grammar,
            reason: "Perbaikan bahasa.",
            origin: .deterministic,
            sourceRange: DocumentTextRange((repeated as NSString).range(of: original))
        )

        let anchors = DocumentReviewPageAnchorMapper.make(
            items: [item],
            in: document
        )

        XCTAssertNil(anchors[item.id])
    }
}
