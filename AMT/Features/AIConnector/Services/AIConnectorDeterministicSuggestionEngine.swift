import Foundation

/// Produces only narrow, low-risk language corrections with explicit source spans.
///
/// This engine is intentionally conservative. It does not infer new legal meaning,
/// rewrite a whole clause, or translate defined terms. Glossary replacement is
/// allowed only when the retrieved definition is present in the target segment.
struct AIConnectorDeterministicSuggestionEngine: Sendable {
    private let ruleStore: AIConnectorRuleStore

    init(ruleStore: AIConnectorRuleStore = AIConnectorRuleStore()) {
        self.ruleStore = ruleStore
    }

    /// Returns every non-overlapping deterministic candidate that can be
    /// proven safe locally. The caller remains responsible for validation and
    /// final conflict resolution.
    func suggestions(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = []
    ) -> [AIParsedReview] {
        var results: [AIParsedReview] = []

        for rule in ruleStore.activeRules {
            guard rule.matcher == .tokenSequence,
                  let change = uniqueChange(
                      searchTerm: rule.value,
                      replacement: rule.replacement,
                      in: segment.targetText
                  ),
                  !rule.exceptions.contains(where: {
                      segment.targetText.localizedCaseInsensitiveContains($0)
                  }) else {
                continue
            }

            results.append(
                AIParsedReview(
                    status: .suggestion,
                    category: rule.category,
                    original: change.original,
                    replacement: change.replacement,
                    glossaryID: nil,
                    reason: rule.reason,
                    ruleID: rule.id
                )
            )
        }

        for match in glossaryMatches where !match.isDirectTermMatch {
            guard let change = replacingDefinition(
                for: match.entry,
                in: segment.targetText
            ) else {
                continue
            }

            results.append(
                AIParsedReview(
                    status: .suggestion,
                    category: .terminology,
                    original: change.original,
                    replacement: match.entry.term,
                    glossaryID: "G1",
                    reason: "Mengusulkan istilah glossary yang cocok dengan pengertian pada target."
                )
            )
        }

        return Array(
            results.prefix(AIConnectorSuggestionConflictResolver.maximumSuggestionsPerSegment)
        )
    }

    func suggestion(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = []
    ) -> AIParsedReview? {
        suggestions(for: segment, glossaryMatches: glossaryMatches).first
    }

    func review(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = []
    ) -> AIParsedReview {
        suggestion(for: segment, glossaryMatches: glossaryMatches)
            ?? noSuggestion(for: segment)
    }

    func noSuggestion(for segment: AIReviewSegment) -> AIParsedReview {
        AIParsedReview(
            status: .noSuggestion,
            category: .none,
            original: nil,
            replacement: nil,
            glossaryID: nil,
            reason: "Tidak ada perubahan bahasa yang jelas pada target."
        )
    }

    private func uniqueChange(
        searchTerm: String,
        replacement: String,
        in text: String
    ) -> TextChange? {
        guard let firstRange = text.range(
            of: searchTerm,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        let first = TextChange(
            original: String(text[firstRange]),
            replacement: replacement
        )
        let afterFirst = text.index(after: firstRange.lowerBound)
        guard afterFirst < text.endIndex else { return first }

        let remainder = text[afterFirst..<text.endIndex]
        guard remainder.range(
            of: searchTerm,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == nil else {
            return nil
        }
        return first
    }

    private func replacingDefinition(
        for entry: LegalDictionaryEntry,
        in text: String
    ) -> TextChange? {
        let definition = entry.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let definitionWithoutTrailingPunctuation = removingTrailingSentencePunctuation(
            from: definition
        )
        let prefixes = [
            "\(entry.term) adalah ",
            "\(entry.term) ialah ",
            "\(entry.term) merupakan "
        ]
        let phrases = [definitionWithoutTrailingPunctuation] + prefixes.compactMap { prefix in
            guard definitionWithoutTrailingPunctuation.lowercased().hasPrefix(prefix.lowercased()) else {
                return nil
            }
            return String(definitionWithoutTrailingPunctuation.dropFirst(prefix.count))
        }

        for phrase in phrases.sorted(by: { $0.count > $1.count }) {
            guard !phrase.isEmpty,
                  text.range(
                      of: entry.term,
                      options: [.caseInsensitive, .diacriticInsensitive]
                  ) == nil,
                  let range = text.range(
                      of: phrase,
                      options: [.caseInsensitive, .diacriticInsensitive]
                  ) else {
                continue
            }

            return TextChange(
                original: String(text[range]),
                replacement: entry.term
            )
        }

        return nil
    }

    private func removingTrailingSentencePunctuation(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentencePunctuation = CharacterSet(charactersIn: ".!?;:")

        while let last = result.unicodeScalars.last,
              sentencePunctuation.contains(last) {
            result.removeLast()
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct TextChange: Sendable {
        let original: String
        let replacement: String
    }
}
