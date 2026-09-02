import Foundation

/// A small, source-grounded excerpt used to show where a review applies.
struct DocumentReviewSourceContext: Equatable, Sendable {
    let prefix: String
    let original: String
    let suffix: String
    let sourceRange: DocumentTextRange
    let hasPreviousText: Bool
    let hasNextText: Bool

    /// Builds a context only when the persisted range still matches the source.
    static func make(
        for item: DocumentReviewItem,
        in sourceText: String,
        surroundingUTF16Length: Int = 160
    ) -> DocumentReviewSourceContext? {
        guard surroundingUTF16Length >= 0,
              item.isActionable,
              let sourceRange = item.sourceRange,
              sourceRange.isValid(inUTF16Length: sourceText.utf16.count)
        else {
            return nil
        }

        let text = sourceText as NSString
        let range = sourceRange.nsRange
        guard !item.original.isEmpty,
              text.substring(with: range) == item.original,
              hasUniqueMatch(for: item.original, in: text, matching: range)
        else {
            return nil
        }

        let textLength = text.length
        let requestedStart = max(0, range.location - surroundingUTF16Length)
        let requestedEnd = min(textLength, NSMaxRange(range) + surroundingUTF16Length)
        let contextStart = safeStart(requestedStart, in: text)
        let contextEnd = safeEnd(requestedEnd, in: text)

        return DocumentReviewSourceContext(
            prefix: text.substring(with: NSRange(
                location: contextStart,
                length: range.location - contextStart
            )),
            original: item.original,
            suffix: text.substring(with: NSRange(
                location: NSMaxRange(range),
                length: contextEnd - NSMaxRange(range)
            )),
            sourceRange: sourceRange,
            hasPreviousText: contextStart > 0,
            hasNextText: contextEnd < textLength
        )
    }

    private static func hasUniqueMatch(
        for original: String,
        in text: NSString,
        matching range: NSRange
    ) -> Bool {
        var matchCount = 0
        var matchingRange: NSRange?
        var searchLocation = 0

        while searchLocation < text.length {
            let match = text.range(
                of: original,
                options: .literal,
                range: NSRange(
                    location: searchLocation,
                    length: text.length - searchLocation
                ),
                locale: nil
            )
            guard match.location != NSNotFound else { break }

            matchCount += 1
            matchingRange = match
            if matchCount > 1 {
                return false
            }
            searchLocation = match.location + 1
        }

        return matchCount == 1
            && matchingRange.map { NSEqualRanges($0, range) } == true
    }

    private static func safeStart(_ offset: Int, in text: NSString) -> Int {
        guard offset > 0,
              offset < text.length,
              isLowSurrogate(text.character(at: offset))
        else {
            return offset
        }
        return offset - 1
    }

    private static func safeEnd(_ offset: Int, in text: NSString) -> Int {
        guard offset > 0,
              offset < text.length,
              isLowSurrogate(text.character(at: offset))
        else {
            return offset
        }
        return min(offset + 1, text.length)
    }

    private static func isLowSurrogate(_ value: unichar) -> Bool {
        (0xDC00...0xDFFF).contains(Int(value))
    }
}
