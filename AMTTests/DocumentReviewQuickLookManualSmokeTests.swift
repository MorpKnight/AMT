import XCTest

/// This test is intentionally manual because AppKit text-editor interactions cannot be proven by XCTest.
final class DocumentReviewTextEditorManualSmokeTests: XCTestCase {
    func testTextEditorComplexDOCXManualSmoke() throws {
        throw XCTSkip(
            "Manual smoke test: run AMT, import a complex DOCX containing headings, tables, lists, "
                + "bold/italic text, footnotes, and page breaks. Verify the text editor shows the analysis text "
                + "and suggestion highlights. Verify the small Review button appears at the top-right, the panel "
                + "opens on hover and stays open after pinning, and selecting a finding synchronizes the editor "
                + "highlight with the source excerpt. Confirm Accept/Reject remains a human action, then export "
                + "a separate '- Reviewed.docx' while the original remains unchanged."
        )
    }
}
