import Foundation

/// Candidate discovery is a policy filter, not proof that unchecked text is correct.
@MainActor
struct LegalReviewSignalPlanner {
    struct Unit {
        let id: String; let text: String; let range: NSRange; let heading: String
        var modelID: String { "U\(range.location)_\(range.length)" }
    }
    struct Pair {
        let id: String; let first: Unit; let second: Unit; let kind: String
        var modelID: String { "P\(first.range.location)_\(second.range.location)" }
    }
    struct Plan { let units: [Unit]; let pairs: [Pair]; let local: [LegalReviewAgent.Finding]; let failures: [String] }
    private let detector = AIConnectorDefinitionDetector(dictionaryStore: LegalDictionaryStore(entries: []))

    func build(_ text: String, structure: AIConnectorDocumentStructure? = nil) -> Plan {
        let protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let blocks = (structure ?? AIConnectorDocumentStructureBuilder().build(documentText: text)).blocks
        var units: [Unit] = []
        var markdownHeading: String?
        for block in blocks {
            if block.kind == .heading { markdownHeading = nil; continue }
            if block.text.utf16.count <= 160, block.text.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
                markdownHeading = block.text.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                continue
            }
            let heading = (block.headingPath + (markdownHeading.map { [$0] } ?? [])).joined(separator: " / ")
            block.text.enumerateSubstrings(in: block.text.startIndex..<block.text.endIndex, options: .bySentences) { value, range, _, _ in
                guard let value else { return }
                let trim = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trim.isEmpty, let localRange = value.range(of: trim) else { return }
                let inBlock = NSRange(range, in: block.text)
                let offset = NSRange(localRange, in: value)
                let source = NSRange(location: block.sourceRange.location + inBlock.location + offset.location, length: trim.utf16.count)
                units.append(.init(id: LegalReviewAgent.digest("unit|\(source.location)|\(trim)"), text: trim, range: source, heading: heading))
            }
        }
        var local = localFindings(text, protection: protection)
        let limited = Array(units.prefix(64))
        var failures = units.count > 64 ? ["unitLimit:\(units.count - 64)"] : []
        let facts = limited.map { fact($0) }
        var postings: [String: [Int]] = [:]
        for (i, f) in facts.enumerated() { for token in f.content.union(f.term.map { ["term:"+$0] } ?? []) { postings[token, default: []].append(i) } }
        var candidates = Set<String>(); var pairs: [Pair] = []
        for (i, a) in facts.enumerated() {
            let neighbors = Set(a.content.union(a.term.map { ["term:"+$0] } ?? []).flatMap { postings[$0] ?? [] }).filter { $0 > i }.sorted()
            for j in neighbors {
                let b = facts[j]
                guard a.text != b.text else { continue }
                // A plain identity definition is not a competing obligation.
                let plainA = a.strong && a.operators.isEmpty && a.values.isEmpty && a.frequency.isEmpty
                let plainB = b.strong && b.operators.isEmpty && b.values.isEmpty && b.frequency.isEmpty
                if (plainA && b.term == nil) || (plainB && a.term == nil) { continue }
                let kind: String?
                if let term = a.term, term == b.term, a.strong || b.strong { kind = "definition" }
                else {
                    let shared = a.content.intersection(b.content)
                    guard !shared.isEmpty else { continue }
                    if !a.values.isEmpty, !b.values.isEmpty, a.values != b.values { kind = "value" }
                    else if !a.frequency.isEmpty, !b.frequency.isEmpty, a.frequency != b.frequency { kind = "frequency" }
                    else if a.operators != b.operators, !a.operators.isEmpty || !b.operators.isEmpty { kind = "operator" }
                    else if a.actors != b.actors, a.exclusive || b.exclusive { kind = "actor" }
                    else { kind = nil }
                }
                guard let kind else { continue }
                let id = LegalReviewAgent.digest(limited[i].id + "|" + limited[j].id + "|" + kind)
                if candidates.insert(id).inserted { pairs.append(.init(id: id, first: limited[i], second: limited[j], kind: kind)) }
            }
        }
        // A literal parameter difference is an observable fact, independent of a
        // model deciding whether both deadlines could be met. It remains read-only.
        pairs = pairs.filter { pair in
            guard ["value", "frequency"].contains(pair.kind), Self.literalParameterDifference(pair) else { return true }
            local.append(.init(id: LegalReviewAgent.digest("parameterDifference|" + pair.id), category: "consistency", original: pair.second.text, replacement: nil, range: pair.second.range, actionable: false,
                               reason: "Dua klausul dengan redaksi yang sama memuat parameter berbeda. Tinjau apakah perbedaan ini disengaja; tidak ada nilai yang dipilih sistem.", evidenceIDs: [pair.first.id, pair.second.id]))
            return false
        }
        if pairs.count > 12 { failures.append("pairLimit:\(pairs.count - 12)") }
        return Plan(units: limited, pairs: Array(pairs.prefix(12)), local: local, failures: failures)
    }

    private func localFindings(_ text: String, protection: AIConnectorDocumentProtectionContext) -> [LegalReviewAgent.Finding] {
        let ns = text as NSString; var findings: [LegalReviewAgent.Finding] = []
        let protectedRanges = LegalReviewProtection.ranges(in: text)
        let duplicate = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])([\p{L}]{3,})[ \t]+\1(?![\p{L}\p{N}_])"#)
        for match in duplicate?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let original = ns.substring(with: match.range), replacement = ns.substring(with: match.range(at: 1))
            guard Self.duplicateWords.contains(replacement),
                  !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  !protection.protectedSourceRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  !protection.partyNames.contains(where: { name in
                      let nameRange = ns.range(of: name)
                      return nameRange.location != NSNotFound && NSIntersectionRange(nameRange, match.range).length > 0
                  }),
                  replacement != replacement.uppercased(), !replacement.prefix(1).allSatisfy(\.isUppercase) else { continue }
            findings.append(.init(id: LegalReviewAgent.digest("duplicate|\(match.range.location)|\(original)"), category: "grammar", original: original, replacement: replacement, range: match.range, actionable: true,
                                  reason: "Pengulangan kata identik yang berdampingan; hapus satu occurrence.", evidenceIDs: [LegalReviewAgent.digest("local|\(match.range.location)")]))
        }
        let placeholder = try? NSRegularExpression(pattern: #"\[[\p{Lu}][\p{Lu}\p{N}_ /-]{2,60}\]|\b(?:akan[ \t]+(?:ditentukan|disepakati))\b"#)
        let quotes = (try? NSRegularExpression(pattern: #"[“"]([^”"\n]+)[”"]|‘[^’\n]+’"#))?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in placeholder?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            // Uppercase placeholder contents are protected identifiers for edits,
            // but may still be flagged read-only as an explicitly open parameter.
            guard !quotes.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }),
                  !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
            let original = ns.substring(with: match.range)
            findings.append(.init(id: LegalReviewAgent.digest("parameter|\(match.range.location)|\(original)"), category: "missing", original: original, replacement: nil, range: match.range, actionable: false,
                                  reason: "Parameter masih terbuka. Konfirmasi apakah pengguna ingin melengkapinya; ini bukan kesimpulan adanya cacat hukum.", evidenceIDs: [LegalReviewAgent.digest("local|\(match.range.location)")]))
        }
        return findings.sorted { $0.range.location < $1.range.location }
    }
    private static func literalParameterDifference(_ pair: Pair) -> Bool {
        // Numbered article titles alone do not establish different scope, but
        // distinct phase/subject headings must be reviewed contextually.
        func headingScope(_ heading: String) -> String {
            heading.lowercased().replacingOccurrences(of: #"\bpasal\s+[0-9]+\b"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard headingScope(pair.first.heading) == headingScope(pair.second.heading) else { return false }
        func signature(_ text: String) -> (String, [String])? {
            let pattern = pair.kind == "value"
                ? #"(?i)(?<![\p{L}\p{N}.,])([0-9]{1,6})\s*(hari|bulan|tahun|minggu)(?![\p{L}\p{N}])"#
                : #"(?i)\b(harian|mingguan|bulanan|tahunan)\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return nil }
            var shell = text, values: [String] = []
            for match in matches {
                if pair.kind == "value" {
                    guard let value = Int(ns.substring(with: match.range(at: 1))) else { return nil }
                    values.append(String(value) + "|" + ns.substring(with: match.range(at: 2)).lowercased())
                } else { values.append(ns.substring(with: match.range).lowercased()) }
            }
            for match in matches.reversed() {
                let marker = pair.kind == "value" ? "PARAMETER " + ns.substring(with: match.range(at: 2)) : "FREQUENCY"
                shell = (shell as NSString).replacingCharacters(in: match.range, with: marker)
            }
            shell = shell.replacingOccurrences(of: #"(?i)\byang\s+sama\b|\bsecara\b"#, with: " ", options: .regularExpression)
            let normalized = shell.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
            return (normalized, values)
        }
        guard let a = signature(pair.first.text), let b = signature(pair.second.text) else { return false }
        return a.0 == b.0 && a.1 != b.1
    }
    private struct Fact {
        let text: String; let content: Set<String>; let values: Set<String>; let frequency: Set<String>
        let operators: Set<String>; let actors: Set<String>; let exclusive: Bool; let term: String?; let strong: Bool
    }
    private func fact(_ unit: Unit) -> Fact {
        let tokens = Set(unit.text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let numbers = captures(#"\b[0-9]+(?:[.,][0-9]+)*\s*(?:hari|bulan|tahun|minggu|persen|%)"#, unit.text)
        let frequency = tokens.intersection(["bulanan", "mingguan", "harian", "tahunan"])
        let operators = tokens.intersection(["boleh", "diizinkan", "diperbolehkan", "berhak", "berkewajiban", "diperkenankan", "tidak", "bukan", "dilarang", "wajib", "diwajibkan", "dapat", "harus", "tanpa", "hanya", "kecuali", "jika", "apabila"])
        let actors = tokens.intersection(Self.actors)
        let content = tokens.subtracting(Self.stopWords.union(Self.actors).union(operators).union(frequency)).filter { $0.count > 2 && !$0.allSatisfy(\.isNumber) }
        let segment = AIReviewSegment(id: 0, sourceLocation: unit.range.location, sourceLength: unit.range.length, targetText: unit.text, previousContext: nil, nextContext: nil)
        let definition = detector.detect(segment: segment, glossaryMatches: [])
        return .init(text: unit.text, content: Set(content), values: numbers, frequency: frequency, operators: operators, actors: actors,
                     exclusive: tokens.contains("eksklusif"), term: definition.term.map { $0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"id_ID")).lowercased().split(whereSeparator:\.isWhitespace).joined(separator:" ") }, strong: definition.explicitSignalStrength == .strong)
    }
    private func captures(_ pattern: String, _ text: String) -> Set<String> {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return Set((regex?.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) ?? []).map { (text as NSString).substring(with: $0.range).lowercased() })
    }
    // Exact repetition is not universally erroneous: masing masing, sama sama,
    // undang undang and plural nouns require separate morphology review.
    private static let duplicateWords: Set<String> = ["wajib", "harus", "dapat", "setelah", "sebelum", "merupakan", "adalah", "bahwa", "akan", "telah", "untuk", "menyimpan", "menjaga", "menerima", "menyerahkan", "menyampaikan", "menyetujui", "dicatat", "dilakukan", "diterima", "ditandatangani", "dibayar", "membayar", "mengirim", "melakukan", "memberikan", "memeriksa", "diperiksa", "berlaku"]
    private static let actors: Set<String> = ["penyedia", "pelanggan", "penerima", "pemegang", "pemasok", "pembeli", "penjual", "pelaksana", "pengguna", "pengolah", "distributor", "pemberi", "pemesan"]
    private static let stopWords: Set<String> = ["yang", "sama", "seluruh", "secara", "adalah", "ialah", "merupakan", "berarti", "dimaksud", "dengan", "dalam", "untuk", "dari", "kepada", "dan", "atau", "oleh", "pada", "ini", "itu", "tersebut", "sejak", "setelah", "sebelum", "selama", "sebagai", "pasal", "ayat", "bagian", "tenggat", "jangka", "waktu", "berlaku", "hari", "bulan", "tahun", "minggu", "akan", "telah"]
}
