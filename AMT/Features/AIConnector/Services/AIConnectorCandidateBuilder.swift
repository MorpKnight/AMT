import Foundation

/// Builds bounded proposals from local evidence before Qwen is invoked.
/// Candidate construction is deliberately deterministic: the model can only
/// judge one of these proposals and cannot invent a replacement or source.
struct AIConnectorCandidateBuilder: Sendable {
    private let deterministicEngine: AIConnectorDeterministicSuggestionEngine
    private let ruleStore: AIConnectorRuleStore

    init(ruleStore: AIConnectorRuleStore) {
        self.ruleStore = ruleStore
        self.deterministicEngine = AIConnectorDeterministicSuggestionEngine(
            ruleStore: ruleStore
        )
    }

    func build(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch]
    ) -> [AIConnectorReviewCandidate] {
        let verifiedMatches = glossaryMatches.filter { $0.entry.authority == .verified }
        let parsedReviews = deterministicEngine.suggestions(
            for: segment,
            glossaryMatches: verifiedMatches
        )

        var proposals = parsedReviews.compactMap { parsedReview -> Proposal? in
            guard let original = parsedReview.original,
                  let replacement = parsedReview.replacement,
                  let range = uniqueRange(of: original, in: segment.targetText) else {
                return nil
            }

            let glossaryMatch = parsedReview.glossaryID == nil
                ? nil
                : verifiedMatches.first {
                    $0.entry.term == replacement
                }

            let confidenceTier: AIConnectorCandidateConfidence
            if parsedReview.category == .terminology, glossaryMatch != nil {
                confidenceTier = .verifiedGlossary
            } else {
                confidenceTier = .deterministicRule
            }

            return Proposal(
                parsedReview: parsedReview,
                range: range,
                priority: priority(for: parsedReview, glossaryMatch: glossaryMatch),
                glossaryMatch: glossaryMatch,
                confidenceTier: confidenceTier
            )
        }

        proposals.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }

            let lhsCategory = categoryRank(lhs.parsedReview.category)
            let rhsCategory = categoryRank(rhs.parsedReview.category)
            if lhsCategory != rhsCategory {
                return lhsCategory < rhsCategory
            }
            if lhs.range.length != rhs.range.length {
                return lhs.range.length < rhs.range.length
            }
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.parsedReview.ruleID ?? "" < rhs.parsedReview.ruleID ?? ""
        }

        var selected: [Proposal] = []
        for proposal in proposals {
            guard !selected.contains(where: { other in
                NSIntersectionRange(proposal.range, other.range).length > 0
            }) else {
                continue
            }
            selected.append(proposal)
            if selected.count == AIConnectorSuggestionConflictResolver.maximumSuggestionsPerSegment {
                break
            }
        }

        return selected.enumerated().map { index, proposal in
            AIConnectorReviewCandidate(
                id: "C\(index + 1)",
                segmentID: segment.id,
                original: proposal.parsedReview.original ?? "",
                replacement: proposal.parsedReview.replacement ?? "",
                category: proposal.parsedReview.category,
                priority: proposal.priority,
                ruleID: proposal.parsedReview.ruleID,
                glossaryMatch: proposal.glossaryMatch,
                explanation: proposal.parsedReview.reason,
                confidenceTier: proposal.confidenceTier
            )
        }
    }

    private func priority(
        for parsedReview: AIParsedReview,
        glossaryMatch: LegalDictionaryMatch?
    ) -> Int {
        if let ruleID = parsedReview.ruleID,
           let rule = ruleStore.rules.first(where: { $0.id == ruleID }) {
            return rule.priority
        }
        if glossaryMatch != nil {
            return 100
        }
        return 200
    }

    private func categoryRank(_ category: AIReviewCategory) -> Int {
        switch category {
        case .spelling:
            0
        case .grammar:
            1
        case .terminology:
            2
        case .clarity:
            3
        case .none:
            4
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

    private struct Proposal: Sendable {
        let parsedReview: AIParsedReview
        let range: NSRange
        let priority: Int
        let glossaryMatch: LegalDictionaryMatch?
        let confidenceTier: AIConnectorCandidateConfidence
    }
}
