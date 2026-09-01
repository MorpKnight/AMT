import Foundation

enum DocumentReviewMapper {
    /// Maps validated AI reviews to the original source text, failing closed for ambiguity.
    static func make(
        reviews: [AIValidatedReview],
        sourceText: String
    ) -> [DocumentReviewItem] {
        var items = reviews.compactMap { review -> DocumentReviewItem? in
            guard review.status == .suggestion,
                  let original = review.original,
                  let replacement = review.replacement,
                  !original.isEmpty,
                  !replacement.isEmpty,
                  original != replacement
            else {
                return nil
            }

            let analysisMatches = ranges(of: original, in: review.segment.targetText)
            let sourceMatches = ranges(of: original, in: sourceText)
            let mappingIssue: DocumentReviewMappingIssue?

            if analysisMatches.isEmpty {
                mappingIssue = .missingFromAnalysis
            } else if analysisMatches.count > 1 {
                mappingIssue = .ambiguousInAnalysis
            } else if sourceMatches.isEmpty {
                mappingIssue = .missingFromSource
            } else if sourceMatches.count > 1 {
                mappingIssue = .ambiguousInSource
            } else {
                mappingIssue = nil
            }

            let sourceRange = sourceMatches.count == 1
                ? DocumentTextRange(sourceMatches[0])
                : nil
            let isActionable = mappingIssue == nil && sourceRange != nil

            return DocumentReviewItem(
                id: review.id,
                segmentID: review.segment.id,
                original: original,
                replacement: replacement,
                category: review.category,
                reason: review.reason,
                origin: review.origin,
                reference: reference(from: review),
                sourceRange: sourceRange,
                decision: isActionable ? .pending : .unavailable,
                mappingIssue: mappingIssue
            )
        }

        markOverlaps(in: &items)
        return items
    }

    private static func ranges(of substring: String, in text: String) -> [NSRange] {
        guard !substring.isEmpty else { return [] }

        let wholeRange = NSRange(location: 0, length: text.utf16.count)
        let nsText = text as NSString
        var matches: [NSRange] = []
        var searchLocation = 0

        while searchLocation < wholeRange.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: wholeRange.length - searchLocation
            )
            let match = nsText.range(
                of: substring,
                options: .literal,
                range: searchRange,
                locale: nil
            )
            guard match.location != NSNotFound else { break }
            matches.append(match)
            // Advance by one UTF-16 code unit so overlapping occurrences are
            // also treated as ambiguous instead of accidentally actionable.
            searchLocation = match.location + 1
        }

        return matches
    }

    private static func markOverlaps(in items: inout [DocumentReviewItem]) {
        for leftIndex in items.indices {
            guard let leftRange = items[leftIndex].sourceRange?.nsRange else { continue }

            for rightIndex in items.indices where rightIndex > leftIndex {
                guard let rightRange = items[rightIndex].sourceRange?.nsRange else { continue }
                guard NSIntersectionRange(leftRange, rightRange).length > 0 else { continue }

                items[leftIndex].decision = .unavailable
                items[leftIndex].mappingIssue = .overlapsAnotherChange
                items[rightIndex].decision = .unavailable
                items[rightIndex].mappingIssue = .overlapsAnotherChange
            }
        }
    }

    private static func reference(from review: AIValidatedReview) -> DocumentReviewReference? {
        guard review.category == .terminology,
              let match = review.glossaryMatch
        else {
            return nil
        }

        return DocumentReviewReference(
            term: match.entry.term,
            regulation: match.entry.regulation,
            regulationTitle: match.entry.regulationTitle,
            sourceURL: match.entry.sourceURL
        )
    }
}
