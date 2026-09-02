import Foundation

/// Finds definition-shaped statements without asking the model to invent a
/// term. Explicit statements are matched against the local corpus; paraphrase
/// candidates come from the already guarded Dictionary/RAG result.
struct AIConnectorDefinitionDetector: Sendable {
    static let maximumCandidates = 3

    private let termRecords: [TermRecord]

    init(dictionaryStore: LegalDictionaryStore) {
        let grouped = Dictionary(
            grouping: dictionaryStore.entries,
            by: { Self.normalize($0.term) }
        )

        termRecords = grouped.values
            .filter { !$0.isEmpty }
            .map { entries in
                let first = entries[0]
                return TermRecord(
                    normalizedTerm: Self.normalize(first.term),
                    displayTerm: first.term,
                    tokens: Self.tokenize(first.term),
                    entries: entries
                )
            }
            .filter { !$0.tokens.isEmpty }
            .sorted { lhs, rhs in
                if lhs.tokens.count != rhs.tokens.count {
                    return lhs.tokens.count > rhs.tokens.count
                }
                return lhs.normalizedTerm < rhs.normalizedTerm
            }
    }

    func detect(
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch]
    ) -> AIConnectorDefinitionDetectionResult {
        let explicitSignal = explicitSignal(in: segment.targetText)
        let usableExplicitEntries = explicitSignal.flatMap { signal in
            termRecords.first {
                Self.normalize($0.displayTerm) == Self.normalize(signal.termText)
            }?.entries.filter(Self.isUsableEvidence)
        } ?? []

        if let explicitSignal {
            let exactCandidates = makeExactCandidates(
                entries: usableExplicitEntries,
                statementText: explicitSignal.statementText
            )
            if !exactCandidates.isEmpty {
                return AIConnectorDefinitionDetectionResult(
                    term: explicitSignal.termText,
                    statementText: explicitSignal.statementText,
                    detection: .explicitPattern,
                    candidates: exactCandidates
                )
            }
        }

        let retrievedCandidates = makeRetrievedCandidates(
            from: glossaryMatches,
            statementText: explicitSignal?.statementText ?? segment.targetText,
            detection: explicitSignal == nil
                ? .retrievedCandidate
                : .explicitPattern
        )
        if !retrievedCandidates.isEmpty {
            return AIConnectorDefinitionDetectionResult(
                term: explicitSignal?.termText ?? retrievedCandidates.first?.term,
                statementText: explicitSignal?.statementText ?? segment.targetText,
                detection: explicitSignal == nil
                    ? .retrievedCandidate
                    : .explicitPattern,
                candidates: retrievedCandidates
            )
        }

        guard let explicitSignal else {
            return AIConnectorDefinitionDetectionResult(
                term: nil,
                statementText: segment.targetText,
                detection: nil,
                candidates: []
            )
        }

        return AIConnectorDefinitionDetectionResult(
            term: explicitSignal.termText,
            statementText: explicitSignal.statementText,
            detection: .explicitPattern,
            candidates: []
        )
    }

    static func isUsableEvidence(_ entry: LegalDictionaryEntry) -> Bool {
        entry.authority == .verified
            && entry.isActionable
            && entry.corpusVersion != LegalDictionaryCorpusVersion.legacyKamusV1
            && entry.corpusVersion != LegalDictionaryCorpusVersion.legacyRAGExportV1
    }

    private func makeExactCandidates(
        entries: [LegalDictionaryEntry],
        statementText: String
    ) -> [AIConnectorDefinitionCandidate] {
        entries
            .sorted { lhs, rhs in lhs.id < rhs.id }
            .prefix(Self.maximumCandidates)
            .enumerated()
            .map { index, entry in
                let match = LegalDictionaryMatch(
                    entry: entry,
                    score: 1_000 - Double(index),
                    rank: index + 1,
                    matchedDefinitionTokenCount: sharedTokenCount(
                        statementText,
                        entry.definition
                    ),
                    isDirectTermMatch: true,
                    retrievalOrigin: .exact
                )
                return AIConnectorDefinitionCandidate(
                    id: "D\(index + 1)",
                    match: match,
                    statementText: statementText,
                    detection: .explicitPattern
                )
            }
    }

    private func makeRetrievedCandidates(
        from matches: [LegalDictionaryMatch],
        statementText: String,
        detection: AIConnectorDefinitionDetection
    ) -> [AIConnectorDefinitionCandidate] {
        var seenEntryIDs: Set<String> = []

        return matches
            .filter { Self.isUsableEvidence($0.entry) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.entry.id < rhs.entry.id
            }
            .compactMap { match in
                guard seenEntryIDs.insert(match.entry.id).inserted else {
                    return nil
                }
                return match
            }
            .prefix(Self.maximumCandidates)
            .enumerated()
            .map { index, match in
                AIConnectorDefinitionCandidate(
                    id: "D\(index + 1)",
                    match: match,
                    statementText: statementText,
                    detection: detection
                )
            }
    }

    private func explicitSignal(in text: String) -> ExplicitSignal? {
        let tokens = wordTokens(in: text)

        for record in termRecords {
            guard tokens.count >= record.tokens.count else { continue }

            for start in 0 ... (tokens.count - record.tokens.count) {
                let end = start + record.tokens.count
                guard Array(tokens[start..<end].map(\.normalized)) == record.tokens else {
                    continue
                }

                let termRange = NSRange(
                    location: tokens[start].range.location,
                    length: NSMaxRange(tokens[end - 1].range)
                        - tokens[start].range.location
                )
                guard let statementText = definitionText(
                    after: termRange,
                    in: text
                ) else {
                    continue
                }

                return ExplicitSignal(
                    termText: record.displayTerm,
                    statementText: statementText
                )
            }
        }

        return regexExplicitSignal(in: text)
    }

    private func definitionText(after termRange: NSRange, in text: String) -> String? {
        let suffix = (text as NSString).substring(from: NSMaxRange(termRange))
        let pattern = #"(?is)^\s*[,;:]?\s*(?:adalah|ialah|merupakan|berarti|didefinisikan\s+sebagai|diartikan\s+sebagai)\s+(.+)$"#
        guard let match = firstMatch(pattern: pattern, in: suffix) else {
            return nil
        }

        let definition = (suffix as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return definition.isEmpty ? nil : definition
    }

    private func regexExplicitSignal(in text: String) -> ExplicitSignal? {
        let pattern = #"(?is)(?:yang\s+dimaksud\s+dengan\s+)?([^,;:.!?]+?)\s+(?:adalah|ialah|merupakan|berarti|didefinisikan\s+sebagai|diartikan\s+sebagai)\s+(.+)$"#
        guard let match = firstMatch(pattern: pattern, in: text) else {
            return nil
        }

        let rawTerm = (text as NSString).substring(with: match.range(at: 1))
        let rawDefinition = (text as NSString).substring(with: match.range(at: 2))
        var term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let markerRange = term.range(
            of: "yang dimaksud dengan",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            term = String(term[markerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let termTokens = Self.tokenize(term)
        guard !termTokens.isEmpty,
              termTokens.count <= 8,
              !termTokens.allSatisfy({ Self.stopWords.contains($0) }) else {
            return nil
        }

        let definition = rawDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else { return nil }

        return ExplicitSignal(termText: term, statementText: definition)
    }

    private func firstMatch(
        pattern: String,
        in text: String
    ) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else {
            return nil
        }
        return expression.firstMatch(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length)
        )
    }

    private func wordTokens(in text: String) -> [WordToken] {
        var result: [WordToken] = []
        text.enumerateSubstrings(
            in: text.startIndex ..< text.endIndex,
            options: .byWords
        ) { substring, range, _, _ in
            guard let substring, !substring.isEmpty else { return }
            let normalized = Self.tokenize(substring).first ?? ""
            guard !normalized.isEmpty else { return }
            result.append(
                WordToken(
                    normalized: normalized,
                    range: NSRange(range, in: text)
                )
            )
        }
        return result
    }

    private func sharedTokenCount(_ lhs: String, _ rhs: String) -> Int {
        Set(Self.tokenize(lhs)).intersection(Self.tokenize(rhs)).count
    }

    private static func normalize(_ value: String) -> String {
        tokenize(value).joined(separator: " ")
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static let stopWords: Set<String> = [
        "adalah", "ialah", "merupakan", "yang", "dan", "atau", "serta",
        "dalam", "dengan", "untuk", "dari", "pada", "oleh", "terhadap",
        "sebagai", "suatu", "sebuah", "dapat", "telah", "akan", "tidak",
        "secara", "baik", "lebih", "lain", "lainnya", "ini", "itu"
    ]

    private struct TermRecord: Sendable {
        let normalizedTerm: String
        let displayTerm: String
        let tokens: [String]
        let entries: [LegalDictionaryEntry]
    }

    private struct ExplicitSignal: Sendable {
        let termText: String
        let statementText: String
    }

    private struct WordToken: Sendable {
        let normalized: String
        let range: NSRange
    }
}
