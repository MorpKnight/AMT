//
//  EditorViewModel.swift
//  AMT
//

import AppKit
import Foundation
import Observation

enum EditorParagraphAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing
    case justified

    var id: Self { self }

    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        case .justified: return .justified
        }
    }

    var systemImage: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        case .justified: return "text.justify"
        }
    }

    var label: String {
        switch self {
        case .leading: return "Align left"
        case .center: return "Align center"
        case .trailing: return "Align right"
        case .justified: return "Justify"
        }
    }

    init(textAlignment: NSTextAlignment) {
        switch textAlignment {
        case .center: self = .center
        case .right: self = .trailing
        case .justified: self = .justified
        default: self = .leading
        }
    }
}

enum IndentDirection: String, CaseIterable, Identifiable {
    case increase
    case decrease

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .increase: return "increase.indent"
        case .decrease: return "decrease.indent"
        }
    }

    var label: String {
        switch self {
        case .increase: return "Increase indent"
        case .decrease: return "Decrease indent"
        }
    }
}

enum FormattingAction: Equatable {
    case textStyle(TextStyle)
    case bold
    case italic
    case underline
    case strikethrough
    case listStyle(ListStyle)
    case alignment(EditorParagraphAlignment)
    case indent(IndentDirection)
    case link(URL?)
    case clearFormatting
    case fontScale(from: CGFloat, to: CGFloat)
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
    var alignment: EditorParagraphAlignment = .leading
    var indentLevel = 0
    var isLink = false
    var linkURL: URL?
    var hasSelection = false
}

@Observable
final class EditorViewModel {
    var pendingAction: FormattingAction?
    var activeState = FormattingState()
    var canUndo = false
    var canRedo = false
    var zoomPercent = EditorZoom.defaultPercent
    /// Font size in points for the body text. Defaults to EditorTypography body size.
    var fontSizePoints: CGFloat = EditorTypography.bodyPointSize

    // MARK: - Zoom
    func zoomIn() {
        zoomPercent = EditorZoom.clamp(zoomPercent + EditorZoom.stepPercent)
    }

    func zoomOut() {
        zoomPercent = EditorZoom.clamp(zoomPercent - EditorZoom.stepPercent)
    }

    func resetZoom() {
        zoomPercent = EditorZoom.defaultPercent
    }

    // MARK: - Font Size
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 36
    static let fontSizeStep: CGFloat = 1

    func increaseFontSize() {
        queueFontSizeChange(to: min(fontSizePoints + Self.fontSizeStep, Self.maximumFontSize))
    }

    func decreaseFontSize() {
        queueFontSizeChange(to: max(fontSizePoints - Self.fontSizeStep, Self.minimumFontSize))
    }

    func resetFontSize() {
        queueFontSizeChange(to: EditorTypography.bodyPointSize)
    }

    /// Resets the transient font-size control when switching documents.
    /// This does not enqueue an edit or create an undo entry.
    func resetFontSizeState() {
        fontSizePoints = EditorTypography.bodyPointSize
        pendingAction = nil
    }

    private func queueFontSizeChange(to requestedSize: CGFloat) {
        let targetSize = min(
            max(requestedSize, Self.minimumFontSize),
            Self.maximumFontSize
        )
        let previousSize = min(
            max(fontSizePoints, Self.minimumFontSize),
            Self.maximumFontSize
        )
        guard abs(targetSize - previousSize) > 0.01 else { return }

        let actionStartSize: CGFloat
        if let pendingAction,
           case let .fontScale(from, _) = pendingAction {
            actionStartSize = from
        } else {
            actionStartSize = previousSize
        }
        fontSizePoints = targetSize
        if abs(targetSize - actionStartSize) <= 0.01 {
            pendingAction = nil
            return
        }
        pendingAction = .fontScale(from: actionStartSize, to: targetSize)
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
    private static let indentStep: CGFloat = 24
    private static let listHeadIndent: CGFloat = 22
    private static let listFirstLineHeadIndent: CGFloat = -12

    @discardableResult
    static func apply(
        _ action: FormattingAction,
        to textView: NSTextView,
        sourceKind: StructuredDocument.SourceKind = .plainText
    ) -> Bool {
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
        case .alignment(let alignment):
            return applyAlignment(alignment, to: textView)
        case .indent(let direction):
            return applyIndent(direction, to: textView)
        case .link(let url):
            return applyLink(url, to: textView)
        case .clearFormatting:
            return clearFormatting(in: textView)
        case .fontScale(let from, let to):
            return applyFontScale(
                from: from,
                to: to,
                to: textView,
                sourceKind: sourceKind
            )
        case .undo, .redo:
            return false
        }
    }

    /// Scales every font run in a canonical Markdown/plain-text document while
    /// preserving each run's family, traits, and all non-font attributes.
    private static func applyFontScale(
        from previousBodySize: CGFloat,
        to targetBodySize: CGFloat,
        to textView: NSTextView,
        sourceKind: StructuredDocument.SourceKind
    ) -> Bool {
        guard sourceKind.usesCanonicalTypography,
              previousBodySize.isFinite,
              targetBodySize.isFinite,
              previousBodySize > 0,
              targetBodySize > 0 else {
            return false
        }

        let scale = targetBodySize / previousBodySize
        guard scale.isFinite, scale > 0,
              let textStorage = textView.textStorage else {
            return false
        }

        var didChange = false
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if fullRange.length > 0 {
            textStorage.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                guard let font = value as? NSFont else { return }
                let scaledFont = scaledFont(font, by: scale)
                guard !font.isEqual(scaledFont) else { return }
                textStorage.addAttribute(.font, value: scaledFont, range: range)
                didChange = true
            }
        }

        let currentTypingFont = (textView.typingAttributes[.font] as? NSFont)
            ?? textView.font
            ?? EditorTypography.defaultFont
        let nextTypingFont = scaledFont(currentTypingFont, by: scale)
        if !currentTypingFont.isEqual(nextTypingFont) {
            var typingAttributes = textView.typingAttributes
            typingAttributes[.font] = nextTypingFont
            textView.typingAttributes = typingAttributes
            didChange = true
        }

        let currentViewFont = textView.font ?? EditorTypography.defaultFont
        let nextViewFont = scaledFont(currentViewFont, by: scale)
        if !currentViewFont.isEqual(nextViewFont) {
            textView.font = nextViewFont
            didChange = true
        }

        return didChange
    }

    private static func scaledFont(_ font: NSFont, by scale: CGFloat) -> NSFont {
        let pointSize = max(1, font.pointSize * scale)
        return NSFont(descriptor: font.fontDescriptor, size: pointSize)
            ?? NSFont(name: font.fontName, size: pointSize)
            ?? font
    }

    static func state(for textView: NSTextView) -> FormattingState {
        let selection = textView.selectedRange()
        let attributedText = textView.attributedString()
        let safeLocation = min(selection.location, attributedText.length)
        let attributes = safeLocation < attributedText.length
            ? attributedText.attributes(at: safeLocation, effectiveRange: nil)
            : textView.typingAttributes
        let font = (attributes[.font] as? NSFont) ?? EditorTypography.defaultFont
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        let headIndent = paragraph?.headIndent ?? 0
        let link: URL?
        if let url = attributes[.link] as? URL {
            link = url
        } else if let url = attributes[.link] as? NSURL {
            link = url as URL
        } else if let value = attributes[.link] as? String {
            link = URL(string: value)
        } else {
            link = nil
        }

        return FormattingState(
            textStyle: EditorTypography.textStyle(for: font),
            isBold: font.fontDescriptor.symbolicTraits.contains(.bold),
            isItalic: font.fontDescriptor.symbolicTraits.contains(.italic),
            isUnderline: numericValue(attributes[.underlineStyle]) != 0,
            isStrikethrough: numericValue(attributes[.strikethroughStyle]) != 0,
            listStyle: listStyle(for: textView.string as NSString, at: safeLocation),
            alignment: EditorParagraphAlignment(textAlignment: paragraph?.alignment ?? .left),
            indentLevel: max(0, Int((headIndent / indentStep).rounded())),
            isLink: link != nil,
            linkURL: link,
            hasSelection: selection.length > 0
        )
    }

    private static func applyTextStyle(_ style: TextStyle, to textView: NSTextView) -> Bool {
        let paragraphRanges = selectedParagraphRanges(in: textView)
        let font = EditorTypography.font(for: style)
        guard !paragraphRanges.isEmpty else {
            let currentFont = textView.typingAttributes[.font] as? NSFont
            guard currentFont?.isEqual(font) != true else { return false }
            var typingAttributes = textView.typingAttributes
            typingAttributes[.font] = font
            textView.typingAttributes = typingAttributes
            return true
        }

        guard let textStorage = textView.textStorage else { return false }
        var didChange = false
        for paragraphRange in paragraphRanges {
            textStorage.enumerateAttribute(.font, in: paragraphRange, options: []) { value, subrange, _ in
                guard (value as? NSFont)?.isEqual(font) != true else { return }
                textStorage.addAttribute(.font, value: font, range: subrange)
                didChange = true
            }
        }
        var typingAttributes = textView.typingAttributes
        if (typingAttributes[.font] as? NSFont)?.isEqual(font) != true {
            typingAttributes[.font] = font
            textView.typingAttributes = typingAttributes
            didChange = true
        }
        return didChange
    }

    private static func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, to textView: NSTextView) -> Bool {
        let range = formattingRange(in: textView)
        let textStorage = textView.textStorage
        let isEnabled = traitIsEnabled(trait, in: textView, range: range)

        if range.length == 0 {
            let currentFont = (textView.typingAttributes[.font] as? NSFont) ?? EditorTypography.defaultFont
            var attributes = textView.typingAttributes
            let updatedFont = font(from: currentFont, toggling: trait, enabled: !isEnabled)
            guard !currentFont.isEqual(updatedFont) else { return false }
            attributes[.font] = updatedFont
            textView.typingAttributes = attributes
            return true
        }

        var didChange = false
        textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let currentFont = (value as? NSFont) ?? EditorTypography.defaultFont
            let updatedFont = font(from: currentFont, toggling: trait, enabled: !isEnabled)
            guard !currentFont.isEqual(updatedFont) else { return }
            textStorage?.addAttribute(.font, value: updatedFont, range: subrange)
            didChange = true
        }
        return didChange
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
            let nextValue = isEnabled ? 0 : enabledValue
            guard numericValue(typingAttributes[key]) != nextValue else { return false }
            typingAttributes[key] = nextValue
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
        let paragraphRanges = selectedParagraphRanges(in: textView)
        guard let textStorage = textView.textStorage, !paragraphRanges.isEmpty else {
            return false
        }

        let currentStyles = paragraphRanges.map { range -> ListStyle? in
            listStyle(for: text.substring(with: range))
        }
        let shouldRemove = currentStyles.allSatisfy { $0 == style }
        let originalSelection = textView.selectedRange()
        var selectionAfterEdits = originalSelection
        var didChange = false

        for (index, range) in paragraphRanges.enumerated().reversed() {
            let line = text.substring(with: range)
            let relativePrefix = listPrefixRange(in: line)
            let currentPrefix = relativePrefix.map {
                NSRange(location: range.location + $0.location, length: $0.length)
            }
            let replacement: String
            if shouldRemove {
                replacement = ""
            } else {
                switch style {
                case .bulleted:
                    replacement = "• "
                case .numbered:
                    replacement = "\(index + 1). "
                }
            }

            let replacementRange = currentPrefix
                ?? NSRange(location: range.location, length: 0)
            let oldPrefixLength = replacementRange.length
            let prefixAttributes: [NSAttributedString.Key: Any]
            if replacementRange.location < textStorage.length {
                prefixAttributes = textStorage.attributes(
                    at: replacementRange.location,
                    effectiveRange: nil
                )
            } else {
                prefixAttributes = textView.typingAttributes
            }

            let oldPrefix = relativePrefix.map { (line as NSString).substring(with: $0) }
            guard oldPrefix != replacement else { continue }

            textStorage.replaceCharacters(in: replacementRange, with: replacement)
            didChange = true
            if !replacement.isEmpty {
                textStorage.addAttributes(
                    prefixAttributes,
                    range: NSRange(
                        location: replacementRange.location,
                        length: (replacement as NSString).length
                    )
                )
            }

            let delta = (replacement as NSString).length - oldPrefixLength
            selectionAfterEdits = adjustedSelection(
                selectionAfterEdits,
                replacing: replacementRange,
                withLength: (replacement as NSString).length
            )

            let newParagraphLength = max(0, range.length + delta)
            guard newParagraphLength > 0,
                  replacementRange.location < textStorage.length else { continue }
            let paragraphRange = NSRange(
                location: replacementRange.location,
                length: min(newParagraphLength, textStorage.length - replacementRange.location)
            )
            let paragraph = mutableParagraphStyle(
                at: paragraphRange.location,
                in: textStorage
            )
            if shouldRemove {
                if abs(paragraph.headIndent - listHeadIndent) < 0.5,
                   abs(paragraph.firstLineHeadIndent - listFirstLineHeadIndent) < 0.5 {
                    paragraph.headIndent = 0
                    paragraph.firstLineHeadIndent = 0
                }
            } else {
                paragraph.headIndent = max(paragraph.headIndent, listHeadIndent)
                paragraph.firstLineHeadIndent = min(
                    paragraph.firstLineHeadIndent,
                    listFirstLineHeadIndent
                )
            }
            textStorage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
        }

        textView.setSelectedRange(selectionAfterEdits)
        return didChange
    }

    private static func applyAlignment(
        _ alignment: EditorParagraphAlignment,
        to textView: NSTextView
    ) -> Bool {
        let paragraphRanges = selectedParagraphRanges(in: textView)
        guard let textStorage = textView.textStorage, !paragraphRanges.isEmpty else {
            var attributes = textView.typingAttributes
            let paragraph = mutableParagraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
            guard paragraph.alignment != alignment.textAlignment else { return false }
            paragraph.alignment = alignment.textAlignment
            attributes[.paragraphStyle] = paragraph
            textView.typingAttributes = attributes
            return true
        }

        var didChange = false
        for range in paragraphRanges {
            let paragraph = mutableParagraphStyle(at: range.location, in: textStorage)
            guard paragraph.alignment != alignment.textAlignment else { continue }
            paragraph.alignment = alignment.textAlignment
            textStorage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            didChange = true
        }
        return didChange
    }

    private static func applyIndent(
        _ direction: IndentDirection,
        to textView: NSTextView
    ) -> Bool {
        let paragraphRanges = selectedParagraphRanges(in: textView)
        guard let textStorage = textView.textStorage, !paragraphRanges.isEmpty else {
            var attributes = textView.typingAttributes
            let paragraph = mutableParagraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
            let nextIndent = max(0, paragraph.headIndent + (direction == .increase ? indentStep : -indentStep))
            guard abs(nextIndent - paragraph.headIndent) > 0.01 else { return false }
            paragraph.headIndent = nextIndent
            attributes[.paragraphStyle] = paragraph
            textView.typingAttributes = attributes
            return true
        }

        let delta = direction == .increase ? indentStep : -indentStep
        var didChange = false
        for range in paragraphRanges {
            let paragraph = mutableParagraphStyle(at: range.location, in: textStorage)
            let nextIndent = max(0, paragraph.headIndent + delta)
            guard abs(nextIndent - paragraph.headIndent) > 0.01 else { continue }
            paragraph.headIndent = nextIndent
            textStorage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            didChange = true
        }
        return didChange
    }

    private static func applyLink(_ url: URL?, to textView: NSTextView) -> Bool {
        let range = formattingRange(in: textView)
        guard range.length > 0, let textStorage = textView.textStorage else {
            return false
        }

        var didChange = false
        textStorage.enumerateAttribute(.link, in: range, options: []) { value, _, _ in
            if linkURL(from: value) != url { didChange = true }
        }
        guard didChange else { return false }

        if let url {
            textStorage.addAttribute(.link, value: url, range: range)
        } else {
            textStorage.removeAttribute(.link, range: range)
        }
        return true
    }

    private static func clearFormatting(in textView: NSTextView) -> Bool {
        let range = formattingRange(in: textView)
        let keys: [NSAttributedString.Key] = [
            .underlineStyle,
            .strikethroughStyle,
            .underlineColor,
            .strikethroughColor,
            .backgroundColor,
            .link,
            .baselineOffset,
            .kern
        ]

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let currentFont = attributes[.font] as? NSFont
            let hasOtherFormatting = keys.contains { attributes[$0] != nil }
            guard currentFont?.isEqual(EditorTypography.defaultFont) != true
                    || !isBlack(attributes[.foregroundColor] as? NSColor)
                    || hasOtherFormatting else {
                return false
            }
            attributes[.font] = EditorTypography.defaultFont
            attributes[.foregroundColor] = NSColor.black
            for key in keys {
                attributes.removeValue(forKey: key)
            }
            textView.typingAttributes = attributes
            return true
        }

        guard let textStorage = textView.textStorage else { return false }
        var didChange = false
        textStorage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            if (attributes[.font] as? NSFont)?.isEqual(EditorTypography.defaultFont) != true {
                didChange = true
            }
            if !isBlack(attributes[.foregroundColor] as? NSColor) {
                didChange = true
            }
            if keys.contains(where: { attributes[$0] != nil }) {
                didChange = true
            }
        }
        guard didChange else { return false }
        textStorage.addAttribute(.font, value: EditorTypography.defaultFont, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        for key in keys {
            textStorage.removeAttribute(key, range: range)
        }
        return true
    }

    private static func selectedParagraphRanges(in textView: NSTextView) -> [NSRange] {
        let text = textView.string as NSString
        guard text.length > 0 else { return [] }

        let selection = textView.selectedRange()
        let start = min(max(selection.location, 0), text.length - 1)
        let end = selection.length == 0
            ? start
            : min(max(NSMaxRange(selection) - 1, start), text.length - 1)
        let first = text.lineRange(for: NSRange(location: start, length: 0))
        let last = text.lineRange(for: NSRange(location: end, length: 0))
        let combined = NSUnionRange(first, last)

        var ranges: [NSRange] = []
        var cursor = combined.location
        let limit = NSMaxRange(combined)
        while cursor < limit {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            ranges.append(range)
            let next = NSMaxRange(range)
            guard next > cursor else { break }
            cursor = next
        }
        return ranges
    }

    private static func paragraphRange(in textView: NSTextView) -> NSRange {
        selectedParagraphRanges(in: textView).reduce(
            into: NSRange(location: NSNotFound, length: 0)
        ) { result, range in
            result = result.location == NSNotFound ? range : NSUnionRange(result, range)
        }.withFallback(location: 0, length: 0)
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
        return listStyle(for: line)
    }

    private static func listStyle(for line: String) -> ListStyle? {
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

    private static func mutableParagraphStyle(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> NSMutableParagraphStyle {
        guard textStorage.length > 0,
              location >= 0,
              location < textStorage.length,
              let original = textStorage.attributes(at: location, effectiveRange: nil)[.paragraphStyle]
                as? NSParagraphStyle,
              let copy = original.mutableCopy() as? NSMutableParagraphStyle else {
            return NSMutableParagraphStyle()
        }
        return copy
    }

    private static func mutableParagraphStyle(
        from original: NSParagraphStyle?
    ) -> NSMutableParagraphStyle {
        if let original,
           let copy = original.mutableCopy() as? NSMutableParagraphStyle {
            return copy
        }
        return NSMutableParagraphStyle()
    }

    private static func linkURL(from value: Any?) -> URL? {
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    private static func isBlack(_ color: NSColor?) -> Bool {
        guard let color,
              let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return abs(rgb.redComponent) < 0.001
            && abs(rgb.greenComponent) < 0.001
            && abs(rgb.blueComponent) < 0.001
            && abs(rgb.alphaComponent - 1) < 0.001
    }

    private static func adjustedSelection(
        _ selection: NSRange,
        replacing oldRange: NSRange,
        withLength newLength: Int
    ) -> NSRange {
        let oldEnd = NSMaxRange(oldRange)
        let delta = newLength - oldRange.length
        var location = selection.location
        var end = NSMaxRange(selection)

        if location >= oldEnd {
            location += delta
        } else if location > oldRange.location {
            location = oldRange.location + newLength
        }

        if end >= oldEnd {
            end += delta
        } else if end > oldRange.location {
            end = oldRange.location + newLength
        }

        if end < location { end = location }
        return NSRange(location: max(0, location), length: max(0, end - location))
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

private extension NSRange {
    func withFallback(location: Int, length: Int) -> NSRange {
        self.location == NSNotFound ? NSRange(location: location, length: length) : self
    }
}
