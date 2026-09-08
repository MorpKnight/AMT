import CryptoKit
import Foundation

/// Builds an editor-relative structure map without trying to reconstruct rich
/// document metadata that is no longer present in the imported text.
struct AIConnectorDocumentStructureBuilder: Sendable {
    static let version = AIConnectorDocumentStructure.currentVersion

    func build(
        documentText: String,
        structuredDocument: StructuredDocument? = nil
    ) -> AIConnectorDocumentStructure {
        let paragraphs = paragraphRecords(
            in: documentText,
            structuredDocument: structuredDocument
        )
        guard !paragraphs.isEmpty else {
            return AIConnectorDocumentStructure(
                blocks: [],
                sections: [],
                headingCount: 0,
                parserVersion: Self.version,
                fingerprint: fingerprint(documentText: documentText, blocks: [])
            )
        }

        var occurrenceBySectionTitle: [String: Int] = [:]
        var stack: [HeadingInfo] = []
        var headings: [HeadingInfo] = []

        for (index, paragraph) in paragraphs.enumerated() {
            guard paragraph.kind == .heading else { continue }
            let level = paragraph.headingLevel ?? 1
            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            let parentID = stack.last?.id
            let key = "\(parentID ?? "root")|\(paragraph.text)"
            let occurrence = occurrenceBySectionTitle[key, default: 0]
            occurrenceBySectionTitle[key] = occurrence + 1
            let id = stableID(
                kind: "section",
                parent: parentID,
                text: paragraph.text,
                occurrence: occurrence
            )
            let path = (stack.map(\.title) + [paragraph.text])
            let info = HeadingInfo(
                paragraphIndex: index,
                id: id,
                title: paragraph.text,
                level: level,
                parentID: parentID,
                path: path
            )
            stack.append(info)
            headings.append(info)
        }

        let documentLength = (documentText as NSString).length
        let sections = headings.map { heading in
            let nextBoundary = headings.drop(while: { $0.paragraphIndex <= heading.paragraphIndex })
                .first { $0.level <= heading.level }
            let start = paragraphs[heading.paragraphIndex].sourceRange.location
            let end = nextBoundary.map {
                paragraphs[$0.paragraphIndex].sourceRange.location
            } ?? documentLength
            return AIConnectorDocumentSection(
                id: heading.id,
                title: heading.title,
                headingBlockID: heading.id,
                sourceRange: NSRange(location: start, length: max(0, end - start)),
                parentSectionID: heading.parentID,
                headingPath: heading.path
            )
        }

        var occurrenceByBlock: [String: Int] = [:]
        var blocks: [AIConnectorDocumentBlock] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let heading = headings.first { $0.paragraphIndex == index }
            let section = sectionContaining(
                paragraph.sourceRange.location,
                sections: sections
            )
            let sectionID = heading?.id ?? section?.id
            let headingPath = heading?.path ?? section?.headingPath ?? []
            let blockID: String
            if let heading {
                blockID = heading.id
            } else {
                let key = "\(sectionID ?? "root")|\(paragraph.kind.rawValue)|\(paragraph.text)"
                let occurrence = occurrenceByBlock[key, default: 0]
                occurrenceByBlock[key] = occurrence + 1
                blockID = stableID(
                    kind: paragraph.kind.rawValue,
                    parent: sectionID,
                    text: paragraph.text,
                    occurrence: occurrence
                )
            }
            blocks.append(
                AIConnectorDocumentBlock(
                    id: blockID,
                    kind: paragraph.kind,
                    sourceRange: paragraph.sourceRange,
                    text: paragraph.text,
                    parentSectionID: sectionID,
                    headingPath: headingPath,
                    numberingLabel: paragraph.numberingLabel,
                    previousBlockID: nil,
                    nextBlockID: nil
                )
            )
        }

        let siblingGroups = Dictionary(grouping: blocks.indices) {
            blocks[$0].parentSectionID ?? "root"
        }
        for indices in siblingGroups.values {
            for (offset, index) in indices.enumerated() {
                let previous = offset > 0 ? blocks[indices[offset - 1]].id : nil
                let next = offset + 1 < indices.count ? blocks[indices[offset + 1]].id : nil
                let block = blocks[index]
                blocks[index] = AIConnectorDocumentBlock(
                    id: block.id,
                    kind: block.kind,
                    sourceRange: block.sourceRange,
                    text: block.text,
                    parentSectionID: block.parentSectionID,
                    headingPath: block.headingPath,
                    numberingLabel: block.numberingLabel,
                    previousBlockID: previous,
                    nextBlockID: next
                )
            }
        }

        return AIConnectorDocumentStructure(
            blocks: blocks,
            sections: sections,
            headingCount: headings.count,
            parserVersion: Self.version,
            fingerprint: fingerprint(documentText: documentText, blocks: blocks)
        )
    }

    private func paragraphRecords(
        in documentText: String,
        structuredDocument: StructuredDocument?
    ) -> [RawBlock] {
        let nsText = documentText as NSString
        var metadataIndex = 0
        var result: [RawBlock] = []

        documentText.enumerateSubstrings(
            in: documentText.startIndex..<documentText.endIndex,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, _ in
            let rawRange = NSRange(paragraphRange, in: documentText)
            var contentRange = rawRange
            while contentRange.length > 0 {
                let character = nsText.character(at: NSMaxRange(contentRange) - 1)
                guard character == 10 || character == 13 || character == 0x2028 || character == 0x2029 else {
                    break
                }
                contentRange.length -= 1
            }
            let rawValue = nsText.substring(with: contentRange)
            let leadingTrim = rawValue
                .prefix { $0.isWhitespace }
                .utf16
                .count
            let trailingTrim = String(rawValue.reversed().prefix { $0.isWhitespace })
                .utf16
                .count
            let valueStart = contentRange.location + leadingTrim
            let valueLength = max(0, contentRange.length - leadingTrim - trailingTrim)
            guard valueLength > 0 else { return }

            let value = nsText.substring(with: NSRange(location: valueStart, length: valueLength))
            let metadata = matchingMetadata(
                value: value,
                structuredDocument: structuredDocument,
                metadataIndex: &metadataIndex
            )

            let cells = splitCells(
                value: value,
                sourceLocation: valueStart
            )
            for cell in cells {
                let kind: AIConnectorDocumentBlockKind
                let headingLevel: Int?
                let listLabel: String?
                if cells.count > 1 {
                    kind = .tableCell
                    headingLevel = nil
                    listLabel = nil
                } else if let metadata {
                    kind = metadata.kind
                    headingLevel = metadata.headingLevel
                    listLabel = metadata.numberingLabel
                } else {
                    kind = fallbackKind(for: cell.text)
                    headingLevel = fallbackHeadingLevel(for: cell.text)
                    listLabel = numberingLabel(in: cell.text)
                }

                result.append(
                    RawBlock(
                        kind: kind,
                        headingLevel: headingLevel,
                        sourceRange: cell.sourceRange,
                        text: cell.text,
                        numberingLabel: listLabel
                    )
                )
            }
        }
        return result
    }

    private func matchingMetadata(
        value: String,
        structuredDocument: StructuredDocument?,
        metadataIndex: inout Int
    ) -> Metadata? {
        guard let structuredDocument else { return nil }
        while metadataIndex < structuredDocument.blocks.count {
            let block = structuredDocument.blocks[metadataIndex]
            let expected = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard expected == value else { return nil }
            metadataIndex += 1
            let kind: AIConnectorDocumentBlockKind
            let level: Int?
            switch block.kind {
            case let .heading(value):
                kind = .heading
                level = value
            case .paragraph:
                kind = block.listStyle == nil ? .paragraph : .listItem
                level = nil
            case .pageBreak:
                kind = .unknown
                level = nil
            }
            return Metadata(
                kind: kind,
                headingLevel: level,
                numberingLabel: block.listOrdinal.map(String.init)
            )
        }
        return nil
    }

    private func splitCells(value: String, sourceLocation: Int) -> [Cell] {
        guard value.contains("\t") else {
            return [Cell(text: value, sourceRange: NSRange(location: sourceLocation, length: value.utf16.count))]
        }
        var result: [Cell] = []
        var cellStart = value.startIndex
        for index in value.indices where value[index] == "\t" {
            appendCell(
                from: cellStart..<index,
                in: value,
                sourceLocation: sourceLocation,
                to: &result
            )
            cellStart = value.index(after: index)
        }
        appendCell(
            from: cellStart..<value.endIndex,
            in: value,
            sourceLocation: sourceLocation,
            to: &result
        )
        return result.isEmpty ? [Cell(text: value, sourceRange: NSRange(location: sourceLocation, length: value.utf16.count))] : result
    }

    private func appendCell(
        from range: Range<String.Index>,
        in value: String,
        sourceLocation: Int,
        to result: inout [Cell]
    ) {
        let rawText = String(value[range])
        let leading = rawText.prefix { $0.isWhitespace }.utf16.count
        let trailing = String(rawText.reversed().prefix { $0.isWhitespace })
            .utf16
            .count
        let textLength = max(0, rawText.utf16.count - leading - trailing)
        let text = textLength > 0
            ? (rawText as NSString).substring(with: NSRange(location: leading, length: textLength))
            : ""
        guard !text.isEmpty else { return }
        let offset = NSRange(value.startIndex..<range.lowerBound, in: value).length + leading
        result.append(
            Cell(
                text: text,
                sourceRange: NSRange(
                    location: sourceLocation + offset,
                    length: text.utf16.count
                )
            )
        )
    }

    private func fallbackKind(for text: String) -> AIConnectorDocumentBlockKind {
        if fallbackHeadingLevel(for: text) != nil { return .heading }
        if text.range(of: #"^(?:Pasal\s+)?\d+(?:\.\d+)*\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .numberedClause
        }
        if text.range(of: #"^(?:\(?[A-Za-z0-9]+[.)]|[-•])\s+"#, options: .regularExpression) != nil {
            return .listItem
        }
        return .paragraph
    }

    private func fallbackHeadingLevel(for text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count <= 160, !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("BAB ") || upper.hasPrefix("BAGIAN ") || upper.hasPrefix("JUDUL ") {
            return 1
        }
        if upper.hasPrefix("SUBBAGIAN ") || upper.hasPrefix("PASAL ") {
            return 2
        }
        let letters = trimmed.filter(\.isLetter)
        if letters.count >= 3, letters.allSatisfy({ String($0) == String($0).uppercased() }) {
            return 1
        }
        return nil
    }

    private func numberingLabel(in text: String) -> String? {
        let pattern = #"^(?:Pasal\s+\d+(?:\.\d+)*|\d+(?:\.\d+)*|\([A-Za-z0-9]+\)|[A-Za-z0-9]+[.)])"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[match])
    }

    private func sectionContaining(
        _ location: Int,
        sections: [AIConnectorDocumentSection]
    ) -> AIConnectorDocumentSection? {
        sections.last {
            NSLocationInRange(location, $0.sourceRange)
                || location == $0.sourceRange.location
        }
    }

    private func stableID(
        kind: String,
        parent: String?,
        text: String,
        occurrence: Int
    ) -> String {
        let material = [kind, parent ?? "root", text, String(occurrence)].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprint(
        documentText: String,
        blocks: [AIConnectorDocumentBlock]
    ) -> String {
        let material = documentText + "|" + blocks.map {
            "\($0.id):\($0.kind.rawValue):\($0.sourceRange.location):\($0.sourceRange.length):\($0.parentSectionID ?? "-")"
        }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct RawBlock: Sendable {
        let kind: AIConnectorDocumentBlockKind
        let headingLevel: Int?
        let sourceRange: NSRange
        let text: String
        let numberingLabel: String?
    }

    private struct Metadata: Sendable {
        let kind: AIConnectorDocumentBlockKind
        let headingLevel: Int?
        let numberingLabel: String?
    }

    private struct Cell: Sendable {
        let text: String
        let sourceRange: NSRange
    }

    private struct HeadingInfo: Sendable {
        let paragraphIndex: Int
        let id: String
        let title: String
        let level: Int
        let parentID: String?
        let path: [String]
    }
}
