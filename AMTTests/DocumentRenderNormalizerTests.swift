import AppKit
import XCTest
@testable import AMT

final class DocumentRenderNormalizerTests: XCTestCase {
    func testEditorTypographyUsesTheSharedScale() {
        XCTAssertEqual(TextStyle.body.rawValue, "Paragraph")
        XCTAssertEqual(EditorTypography.font(for: .body).pointSize, 20, accuracy: 0.01)
        XCTAssertEqual(EditorTypography.font(for: .heading1).pointSize, 36, accuracy: 0.01)
        XCTAssertEqual(EditorTypography.font(for: .heading2).pointSize, 28, accuracy: 0.01)
        XCTAssertEqual(EditorTypography.font(for: .heading3).pointSize, 23, accuracy: 0.01)
        XCTAssertTrue(EditorTypography.font(for: .heading1).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(EditorTypography.font(for: .heading2).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(EditorTypography.font(for: .heading3).fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testEditorZoomClampsAndUsesTenPercentSteps() {
        XCTAssertEqual(EditorZoom.clamp(20), 75)
        XCTAssertEqual(EditorZoom.clamp(100), 100)
        XCTAssertEqual(EditorZoom.clamp(500), 200)
        XCTAssertEqual(EditorZoom.percent(for: 0.75), 75)
        XCTAssertEqual(EditorZoom.percent(for: 0.90), 90)
        XCTAssertEqual(EditorZoom.percent(for: 2.0), 200)
        XCTAssertEqual(EditorZoom.percent(for: .nan), EditorZoom.defaultPercent)
        XCTAssertEqual(EditorZoom.percent(for: .infinity), EditorZoom.maximumPercent)
    }

    func testEditorZoomOutUsesTenPercentStepsAndClampsAtMinimum() {
        let viewModel = EditorViewModel()

        viewModel.zoomOut()
        XCTAssertEqual(viewModel.zoomPercent, 90)
        viewModel.zoomOut()
        XCTAssertEqual(viewModel.zoomPercent, 80)
        viewModel.zoomOut()
        XCTAssertEqual(viewModel.zoomPercent, EditorZoom.minimumPercent)

        viewModel.zoomPercent = EditorZoom.minimumPercent
        viewModel.zoomOut()
        XCTAssertEqual(viewModel.zoomPercent, EditorZoom.minimumPercent)
    }

    func testEditorZoomSafeCenterRejectsInvalidViewportAndClampsToDocument() {
        let documentBounds = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let center = EditorZoom.safeCenter(
            visibleRect: NSRect(x: -250, y: 650, width: 500, height: 300),
            documentBounds: documentBounds
        )

        XCTAssertEqual(center?.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(center?.y ?? -1, 800, accuracy: 0.01)
        XCTAssertNil(
            EditorZoom.safeCenter(
                visibleRect: NSRect(x: 0, y: 0, width: 0, height: 100),
                documentBounds: documentBounds
            )
        )
        XCTAssertNil(
            EditorZoom.safeCenter(
                visibleRect: NSRect(x: .nan, y: 0, width: 100, height: 100),
                documentBounds: documentBounds
            )
        )
        XCTAssertNil(
            EditorZoom.safeCenter(
                visibleRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                documentBounds: NSRect(x: 0, y: 0, width: 0, height: 800)
            )
        )
    }

    func testFontSizeControlsQueueAWholeDocumentScaleAction() {
        let viewModel = EditorViewModel()

        viewModel.increaseFontSize()

        XCTAssertEqual(viewModel.fontSizePoints, 21, accuracy: 0.01)
        guard let pendingAction = viewModel.pendingAction,
              case let .fontScale(from, to) = pendingAction else {
            return XCTFail("Expected a font scale action")
        }
        XCTAssertEqual(from, EditorTypography.bodyPointSize, accuracy: 0.01)
        XCTAssertEqual(to, 21, accuracy: 0.01)
    }

    func testMarkdownUsesTheSharedTypographyScale() {
        let payload = DocumentRenderNormalizer.fromMarkdown(
            "Paragraph\n\n# H1\n\n## H2\n\n### H3"
        )
        let rendered = payload.attributedText

        let paragraphRange = (rendered.string as NSString).range(of: "Paragraph")
        let h1Range = (rendered.string as NSString).range(of: "H1")
        let h2Range = (rendered.string as NSString).range(of: "H2")
        let h3Range = (rendered.string as NSString).range(of: "H3")

        XCTAssertEqual((rendered.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual((rendered.attribute(.font, at: h1Range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0, 36, accuracy: 0.01)
        XCTAssertEqual((rendered.attribute(.font, at: h2Range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0, 28, accuracy: 0.01)
        XCTAssertEqual((rendered.attribute(.font, at: h3Range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0, 23, accuracy: 0.01)
    }

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

    func testLegacyCanonicalTypographyMigratesOnlyMarkdownPlainTextRuns() {
        let oldDocument = StructuredDocument(
            blocks: [
                StructuredBlock(
                    kind: .paragraph,
                    runs: [StructuredRun(
                        text: "Body",
                        fontName: "Helvetica",
                        fontSize: Double(EditorTypography.legacyBodyPointSize)
                    )]
                ),
                StructuredBlock(
                    kind: .heading(level: 1),
                    runs: [StructuredRun(
                        text: "Heading",
                        marks: [.bold],
                        fontName: "Helvetica",
                        fontSize: Double(EditorTypography.legacyHeading1PointSize)
                    )]
                ),
                StructuredBlock(
                    kind: .paragraph,
                    runs: [StructuredRun(
                        text: "Custom",
                        fontName: "Helvetica",
                        fontSize: 19
                    )]
                )
            ],
            sourceKind: .markdown,
            typographyVersion: 1
        )

        let migrated = DocumentRenderNormalizer.migrate(
            content: "Body\nHeading\nCustom",
            richTextData: oldDocument.richTextData,
            sourceFileName: "legacy.md",
            structuredDocument: oldDocument
        )

        let bodyRange = (migrated.attributedText.string as NSString).range(of: "Body")
        let headingRange = (migrated.attributedText.string as NSString).range(of: "Heading")
        let customRange = (migrated.attributedText.string as NSString).range(of: "Custom")
        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            EditorTypography.bodyPointSize,
            accuracy: 0.01
        )
        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            EditorTypography.heading1PointSize,
            accuracy: 0.01
        )
        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: customRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            19,
            accuracy: 0.01
        )
        XCTAssertEqual(migrated.structuredDocument.typographyVersion, EditorTypography.typographyVersion)
        XCTAssertEqual(migrated.structuredDocument.sourceKind, .markdown)
    }

    func testNativeTypographyIsNotMarkedForMigration() {
        let source = NSAttributedString(
            string: "Native",
            attributes: [
                .font: NSFont(name: "Helvetica", size: 18) ?? NSFont.systemFont(ofSize: 18)
            ]
        )
        let nativeDocument = StructuredDocument.normalize(
            source,
            sourceKind: .native,
            typographyVersion: 1
        )

        XCTAssertFalse(
            DocumentRenderNormalizer.needsMigration(
                structuredDocument: nativeDocument,
                sourceFileName: "native.docx"
            )
        )
        let payload = DocumentRenderNormalizer.migrate(
            content: "Native",
            richTextData: nativeDocument.richTextData,
            sourceFileName: "native.docx",
            structuredDocument: nativeDocument
        )
        XCTAssertEqual(
            (payload.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            18,
            accuracy: 0.01
        )
    }

    func testLegacyNativeDocumentOnlyBackfillsSourceMetadata() {
        let source = NSMutableAttributedString(
            string: "Native",
            attributes: [
                .font: NSFont(name: "Helvetica", size: 18) ?? NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.systemRed
            ]
        )
        let oldDocument = StructuredDocument.normalize(
            source,
            sourceKind: .unknown,
            typographyVersion: 0
        )

        XCTAssertTrue(
            DocumentRenderNormalizer.needsMigration(
                structuredDocument: oldDocument,
                sourceFileName: "native.docx"
            )
        )
        let migrated = DocumentRenderNormalizer.migrate(
            content: "Native",
            richTextData: oldDocument.richTextData,
            sourceFileName: "native.docx",
            structuredDocument: oldDocument
        )
        XCTAssertEqual(migrated.sourceKind, .native)
        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            18,
            accuracy: 0.01
        )
    }

    func testLegacyDocumentWithoutSourceMetadataMigratesAsPlainText() {
        let oldDocument = StructuredDocument(
            blocks: [
                StructuredBlock(
                    runs: [StructuredRun(
                        text: "Isi lama",
                        fontName: "Helvetica",
                        fontSize: Double(EditorTypography.legacyBodyPointSize)
                    )]
                )
            ],
            sourceKind: .unknown,
            typographyVersion: 0
        )

        XCTAssertTrue(
            DocumentRenderNormalizer.needsMigration(
                structuredDocument: oldDocument,
                sourceFileName: nil
            )
        )

        let migrated = DocumentRenderNormalizer.migrate(
            content: "Isi lama",
            richTextData: oldDocument.richTextData,
            sourceFileName: nil,
            structuredDocument: oldDocument
        )
        XCTAssertEqual(migrated.sourceKind, .plainText)
        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            EditorTypography.bodyPointSize,
            accuracy: 0.01
        )
    }

    func testCanonicalMigrationKeepsRichTextFallbackAttributes() {
        let source = NSMutableAttributedString(
            string: "Rich",
            attributes: [
                .font: NSFont.systemFont(ofSize: EditorTypography.legacyBodyPointSize),
                .foregroundColor: NSColor.systemBlue,
                .superscript: 1
            ]
        )
        let oldDocument = StructuredDocument.normalize(
            source,
            sourceKind: .plainText,
            typographyVersion: 1
        )

        let migrated = DocumentRenderNormalizer.migrate(
            content: "Rich",
            richTextData: oldDocument.richTextData,
            sourceFileName: "legacy.txt",
            structuredDocument: oldDocument
        )

        XCTAssertEqual(
            (migrated.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            EditorTypography.bodyPointSize,
            accuracy: 0.01
        )
        XCTAssertEqual(
            (migrated.attributedText.attribute(.superscript, at: 0, effectiveRange: nil) as? NSNumber)?.intValue,
            1
        )
    }
}

@MainActor
final class RichTextFormatterTests: XCTestCase {
    func testInlineFormattingPreservesNativeFontSize() {
        let textView = makeTextView("Native")
        let nativeFont = NSFont(name: "Helvetica", size: 19) ?? NSFont.systemFont(ofSize: 19)
        textView.textStorage?.addAttribute(
            .font,
            value: nativeFont,
            range: NSRange(location: 0, length: 6)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 6))

        XCTAssertTrue(RichTextFormatter.apply(.bold, to: textView))

        let font = textView.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 19, accuracy: 0.01)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testFontScaleUpdatesAllCanonicalRunsAndPreservesAttributes() {
        let textView = makeTextView("body\nheading")
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        let headingRange = NSRange(location: 5, length: 7)
        let headingFont = NSFont.systemFont(ofSize: EditorTypography.heading1PointSize, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        textView.textStorage?.addAttribute(
            .font,
            value: headingFont,
            range: headingRange
        )
        textView.textStorage?.addAttributes([
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.systemRed,
            .link: URL(string: "https://example.com")!,
            .paragraphStyle: paragraph
        ], range: fullRange)

        XCTAssertTrue(
            RichTextFormatter.apply(
                .fontScale(from: EditorTypography.bodyPointSize, to: 22),
                to: textView,
                sourceKind: .markdown
            )
        )

        let bodyFont = textView.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let scaledHeadingFont = textView.attributedString().attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        XCTAssertEqual(bodyFont?.pointSize ?? 0, 22, accuracy: 0.01)
        XCTAssertEqual(scaledHeadingFont?.pointSize ?? 0, 39.6, accuracy: 0.01)
        XCTAssertTrue(scaledHeadingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertNotNil(textView.attributedString().attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertNotNil(textView.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            (textView.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
            .center
        )
    }

    func testFontScaleLeavesNativeDocumentsUntouched() {
        let textView = makeTextView("native")
        let nativeFont = NSFont(name: "Helvetica", size: 19) ?? NSFont.systemFont(ofSize: 19)
        textView.textStorage?.addAttribute(
            .font,
            value: nativeFont,
            range: NSRange(location: 0, length: textView.string.utf16.count)
        )

        XCTAssertFalse(
            RichTextFormatter.apply(
                .fontScale(from: 20, to: 24),
                to: textView,
                sourceKind: .native
            )
        )
        XCTAssertEqual(
            (textView.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0,
            19,
            accuracy: 0.01
        )
    }

    func testParagraphFormattingAppliesToMultipleParagraphs() {
        let textView = makeTextView("one\ntwo")
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        XCTAssertTrue(RichTextFormatter.apply(.alignment(.center), to: textView))
        XCTAssertEqual(
            (textView.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
            .center
        )
        XCTAssertEqual(
            (textView.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)?.alignment,
            .center
        )

        XCTAssertTrue(RichTextFormatter.apply(.indent(.increase), to: textView))
        XCTAssertEqual(
            (textView.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0,
            24,
            accuracy: 0.01
        )
        XCTAssertEqual(
            (textView.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0,
            24,
            accuracy: 0.01
        )
    }

    func testListFormattingNumbersAndTogglesSelectedParagraphs() {
        let textView = makeTextView("one\ntwo")
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        XCTAssertTrue(RichTextFormatter.apply(.listStyle(.numbered), to: textView))
        XCTAssertEqual(textView.string, "1. one\n2. two", "after applying list: \(textView.string.debugDescription)")

        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        XCTAssertTrue(RichTextFormatter.apply(.listStyle(.numbered), to: textView))
        XCTAssertEqual(textView.string, "one\ntwo", "after toggling list: \(textView.string.debugDescription)")
    }

    func testLinkAndClearFormattingKeepParagraphLayout() {
        let textView = makeTextView("Link")
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        XCTAssertTrue(RichTextFormatter.apply(.alignment(.trailing), to: textView))
        XCTAssertTrue(
            RichTextFormatter.apply(
                .link(URL(string: "https://example.com")!),
                to: textView
            )
        )

        XCTAssertTrue(RichTextFormatter.apply(.clearFormatting, to: textView))
        let attributes = textView.attributedString().attributes(at: 0, effectiveRange: nil)
        XCTAssertNil(attributes[.link])
        XCTAssertNil(attributes[.underlineStyle])
        XCTAssertEqual(
            (attributes[.font] as? NSFont)?.pointSize ?? 0,
            EditorTypography.bodyPointSize,
            accuracy: 0.01
        )
        XCTAssertEqual(
            (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment,
            .right
        )
    }

    private func makeTextView(_ string: String) -> NSTextView {
        let storage = NSTextStorage(
            string: string,
            attributes: MarkdownRichTextCodec.baseAttributes(font: EditorTypography.defaultFont)
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 640, height: 10_000))
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.allowsUndo = true
        return textView
    }
}
