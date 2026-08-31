import Foundation

/// Builds bounded proposals from local evidence before Qwen is invoked.
/// Candidate construction is deliberately deterministic: the model can only
/// judge one of these proposals and cannot invent a replacement or source.
struct AIConnectorCandidateBuilder: Sendable {
    private let deterministicEngine: AIConnectorDeterministicSuggestionEngine
    private let ruleStore: AIConnectorRuleStore
    private let retrievalConfiguration: LegalCorpusRetrievalConfiguration?

    init(
        ruleStore: AIConnectorRuleStore,
        retrievalConfiguration: LegalCorpusRetrievalConfiguration? = nil
    ) {
        self.ruleStore = ruleStore
        self.retrievalConfiguration = retrievalConfiguration
        self.deterministicEngine = AIConnectorDeterministicSuggestionEngine(
            ruleStore: ruleStore
        )
    }

    func build(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch]
    ) -> [AIConnectorReviewCandidate] {
        let verifiedMatches = glossaryMatches.filter {
            $0.entry.authority == .verified
                && $0.entry.isActionable
                && $0.entry.corpusVersion != LegalDictionaryCorpusVersion.legacyKamusV1
                && $0.entry.corpusVersion != LegalDictionaryCorpusVersion.legacyRAGExportV1
        }
        var parsedReviews = deterministicEngine.suggestions(
            for: segment,
            glossaryMatches: verifiedMatches
        )

        // A retrieved definition is often paraphrased in a contract rather
        // than copied verbatim. In that case generate the smallest local
        // source span whose words cover the calibrated definition keywords.
        // The replacement remains the canonical term from the corpus.
        for match in verifiedMatches where !match.isDirectTermMatch {
            guard let change = terminologyChange(for: match.entry, in: segment.targetText),
                  !parsedReviews.contains(where: {
                      // Prefer the complete, exact definition replacement
                      // produced above. A shorter semantic window is useful
                      // only when no exact definition span was found; it must
                      // not outrank the safer, fully grounded proposal.
                      $0.category == .terminology
                          && $0.replacement == match.entry.term
                  }) else {
                continue
            }

            parsedReviews.append(
                AIParsedReview(
                    status: .suggestion,
                    category: .terminology,
                    original: change.original,
                    replacement: match.entry.term,
                    glossaryID: "G1",
                    reason: "Mencocokkan uraian pada target dengan istilah canonical dari corpus terverifikasi."
                )
            )
        }

        var proposals = parsedReviews.compactMap { parsedReview -> Proposal? in
            guard let original = parsedReview.original,
                  let replacement = parsedReview.replacement,
                  let range = uniqueRange(of: original, in: segment.targetText),
                  isAllowedRange(
                      range,
                      category: parsedReview.category,
                      in: segment.targetText
                  ) else {
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

    private func terminologyChange(
        for entry: LegalDictionaryEntry,
        in text: String
    ) -> TextChange? {
        let tokens = wordTokens(in: text)
        let minimumWindow = max(
            1,
            retrievalConfiguration?.suggestionMinimumSpanTokens ?? 6
        )
        guard tokens.count >= minimumWindow else { return nil }

        let definitionTokens = Set(
            tokenize(entry.definition)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )
        guard !definitionTokens.isEmpty else { return nil }

        let maximumWindow = min(
            max(minimumWindow, retrievalConfiguration?.suggestionMaximumSpanTokens ?? 80),
            tokens.count
        )
        let minimumCoverage = retrievalConfiguration?
            .suggestionMinimumKeywordCoverage ?? 0.70
        var best: Window?

        for windowLength in minimumWindow ... maximumWindow {
            for start in 0 ... (tokens.count - windowLength) {
                let end = start + windowLength
                let covered = Set(tokens[start..<end].map(\.normalized))
                    .intersection(definitionTokens)
                let coverage = Double(covered.count) / Double(definitionTokens.count)
                guard coverage >= minimumCoverage else { continue }

                let original = substring(
                    in: text,
                    from: tokens[start].range.location,
                    through: NSMaxRange(tokens[end - 1].range)
                )
                guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !original.localizedCaseInsensitiveContains(entry.term) else {
                    continue
                }

                let candidate = Window(
                    original: original.trimmingCharacters(in: .whitespacesAndNewlines),
                    coverage: coverage,
                    length: windowLength,
                    location: tokens[start].range.location
                )
                if best == nil || candidate.isBetter(than: best!) {
                    best = candidate
                }
            }

            // The first viable length is the shortest span by design. The
            // tie-breakers still make output stable when several spans have
            // the same number of words.
            if best != nil { break }
        }

        guard let best else { return nil }
        return TextChange(original: best.original, replacement: entry.term)
    }

    private func isAllowedRange(
        _ range: NSRange,
        category: AIReviewCategory,
        in text: String
    ) -> Bool {
        guard category == .terminology else { return true }

        let minimum = max(
            1,
            retrievalConfiguration?.suggestionMinimumSpanTokens ?? 6
        )
        let maximum = max(
            minimum,
            retrievalConfiguration?.suggestionMaximumSpanTokens ?? 80
        )
        let original = (text as NSString).substring(with: range)
        let tokenCount = tokenize(original).count
        return tokenCount >= minimum && tokenCount <= maximum
    }

    private func wordTokens(in text: String) -> [WordToken] {
        var result: [WordToken] = []
        let fullRange = text.startIndex ..< text.endIndex
        text.enumerateSubstrings(in: fullRange, options: .byWords) { substring, range, _, _ in
            guard let substring, !substring.isEmpty else { return }
            result.append(
                WordToken(
                    normalized: tokenize(substring).first ?? "",
                    range: NSRange(range, in: text)
                )
            )
        }
        return result.filter { !$0.normalized.isEmpty }
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func substring(in text: String, from start: Int, through end: Int) -> String {
        let nsText = text as NSString
        guard start >= 0, end <= nsText.length, start < end else { return "" }
        return nsText.substring(with: NSRange(location: start, length: end - start))
    }

    private static let stopWords: Set<String> = [
        "adalah", "ialah", "merupakan", "yang", "dan", "atau", "serta",
        "dalam", "dengan", "untuk", "dari", "pada", "oleh", "terhadap",
        "sebagai", "suatu", "sebuah", "dapat", "telah", "akan", "tidak",
        "secara", "baik", "lebih", "lain", "lainnya", "ini", "itu"
    ]

    private struct WordToken: Sendable {
        let normalized: String
        let range: NSRange
    }

    private struct Window: Sendable {
        let original: String
        let coverage: Double
        let length: Int
        let location: Int

        func isBetter(than other: Window) -> Bool {
            if length != other.length { return length < other.length }
            if coverage != other.coverage { return coverage > other.coverage }
            return location < other.location
        }
    }

    private struct TextChange: Sendable {
        let original: String
        let replacement: String
    }

    private struct Proposal: Sendable {
        let parsedReview: AIParsedReview
        let range: NSRange
        let priority: Int
        let glossaryMatch: LegalDictionaryMatch?
        let confidenceTier: AIConnectorCandidateConfidence
    }
}
