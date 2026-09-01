import XCTest

/// This test is intentionally manual because Quick Look rendering fidelity cannot be proven by XCTest.
final class DocumentReviewQuickLookManualSmokeTests: XCTestCase {
    func testQuickLookComplexDOCXManualSmoke() throws {
        throw XCTSkip(
            "Manual smoke test: run AMT, import a complex DOCX containing headings, tables, lists, "
                + "bold/italic text, footnotes, and page breaks. Verify Quick Look preserves the native "
                + "layout, the review panel shows segment-based quotes without fake page numbers, and "
                + "export creates a separate '- Reviewed.docx' while the original remains unchanged."
        )
    }
}
