import AppKit
import Foundation

/// The single source-aware entry point used by imports and legacy-document
/// migration. Markdown is parsed as Markdown; Word/RTF is kept as native
/// attributed text and only receives a non-destructive marker overlay.
struct DocumentRenderPayload {
    let attributedText: NSAttributedString
    let structuredDocument: StructuredDocument

    var plainText: String {
        attributedText.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var richTextData: Data? { structuredDocument.richTextData }
}

enum DocumentRenderNormalizer {
    static func fromMarkdown(_ markdown: String, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        makePayload(MarkdownRichTextCodec.render(markdown, defaultFont: defaultFont))
    }

    static func fromNative(_ native: NSAttributedString, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        makePayload(MarkdownRichTextCodec.render(normalizeLineSeparators(native), defaultFont: defaultFont))
    }

    static func fromPlainText(_ text: String, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        let normalized = text
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        return makePayload(NSAttributedString(string: normalized, attributes: MarkdownRichTextCodec.baseAttributes(font: defaultFont)))
    }

    /// Migrates records written before `StructuredDocument` carried its own
    /// fidelity payload. Existing RTF is authoritative; Markdown is parsed
    /// only when no native rich-text source exists.
    static func migrate(
        content: String,
        richTextData: Data?,
        sourceFileName: String?,
        sourceURL: URL? = nil,
        defaultFont: NSFont = EditorTypography.defaultFont
    ) -> DocumentRenderPayload {
        if let richTextData,
           let native = try? NSAttributedString(
               data: richTextData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return fromNative(native, defaultFont: defaultFont)
        }

        // Some pre-v2 imports kept the untouched source file but did not
        // persist the editable RTF payload. Prefer that native source over
        // interpreting the old plain-text/Markdown projection so Word
        // formatting can still be recovered during the one-time migration.
        if let sourceURL,
           ["docx", "doc", "rtf", "html", "htm"].contains(sourceURL.pathExtension.lowercased()),
           let native = try? DocxToMarkdownConverter.loadAttributedString(fileURL: sourceURL) {
            return fromNative(native, defaultFont: defaultFont)
        }

        let ext = sourceFileName.map { URL(fileURLWithPath: $0).pathExtension.lowercased() } ?? ""
        if ext == "md" || ext == "markdown" || looksLikeMarkdown(content) {
            return fromMarkdown(content, defaultFont: defaultFont)
        }
        return fromPlainText(content, defaultFont: defaultFont)
    }

    private static func makePayload(_ attributedText: NSAttributedString) -> DocumentRenderPayload {
        let structuredDocument = StructuredDocument.normalize(attributedText)
        return DocumentRenderPayload(
            attributedText: attributedText,
            structuredDocument: structuredDocument
        )
    }

    private static func looksLikeMarkdown(_ content: String) -> Bool {
        let patterns = [
            #"\*\*[^\n]+\*\*"#,
            #"~~[^\n]+~~"#,
            #"\[[^\]]+\]\([^\)]+\)"#,
            #"(?m)^#{1,6}\s+"#,
            #"(?m)^(?:[-+*]|\d+\.)\s+"#
        ]
        return patterns.contains { content.range(of: $0, options: .regularExpression) != nil }
    }

    private static func normalizeLineSeparators(_ value: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        let source = value.string as NSString
        var replacements: [NSRange] = []
        for separator in ["\u{2028}", "\u{2029}"] {
            var search = NSRange(location: 0, length: source.length)
            while search.location < source.length,
                  let found = source.range(of: separator, options: [], range: search).toOptionalRange() {
                replacements.append(found)
                let next = NSMaxRange(found)
                search = NSRange(location: next, length: source.length - next)
            }
        }
        for range in replacements.sorted(by: { $0.location > $1.location }) {
            let attributes = value.attributes(at: range.location, effectiveRange: nil)
            result.replaceCharacters(in: range, with: "\n")
            result.addAttributes(attributes, range: NSRange(location: range.location, length: 1))
        }
        return result
    }
}

private extension NSRange {
    func toOptionalRange() -> NSRange? {
        location == NSNotFound ? nil : self
    }
}
