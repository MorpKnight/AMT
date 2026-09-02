import AppKit
import XCTest
@testable import AMT

final class StructuredDocumentTests: XCTestCase {
    func testNormalizationKeepsInlineMarksWithoutMarkdownDelimiters() {
        let value = NSMutableAttributedString(string: "Teks tebal")
        value.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: NSRange(location: 5, length: 5))

        let document = StructuredDocument.normalize(value)

        XCTAssertEqual(document.plainText, "Teks tebal")
        XCTAssertFalse(document.plainText.contains("**"))
        XCTAssertTrue(document.blocks[0].runs.contains { $0.marks.contains(.bold) })
    }

    func testRoundTripBuildsLegalAttributedText() {
        let document = StructuredDocument(blocks: [
            StructuredBlock(kind: .heading(level: 1), runs: [StructuredRun(text: "BAB I")]),
            StructuredBlock(runs: [StructuredRun(text: "Isi", marks: [.italic])])
        ])

        let rendered = document.attributedString()
        XCTAssertEqual(rendered.string, "BAB I\nIsi")
        XCTAssertTrue((rendered.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont)?.pointSize == 16)
    }
}
