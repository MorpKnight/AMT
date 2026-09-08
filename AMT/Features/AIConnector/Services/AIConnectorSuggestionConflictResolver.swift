import Foundation

struct AIConnectorSuggestionConflictResolver: Sendable {
    static let maximumSuggestionsPerSegment = 3

    func resolve(_ reviews: [AIValidatedReview]) -> [AIValidatedReview] {
        let nonActionable = reviews.filter { $0.status != .suggestion }
        let actionable = reviews
            .filter { $0.status == .suggestion }
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs)
                let rhsPriority = priority(for: rhs)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

                let lhsLength = lhs.original?.utf16.count ?? Int.max
                let rhsLength = rhs.original?.utf16.count ?? Int.max
                if lhsLength != rhsLength { return lhsLength < rhsLength }
                let lhsLocation = sourceRange(for: lhs)?.location ?? Int.max
                let rhsLocation = sourceRange(for: rhs)?.location ?? Int.max
                if lhsLocation != rhsLocation { return lhsLocation < rhsLocation }
                if lhs.segment.id != rhs.segment.id { return lhs.segment.id < rhs.segment.id }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var accepted: [AIValidatedReview] = []
        var countsBySegment: [Int: Int] = [:]

        for review in actionable {
            guard let localRange = sourceRange(for: review),
                  countsBySegment[review.segment.id, default: 0]
                    < Self.maximumSuggestionsPerSegment else {
                continue
            }

            let conflicts = accepted.contains { other in
                guard other.segment.id == review.segment.id,
                      let otherRange = sourceRange(for: other) else {
                    return false
                }
                return NSIntersectionRange(localRange, otherRange).length > 0
            }
            guard !conflicts else { continue }

            accepted.append(review)
            countsBySegment[review.segment.id, default: 0] += 1
        }

        return (nonActionable + accepted).sorted { lhs, rhs in
            if lhs.segment.id != rhs.segment.id { return lhs.segment.id < rhs.segment.id }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sourceRange(for review: AIValidatedReview) -> NSRange? {
        guard let original = review.original else { return nil }
        if let anchor = review.sourceAnchor {
            return anchor.isValid(for: review.segment, original: original)
                ? anchor.range
                : nil
        }
        return uniqueRange(of: original, in: review.segment.targetText)
    }

    private func priority(for review: AIValidatedReview) -> Int {
        switch review.origin {
        case .deterministic:
            switch review.category {
            case .spelling:
                0
            case .grammar, .clarity:
                1
            case .terminology:
                2
            case .none:
                5
            }
        case .deterministicFallback:
            switch review.category {
            case .spelling:
                10
            case .grammar, .clarity:
                11
            case .terminology:
                12
            case .none:
                15
            }
        case .qwenRepaired:
            20
        case .qwen:
            21
        }
    }

    private func uniqueRange(of substring: String, in text: String) -> NSRange? {
        guard !substring.isEmpty else { return nil }
        let wholeRange = NSRange(location: 0, length: text.utf16.count)
        let first = (text as NSString).range(
            of: substring,
            options: .literal,
            range: wholeRange,
            locale: nil
        )
        guard first.location != NSNotFound else { return nil }

        let afterFirst = NSMaxRange(first)
        guard afterFirst < wholeRange.length else { return first }
        let second = (text as NSString).range(
            of: substring,
            options: .literal,
            range: NSRange(
                location: afterFirst,
                length: wholeRange.length - afterFirst
            ),
            locale: nil
        )
        return second.location == NSNotFound ? first : nil
    }
}
