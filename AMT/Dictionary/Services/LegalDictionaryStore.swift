import Foundation

enum LegalDictionaryEntryAuthority: String, Codable, Hashable, Sendable {
    case legacy
    case verified
}

struct LegalDictionaryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let term: String
    let definition: String
    let regulation: String
    let regulationTitle: String
    let sourceURL: URL?
    let authority: LegalDictionaryEntryAuthority

    init(
        id: String,
        term: String,
        definition: String,
        regulation: String,
        regulationTitle: String,
        sourceURL: URL?,
        authority: LegalDictionaryEntryAuthority = .verified
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.regulation = regulation
        self.regulationTitle = regulationTitle
        self.sourceURL = sourceURL
        self.authority = authority
    }

    nonisolated static let previewEntries = [
        LegalDictionaryEntry(
            id: "preview-data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        ),
        LegalDictionaryEntry(
            id: "preview-hukum-adat",
            term: "Hukum Adat",
            definition: "Aturan atau norma tidak tertulis yang hidup dalam masyarakat hukum adat.",
            regulation: "Undang-Undang Nomor 21 Tahun 2001",
            regulationTitle: "Otonomi Khusus bagi Provinsi Papua",
            sourceURL: nil
        )
    ]
}

/// A source-backed glossary candidate returned by the local retrieval index.
struct LegalDictionaryMatch: Identifiable, Hashable, Sendable {
    let entry: LegalDictionaryEntry
    let score: Double
    let rank: Int
    let matchedDefinitionTokenCount: Int
    let isDirectTermMatch: Bool

    var id: String { entry.id }
}

struct LegalDictionaryStore: Sendable {
    private static let suggestionMinimumScore = 20.0
    private static let suggestionMinimumMargin = 3.0
    private static let suggestionMinimumMatchedDefinitionTokens = 4

    private struct RetrievalIndexEntry: Sendable {
        let termTokens: [String]
        let definitionTokenSet: Set<String>
        let termFrequencies: [String: Int]
        let tokenCount: Int
    }

    let entries: [LegalDictionaryEntry]
    private let retrievalIndex: [RetrievalIndexEntry]
    private let inverseDocumentFrequencies: [String: Double]
    private let averageDocumentLength: Double

    nonisolated init(bundle: Bundle = .main) {
        if let resourceURL = bundle.url(forResource: "kamus_hukum", withExtension: "csv"),
           let data = try? Data(contentsOf: resourceURL),
           let loadedEntries = Self.loadEntries(from: data),
           !loadedEntries.isEmpty {
            self.init(entries: loadedEntries)
        } else {
            self.init(entries: LegalDictionaryEntry.previewEntries)
        }
    }

    nonisolated init(entries: [LegalDictionaryEntry]) {
        self.entries = entries

        let index = entries.map { entry in
            let retrievalDefinition = Self.retrievalDefinition(for: entry)
            let tokens = Self.tokenize("\(entry.term) \(retrievalDefinition)")

            return RetrievalIndexEntry(
                termTokens: Self.tokenize(entry.term),
                definitionTokenSet: Set(Self.tokenize(retrievalDefinition)),
                termFrequencies: Self.termFrequencies(for: tokens),
                tokenCount: tokens.count
            )
        }
        retrievalIndex = index

        var documentFrequency: [String: Int] = [:]
        for document in index {
            for token in document.termFrequencies.keys {
                documentFrequency[token, default: 0] += 1
            }
        }

        let documentCount = Double(index.count)
        inverseDocumentFrequencies = Dictionary(uniqueKeysWithValues: documentFrequency.map { token, frequency in
            let frequency = Double(frequency)
            return (
                token,
                log(1.0 + (documentCount - frequency + 0.5) / (frequency + 0.5))
            )
        })
        averageDocumentLength = index.isEmpty
            ? 0
            : Double(index.reduce(0) { $0 + $1.tokenCount }) / documentCount
    }

    func search(_ query: String, limit: Int = 30) -> [LegalDictionaryEntry] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))

        return entries
            .compactMap { entry -> (entry: LegalDictionaryEntry, score: Int)? in
                let normalizedTerm = Self.normalize(entry.term)
                let normalizedDefinition = Self.normalize(entry.definition)

                if normalizedTerm == normalizedQuery {
                    return (entry, 0)
                }

                if normalizedTerm.hasPrefix(normalizedQuery) {
                    return (entry, 1)
                }

                if normalizedTerm.contains(normalizedQuery) {
                    return (entry, 2)
                }

                if normalizedDefinition.contains(normalizedQuery) {
                    return (entry, 3)
                }

                let termTokens = Set(normalizedTerm.split(separator: " ").map(String.init))
                let definitionTokens = Set(normalizedDefinition.split(separator: " ").map(String.init))
                let matches = queryTokens.intersection(termTokens.union(definitionTokens)).count

                return matches > 0 ? (entry, 4) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.entry.term.localizedCaseInsensitiveCompare(rhs.entry.term) == .orderedAscending
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// Returns only a conservative, source-backed candidate for model context.
    ///
    /// The score threshold and margin are calibrated against the current full
    /// glossary as a provisional guard. They are intentionally stricter than
    /// ordinary dictionary search because an unrelated candidate can mislead a
    /// suggestion model. This method returns no candidate when the evidence is
    /// weak or ambiguous.
    func suggestionCandidates(for text: String, limit: Int = 3) -> [LegalDictionaryMatch] {
        guard limit > 0 else { return [] }

        let queryTokens = Self.tokenize(text)
        guard !queryTokens.isEmpty, !entries.isEmpty else { return [] }

        let uniqueTermIndices = Dictionary(grouping: entries.indices, by: { index in
            Self.normalize(entries[index].term)
        })
            .compactMapValues { indices in
                indices.max { lhs, rhs in
                    bm25Score(queryTokens: queryTokens, documentIndex: lhs)
                        < bm25Score(queryTokens: queryTokens, documentIndex: rhs)
                }
            }

        let directTermIndices = uniqueTermIndices.values.filter { index in
            let termTokens = retrievalIndex[index].termTokens
            return termTokens.count >= 2
                && Self.containsTokenSequence(queryTokens, termTokens)
        }
        .sorted { lhs, rhs in
            let lhsTokens = retrievalIndex[lhs].termTokens.count
            let rhsTokens = retrievalIndex[rhs].termTokens.count
            if lhsTokens != rhsTokens { return lhsTokens > rhsTokens }
            return entries[lhs].term.localizedCaseInsensitiveCompare(entries[rhs].term) == .orderedAscending
        }

        let scored = uniqueTermIndices.values.compactMap { index -> LegalDictionaryMatch? in
            let score = bm25Score(queryTokens: queryTokens, documentIndex: index)
            guard score > 0 else { return nil }

            let document = retrievalIndex[index]
            let matchedDefinitionTokenCount = Set(queryTokens)
                .intersection(document.definitionTokenSet)
                .count
            let isDirectTermMatch = document.termTokens.count >= 2
                && Self.containsTokenSequence(queryTokens, document.termTokens)

            return LegalDictionaryMatch(
                entry: entries[index],
                score: score,
                rank: 0,
                matchedDefinitionTokenCount: matchedDefinitionTokenCount,
                isDirectTermMatch: isDirectTermMatch
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.term.localizedCaseInsensitiveCompare(rhs.entry.term) == .orderedAscending
        }

        guard let first = scored.first else { return [] }

        let secondScore = scored.dropFirst().first?.score ?? 0
        let margin = first.score - secondScore
        if first.score >= Self.suggestionMinimumScore,
           first.matchedDefinitionTokenCount >= Self.suggestionMinimumMatchedDefinitionTokens,
           (scored.count == 1 || margin >= Self.suggestionMinimumMargin) {
            return scored
                .filter {
                    $0.score >= Self.suggestionMinimumScore
                        && $0.matchedDefinitionTokenCount
                            >= Self.suggestionMinimumMatchedDefinitionTokens
                }
                .prefix(limit)
                .enumerated()
                .map { index, match in
                    LegalDictionaryMatch(
                        entry: match.entry,
                        score: match.score,
                        rank: index + 1,
                        matchedDefinitionTokenCount: match.matchedDefinitionTokenCount,
                        isDirectTermMatch: match.isDirectTermMatch
                    )
                }
        }

        return directTermIndices.prefix(limit).enumerated().map { rank, index in
            LegalDictionaryMatch(
                entry: entries[index],
                score: bm25Score(queryTokens: queryTokens, documentIndex: index),
                rank: rank + 1,
                matchedDefinitionTokenCount: Set(queryTokens)
                    .intersection(retrievalIndex[index].definitionTokenSet)
                    .count,
                isDirectTermMatch: true
            )
        }
    }

    private func bm25Score(queryTokens: [String], documentIndex: Int) -> Double {
        guard !queryTokens.isEmpty,
              let document = retrievalIndex[safe: documentIndex],
              averageDocumentLength > 0 else {
            return 0
        }

        let k1 = 1.5
        let b = 0.75
        let documentLength = Double(document.tokenCount)
        let normalization = 1.0 - b + b * (documentLength / averageDocumentLength)
        var score = 0.0

        for token in queryTokens {
            let frequency = Double(document.termFrequencies[token] ?? 0)
            guard frequency > 0 else { continue }

            let numerator = frequency * (k1 + 1.0)
            let denominator = frequency + k1 * normalization
            score += (inverseDocumentFrequencies[token] ?? 0) * numerator / denominator
        }

        return score
    }

    nonisolated private static func loadEntries(from data: Data) -> [LegalDictionaryEntry]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let rows = CSVParser.parse(text)
        guard let headerRow = rows.first else { return nil }

        let headers = headerRow.map {
            $0.replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        return rows.dropFirst().enumerated().compactMap { index, row -> LegalDictionaryEntry? in
            let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
            guard let term = values["istilah"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let definition = values["pengertian"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty,
                  !definition.isEmpty else {
                return nil
            }

            let authority: LegalDictionaryEntryAuthority
            if let status = values["status"], !status.isEmpty {
                if status.caseInsensitiveCompare("VERIFIED") == .orderedSame {
                    authority = .verified
                } else if status.caseInsensitiveCompare("OK") == .orderedSame {
                    authority = .legacy
                } else {
                    return nil
                }
            } else {
                authority = .legacy
            }

            return LegalDictionaryEntry(
                id: "csv-\(index)-\(term)",
                term: term,
                definition: definition,
                regulation: values["undang_undang"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                regulationTitle: values["uu"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceURL: URL(string: values["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
                authority: authority
            )
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func tokenize(_ value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    nonisolated private static func termFrequencies(for tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
    }

    nonisolated private static func retrievalDefinition(for entry: LegalDictionaryEntry) -> String {
        let normalizedTerm = normalize(entry.term)
        let normalizedDefinition = normalize(entry.definition)

        for connector in ["adalah", "ialah", "merupakan"] {
            let prefix = "\(normalizedTerm) \(connector) "
            if normalizedDefinition.hasPrefix(prefix) {
                return String(normalizedDefinition.dropFirst(prefix.count))
            }
        }

        return normalizedDefinition
    }

    nonisolated private static func containsTokenSequence(_ tokens: [String], _ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= tokens.count else { return false }

        for start in 0...(tokens.count - sequence.count) {
            if Array(tokens[start..<(start + sequence.count)]) == sequence {
                return true
            }
        }

        return false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private enum CSVParser {
    nonisolated static func parse(_ input: String) -> [[String]] {
        let characters = Array(input)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isQuoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        isQuoted = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            switch character {
            case "\"":
                isQuoted = true
                index += 1
            case ",":
                row.append(field)
                field = ""
                index += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
            case "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
                if index < characters.count, characters[index] == "\n" {
                    index += 1
                }
            default:
                field.append(character)
                index += 1
            }
        }

        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
