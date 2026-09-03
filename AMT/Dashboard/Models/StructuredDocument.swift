import AppKit
import Foundation

/// A persisted semantic representation backed by a lossless RTF snapshot.
///
/// The semantic fields make the document inspectable and Codable, while the
/// embedded RTF keeps the complete AppKit attribute dictionary available for
/// rendering/export. This is important for Word/RTF imports: unsupported or
/// uncommon attributes must not disappear just because they do not have a
/// first-class Swift property yet.
struct StructuredDocument: Codable, Equatable, Hashable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var blocks: [StructuredBlock]
    /// Semantic table cells for Markdown tables and tabular native text. The
    /// embedded RTF remains authoritative for borders, merged cells, and
    /// other table layout details that AppKit does not expose portably.
    var tables: [StructuredTable]
    /// Lossless presentation payload for native rich text and normalized
    /// Markdown. It is deliberately duplicated from DashboardDocument's
    /// compatibility field so this model remains self-contained after a
    /// migration.
    var richTextData: Data?

    init(blocks: [StructuredBlock] = [], tables: [StructuredTable] = [], richTextData: Data? = nil) {
        self.blocks = blocks
        self.tables = tables
        self.richTextData = richTextData
    }

    private enum CodingKeys: String, CodingKey { case version, blocks, tables, richTextData }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        blocks = try container.decodeIfPresent([StructuredBlock].self, forKey: .blocks) ?? []
        tables = try container.decodeIfPresent([StructuredTable].self, forKey: .tables) ?? []
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(tables, forKey: .tables)
        try container.encodeIfPresent(richTextData, forKey: .richTextData)
    }

    var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    static func normalize(_ attributed: NSAttributedString) -> StructuredDocument {
        let text = attributed.string as NSString
        var blocks: [StructuredBlock] = []
        let full = NSRange(location: 0, length: text.length)

        text.enumerateSubstrings(in: full, options: .byParagraphs) { _, range, _, _ in
            var contentRange = range
            while contentRange.length > 0 {
                let lastCharacter = text.character(at: NSMaxRange(contentRange) - 1)
                guard lastCharacter == 10 || lastCharacter == 13 || lastCharacter == 0x2028 || lastCharacter == 0x2029 else { break }
                contentRange.length -= 1
            }
            let value = text.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            let attributes = attributed.attributes(at: contentRange.location, effectiveRange: nil)
            let style = attributes[.paragraphStyle] as? NSParagraphStyle
            let alignment = StructuredAlignment(style?.alignment ?? .natural)
            let runs = StructuredRun.runs(in: attributed, range: contentRange)
            let upper = value.uppercased()
            let kind: StructuredBlock.Kind
            if upper.hasPrefix("BAB ") {
                kind = .heading(level: 1)
            } else if upper.hasPrefix("PASAL ") {
                kind = .heading(level: 2)
            } else if let font = attributes[.font] as? NSFont, font.pointSize >= EditorTypography.heading1PointSize - 2 {
                kind = .heading(level: 1)
            } else if let font = attributes[.font] as? NSFont, font.pointSize >= EditorTypography.heading2PointSize - 1 {
                kind = .heading(level: 2)
            } else if let font = attributes[.font] as? NSFont, font.pointSize >= EditorTypography.heading3PointSize {
                kind = .heading(level: 3)
            } else {
                kind = .paragraph
            }

            let listStyle: StructuredListStyle?
            let listOrdinal: Int?
            if value.hasPrefix("• ") {
                listStyle = .unordered
                listOrdinal = nil
            } else if let match = value.range(of: #"^\d+\. "#, options: .regularExpression) {
                listStyle = .ordered
                let ordinalText = value[match].dropLast(2)
                listOrdinal = Int(ordinalText)
            } else {
                listStyle = nil
                listOrdinal = nil
            }

            blocks.append(StructuredBlock(
                kind: kind,
                alignment: alignment,
                listStyle: listStyle,
                listOrdinal: listOrdinal,
                lineSpacing: Double(style?.lineSpacing ?? 2),
                paragraphSpacing: Double(style?.paragraphSpacing ?? 10),
                paragraphSpacingBefore: Double(style?.paragraphSpacingBefore ?? 0),
                headIndent: Double(style?.headIndent ?? 0),
                firstLineHeadIndent: Double(style?.firstLineHeadIndent ?? 0),
                tailIndent: Double(style?.tailIndent ?? 0),
                lineHeightMultiple: Double(style?.lineHeightMultiple ?? 0),
                minimumLineHeight: Double(style?.minimumLineHeight ?? 0),
                maximumLineHeight: Double(style?.maximumLineHeight ?? 0),
                lineBreakMode: style?.lineBreakMode.rawValue,
                runs: runs
            ))
        }

        // RTF is the fidelity layer. It preserves font family/size/traits,
        // colors, underline/strikethrough styles, links, paragraph layout,
        // and attributes that are not modeled above (including native table
        // and attachment information supported by AppKit).
        let serializedRichText = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        return StructuredDocument(
            blocks: blocks,
            tables: StructuredTable.extract(from: blocks),
            richTextData: serializedRichText
        )
    }

    func attributedString() -> NSAttributedString {
        if let richTextData,
           let richText = try? NSAttributedString(
               data: richTextData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return richText
        }

        // Compatibility path for pre-v2 JSON that has semantic blocks but no
        // RTF snapshot. New documents take the lossless path above.
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = block.alignment.nsTextAlignment
            paragraph.lineSpacing = CGFloat(block.lineSpacing)
            paragraph.paragraphSpacing = CGFloat(block.paragraphSpacing)
            paragraph.paragraphSpacingBefore = CGFloat(block.paragraphSpacingBefore)
            paragraph.headIndent = CGFloat(block.headIndent)
            paragraph.firstLineHeadIndent = CGFloat(block.firstLineHeadIndent)
            paragraph.tailIndent = CGFloat(block.tailIndent)
            paragraph.lineHeightMultiple = CGFloat(block.lineHeightMultiple)
            paragraph.minimumLineHeight = CGFloat(block.minimumLineHeight)
            paragraph.maximumLineHeight = CGFloat(block.maximumLineHeight)
            if let lineBreakMode = block.lineBreakMode {
                paragraph.lineBreakMode = NSLineBreakMode(rawValue: lineBreakMode) ?? .byWordWrapping
            }
            if block.listStyle != nil {
                paragraph.headIndent = max(paragraph.headIndent, 22)
                paragraph.firstLineHeadIndent = min(paragraph.firstLineHeadIndent, -12)
            }

            for run in block.runs {
                let font = font(for: block, run: run)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: run.foregroundColor?.nsColor ?? NSColor.black,
                    .paragraphStyle: paragraph
                ]
                if let backgroundColor = run.backgroundColor?.nsColor { attrs[.backgroundColor] = backgroundColor }
                if let underlineStyle = run.underlineStyle { attrs[.underlineStyle] = underlineStyle }
                else if run.marks.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if let strikethroughStyle = run.strikethroughStyle { attrs[.strikethroughStyle] = strikethroughStyle }
                else if run.marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let underlineColor = run.underlineColor?.nsColor { attrs[.underlineColor] = underlineColor }
                if let strikethroughColor = run.strikethroughColor?.nsColor { attrs[.strikethroughColor] = strikethroughColor }
                if let baselineOffset = run.baselineOffset { attrs[.baselineOffset] = baselineOffset }
                if let kern = run.kern { attrs[.kern] = kern }
                if let link = run.link { attrs[.link] = link }
                result.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            if index < blocks.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    private func font(for block: StructuredBlock, run: StructuredRun) -> NSFont {
        let defaultSize: CGFloat
        switch block.kind {
        case .heading(let level):
            switch level {
            case 1: defaultSize = EditorTypography.heading1PointSize
            case 2: defaultSize = EditorTypography.heading2PointSize
            case 3: defaultSize = EditorTypography.heading3PointSize
            default: defaultSize = EditorTypography.bodyPointSize
            }
        default: defaultSize = EditorTypography.bodyPointSize
        }
        let size = CGFloat(run.fontSize ?? Double(defaultSize))
        let baseName = run.fontName ?? run.fontFamily ?? "Times New Roman"
        let base = NSFont(name: baseName, size: size) ?? NSFont.systemFont(ofSize: size)

        var traits = run.fontTraits.map(NSFontDescriptor.SymbolicTraits.init(rawValue:)) ?? base.fontDescriptor.symbolicTraits
        if run.marks.contains(.bold) || block.kind.isHeading { traits.insert(.bold) }
        if run.marks.contains(.italic) { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

struct StructuredTable: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var rows: [[String]]

    init(id: UUID = UUID(), rows: [[String]] = []) {
        self.id = id
        self.rows = rows
    }

    var columnCount: Int { rows.map(\.count).max() ?? 0 }

    fileprivate static func extract(from blocks: [StructuredBlock]) -> [StructuredTable] {
        var tables: [StructuredTable] = []
        var pendingRows: [[String]] = []

        func flush() {
            guard pendingRows.count >= 2 else {
                pendingRows.removeAll()
                return
            }
            tables.append(StructuredTable(rows: pendingRows))
            pendingRows.removeAll()
        }

        for block in blocks {
            let cells = block.plainText
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            if cells.count > 1 {
                pendingRows.append(cells)
            } else {
                flush()
            }
        }
        flush()
        return tables
    }
}

struct StructuredBlock: Codable, Equatable, Hashable, Identifiable {
    enum Kind: Codable, Equatable, Hashable {
        case paragraph
        case heading(level: Int)
        case pageBreak

        var isHeading: Bool {
            if case .heading = self { return true }
            return false
        }
    }

    var id: UUID
    var kind: Kind
    var alignment: StructuredAlignment
    var listStyle: StructuredListStyle?
    var listOrdinal: Int?
    var lineSpacing: Double
    var paragraphSpacing: Double
    var paragraphSpacingBefore: Double
    var headIndent: Double
    var firstLineHeadIndent: Double
    var tailIndent: Double
    var lineHeightMultiple: Double
    var minimumLineHeight: Double
    var maximumLineHeight: Double
    var lineBreakMode: UInt?
    var runs: [StructuredRun]

    init(
        id: UUID = UUID(),
        kind: Kind = .paragraph,
        alignment: StructuredAlignment = .leading,
        listStyle: StructuredListStyle? = nil,
        listOrdinal: Int? = nil,
        lineSpacing: Double = 2,
        paragraphSpacing: Double = 10,
        paragraphSpacingBefore: Double = 0,
        headIndent: Double = 0,
        firstLineHeadIndent: Double = 0,
        tailIndent: Double = 0,
        lineHeightMultiple: Double = 0,
        minimumLineHeight: Double = 0,
        maximumLineHeight: Double = 0,
        lineBreakMode: UInt? = nil,
        runs: [StructuredRun] = []
    ) {
        self.id = id
        self.kind = kind
        self.alignment = alignment
        self.listStyle = listStyle
        self.listOrdinal = listOrdinal
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.headIndent = headIndent
        self.firstLineHeadIndent = firstLineHeadIndent
        self.tailIndent = tailIndent
        self.lineHeightMultiple = lineHeightMultiple
        self.minimumLineHeight = minimumLineHeight
        self.maximumLineHeight = maximumLineHeight
        self.lineBreakMode = lineBreakMode
        self.runs = runs
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, alignment, listStyle, listOrdinal, lineSpacing, paragraphSpacing, paragraphSpacingBefore
        case headIndent, firstLineHeadIndent, tailIndent, lineHeightMultiple
        case minimumLineHeight, maximumLineHeight, lineBreakMode, runs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .paragraph
        alignment = try container.decodeIfPresent(StructuredAlignment.self, forKey: .alignment) ?? .leading
        listStyle = try container.decodeIfPresent(StructuredListStyle.self, forKey: .listStyle)
        listOrdinal = try container.decodeIfPresent(Int.self, forKey: .listOrdinal)
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 2
        paragraphSpacing = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 10
        paragraphSpacingBefore = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacingBefore) ?? 0
        headIndent = try container.decodeIfPresent(Double.self, forKey: .headIndent) ?? 0
        firstLineHeadIndent = try container.decodeIfPresent(Double.self, forKey: .firstLineHeadIndent) ?? 0
        tailIndent = try container.decodeIfPresent(Double.self, forKey: .tailIndent) ?? 0
        lineHeightMultiple = try container.decodeIfPresent(Double.self, forKey: .lineHeightMultiple) ?? 0
        minimumLineHeight = try container.decodeIfPresent(Double.self, forKey: .minimumLineHeight) ?? 0
        maximumLineHeight = try container.decodeIfPresent(Double.self, forKey: .maximumLineHeight) ?? 0
        lineBreakMode = try container.decodeIfPresent(UInt.self, forKey: .lineBreakMode)
        runs = try container.decodeIfPresent([StructuredRun].self, forKey: .runs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(alignment, forKey: .alignment)
        try container.encodeIfPresent(listStyle, forKey: .listStyle)
        try container.encodeIfPresent(listOrdinal, forKey: .listOrdinal)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try container.encode(paragraphSpacingBefore, forKey: .paragraphSpacingBefore)
        try container.encode(headIndent, forKey: .headIndent)
        try container.encode(firstLineHeadIndent, forKey: .firstLineHeadIndent)
        try container.encode(tailIndent, forKey: .tailIndent)
        try container.encode(lineHeightMultiple, forKey: .lineHeightMultiple)
        try container.encode(minimumLineHeight, forKey: .minimumLineHeight)
        try container.encode(maximumLineHeight, forKey: .maximumLineHeight)
        try container.encodeIfPresent(lineBreakMode, forKey: .lineBreakMode)
        try container.encode(runs, forKey: .runs)
    }

    var plainText: String { runs.map(\.text).joined() }
}

struct StructuredRun: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var marks: Set<StructuredMark>
    var link: URL?

    var fontFamily: String?
    var fontName: String?
    var fontSize: Double?
    var fontTraits: UInt32?
    var foregroundColor: StructuredColor?
    var backgroundColor: StructuredColor?
    var underlineStyle: Int?
    var strikethroughStyle: Int?
    var underlineColor: StructuredColor?
    var strikethroughColor: StructuredColor?
    var baselineOffset: Double?
    var kern: Double?

    init(
        id: UUID = UUID(),
        text: String,
        marks: Set<StructuredMark> = [],
        link: URL? = nil,
        fontFamily: String? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        fontTraits: UInt32? = nil,
        foregroundColor: StructuredColor? = nil,
        backgroundColor: StructuredColor? = nil,
        underlineStyle: Int? = nil,
        strikethroughStyle: Int? = nil,
        underlineColor: StructuredColor? = nil,
        strikethroughColor: StructuredColor? = nil,
        baselineOffset: Double? = nil,
        kern: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.marks = marks
        self.link = link
        self.fontFamily = fontFamily
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontTraits = fontTraits
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.underlineStyle = underlineStyle
        self.strikethroughStyle = strikethroughStyle
        self.underlineColor = underlineColor
        self.strikethroughColor = strikethroughColor
        self.baselineOffset = baselineOffset
        self.kern = kern
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, marks, link, fontFamily, fontName, fontSize, fontTraits
        case foregroundColor, backgroundColor, underlineStyle, strikethroughStyle
        case underlineColor, strikethroughColor, baselineOffset, kern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        marks = try container.decodeIfPresent(Set<StructuredMark>.self, forKey: .marks) ?? []
        link = try container.decodeIfPresent(URL.self, forKey: .link)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        fontTraits = try container.decodeIfPresent(UInt32.self, forKey: .fontTraits)
        foregroundColor = try container.decodeIfPresent(StructuredColor.self, forKey: .foregroundColor)
        backgroundColor = try container.decodeIfPresent(StructuredColor.self, forKey: .backgroundColor)
        underlineStyle = try container.decodeIfPresent(Int.self, forKey: .underlineStyle)
        strikethroughStyle = try container.decodeIfPresent(Int.self, forKey: .strikethroughStyle)
        underlineColor = try container.decodeIfPresent(StructuredColor.self, forKey: .underlineColor)
        strikethroughColor = try container.decodeIfPresent(StructuredColor.self, forKey: .strikethroughColor)
        baselineOffset = try container.decodeIfPresent(Double.self, forKey: .baselineOffset)
        kern = try container.decodeIfPresent(Double.self, forKey: .kern)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(marks, forKey: .marks)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try container.encodeIfPresent(fontName, forKey: .fontName)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
        try container.encodeIfPresent(fontTraits, forKey: .fontTraits)
        try container.encodeIfPresent(foregroundColor, forKey: .foregroundColor)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(underlineStyle, forKey: .underlineStyle)
        try container.encodeIfPresent(strikethroughStyle, forKey: .strikethroughStyle)
        try container.encodeIfPresent(underlineColor, forKey: .underlineColor)
        try container.encodeIfPresent(strikethroughColor, forKey: .strikethroughColor)
        try container.encodeIfPresent(baselineOffset, forKey: .baselineOffset)
        try container.encodeIfPresent(kern, forKey: .kern)
    }

    static func runs(in value: NSAttributedString, range: NSRange) -> [StructuredRun] {
        let source = value.string as NSString
        var output: [StructuredRun] = []
        value.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            let font = attrs[.font] as? NSFont
            var marks: Set<StructuredMark> = []
            if font?.fontDescriptor.symbolicTraits.contains(.bold) == true { marks.insert(.bold) }
            if font?.fontDescriptor.symbolicTraits.contains(.italic) == true { marks.insert(.italic) }

            let underlineStyle = numberValue(attrs[.underlineStyle])
            let strikethroughStyle = numberValue(attrs[.strikethroughStyle])
            if underlineStyle != 0 { marks.insert(.underline) }
            if strikethroughStyle != 0 { marks.insert(.strikethrough) }
            let link: URL?
            if let url = attrs[.link] as? URL {
                link = url
            } else if let url = attrs[.link] as? NSURL {
                link = url as URL
            } else if let string = attrs[.link] as? String {
                link = URL(string: string)
            } else {
                link = nil
            }

            output.append(StructuredRun(
                text: source.substring(with: subrange),
                marks: marks,
                link: link,
                fontFamily: font?.familyName,
                fontName: font?.fontName,
                fontSize: font.map { Double($0.pointSize) },
                fontTraits: font.map { $0.fontDescriptor.symbolicTraits.rawValue },
                foregroundColor: StructuredColor(nsColor: attrs[.foregroundColor] as? NSColor),
                backgroundColor: StructuredColor(nsColor: attrs[.backgroundColor] as? NSColor),
                underlineStyle: underlineStyle == 0 ? nil : underlineStyle,
                strikethroughStyle: strikethroughStyle == 0 ? nil : strikethroughStyle,
                underlineColor: StructuredColor(nsColor: attrs[.underlineColor] as? NSColor),
                strikethroughColor: StructuredColor(nsColor: attrs[.strikethroughColor] as? NSColor),
                baselineOffset: numberOptional(attrs[.baselineOffset]),
                kern: numberOptional(attrs[.kern])
            ))
        }
        return output
    }
}

private func numberValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber { return number.intValue }
    if let value = value as? Int { return value }
    return 0
}

private func numberOptional(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let value = value as? Double { return value }
    if let value = value as? CGFloat { return Double(value) }
    return nil
}

struct StructuredColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init?(nsColor: NSColor?) {
        guard let nsColor,
              let rgb = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        red = Double(rgb.redComponent)
        green = Double(rgb.greenComponent)
        blue = Double(rgb.blueComponent)
        alpha = Double(rgb.alphaComponent)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

enum StructuredMark: String, Codable, Hashable {
    case bold, italic, underline, strikethrough
}

enum StructuredListStyle: String, Codable, Hashable {
    case unordered
    case ordered
}

enum StructuredAlignment: String, Codable, Hashable {
    case leading, center, trailing, justified

    init(_ value: NSTextAlignment) {
        switch value {
        case .center: self = .center
        case .right: self = .trailing
        case .justified: self = .justified
        default: self = .leading
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .center: return .center
        case .trailing: return .right
        case .justified: return .justified
        case .leading: return .left
        }
    }
}
