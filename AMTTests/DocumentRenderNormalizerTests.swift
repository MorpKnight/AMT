import AppKit
import XCTest
@testable import AMT

final class DocumentRenderNormalizerTests: XCTestCase {
    func testMarkdownIsRenderedWithInlineBlocksListsTablesAndLinks() {
        let markdown = """
        # Judul

        **tebal** *miring* ~~coret~~ `kode` [tautan](https://example.com)

        - satu
        - dua

        | A | B |
        |---|---|
        | 1 | 2 |
        """

        let payload = DocumentRenderNormalizer.fromMarkdown(markdown)
        let rendered = payload.attributedText

        XCTAssertTrue(rendered.string.contains("Judul"))
        XCTAssertTrue(rendered.string.contains("• satu"))
        XCTAssertTrue(rendered.string.contains("• dua"))
        XCTAssertTrue(rendered.string.contains("A\tB"))
        XCTAssertTrue(rendered.string.contains("1\t2"))
        XCTAssertEqual(payload.structuredDocument.tables.first?.rows, [["A", "B"], ["1", "2"]])
        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertFalse(rendered.string.contains("~~"))

        let boldRange = (rendered.string as NSString).range(of: "tebal")
        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        let italicRange = (rendered.string as NSString).range(of: "miring")
        let italicFont = rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)

        let linkRange = (rendered.string as NSString).range(of: "tautan")
        XCTAssertNotNil(rendered.attribute(.link, at: linkRange.location, effectiveRange: nil))
    }

    func testMarkdownRepairsAnUnpairedMarkerConservatively() {
        let payload = DocumentRenderNormalizer.fromMarkdown("**TERGUGAT II**; gitu**")

        XCTAssertEqual(payload.plainText, "TERGUGAT II; gitu")
        XCTAssertFalse(payload.attributedText.string.contains("**"))
        let range = (payload.attributedText.string as NSString).range(of: "TERGUGAT II")
        let font = payload.attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        let emphasis = DocumentRenderNormalizer.fromMarkdown("*miring*; orphan*")
        XCTAssertEqual(emphasis.plainText, "miring; orphan")

        let combined = DocumentRenderNormalizer.fromMarkdown("***tebal miring***")
        let combinedFont = combined.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(combinedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertTrue(combinedFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    func testAsteriskUnorderedListIsNotMistakenForAnOrphanItalicMarker() {
        let payload = DocumentRenderNormalizer.fromMarkdown("* satu\n* dua")
        XCTAssertEqual(payload.plainText, "• satu\n• dua")
        XCTAssertFalse(payload.attributedText.string.contains("*"))
        XCTAssertTrue(payload.structuredDocument.blocks.allSatisfy { $0.listStyle == .unordered })

        let ordered = DocumentRenderNormalizer.fromMarkdown("1. satu\n2. dua")
        XCTAssertEqual(ordered.plainText, "1. satu\n2. dua")
        XCTAssertTrue(ordered.structuredDocument.blocks.allSatisfy { $0.listStyle == .ordered })
    }

    func testMarkerTextInsideCodeSpanRemainsLiteral() {
        let payload = DocumentRenderNormalizer.fromMarkdown("`**literal**`")
        XCTAssertEqual(payload.plainText, "**literal**")
        let range = (payload.attributedText.string as NSString).range(of: "literal")
        let font = payload.attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testNativeFormattingAndMarkerOverlaySurviveStructuredRoundTrip() {
        let source = NSMutableAttributedString(string: "**TERGUGAT II**")
        let fullRange = NSRange(location: 0, length: source.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 11
        paragraph.headIndent = 18

        source.addAttributes([
            .font: NSFont(name: "Helvetica", size: 19) ?? NSFont.systemFont(ofSize: 19),
            .foregroundColor: NSColor(calibratedRed: 0.8, green: 0.1, blue: 0.2, alpha: 1),
            .backgroundColor: NSColor(calibratedRed: 0.95, green: 0.9, blue: 0.2, alpha: 1),
            .underlineStyle: NSUnderlineStyle.double.rawValue,
            .strikethroughStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraph,
            .link: URL(string: "https://example.com")!
        ], range: fullRange)

        let payload = DocumentRenderNormalizer.fromNative(source)
        XCTAssertEqual(payload.plainText, "TERGUGAT II")
        XCTAssertFalse(payload.attributedText.string.contains("**"))

        let visibleRange = (payload.attributedText.string as NSString).range(of: "TERGUGAT II")
        let attrs = payload.attributedText.attributes(at: visibleRange.location, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 19, accuracy: 0.01)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertNotNil(attrs[.foregroundColor])
        XCTAssertNotNil(attrs[.backgroundColor])
        XCTAssertNotNil(attrs[.link])
        XCTAssertNotEqual((attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0, 0)
        XCTAssertNotEqual((attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0, 0)
        let renderedParagraph = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(renderedParagraph?.alignment, .center)
        XCTAssertEqual(renderedParagraph?.lineSpacing ?? 0, 7, accuracy: 0.01)
        XCTAssertEqual(renderedParagraph?.headIndent ?? 0, 18, accuracy: 0.01)

        let roundTrip = payload.structuredDocument.attributedString()
        XCTAssertEqual(roundTrip.string, "TERGUGAT II")
        let roundTripAttrs = roundTrip.attributes(at: 0, effectiveRange: nil)
        let roundTripFont = roundTripAttrs[.font] as? NSFont
        XCTAssertEqual(roundTripFont?.pointSize ?? 0, 19, accuracy: 0.01)
        XCTAssertTrue(roundTripFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertNotNil(roundTripAttrs[.backgroundColor])
        XCTAssertNotNil(roundTripAttrs[.link])

        let semanticRun = payload.structuredDocument.blocks
            .flatMap(\.runs)
            .first { $0.text.contains("TERGUGAT") }
        XCTAssertEqual(semanticRun?.fontSize ?? 0, 19, accuracy: 0.01)
        XCTAssertNotNil(semanticRun?.fontFamily)
        XCTAssertNotNil(semanticRun?.foregroundColor)
        XCTAssertNotNil(semanticRun?.backgroundColor)
        XCTAssertNotNil(semanticRun?.underlineStyle)
        XCTAssertNotNil(semanticRun?.strikethroughStyle)
    }
}
