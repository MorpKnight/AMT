//
//  EditorViewModel.swift
//  AMT
//

import AppKit
import Foundation
import Observation

enum FormattingAction: Equatable {
    case textStyle(TextStyle)
    case bold
    case italic
    case underline
    case strikethrough
    case listStyle(ListStyle)
    case undo
    case redo
}

struct FormattingState: Equatable {
    var textStyle: TextStyle = .body
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var listStyle: ListStyle?
}

@Observable
final class EditorViewModel {
    var pendingAction: FormattingAction?
    var activeState = FormattingState()
    var canUndo = false
    var canRedo = false
    var zoomPercent = EditorZoom.defaultPercent

    func zoomIn() {
        zoomPercent = EditorZoom.clamp(zoomPercent + EditorZoom.stepPercent)
    }

    func zoomOut() {
        zoomPercent = EditorZoom.clamp(zoomPercent - EditorZoom.stepPercent)
    }

    func resetZoom() {
        zoomPercent = EditorZoom.defaultPercent
    }

    func resetHistoryState() {
        canUndo = false
        canRedo = false
    }
}

/// Converts the persisted Markdown representation to AppKit rich text. The
/// inverse conversion intentionally reuses the importer's attributed-text
/// serializer, so storage and editing share one Markdown dialect.
enum MarkdownRichTextCodec {
    private static let presentationIntentKey = NSAttributedString.Key("NSPresentationIntent")
    private static let inlinePresentationIntentKey = NSAttributedString.Key("NSInlinePresentationIntent")

    private struct PresentationInfo {
        var blockID: Int?
        var headingLevel: Int?
        var listOrdinal: Int?
        var listItemID: Int?
        var isOrderedList = false
        var isUnorderedList = false
        var isCodeBlock = false
        var isBlockQuote = false
        var tableID: Int?
        var tableRowID: Int?
        var tableColumn: Int?
    }

    private struct BlockKey: Hashable {
        let kind: Int
        let first: Int
    }

    private struct Insertion {
        let location: Int
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let order: Int
    }

    private struct TableCellKey: Hashable {
        let tableID: Int
        let rowID: Int
        let column: Int
    }

    private struct TableCellSpan {
        var key: TableCellKey
        var range: NSRange
    }

    private struct MarkerPair {
        let opening: NSRange
        let closing: NSRange
        let marks: OverlayMarks
    }

    private struct MarkerSpec {
        let token: String
        let marks: OverlayMarks
    }

    private struct OverlayMarks: OptionSet {
        let rawValue: Int
        static let bold = OverlayMarks(rawValue: 1 << 0)
        static let italic = OverlayMarks(rawValue: 1 << 1)
        static let strikethrough = OverlayMarks(rawValue: 1 << 2)
        static let code = OverlayMarks(rawValue: 1 << 3)
    }

    static func render(_ markdown: String, defaultFont: NSFont = EditorTypography.defaultFont) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttributes(font: defaultFont))
        }

        let repairedMarkdown = repairUnbalancedMarkers(markdown)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        let parsed = (try? NSAttributedString(
            markdown: Data(repairedMarkdown.utf8),
            options: options,
            baseURL: nil
        )) ?? NSAttributedString(string: repairedMarkdown, attributes: baseAttributes(font: defaultFont))

        return applyMarkdownPresentationAttributes(to: parsed, defaultFont: defaultFont)
    }

    /// Applies clear Markdown markers found in a native Word/RTF attributed
    /// string without converting the document through Markdown. Every source
    /// character is copied with its original attributes; only marker ranges
    /// are omitted and the corresponding traits are layered on top.
    static func render(_ native: NSAttributedString, defaultFont: NSFont) -> NSAttributedString {
        guard native.length > 0 else {
            return NSAttributedString(string: "", attributes: baseAttributes(font: defaultFont))
        }

        let source = native.string as NSString
        let pairs = markerPairs(in: source)
        let orphanMarkers = orphanMarkerRanges(in: source, excluding: pairs)
        guard !pairs.isEmpty || !orphanMarkers.isEmpty else {
            return ensureDefaults(in: native, defaultFont: defaultFont)
        }

        let markerRanges = (pairs.flatMap { [$0.opening, $0.closing] } + orphanMarkers)
            .sorted { $0.location < $1.location }
        let output = NSMutableAttributedString()
        var index = 0
        var markerCursor = 0

        while index < source.length {
            while markerCursor < markerRanges.count,
                  index >= NSMaxRange(markerRanges[markerCursor]) {
                markerCursor += 1
            }
            if markerCursor < markerRanges.count,
               index >= markerRanges[markerCursor].location {
                let markerRange = markerRanges[markerCursor]
                index = NSMaxRange(markerRange)
                continue
            }

            let characterRange = source.rangeOfComposedCharacterSequence(at: index)
            let piece = NSMutableAttributedString(attributedString: native.attributedSubstring(from: characterRange))
            var activeMarks: OverlayMarks = []
            for pair in pairs where index >= NSMaxRange(pair.opening) && index < pair.closing.location {
                activeMarks.formUnion(pair.marks)
            }
            apply(activeMarks, to: piece, defaultFont: defaultFont)
            output.append(piece)
            index = NSMaxRange(characterRange)
        }

        return ensureDefaults(in: output, defaultFont: defaultFont)
    }

    static func markdown(from richText: NSAttributedString) -> String {
        DocxToMarkdownConverter.convert(attributedString: richText)
    }

    static func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.black
        ]
    }

    private static func applyMarkdownPresentationAttributes(
        to parsed: NSAttributedString,
        defaultFont: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: result.length)
        guard result.length > 0 else { return result }

        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        var extraInsertions: [Insertion] = []
        var tableSpans: [TableCellSpan] = []
        var tableIndices: [TableCellKey: Int] = [:]
        var previousBlockKey: BlockKey?

        result.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let info = presentationInfo(from: attributes)
            let inlineBits = (attributes[inlinePresentationIntentKey] as? NSNumber)?.intValue ?? 0
            var additions: [NSAttributedString.Key: Any] = [:]

            // Foundation's Markdown parser supplies its own small default
            // font. Replace that parser fallback with the editor's shared
            // typography token, while retaining semantic traits below.
            var font = defaultFont
            var shouldSetFont = true
            if let level = info.headingLevel {
                font = fontWithTraits(font, pointSize: headingPointSize(level), bold: true, italic: nil)
                shouldSetFont = true
            }
            if inlineBits & (1 << 1) != 0 { // strongly emphasized
                font = fontWithTraits(font, pointSize: nil, bold: true, italic: nil)
                shouldSetFont = true
            }
            if inlineBits & (1 << 0) != 0 { // emphasized
                font = fontWithTraits(font, pointSize: nil, bold: nil, italic: true)
                shouldSetFont = true
            }
            if info.isCodeBlock || inlineBits & (1 << 2) != 0 {
                font = fontWithTraits(font, pointSize: nil, bold: nil, italic: nil, monospaced: true)
                shouldSetFont = true
                additions[.backgroundColor] = NSColor(calibratedWhite: 0.95, alpha: 1)
            }
            if shouldSetFont { additions[.font] = font }
            if attributes[.foregroundColor] == nil {
                additions[.foregroundColor] = NSColor.black
            }
            if inlineBits & (1 << 5) != 0 { // strikethrough
                additions[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            if info.headingLevel != nil || info.isOrderedList || info.isUnorderedList || info.isBlockQuote {
                let paragraph = paragraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
                if info.headingLevel != nil {
                    paragraph.paragraphSpacingBefore = max(paragraph.paragraphSpacingBefore, 8)
                    paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, 6)
                }
                if info.isOrderedList || info.isUnorderedList {
                    paragraph.headIndent = max(paragraph.headIndent, 22)
                    paragraph.firstLineHeadIndent = min(paragraph.firstLineHeadIndent, -12)
                }
                if info.isBlockQuote {
                    paragraph.headIndent = max(paragraph.headIndent, 22)
                    paragraph.firstLineHeadIndent = max(paragraph.firstLineHeadIndent, 0)
                }
                additions[.paragraphStyle] = paragraph
            }
            updates.append((range, additions))

            if let ordinal = info.listOrdinal {
                let prefix = info.isOrderedList ? "\(ordinal). " : "• "
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: attributes[.foregroundColor] ?? NSColor.black
                ]
                if !extraInsertions.contains(where: { $0.location == range.location && $0.text == prefix }) {
                    extraInsertions.append(Insertion(location: range.location, text: prefix, attributes: attrs, order: 20))
                }
            }

            let blockKey: BlockKey?
            if let tableID = info.tableID {
                blockKey = BlockKey(kind: 4, first: tableID)
            } else if let listItemID = info.listItemID {
                blockKey = BlockKey(kind: 3, first: listItemID)
            } else if let blockID = info.blockID {
                blockKey = BlockKey(kind: info.headingLevel == nil ? 2 : 1, first: blockID)
            } else {
                blockKey = nil
            }
            if let blockKey, let previousBlockKey, blockKey != previousBlockKey, range.location > 0 {
                let attrs = result.attributes(at: range.location, effectiveRange: nil)
                    .filter { $0.key == .font || $0.key == .foregroundColor }
                extraInsertions.append(Insertion(location: range.location, text: "\n", attributes: attrs, order: 10))
            }
            if let blockKey { previousBlockKey = blockKey }

            if let tableID = info.tableID, let rowID = info.tableRowID, let column = info.tableColumn {
                let key = TableCellKey(tableID: tableID, rowID: rowID, column: column)
                if let existingIndex = tableIndices[key] {
                    tableSpans[existingIndex].range = NSUnionRange(tableSpans[existingIndex].range, range)
                } else {
                    tableIndices[key] = tableSpans.count
                    tableSpans.append(TableCellSpan(key: key, range: range))
                }
            }
        }

        for (range, additions) in updates where !additions.isEmpty {
            result.addAttributes(additions, range: range)
        }

        // Reconstruct readable separators that Foundation intentionally omits
        // from Markdown table presentation intents.
        let orderedCells = tableSpans.sorted { $0.range.location < $1.range.location }
        var tableInsertions: [Insertion] = []
        for index in 0..<(max(orderedCells.count - 1, 0)) {
            let current = orderedCells[index]
            let next = orderedCells[index + 1]
            guard current.key.tableID == next.key.tableID else { continue }
            let text = current.key.rowID == next.key.rowID ? "\t" : "\n"
            let attrs = result.attributes(at: current.range.location, effectiveRange: nil)
                .filter { $0.key == .font || $0.key == .foregroundColor }
            tableInsertions.append(Insertion(location: NSMaxRange(current.range), text: text, attributes: attrs, order: 0))
        }

        for insertion in (extraInsertions + tableInsertions).sorted(by: {
            if $0.location == $1.location { return $0.order > $1.order }
            return $0.location > $1.location
        }) {
            result.insert(NSAttributedString(string: insertion.text, attributes: insertion.attributes), at: insertion.location)
        }

        // Presentation intents are parser metadata, not visual attributes.
        // Removing them keeps RTF serialization portable while retaining the
        // concrete AppKit attributes applied above.
        result.removeAttribute(presentationIntentKey, range: NSRange(location: 0, length: result.length))
        result.removeAttribute(inlinePresentationIntentKey, range: NSRange(location: 0, length: result.length))
        return ensureDefaults(in: result, defaultFont: defaultFont)
    }

    private static func presentationInfo(from attributes: [NSAttributedString.Key: Any]) -> PresentationInfo {
        var info = PresentationInfo()
        guard let intent = attributes[presentationIntentKey] as? PresentationIntent else { return info }

        for component in intent.components {
            switch component.kind {
            case .paragraph: info.blockID = component.identity
            case .header(let level):
                info.blockID = component.identity
                info.headingLevel = level
            case .orderedList: info.isOrderedList = true
            case .unorderedList: info.isUnorderedList = true
            case .listItem(let ordinal):
                info.listItemID = component.identity
                info.listOrdinal = ordinal
            case .codeBlock:
                info.blockID = component.identity
                info.isCodeBlock = true
            case .blockQuote:
                info.blockID = component.identity
                info.isBlockQuote = true
            case .table: info.tableID = component.identity
            case .tableHeaderRow: info.tableRowID = component.identity
            case .tableRow: info.tableRowID = component.identity
            case .tableCell(let column): info.tableColumn = column
            default: break
            }
        }
        return info
    }

    private static func paragraphStyle(from original: NSParagraphStyle?) -> NSMutableParagraphStyle {
        if let original,
           let copy = original.mutableCopy() as? NSMutableParagraphStyle {
            return copy
        }
        return NSMutableParagraphStyle()
    }

    private static func headingPointSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return EditorTypography.heading1PointSize
        case 2: return EditorTypography.heading2PointSize
        case 3: return EditorTypography.heading3PointSize
        default: return EditorTypography.bodyPointSize
        }
    }

    private static func fontWithTraits(
        _ font: NSFont,
        pointSize: CGFloat?,
        bold: Bool?,
        italic: Bool?,
        monospaced: Bool = false
    ) -> NSFont {
        let size = pointSize ?? font.pointSize
        let descriptor = font.fontDescriptor
        var traits = descriptor.symbolicTraits
        if let bold {
            if bold { traits.insert(.bold) } else { traits.remove(.bold) }
        }
        if let italic {
            if italic { traits.insert(.italic) } else { traits.remove(.italic) }
        }
        if monospaced {
            let weight: NSFont.Weight = traits.contains(.bold) ? .bold : .regular
            var mono = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            if traits.contains(.italic) {
                mono = NSFontManager.shared.convert(mono, toHaveTrait: .italicFontMask)
            }
            return mono
        }
        let updatedDescriptor = descriptor.withSymbolicTraits(traits)
        if let converted = NSFont(descriptor: updatedDescriptor, size: size) {
            return converted
        }
        var converted = NSFont(name: font.fontName, size: size) ?? font
        if traits.contains(.bold) { converted = NSFontManager.shared.convert(converted, toHaveTrait: .boldFontMask) }
        if traits.contains(.italic) { converted = NSFontManager.shared.convert(converted, toHaveTrait: .italicFontMask) }
        return converted
    }

    private static func apply(_ marks: OverlayMarks, to value: NSMutableAttributedString, defaultFont: NSFont) {
        guard value.length > 0, marks != [] else { return }
        let range = NSRange(location: 0, length: value.length)
        let attributes = value.attributes(at: 0, effectiveRange: nil)
        var font = (attributes[.font] as? NSFont) ?? defaultFont
        if marks.contains(.code) {
            font = fontWithTraits(font, pointSize: nil, bold: nil, italic: nil, monospaced: true)
        }
        if marks.contains(.bold) {
            font = fontWithTraits(font, pointSize: nil, bold: true, italic: nil)
        }
        if marks.contains(.italic) {
            font = fontWithTraits(font, pointSize: nil, bold: nil, italic: true)
        }
        value.addAttribute(.font, value: font, range: range)
        if marks.contains(.strikethrough) {
            value.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    private static func ensureDefaults(in value: NSAttributedString, defaultFont: NSFont) -> NSAttributedString {
        let result = value.mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: value)
        guard result.length > 0 else { return result }
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length), options: []) { attributes, range, _ in
            if attributes[.font] == nil { result.addAttribute(.font, value: defaultFont, range: range) }
            if attributes[.foregroundColor] == nil { result.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }
        return result
    }

    private static func repairUnbalancedMarkers(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "***" {
                return line
            }
            var repaired = line
            for token in ["***", "**", "___", "__", "~~", "`", "_", "*"] {
                let protectedRanges = markerPairs(in: repaired as NSString)
                    .filter { $0.marks.contains(.code) }
                    .map { NSRange(location: NSMaxRange($0.opening), length: max($0.closing.location - NSMaxRange($0.opening), 0)) }
                let occurrences = markerOccurrences(in: repaired as NSString, token: token, excluding: protectedRanges)
                let isSingleEmphasis = token == "*" || token == "_"
                guard occurrences.count % 2 == 1,
                      (!isSingleEmphasis || occurrences.count >= 3),
                      let orphan = occurrences.last else { continue }
                repaired = (repaired as NSString).replacingCharacters(in: orphan, with: "")
            }
            return repaired
        }.joined(separator: "\n")
    }

    private static func markerPairs(in text: NSString) -> [MarkerPair] {
        let specs = [
            MarkerSpec(token: "***", marks: [.bold, .italic]),
            MarkerSpec(token: "**", marks: [.bold]),
            MarkerSpec(token: "___", marks: [.bold, .italic]),
            MarkerSpec(token: "__", marks: [.bold]),
            MarkerSpec(token: "~~", marks: [.strikethrough]),
            MarkerSpec(token: "`", marks: [.code]),
            MarkerSpec(token: "_", marks: [.italic]),
            MarkerSpec(token: "*", marks: [.italic])
        ]
        var pairs: [MarkerPair] = []
        var index = 0
        while index < text.length {
            var matched = false
            for spec in specs {
                let tokenLength = (spec.token as NSString).length
                guard index + tokenLength <= text.length,
                      text.substring(with: NSRange(location: index, length: tokenLength)) == spec.token,
                      !isEscaped(text, at: index),
                      !isPartOfLongerAsteriskDelimiter(text, at: index, token: spec.token) else { continue }
                if let closing = nextMarker(spec.token, in: text, from: index + tokenLength) {
                    pairs.append(MarkerPair(
                        opening: NSRange(location: index, length: tokenLength),
                        closing: closing,
                        marks: spec.marks
                    ))
                    index = NSMaxRange(closing)
                    matched = true
                    break
                }
            }
            if !matched { index += 1 }
        }
        return pairs
    }

    private static func nextMarker(_ token: String, in text: NSString, from start: Int) -> NSRange? {
        let tokenLength = (token as NSString).length
        var index = start
        while index + tokenLength <= text.length {
            if text.substring(with: NSRange(location: index, length: tokenLength)) == token,
               !isEscaped(text, at: index),
               !isPartOfLongerAsteriskDelimiter(text, at: index, token: token) {
                return NSRange(location: index, length: tokenLength)
            }
            index += 1
        }
        return nil
    }

    private static func orphanMarkerRanges(in text: NSString, excluding pairs: [MarkerPair]) -> [NSRange] {
        var orphans: [NSRange] = []
        let protectedRanges = pairs
            .filter { $0.marks.contains(.code) }
            .map { NSRange(location: NSMaxRange($0.opening), length: max($0.closing.location - NSMaxRange($0.opening), 0)) }
        for token in ["***", "**", "___", "__", "~~", "`", "_", "*"] {
            let occurrences = markerOccurrences(in: text, token: token, excluding: protectedRanges).filter { occurrence in
                !pairs.contains { NSIntersectionRange(occurrence, $0.opening).length > 0 || NSIntersectionRange(occurrence, $0.closing).length > 0 }
            }
            let isSingleEmphasis = token == "*" || token == "_"
            if occurrences.count % 2 == 1,
               (!isSingleEmphasis || occurrences.count >= 3),
               let last = occurrences.last {
                orphans.append(last)
            }
        }
        return orphans
    }

    private static func markerOccurrences(in text: NSString, token: String, excluding protectedRanges: [NSRange] = []) -> [NSRange] {
        let tokenLength = (token as NSString).length
        guard tokenLength > 0 else { return [] }
        var occurrences: [NSRange] = []
        var index = 0
        while index + tokenLength <= text.length {
            let range = NSRange(location: index, length: tokenLength)
            if text.substring(with: range) == token,
               !isEscaped(text, at: index),
               !isPartOfLongerAsteriskDelimiter(text, at: index, token: token),
               !isUnorderedListMarker(text, at: index, token: token),
               !protectedRanges.contains(where: { NSLocationInRange(index, $0) }) {
                occurrences.append(range)
                index += tokenLength
            } else {
                index += 1
            }
        }
        return occurrences
    }

    private static func isUnorderedListMarker(_ text: NSString, at index: Int, token: String) -> Bool {
        guard token == "*", (index == 0 || text.character(at: index - 1) == 10) else { return false }
        let next = index + 1
        guard next < text.length else { return false }
        return text.character(at: next) == 32 || text.character(at: next) == 9
    }

    private static func isPartOfLongerAsteriskDelimiter(_ text: NSString, at index: Int, token: String) -> Bool {
        guard token.contains("*") else { return false }
        let previous = index > 0 ? text.character(at: index - 1) : 0
        let nextIndex = index + (token as NSString).length
        let next = nextIndex < text.length ? text.character(at: nextIndex) : 0
        if token == "*" { return previous == 42 || next == 42 }
        if token == "**" { return previous == 42 || next == 42 }
        return false
    }

    private static func isEscaped(_ text: NSString, at index: Int) -> Bool {
        guard index > 0 else { return false }
        var slashCount = 0
        var cursor = index - 1
        while cursor >= 0, text.character(at: cursor) == 92 {
            slashCount += 1
            cursor -= 1
        }
        return slashCount % 2 == 1
    }
}

enum RichTextFormatter {
    @discardableResult
    static func apply(_ action: FormattingAction, to textView: NSTextView) -> Bool {
        switch action {
        case .textStyle(let style):
            return applyTextStyle(style, to: textView)
        case .bold:
            return applyFontTrait(.bold, to: textView)
        case .italic:
            return applyFontTrait(.italic, to: textView)
        case .underline:
            return toggleAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue, in: textView)
        case .strikethrough:
            return toggleAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue, in: textView)
        case .listStyle(let style):
            return applyListStyle(style, to: textView)
        case .undo, .redo:
            return false
        }
    }

    static func state(for textView: NSTextView) -> FormattingState {
        let selection = textView.selectedRange()
        let attributedText = textView.attributedString()
        let safeLocation = min(selection.location, attributedText.length)
        let attributes = safeLocation < attributedText.length
            ? attributedText.attributes(at: safeLocation, effectiveRange: nil)
            : textView.typingAttributes
        let font = (attributes[.font] as? NSFont) ?? EditorTypography.defaultFont

        return FormattingState(
            textStyle: EditorTypography.textStyle(for: font),
            isBold: font.fontDescriptor.symbolicTraits.contains(.bold),
            isItalic: font.fontDescriptor.symbolicTraits.contains(.italic),
            isUnderline: numericValue(attributes[.underlineStyle]) != 0,
            isStrikethrough: numericValue(attributes[.strikethroughStyle]) != 0,
            listStyle: listStyle(for: textView.string as NSString, at: safeLocation)
        )
    }

    private static func applyTextStyle(_ style: TextStyle, to textView: NSTextView) -> Bool {
        let paragraphRange = paragraphRange(in: textView)
        guard paragraphRange.length > 0 else { return false }

        let font = EditorTypography.font(for: style)

        textView.textStorage?.addAttributes(MarkdownRichTextCodec.baseAttributes(font: font), range: paragraphRange)
        textView.typingAttributes = MarkdownRichTextCodec.baseAttributes(font: font)
        return true
    }

    private static func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, to textView: NSTextView) -> Bool {
        let range = formattingRange(in: textView)
        let textStorage = textView.textStorage
        let isEnabled = traitIsEnabled(trait, in: textView, range: range)

        if range.length == 0 {
            let currentFont = (textView.typingAttributes[.font] as? NSFont) ?? EditorTypography.defaultFont
            var attributes = textView.typingAttributes
            attributes[.font] = font(from: currentFont, toggling: trait, enabled: !isEnabled)
            textView.typingAttributes = attributes
            return true
        }

        textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let currentFont = (value as? NSFont) ?? EditorTypography.defaultFont
            textStorage?.addAttribute(
                .font,
                value: font(from: currentFont, toggling: trait, enabled: !isEnabled),
                range: subrange
            )
        }
        return true
    }

    private static func toggleAttribute(
        _ key: NSAttributedString.Key,
        enabledValue: Int,
        in textView: NSTextView
    ) -> Bool {
        let range = formattingRange(in: textView)
        let attributes = range.length > 0
            ? textView.attributedString().attributes(at: range.location, effectiveRange: nil)
            : textView.typingAttributes
        let isEnabled = numericValue(attributes[key]) != 0

        if range.length == 0 {
            var typingAttributes = textView.typingAttributes
            typingAttributes[key] = isEnabled ? 0 : enabledValue
            textView.typingAttributes = typingAttributes
        } else if isEnabled {
            textView.textStorage?.removeAttribute(key, range: range)
        } else {
            textView.textStorage?.addAttribute(key, value: enabledValue, range: range)
        }
        return true
    }

    private static func applyListStyle(_ style: ListStyle, to textView: NSTextView) -> Bool {
        let text = textView.string as NSString
        let range = paragraphRange(in: textView)
        let line = text.substring(with: range)
        let prefix: String

        switch style {
        case .bulleted:
            prefix = "• "
        case .numbered:
            prefix = "1. "
        }

        let currentPrefixRange = listPrefixRange(in: line)
        if let currentPrefixRange, (line as NSString).substring(with: currentPrefixRange) == prefix {
            textView.insertText("", replacementRange: NSRange(location: range.location, length: currentPrefixRange.length))
        } else {
            if let currentPrefixRange {
                textView.insertText(prefix, replacementRange: NSRange(location: range.location, length: currentPrefixRange.length))
            } else {
                textView.insertText(prefix, replacementRange: NSRange(location: range.location, length: 0))
            }
        }
        return true
    }

    private static func paragraphRange(in textView: NSTextView) -> NSRange {
        let text = textView.string as NSString
        guard text.length > 0 else { return .init(location: 0, length: 0) }
        let location = min(textView.selectedRange().location, text.length - 1)
        return text.lineRange(for: NSRange(location: location, length: 0))
    }

    private static func formattingRange(in textView: NSTextView) -> NSRange {
        let textLength = textView.string.utf16.count
        let selection = textView.selectedRange()
        guard selection.location <= textLength else { return .init(location: textLength, length: 0) }
        return selection
    }

    private static func listStyle(for text: NSString, at location: Int) -> ListStyle? {
        guard text.length > 0 else { return nil }
        let line = text.substring(with: text.lineRange(for: NSRange(location: min(location, text.length - 1), length: 0)))
        if line.hasPrefix("• ") { return .bulleted }
        if line.range(of: "^[0-9]+\\. ", options: .regularExpression) != nil { return .numbered }
        return nil
    }

    private static func listPrefixRange(in line: String) -> NSRange? {
        let string = line as NSString
        if line.hasPrefix("• ") { return NSRange(location: 0, length: 2) }
        let range = string.range(of: "^[0-9]+\\. ", options: .regularExpression)
        return range.location == NSNotFound ? nil : range
    }

    private static func traitIsEnabled(
        _ trait: NSFontDescriptor.SymbolicTraits,
        in textView: NSTextView,
        range: NSRange
    ) -> Bool {
        let attributes = range.length > 0
            ? textView.attributedString().attributes(at: range.location, effectiveRange: nil)
            : textView.typingAttributes
        let font = (attributes[.font] as? NSFont) ?? EditorTypography.defaultFont
        return font.fontDescriptor.symbolicTraits.contains(trait)
    }

    private static func font(
        from font: NSFont,
        toggling trait: NSFontDescriptor.SymbolicTraits,
        enabled: Bool
    ) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        if enabled {
            traits.insert(trait)
        } else {
            traits.remove(trait)
        }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func numericValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return 0
    }
}
