import AppKit
import Foundation
import PDFKit

struct DocumentReviewPDFConfiguration {
    let paperSize: NSSize
    let margins: NSEdgeInsets
    let fontName: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat

    init(
        paperSize: NSSize = NSSize(width: 595.28, height: 841.89),
        margins: NSEdgeInsets = NSEdgeInsets(top: 54, left: 54, bottom: 54, right: 54),
        font: NSFont = NSFont.systemFont(ofSize: 12),
        lineSpacing: CGFloat = 2,
        paragraphSpacing: CGFloat = 8
    ) {
        self.paperSize = paperSize
        self.margins = margins
        self.fontName = font.fontName
        self.fontSize = font.pointSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
    }

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    static let standard = DocumentReviewPDFConfiguration()
}

enum DocumentReviewPDFRenderError: LocalizedError, Equatable {
    case emptyContent
    case invalidPageSize
    case failedToCreatePDF

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            "Dokumen tidak memiliki isi yang dapat dirender."
        case .invalidPageSize:
            "Ukuran halaman PDF tidak valid."
        case .failedToCreatePDF:
            "PDF preview tidak dapat dibuat."
        }
    }
}

/// Creates a paginated, read-only PDF representation for the review viewer.
/// The original DOCX remains the source of truth and is never modified here.
struct DocumentReviewPDFRenderer {
    static func render(
        attributedString: NSAttributedString,
        configuration: DocumentReviewPDFConfiguration = .standard
    ) throws -> Data {
        guard attributedString.length > 0 else {
            throw DocumentReviewPDFRenderError.emptyContent
        }
        guard configuration.paperSize.width > 0,
              configuration.paperSize.height > 0,
              configuration.margins.left + configuration.margins.right < configuration.paperSize.width,
              configuration.margins.top + configuration.margins.bottom < configuration.paperSize.height else {
            throw DocumentReviewPDFRenderError.invalidPageSize
        }

        let contentWidth = configuration.paperSize.width
            - configuration.margins.left
            - configuration.margins.right
        let contentHeight = configuration.paperSize.height
            - configuration.margins.top
            - configuration.margins.bottom
        let textStorage = NSTextStorage(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = configuration.lineSpacing
        paragraphStyle.paragraphSpacing = configuration.paragraphSpacing

        textStorage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var additions: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle
            ]
            if attributes[.font] == nil {
                additions[.font] = configuration.font
            }
            if attributes[.foregroundColor] == nil {
                // The generated page background is white, so do not use the
                // appearance-dependent NSColor.textColor here. In Dark Mode
                // that dynamic color could render white text on a white page.
                additions[.foregroundColor] = NSColor.black
            }
            textStorage.addAttributes(additions, range: range)
        }

        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        textStorage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        var coveredCharacterCount = 0
        let maximumPageCount = max(textStorage.length + 1, 2)

        while coveredCharacterCount < textStorage.length || containers.isEmpty {
            guard containers.count < maximumPageCount else {
                throw DocumentReviewPDFRenderError.failedToCreatePDF
            }

            let container = NSTextContainer(
                size: NSSize(width: contentWidth, height: contentHeight)
            )
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let nextCoveredCharacterCount = NSMaxRange(characterRange)
            guard nextCoveredCharacterCount > coveredCharacterCount
                    || nextCoveredCharacterCount == textStorage.length else {
                throw DocumentReviewPDFRenderError.failedToCreatePDF
            }
            coveredCharacterCount = nextCoveredCharacterCount
        }

        let output = NSMutableData()
        var mediaBox = NSRect(
            origin: .zero,
            size: configuration.paperSize
        )
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(
                  consumer: consumer,
                  mediaBox: &mediaBox,
                  nil
              ) else {
            throw DocumentReviewPDFRenderError.failedToCreatePDF
        }

        for container in containers {
            let glyphRange = layoutManager.glyphRange(for: container)
            context.beginPDFPage([
                kCGPDFContextMediaBox as String: mediaBox
            ] as CFDictionary)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)

            context.saveGState()
            context.translateBy(x: 0, y: configuration.paperSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(
                cgContext: context,
                flipped: true
            )
            let textOrigin = NSPoint(
                x: configuration.margins.left,
                y: configuration.margins.top
            )
            layoutManager.drawBackground(
                forGlyphRange: glyphRange,
                at: textOrigin
            )
            layoutManager.drawGlyphs(
                forGlyphRange: glyphRange,
                at: textOrigin
            )
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        guard output.length > 0 else {
            throw DocumentReviewPDFRenderError.failedToCreatePDF
        }
        return output as Data
    }
}

/// A review item location in the derived PDF coordinate space.
struct DocumentReviewPageAnchor: Hashable, Sendable {
    let pageIndex: Int
    let pageLabel: String
    let rects: [CGRect]
}

/// Maps only unique PDF text matches. Ambiguous or missing locations are omitted.
struct DocumentReviewPageAnchorMapper {
    static func make(
        items: [DocumentReviewItem],
        in document: PDFDocument
    ) -> [UUID: DocumentReviewPageAnchor] {
        var result: [UUID: DocumentReviewPageAnchor] = [:]

        for item in items where item.isActionable && !item.original.isEmpty {
            var match: (pageIndex: Int, page: PDFPage, range: NSRange)?
            var matchCount = 0

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex),
                      let pageText = page.string else {
                    continue
                }

                let ranges = ranges(of: item.original, in: pageText)
                guard !ranges.isEmpty else { continue }
                matchCount += ranges.count
                if ranges.count == 1, match == nil {
                    match = (pageIndex, page, ranges[0])
                }
                if matchCount > 1 {
                    break
                }
            }

            guard matchCount == 1,
                  let match,
                  let selection = match.page.selection(for: match.range) else {
                continue
            }

            var rects = selection.selectionsByLine()
                .map { $0.bounds(for: match.page) }
                .filter { $0.width > 0 && $0.height > 0 }
            if rects.isEmpty {
                let bounds = selection.bounds(for: match.page)
                if bounds.width > 0, bounds.height > 0 {
                    rects = [bounds]
                }
            }

            guard !rects.isEmpty else { continue }
            result[item.id] = DocumentReviewPageAnchor(
                pageIndex: match.pageIndex,
                pageLabel: match.page.label?.isEmpty == false
                    ? match.page.label ?? String(match.pageIndex + 1)
                    : String(match.pageIndex + 1),
                rects: rects
            )
        }

        return result
    }

    private static func ranges(of substring: String, in text: String) -> [NSRange] {
        guard !substring.isEmpty else { return [] }
        let nsText = text as NSString
        let wholeRange = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []
        var searchLocation = 0

        while searchLocation < wholeRange.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: wholeRange.length - searchLocation
            )
            let range = nsText.range(
                of: substring,
                options: .literal,
                range: searchRange,
                locale: nil
            )
            guard range.location != NSNotFound else { break }
            ranges.append(range)
            searchLocation = range.location + max(range.length, 1)
        }

        return ranges
    }
}
