import XCTest

/// This test is intentionally manual because Quick Look rendering fidelity cannot be proven by XCTest.
final class DocumentReviewQuickLookManualSmokeTests: XCTestCase {
    func testQuickLookComplexDOCXManualSmoke() throws {
        throw XCTSkip(
            "Manual smoke test: run AMT, import a complex DOCX containing headings, tables, lists, "
                + "bold/italic text, footnotes, and page breaks. Verify the native Quick Look preview "
                + "preserves the original layout. Verify the small Review button appears at the top-right, "
                + "the panel opens on hover and stays open after pinning, and selecting a finding shows the "
                + "matched source excerpt with a visible mark. Confirm no page number or fake page navigation "
                + "is shown, then export a separate '- Reviewed.docx' while the original remains unchanged."
        )
    }
}
