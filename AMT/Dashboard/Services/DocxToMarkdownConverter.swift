//
//  DocxToMarkdownConverter.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Converts Word documents (.docx, .doc), Rich Text (.rtf), and other formats into structured Markdown (.md).
nonisolated struct DocxToMarkdownConverter: Sendable {

    /// The text used for analysis and the unformatted source text used for safe range mapping.
    struct ExtractionResult: Equatable, Sendable {
        let analysisText: String
        let sourceText: String
    }

    // MARK: - Public API

    /// Converts a file at the given URL into a clean Markdown string.
    static func convert(fileURL: URL) throws -> String {
        let ext = fileURL.pathExtension.lowercased()

        // 1. Direct Markdown or plain text handling
        if ext == "md" || ext == "markdown" {
            return try String(contentsOf: fileURL, encoding: .utf8)
        }

        if ext == "txt" {
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                return text
            }
            return try String(contentsOf: fileURL, encoding: .isoLatin1)
        }

        // 2. Rich Text & Word Document loading via NSAttributedString
        guard let attrString = try? loadAttributedString(fileURL: fileURL), attrString.length > 0 else {
            // Fallback to raw string if attributed loading is unavailable
            if let rawText = try? String(contentsOf: fileURL, encoding: .utf8) {
                return rawText
            }
            throw CocoaError(.fileReadCorruptFile)
        }

        return convert(attributedString: attrString)
    }

    /// Extracts Markdown for analysis while retaining the original text for UTF-16 mapping.
    static func extract(fileURL: URL) throws -> ExtractionResult {
        let attributedString = try loadAttributedString(fileURL: fileURL)
        guard attributedString.length > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return ExtractionResult(
            analysisText: convert(attributedString: attributedString),
            sourceText: attributedString.string
        )
    }

    /// Loads a document through AppKit so the original attributes remain available for export.
    static func loadAttributedString(fileURL: URL) throws -> NSAttributedString {
        let ext = fileURL.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]

        if ext == "docx" || ext == "doc" {
            options[.documentType] = NSAttributedString.DocumentType.wordML
        } else if ext == "rtf" {
            options[.documentType] = NSAttributedString.DocumentType.rtf
        } else if ext == "html" || ext == "htm" {
            options[.documentType] = NSAttributedString.DocumentType.html
        }

        if let direct = try? NSAttributedString(url: fileURL, options: options, documentAttributes: nil) {
            return direct
        }

        if let fallback = try? NSAttributedString(url: fileURL, options: [:], documentAttributes: nil) {
            return fallback
        }

        let data = try Data(contentsOf: fileURL)
        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    /// Converts an NSAttributedString into structured Markdown.
    static func convert(attributedString: NSAttributedString) -> String {
        let fullString = attributedString.string
        guard !fullString.isEmpty else { return "" }

        var markdownParagraphs: [String] = []
        let nsString = fullString as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Enumerate paragraphs
        nsString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, paragraphRange, _, _ in
            guard let rawPara = substring else { return }
            let trimmedPara = rawPara.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPara.isEmpty else { return }

            let paraMarkdown = convertParagraph(
                attributedString: attributedString,
                paragraphRange: paragraphRange,
                trimmedText: trimmedPara
            )

            if !paraMarkdown.isEmpty {
                markdownParagraphs.append(paraMarkdown)
            }
        }

        return formatMarkdownDocument(paragraphs: markdownParagraphs)
    }

    // MARK: - Paragraph Processing

    private static func convertParagraph(
        attributedString: NSAttributedString,
        paragraphRange: NSRange,
        trimmedText: String
    ) -> String {
        // Determine dominant/first font attributes in the paragraph
        var headingPrefix = ""
        var isDominantBold = false

        let sampleLocation = paragraphRange.location
        if sampleLocation < attributedString.length {
            let attrs = attributedString.attributes(at: sampleLocation, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont {
                let size = font.pointSize
                let traits = font.fontDescriptor.symbolicTraits
                isDominantBold = traits.contains(.bold)

                // Detect heading level based on font size & styling
                if size >= 22 {
                    headingPrefix = "# "
                } else if size >= 18 {
                    headingPrefix = "## "
                } else if size >= 15 && isDominantBold {
                    headingPrefix = "### "
                }
            }
        }

        // Detect Indonesian legal document structural markers if no font heading was applied
        if headingPrefix.isEmpty {
            let upper = trimmedText.uppercased()
            if upper.hasPrefix("BAB ") {
                headingPrefix = "## "
            } else if upper.hasPrefix("PASAL ") {
                headingPrefix = "### "
            }
        }

        // Convert inline formatted runs
        let formattedContent = convertInlineRuns(
            attributedString: attributedString,
            range: paragraphRange,
            isHeading: !headingPrefix.isEmpty
        )

        // Handle list bullet normalization
        let cleanText = formattedContent.trimmingCharacters(in: .whitespaces)

        // Check if paragraph starts with bullet symbol
        if cleanText.hasPrefix("• ") || cleanText.hasPrefix("⁃ ") || cleanText.hasPrefix("– ") {
            let itemText = cleanText.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return "- \(itemText)"
        }

        // If heading prefix is present, ensure no double header syntax
        if !headingPrefix.isEmpty {
            if cleanText.hasPrefix("#") {
                return cleanText
            }
            return "\(headingPrefix)\(cleanText)"
        }

        return cleanText
    }

    // MARK: - Inline Formatting Conversion

    private static func convertInlineRuns(
        attributedString: NSAttributedString,
        range: NSRange,
        isHeading: Bool
    ) -> String {
        var result = ""
        let nsString = attributedString.string as NSString

        attributedString.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            let rawSub = nsString.substring(with: subRange)
            let trimmedSub = rawSub.trimmingCharacters(in: .whitespacesAndNewlines)

            // If whitespace only, preserve as is
            if trimmedSub.isEmpty {
                result += rawSub
                return
            }

            var isBold = false
            var isItalic = false
            var isCode = false
            var isStrikethrough = false
            var linkURL: String?

            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                isBold = traits.contains(.bold)
                isItalic = traits.contains(.italic)

                let fontName = font.fontName.lowercased()
                if fontName.contains("mono") || fontName.contains("courier") || fontName.contains("menlo") {
                    isCode = true
                }
            }

            if let strike = attributes[.strikethroughStyle] as? Int, strike > 0 {
                isStrikethrough = true
            }

            if let link = attributes[.link] {
                if let url = link as? URL {
                    linkURL = url.absoluteString
                } else if let str = link as? String {
                    linkURL = str
                }
            }

            // Lead and trail spaces handling around markdown delimiters
            let leadingSpaces = String(rawSub.prefix(while: { $0 == " " || $0 == "\t" }))
            let trailingSpaces = String(rawSub.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            var styled = trimmedSub

            // Don't add extra **bold** inside heading lines (headings are already bold)
            if isBold && !isHeading {
                styled = "**\(styled)**"
            }

            if isItalic {
                styled = "*\(styled)*"
            }

            if isStrikethrough {
                styled = "~~\(styled)~~"
            }

            if isCode && !isHeading {
                styled = "`\(styled)`"
            }

            if let url = linkURL {
                styled = "[\(styled)](\(url))"
            }

            result += "\(leadingSpaces)\(styled)\(trailingSpaces)"
        }

        return result
    }

    // MARK: - Document Final Formatting

    private static func formatMarkdownDocument(paragraphs: [String]) -> String {
        var output = ""

        for (index, para) in paragraphs.enumerated() {
            output += para

            if index < paragraphs.count - 1 {
                let nextPara = paragraphs[index + 1]

                // Use single newline between list items, double newline between regular paragraphs
                let isCurrentListItem = para.hasPrefix("- ") || para.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                let isNextListItem = nextPara.hasPrefix("- ") || nextPara.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

                if isCurrentListItem && isNextListItem {
                    output += "\n"
                } else {
                    output += "\n\n"
                }
            }
        }

        // Clean non-breaking spaces and irregular characters
        return output
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
