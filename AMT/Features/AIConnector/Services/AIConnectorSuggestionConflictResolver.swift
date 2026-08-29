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
                let lhsLocation = lhs.original.flatMap {
                    uniqueRange(of: $0, in: lhs.segment.targetText)?.location
                } ?? Int.max
                let rhsLocation = rhs.original.flatMap {
                    uniqueRange(of: $0, in: rhs.segment.targetText)?.location
                } ?? Int.max
                if lhsLocation != rhsLocation { return lhsLocation < rhsLocation }
                if lhs.segment.id != rhs.segment.id { return lhs.segment.id < rhs.segment.id }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var accepted: [AIValidatedReview] = []
        var countsBySegment: [Int: Int] = [:]

        for review in actionable {
            guard let original = review.original,
                  let localRange = uniqueRange(of: original, in: review.segment.targetText),
                  countsBySegment[review.segment.id, default: 0]
                    < Self.maximumSuggestionsPerSegment else {
                continue
            }

            let conflicts = accepted.contains { other in
                guard other.segment.id == review.segment.id,
                      let otherOriginal = other.original,
                      let otherRange = uniqueRange(
                          of: otherOriginal,
                          in: other.segment.targetText
                      ) else {
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
