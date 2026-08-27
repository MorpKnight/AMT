import Foundation

struct LegalDictionaryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let term: String
    let definition: String
    let regulation: String
    let regulationTitle: String
    let sourceURL: URL?

    static let previewEntries = [
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

struct LegalDictionaryStore: Sendable {
    let entries: [LegalDictionaryEntry]

    init(bundle: Bundle = .main) {
        if let resourceURL = bundle.url(forResource: "kamus_hukum", withExtension: "csv"),
           let data = try? Data(contentsOf: resourceURL),
           let loadedEntries = Self.loadEntries(from: data),
           !loadedEntries.isEmpty {
            entries = loadedEntries
        } else {
            entries = LegalDictionaryEntry.previewEntries
        }
    }

    init(entries: [LegalDictionaryEntry]) {
        self.entries = entries
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

    private static func loadEntries(from data: Data) -> [LegalDictionaryEntry]? {
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

            if let status = values["status"],
               !status.isEmpty,
               status.caseInsensitiveCompare("OK") != .orderedSame {
                return nil
            }

            return LegalDictionaryEntry(
                id: "csv-\(index)-\(term)",
                term: term,
                definition: definition,
                regulation: values["undang_undang"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                regulationTitle: values["uu"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceURL: URL(string: values["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            )
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private enum CSVParser {
    static func parse(_ input: String) -> [[String]] {
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
