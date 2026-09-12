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
        anchoredSuggestions(for: segment, glossaryMatches: glossaryMatches)
            .map(\.parsedReview)
    }

    /// Returns deterministic reviews together with every source occurrence.
    /// The legacy `suggestions` method above intentionally remains available
    /// for callers that only need parsed output.
    func anchoredSuggestions(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = []
    ) -> [AIConnectorAnchoredParsedReview] {
        var anchoredResults: [AIConnectorAnchoredParsedReview] = []

        for rule in ruleStore.activeRules {
            guard rule.matcher == .tokenSequence,
                  !rule.exceptions.contains(where: {
                      segment.targetText.localizedCaseInsensitiveContains($0)
                  }) else {
                continue
            }

            for change in changes(
                searchTerm: rule.value,
                replacement: rule.replacement,
                in: segment.targetText
            ) {
                let parsedReview = AIParsedReview(
                    status: .suggestion,
                    category: rule.category,
                    original: change.original,
                    replacement: change.replacement,
                    glossaryID: nil,
                    reason: rule.reason,
                    ruleID: rule.id
                )
                anchoredResults.append(
                    AIConnectorAnchoredParsedReview(
                        parsedReview: parsedReview,
                        sourceAnchor: AIConnectorReviewAnchor(
                            segmentID: segment.id,
                            sourceRange: change.range,
                            original: change.original
                        )
                    )
                )
            }
        }

        for match in glossaryMatches where !match.isDirectTermMatch {
            for change in replacingDefinitions(
                for: match.entry,
                in: segment.targetText
            ) {
                let parsedReview = AIParsedReview(
                    status: .suggestion,
                    category: .terminology,
                    original: change.original,
                    replacement: match.entry.term,
                    glossaryID: "G1",
                    reason: "Mengusulkan istilah glossary yang cocok dengan pengertian pada target."
                )
                anchoredResults.append(
                    AIConnectorAnchoredParsedReview(
                        parsedReview: parsedReview,
                        sourceAnchor: AIConnectorReviewAnchor(
                            segmentID: segment.id,
                            sourceRange: change.range,
                            original: change.original
                        )
                    )
                )
            }
        }

        // Candidate-first selection applies the segment cap after all local
        // evidence (rules and verified glossary matches) has been collected.
        // Keeping every local proposal here prevents a third rule from
        // accidentally hiding a stronger verified terminology candidate.
        return anchoredResults
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

    private func changes(
        searchTerm: String,
        replacement: String,
        in text: String
    ) -> [TextChange] {
        guard !searchTerm.isEmpty else { return [] }

        var changes: [TextChange] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                  of: searchTerm,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            changes.append(
                TextChange(
                    original: String(text[range]),
                    replacement: replacement,
                    range: NSRange(range, in: text)
                )
            )
            searchStart = range.upperBound
        }
        return changes
    }

    private func replacingDefinitions(
        for entry: LegalDictionaryEntry,
        in text: String
    ) -> [TextChange] {
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

        guard text.range(
            of: entry.term,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == nil else {
            return []
        }

        return phrases
            .sorted(by: { $0.count > $1.count })
            .flatMap { phrase in
                guard !phrase.isEmpty else { return [TextChange]() }
                return changes(
                    searchTerm: phrase,
                    replacement: entry.term,
                    in: text
                )
            }
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
        let range: NSRange
    }
}
