import AppKit
import Foundation

/// The single source-aware entry point used by imports and legacy-document
/// migration. Markdown is parsed as Markdown; Word/RTF is kept as native
/// attributed text and only receives a non-destructive marker overlay.
struct DocumentRenderPayload {
    let attributedText: NSAttributedString
    let structuredDocument: StructuredDocument
    let sourceKind: StructuredDocument.SourceKind

    init(
        attributedText: NSAttributedString,
        structuredDocument: StructuredDocument,
        sourceKind: StructuredDocument.SourceKind? = nil
    ) {
        self.attributedText = attributedText
        self.structuredDocument = structuredDocument
        self.sourceKind = sourceKind ?? structuredDocument.sourceKind
    }

    var plainText: String {
        attributedText.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var richTextData: Data? { structuredDocument.richTextData }
}

enum DocumentRenderNormalizer {
    static func needsMigration(
        structuredDocument: StructuredDocument?,
        sourceFileName: String?,
        sourceURL: URL? = nil
    ) -> Bool {
        guard let structuredDocument else { return true }
        guard structuredDocument.richTextData != nil else { return true }
        let sourceKind = resolveSourceKind(
            structuredDocument: structuredDocument,
            sourceFileName: sourceFileName,
            sourceURL: sourceURL
        )
        // Records written before source metadata was introduced are marked
        // `.unknown`. When no native source extension is available, their
        // persisted rich text came from the editor's plain-text fallback, so
        // it is safe to apply the canonical typography migration once.
        let migrationKind = sourceKind == .unknown ? .plainText : sourceKind
        let shouldBackfillSourceMetadata = structuredDocument.sourceKind == .unknown
            && sourceKind != .unknown
        return shouldBackfillSourceMetadata
            || (migrationKind.usesCanonicalTypography
                && structuredDocument.typographyVersion < EditorTypography.typographyVersion)
    }

    static func fromMarkdown(_ markdown: String, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        makePayload(
            MarkdownRichTextCodec.render(markdown, defaultFont: defaultFont),
            sourceKind: .markdown
        )
    }

    static func fromNative(_ native: NSAttributedString, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        makePayload(
            MarkdownRichTextCodec.render(normalizeLineSeparators(native), defaultFont: defaultFont),
            sourceKind: .native
        )
    }

    static func fromPlainText(_ text: String, defaultFont: NSFont = EditorTypography.defaultFont) -> DocumentRenderPayload {
        let normalized = text
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        return makePayload(
            NSAttributedString(string: normalized, attributes: MarkdownRichTextCodec.baseAttributes(font: defaultFont)),
            sourceKind: .plainText
        )
    }

    /// Migrates records written before `StructuredDocument` carried its own
    /// fidelity payload. Existing RTF is authoritative; Markdown is parsed
    /// only when no native rich-text source exists.
    static func migrate(
        content: String,
        richTextData: Data?,
        sourceFileName: String?,
        sourceURL: URL? = nil,
        structuredDocument: StructuredDocument? = nil,
        defaultFont: NSFont = EditorTypography.defaultFont
    ) -> DocumentRenderPayload {
        let sourceKind = resolveSourceKind(
            structuredDocument: structuredDocument,
            sourceFileName: sourceFileName,
            sourceURL: sourceURL
        )
        let effectiveSourceKind = sourceKind == .unknown ? .plainText : sourceKind

        if let structuredDocument,
           effectiveSourceKind.usesCanonicalTypography,
           structuredDocument.typographyVersion < EditorTypography.typographyVersion {
            return migrateCanonicalTypography(
                structuredDocument,
                sourceKind: effectiveSourceKind,
                defaultFont: defaultFont
            )
        }

        if let richTextData,
           let native = loadRTF(richTextData) {
            if effectiveSourceKind.usesCanonicalTypography {
                let legacyStructured = structuredDocument
                    ?? StructuredDocument.normalize(
                        native,
                        sourceKind: effectiveSourceKind,
                        typographyVersion: 0
                    )
                if legacyStructured.typographyVersion < EditorTypography.typographyVersion {
                    return migrateCanonicalTypography(
                        legacyStructured,
                        sourceKind: effectiveSourceKind,
                        defaultFont: defaultFont
                    )
                }
                return makePayload(native, sourceKind: effectiveSourceKind)
            }
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

        if sourceKind == .markdown,
           let sourceURL,
           let markdown = try? String(contentsOf: sourceURL, encoding: .utf8) {
            return fromMarkdown(markdown, defaultFont: defaultFont)
        }
        if sourceKind == .markdown || (sourceKind == .unknown && looksLikeMarkdown(content)) {
            return fromMarkdown(content, defaultFont: defaultFont)
        }
        return fromPlainText(content, defaultFont: defaultFont)
    }

    // Source-compatible overload for callers that supplied a custom default
    // font before the structured-document argument was introduced.
    static func migrate(
        content: String,
        richTextData: Data?,
        sourceFileName: String?,
        sourceURL: URL?,
        defaultFont: NSFont
    ) -> DocumentRenderPayload {
        migrate(
            content: content,
            richTextData: richTextData,
            sourceFileName: sourceFileName,
            sourceURL: sourceURL,
            structuredDocument: nil,
            defaultFont: defaultFont
        )
    }

    static func migrate(
        content: String,
        richTextData: Data?,
        sourceFileName: String?,
        defaultFont: NSFont
    ) -> DocumentRenderPayload {
        migrate(
            content: content,
            richTextData: richTextData,
            sourceFileName: sourceFileName,
            sourceURL: nil,
            structuredDocument: nil,
            defaultFont: defaultFont
        )
    }

    private static func makePayload(
        _ attributedText: NSAttributedString,
        sourceKind: StructuredDocument.SourceKind
    ) -> DocumentRenderPayload {
        let structuredDocument = StructuredDocument.normalize(
            attributedText,
            sourceKind: sourceKind,
            typographyVersion: EditorTypography.typographyVersion
        )
        return DocumentRenderPayload(
            attributedText: attributedText,
            structuredDocument: structuredDocument,
            sourceKind: sourceKind
        )
    }

    private static func migrateCanonicalTypography(
        _ structuredDocument: StructuredDocument,
        sourceKind: StructuredDocument.SourceKind,
        defaultFont: NSFont
    ) -> DocumentRenderPayload {
        let migrated: NSAttributedString
        if structuredDocument.richTextData != nil,
           structuredDocument.attributedString().length > 0 {
            // Keep the RTF layer as the migration input whenever it exists.
            // This preserves attributes that do not have a first-class
            // StructuredRun property while changing only legacy canonical
            // font sizes.
            migrated = migrateAttributedTypography(
                structuredDocument.attributedString(),
                using: structuredDocument
            )
        } else {
            migrated = structuredDocument.attributedString(
                preferRichText: false,
                applyingCurrentTypography: true
            )
        }
        if migrated.length > 0 {
            let payload = makePayload(migrated, sourceKind: sourceKind)
            return preserveSemanticBlocks(
                from: structuredDocument,
                in: payload,
                sourceKind: sourceKind
            )
        }
        return fromPlainText(structuredDocument.plainText, defaultFont: defaultFont)
    }

    private static func migrateAttributedTypography(
        _ value: NSAttributedString,
        using legacy: StructuredDocument
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        let source = result.string as NSString
        var searchLocation = 0

        for block in legacy.blocks {
            let blockText = block.plainText
            guard !blockText.isEmpty else { continue }

            let remainingLength = max(0, source.length - searchLocation)
            let searchedRange = NSRange(location: searchLocation, length: remainingLength)
            let blockRange = source.range(of: blockText, options: [], range: searchedRange)
            guard blockRange.location != NSNotFound else { continue }
            searchLocation = NSMaxRange(blockRange)

            let style = textStyle(for: block.kind)
            let legacySize = EditorTypography.legacyPointSize(for: style)
            let currentSize = EditorTypography.canonicalPointSize(for: style)
            result.enumerateAttribute(.font, in: blockRange, options: []) { value, range, _ in
                guard let font = value as? NSFont,
                      abs(font.pointSize - legacySize) < 0.01,
                      let updatedFont = NSFont(descriptor: font.fontDescriptor, size: currentSize)
                else { return }
                result.addAttribute(.font, value: updatedFont, range: range)
            }
        }

        return result
    }

    private static func textStyle(for kind: StructuredBlock.Kind) -> TextStyle {
        guard case .heading(let level) = kind else { return .body }
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        default: return .body
        }
    }

    /// Re-normalization observes the new font sizes, which can otherwise
    /// demote a legacy heading that intentionally uses a custom point size.
    /// Keep the persisted semantic block identity/style while taking all
    /// visual attributes from the migrated attributed string.
    private static func preserveSemanticBlocks(
        from legacy: StructuredDocument,
        in payload: DocumentRenderPayload,
        sourceKind: StructuredDocument.SourceKind
    ) -> DocumentRenderPayload {
        guard !legacy.blocks.isEmpty,
              !payload.structuredDocument.blocks.isEmpty else {
            return payload
        }

        var migrated = payload.structuredDocument
        var usedLegacyIndices: Set<Int> = []
        for index in migrated.blocks.indices {
            let block = migrated.blocks[index]
            let match = legacy.blocks.indices.first { legacyIndex in
                guard !usedLegacyIndices.contains(legacyIndex) else { return false }
                return legacy.blocks[legacyIndex].plainText == block.plainText
            } ?? (index < legacy.blocks.count && !usedLegacyIndices.contains(index) ? index : nil)

            guard let legacyIndex = match else { continue }
            usedLegacyIndices.insert(legacyIndex)
            migrated.blocks[index].id = legacy.blocks[legacyIndex].id
            migrated.blocks[index].kind = legacy.blocks[legacyIndex].kind
            migrated.blocks[index].listStyle = legacy.blocks[legacyIndex].listStyle
            migrated.blocks[index].listOrdinal = legacy.blocks[legacyIndex].listOrdinal
        }

        return DocumentRenderPayload(
            attributedText: payload.attributedText,
            structuredDocument: migrated,
            sourceKind: sourceKind
        )
    }

    private static func loadRTF(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    private static func resolveSourceKind(
        structuredDocument: StructuredDocument?,
        sourceFileName: String?,
        sourceURL: URL?
    ) -> StructuredDocument.SourceKind {
        if let sourceKind = structuredDocument?.sourceKind,
           sourceKind != .unknown {
            return sourceKind
        }

        let extensionName = sourceFileName
            .map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
            ?? sourceURL?.pathExtension.lowercased()
            ?? ""
        switch extensionName {
        case "md", "markdown": return .markdown
        case "txt": return .plainText
        case "": return .unknown
        case "docx", "doc", "rtf", "html", "htm": return .native
        default: return .plainText
        }
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
