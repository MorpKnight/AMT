import Foundation

/// The automatic route recognizes whole, unquoted commands only. Caller-supplied
/// typed permissions are checked separately and never extracted from document text.
@MainActor
enum DraftingLiteralRouter {
    static func requestWithLiteralPermission(_ prepared: DraftingReview.PreparedRequest) -> DraftingReview.Request? {
        let input = prepared.request
        if !input.permissions.isEmpty { return input }
        guard input.scope == .rewriteTarget, input.targetClauseIDs.count == 1,
              prepared.definitions.isEmpty, prepared.references.isEmpty,
              input.requiredDefinitionIDs.isEmpty, input.requiredReferenceIDs.isEmpty,
              let clause = input.clauses.first(where: { $0.id == input.targetClauseIDs[0] }) else { return nil }
        // Other clauses and irrelevant definitions are context, not an additional
        // edit target. Permission still binds only to the selected clause.
        let brief = input.brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = CharacterSet(charactersIn: "\"'`“”‘’«»")
        guard brief.rangeOfCharacter(from: quotes) == nil, clause.text.rangeOfCharacter(from: quotes) == nil else { return nil }
        let id = NSRegularExpression.escapedPattern(for: clause.id)
        let subjects = "tenggat laporan|tenggat pembayaran|durasi perjanjian|durasi kerahasiaan|masa pemberitahuan pengakhiran|masa jaminan|frekuensi laporan"
        let pattern = "^(?:Tinjau hanya (?:klausul )?" + id + "\\.\\s*)?(?:Ubah|Ganti) (" + subjects + ") menjadi ([^.]+)\\.(?:\\s*(Pertahankan [^.]+\\.))?$"
        guard let command = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = command.firstMatch(in: brief, range: NSRange(location: 0, length: brief.utf16.count)) else { return nil }
        let nsBrief = brief as NSString
        let subject = nsBrief.substring(with: match.range(at: 1)).lowercased()
        let requested = nsBrief.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = match.range(at: 3).location == NSNotFound ? "" : nsBrief.substring(with: match.range(at: 3)).lowercased()
        if remainder.range(of: #"\b(?:ubah|ganti|jangan|tetapi|namun)\b"#, options: .regularExpression) != nil { return nil }
        let frequency = subject == "frekuensi laporan"
        let unit = #"[0-9]+ (?:hari kerja|hari kalender|hari|jam|minggu|bulan|tahun)"#
        let valuePattern = frequency
            ? #"^(harian|mingguan|bulanan|tahunan)$"#
            : "^(" + unit + #")(?: ((?:setelah|sejak|sebelum) [\p{L} ]+))?$"#
        guard let valueExpression = try? NSRegularExpression(pattern: valuePattern, options: .caseInsensitive),
              let valueMatch = valueExpression.firstMatch(in: requested, range: NSRange(location: 0, length: requested.utf16.count)) else { return nil }
        let value = (requested as NSString).substring(with: valueMatch.range(at: 1))
        // A single eligible time/frequency atom avoids selecting a phase, report
        // type or second deadline on behalf of the user.
        let atomPattern = frequency ? #"\b(?:harian|mingguan|bulanan|tahunan)\b"# : "\\b" + unit + "\\b"
        guard let atoms = try? NSRegularExpression(pattern: atomPattern),
              atoms.numberOfMatches(in: clause.text, range: NSRange(location: 0, length: clause.text.utf16.count)) == 1 else { return nil }
        let predicate: String
        switch subject {
        case "tenggat laporan": predicate = #"\b(?:mengirim|menyerahkan|menyampaikan) laporan (?:dalam|paling lambat)\s+"#
        case "tenggat pembayaran": predicate = #"\b(?:(?:membayar|melakukan pembayaran) (?:dalam|paling lambat)|[Pp]embayaran dilakukan (?:dalam|paling lambat))\s+"#
        case "durasi kerahasiaan": predicate = #"\b(?:[Kk]ewajiban )?kerahasiaan berlaku selama\s+"#
        case "masa pemberitahuan pengakhiran": predicate = #"\b(?:memberi|memberikan) pemberitahuan pengakhiran\s+"#
        case "masa jaminan": predicate = #"\b(?:menjamin hasil pekerjaan selama|masa jaminan (?:adalah|selama))\s+"#
        case "frekuensi laporan": predicate = #"\b(?:mengirim|menyerahkan|menyampaikan) laporan\s+"#
        default: predicate = #"\b(?:[Pp]erjanjian|[Kk]ontrak) berlaku selama\s+"#
        }
        let oldPattern = predicate + "(" + (frequency ? #"harian|mingguan|bulanan|tahunan"# : unit) + ")\\b"
        guard let expression = try? NSRegularExpression(pattern: oldPattern) else { return nil }
        let matches = expression.matches(in: clause.text, range: NSRange(location: 0, length: clause.text.utf16.count))
        guard matches.count == 1, let oldMatch = matches.first else { return nil }
        let range = oldMatch.range(at: 1)
        let ns = clause.text as NSString
        let original = ns.substring(with: range)
        guard original.lowercased() != value.lowercased() else { return nil }
        let preceding = ns.substring(to: oldMatch.range.location).lowercased()
        if preceding.range(of: #"\b(?:kecuali|jika|apabila|sepanjang|asalkan|setelah|sebelum|sejak)\b"#, options: .regularExpression) != nil { return nil }
        if !frequency, valueMatch.range(at: 2).location != NSNotFound {
            let trigger = DraftingReviewPreparation.normalized((requested as NSString).substring(with: valueMatch.range(at: 2)))
            let tail = ns.substring(from: NSMaxRange(range))
                .components(separatedBy: CharacterSet(charactersIn: ",.;!?"))[0]
            guard DraftingReviewPreparation.normalized(tail) == trigger else { return nil }
        }
        let before = DraftingReviewValidator.signature(original)
        let after = DraftingReviewValidator.signature(value)
        for key in before.keys where before[key] != after[key] {
            if before[key, default: []].contains(where: { remainder.contains($0) }) { return nil }
        }
        var request = input
        request.permissions = [.init(clauseID: clause.id, original: original, replacement: value, source: .brief)]
        let candidate = DraftingReview.PreparedRequest(request: request, definitions: prepared.definitions,
            references: prepared.references, protectionContext: prepared.protectionContext)
        return DraftingReviewPreparation.permissionFailures(candidate).isEmpty ? request : nil
    }

    static func response(_ prepared: DraftingReview.PreparedRequest) -> DraftingReview.Response? {
        let request = prepared.request
        guard request.scope == .rewriteTarget, !request.permissions.isEmpty,
              DraftingReviewPreparation.permissionFailures(prepared).isEmpty else { return nil }
        let targets = Set(request.permissions.map(\.clauseID))
        let findings = request.clauses.filter { targets.contains($0.id) }.compactMap { clause -> DraftingReview.Finding? in
            let proposed = DraftingReviewPreparation.expectedText(for: clause, request: request)
            guard proposed != clause.text else { return nil }
            let referenceIDs = request.requiredReferenceIDs.filter { id in
                request.permissions.contains { $0.clauseID == clause.id && $0.source == .reference(id) }
            }
            return .init(clauseID: clause.id, quote: clause.text, category: "business",
                         reason: "Perubahan literal mengikuti izin eksplisit peminta.", suggestedText: proposed,
                         clarificationQuestion: nil, substanceChange: "authorized", referenceIDs: referenceIDs)
        }
        return findings.isEmpty ? nil : .init(decision: .revise, findings: findings)
    }
}
