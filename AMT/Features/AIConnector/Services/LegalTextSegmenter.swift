import Foundation
import NaturalLanguage

struct LegalTextSegmenter: Sendable {
    static let maximumSegments = 12

    private static let longSentenceCharacterThreshold = 2_048

    func segment(documentText: String) -> AITextSegmentationResult {
        guard !documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AITextSegmentationResult(
                segments: [],
                headingCount: 0,
                tooLongSegmentCount: 0,
                omittedSegmentCount: 0
            )
        }

        var rawSegments: [RawSegment] = []
        var headingCount = 0

        documentText.enumerateSubstrings(
            in: documentText.startIndex..<documentText.endIndex,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, _ in
            let paragraph = String(documentText[paragraphRange])
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParagraph.isEmpty else { return }

            if Self.isShortHeading(trimmedParagraph) {
                headingCount += 1
                return
            }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = paragraph
            tokenizer.setLanguage(.indonesian)

            var sentenceRanges: [Range<String.Index>] = []
            tokenizer.enumerateTokens(
                in: paragraph.startIndex..<paragraph.endIndex
            ) { range, _ in
                sentenceRanges.append(range)
                return true
            }

            if sentenceRanges.isEmpty {
                sentenceRanges = [paragraph.startIndex..<paragraph.endIndex]
            }

            for sentenceRange in sentenceRanges {
                guard let trimmedSentenceRange = Self.trimmedRange(sentenceRange, in: paragraph) else {
                    continue
                }
                let sentence = String(paragraph[trimmedSentenceRange])

                let ranges = Self.shouldSplit(sentence)
                    ? Self.semicolonParts(in: sentence)
                    : [sentence.startIndex..<sentence.endIndex]

                for partRange in ranges {
                    let part = String(sentence[partRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !part.isEmpty else { continue }

                    let paragraphOffset = NSRange(paragraphRange, in: documentText).location
                    let sentenceOffset = NSRange(trimmedSentenceRange, in: paragraph).location
                    let partOffset = NSRange(partRange, in: sentence).location
                    let sourceLocation = paragraphOffset + sentenceOffset + partOffset
                    let sourceLength = part.utf16.count

                    rawSegments.append(
                        RawSegment(
                            sourceLocation: sourceLocation,
                            sourceLength: sourceLength,
                            text: part
                        )
                    )
                }
            }
        }

        let selectedSegments = Array(rawSegments.prefix(Self.maximumSegments))
        let omittedSegmentCount = max(0, rawSegments.count - selectedSegments.count)
        let segments = selectedSegments.enumerated().map { offset, rawSegment in
            AIReviewSegment(
                id: offset + 1,
                sourceLocation: rawSegment.sourceLocation,
                sourceLength: rawSegment.sourceLength,
                targetText: rawSegment.text,
                previousContext: offset > 0 ? rawSegments[offset - 1].text : nil,
                nextContext: offset + 1 < rawSegments.count
                    ? rawSegments[offset + 1].text
                    : nil
            )
        }

        return AITextSegmentationResult(
            segments: segments,
            headingCount: headingCount,
            tooLongSegmentCount: 0,
            omittedSegmentCount: omittedSegmentCount
        )
    }

    private static func isShortHeading(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, text.count <= 120 else { return false }
        return letters.allSatisfy { String($0) == String($0).uppercased() }
    }

    private static func shouldSplit(_ sentence: String) -> Bool {
        sentence.utf16.count > longSentenceCharacterThreshold && sentence.contains(";")
    }

    private static func semicolonParts(in sentence: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var partStart = sentence.startIndex

        for index in sentence.indices where sentence[index] == ";" {
            let partEnd = sentence.index(after: index)
            if let trimmed = trimmedRange(partStart..<partEnd, in: sentence) {
                ranges.append(trimmed)
            }
            partStart = partEnd
        }

        if let trimmed = trimmedRange(partStart..<sentence.endIndex, in: sentence) {
            ranges.append(trimmed)
        }

        return ranges.isEmpty ? [sentence.startIndex..<sentence.endIndex] : ranges
    }

    private static func trimmedRange(
        _ range: Range<String.Index>,
        in text: String
    ) -> Range<String.Index>? {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound

        while lowerBound < upperBound, text[lowerBound].isWhitespace {
            lowerBound = text.index(after: lowerBound)
        }

        while lowerBound < upperBound {
            let previous = text.index(before: upperBound)
            guard text[previous].isWhitespace else { break }
            upperBound = previous
        }

        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }

    private struct RawSegment: Sendable {
        let sourceLocation: Int
        let sourceLength: Int
        let text: String
    }
}
