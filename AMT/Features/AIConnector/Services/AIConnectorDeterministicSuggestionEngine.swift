import Foundation

/// Produces only narrow, low-risk language corrections with explicit source spans.
///
/// This engine is intentionally conservative. It does not infer new legal meaning,
/// rewrite a whole clause, or translate defined terms. Glossary replacement is
/// allowed only when the retrieved definition is present in the target segment.
struct AIConnectorDeterministicSuggestionEngine: Sendable {
    func suggestion(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = []
    ) -> AIParsedReview? {
        let safeRules: [(String, String, AIReviewCategory, String)] = [
            (
                "wajib untuk",
                "wajib",
                .grammar,
                "Menghapus kata yang tidak diperlukan tanpa mengubah makna kewajiban."
            ),
            (
                "ditanda tangani",
                "ditandatangani",
                .spelling,
                "Memperbaiki ejaan kata menjadi bentuk baku tanpa mengubah makna hukum."
            ),
            (
                "di simpan",
                "disimpan",
                .spelling,
                "Memperbaiki pemisahan imbuhan tanpa mengubah makna hukum."
            )
        ]

        for (searchTerm, replacement, category, reason) in safeRules {
            guard let change = replacingFirst(
                searchTerm,
                with: replacement,
                in: segment.targetText
            ) else {
                continue
            }

            return AIParsedReview(
                status: .suggestion,
                category: category,
                original: change.original,
                replacement: change.replacement,
                glossaryID: nil,
                reason: reason
            )
        }

        for match in glossaryMatches where !match.isDirectTermMatch {
            guard let change = replacingDefinition(
                for: match.entry,
                in: segment.targetText
            ) else {
                continue
            }

            return AIParsedReview(
                status: .suggestion,
                category: .terminology,
                original: change.original,
                replacement: match.entry.term,
                glossaryID: "G1",
                reason: "Mengusulkan istilah glossary yang cocok dengan pengertian pada target."
            )
        }

        return nil
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

    private func replacingFirst(
        _ searchTerm: String,
        with replacement: String,
        in text: String
    ) -> TextChange? {
        guard let range = text.range(
            of: searchTerm,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        return TextChange(
            original: String(text[range]),
            replacement: replacement
        )
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
