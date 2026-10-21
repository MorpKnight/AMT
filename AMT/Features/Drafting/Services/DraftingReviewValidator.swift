import Foundation

/// Validates schema, source namespaces and bounded protected-pattern changes.
/// Passing this validator never makes a proposal an actionable editor edit.
@MainActor
enum DraftingReviewValidator {
    struct Validation {
        let response: DraftingReview.Response?
        let failures: [String]
        let anchors: [DraftingReview.Anchor]
    }

    static func parse(_ raw: String, prepared: DraftingReview.PreparedRequest) -> Validation {
        guard let data = raw.data(using: .utf8),
              let parsed = DraftingReviewJSON.object(raw), !parsed.hasDuplicateKeys,
              case let root = parsed.root,
              Set(root.keys) == ["decision", "findings"],
              let list = root["findings"] as? [[String: Any]], list.count <= 4,
              list.allSatisfy({ Set($0.keys) == ["clause_id", "quote", "category", "reason", "suggested_text", "clarification_question", "substance_change", "reference_ids"] }),
              let response = try? JSONDecoder().decode(DraftingReview.Response.self, from: data) else {
            return .init(response: nil, failures: ["invalidSchema"], anchors: [])
        }
        return validate(response, prepared: prepared)
    }

    static func validate(_ response: DraftingReview.Response, prepared: DraftingReview.PreparedRequest) -> Validation {
        let request = prepared.request
        var failures = DraftingReviewPreparation.permissionFailures(prepared)
        var anchors: [DraftingReview.Anchor] = []
        var seen: Set<String> = []
        if response.findings.count > 4 { failures.append("tooManyFindings") }
        if (response.decision == .noChange) != response.findings.isEmpty { failures.append("decisionFindingsConflict") }
        if response.decision != .revise && !request.permissions.isEmpty { failures.append("authorizedChangesNotReviewed") }
        for finding in response.findings {
            guard request.targetClauseIDs.contains(finding.clauseID),
                  let clause = request.clauses.first(where: { $0.id == finding.clauseID }) else {
                failures.append("nonTargetClause"); continue
            }
            guard let quoteRange = DraftingReviewPreparation.uniqueRange(of: finding.quote, in: clause.text) else {
                failures.append("invalidOrAmbiguousQuote"); continue
            }
            anchors.append(.init(clauseID: clause.id,
                                 sourceRange: NSRange(location: clause.sourceRange.location + quoteRange.location, length: quoteRange.length),
                                 original: finding.quote))
            if !seen.insert(clause.id).inserted { failures.append("duplicateFinding") }
            if finding.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failures.append("missingReason") }
            if !["language", "consistency", "completeness", "business"].contains(finding.category) { failures.append("invalidCategory") }
            if Set(finding.referenceIDs).count != finding.referenceIDs.count
                || !Set(finding.referenceIDs).isSubset(of: Set(prepared.references.map(\.id))) { failures.append("unknownReference") }
            let numericEvidence = request.brief + " " + clause.text + " "
                + prepared.references.filter { finding.referenceIDs.contains($0.id) }.map(\.body).joined(separator: " ")
            if response.decision == .clarify {
                if finding.suggestedText != nil || finding.clarificationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                    || finding.substanceChange != "undetermined" { failures.append("invalidClarificationContract") }
                if let question = finding.clarificationQuestion, !Set(numbers(question)).isSubset(of: Set(numbers(numericEvidence))) {
                    failures.append("unsupportedQuestionValue")
                }
            }
            if response.decision == .revise {
                guard let replacement = finding.suggestedText, !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      finding.clarificationQuestion == nil, replacement != finding.quote,
                      ["none", "authorized"].contains(finding.substanceChange) else {
                    failures.append("invalidRevisionContract"); continue
                }
                if !Set(numbers(replacement)).isSubset(of: Set(numbers(numericEvidence))) { failures.append("unsupportedRevisionValue") }
                let proposed = (clause.text as NSString).replacingCharacters(in: quoteRange, with: replacement)
                let permissions = request.permissions.filter { $0.clauseID == clause.id }
                if finding.substanceChange == "authorized" && permissions.isEmpty { failures.append("missingMutationPermission") }
                if !permissions.isEmpty {
                    if finding.substanceChange != "authorized" { failures.append("invalidPermissionFlag") }
                    if proposed != DraftingReviewPreparation.expectedText(for: clause, request: request) { failures.append("outsideAuthorizedRanges") }
                    for permission in permissions {
                        if case .reference(let id) = permission.source, !finding.referenceIDs.contains(id) { failures.append("permissionReferenceNotCited") }
                    }
                }
                let expected = DraftingReviewPreparation.expectedText(for: clause, request: request)
                let before = signature(expected), after = signature(proposed)
                for key in before.keys.sorted() where before[key] != after[key] { failures.append("protectedDelta:" + key) }
                if permissions.isEmpty {
                    let changed = changedRange(original: finding.quote, replacement: replacement)
                    let absolute = NSRange(location: clause.sourceRange.location + quoteRange.location + changed.location, length: changed.length)
                    if prepared.protectionContext.protectedSourceRanges.contains(where: {
                        NSIntersectionRange($0, absolute).length > 0 || (absolute.length == 0 && NSLocationInRange(absolute.location, $0))
                    }) { failures.append("protectedSourceDelta") }
                }
            }
        }
        if response.decision == .revise && !Set(request.permissions.map(\.clauseID)).isSubset(of: seen) {
            failures.append("missingAuthorizedTarget")
        }
        return .init(response: response, failures: Array(Set(failures)).sorted(), anchors: anchors)
    }

    static func signature(_ text: String) -> [String: [String]] {
        let value = DraftingReviewPreparation.normalized(text)
        let patterns = [
            "numbers": #"[0-9]+(?:[.,][0-9]+)*"#,
            "units": #"\b(?:hari kerja|hari kalender|hari|jam|menit|minggu|bulan|tahun|harian|mingguan|bulanan|tahunan|rupiah|persen)\b"#,
            "actors": #"\b(?:pemberi kerja|pemberi|penerima|penyedia|pelanggan|pekerja|pengguna|penasihat)\b"#,
            "modality": #"\b(?:wajib|harus|dapat|boleh|dilarang)\b"#,
            "negation": #"\b(?:tidak|bukan|tanpa)\b"#,
            "triggers": #"\b(?:sejak|setelah|sebelum)\b[^.;!?]*"#,
            "conditions": #"\b(?:kecuali|jika|apabila|sepanjang|asalkan)\b[^.;!?]*"#
        ]
        return patterns.mapValues { matches($0, in: value) }
    }

    private static func numbers(_ text: String) -> [String] { matches(#"[0-9]+(?:[.,][0-9]+)*"#, in: text) }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func changedRange(original: String, replacement: String) -> NSRange {
        let prefix = zip(original, replacement).prefix { $0 == $1 }.count
        let first = original.index(original.startIndex, offsetBy: prefix)
        let otherFirst = replacement.index(replacement.startIndex, offsetBy: prefix)
        let suffix = zip(original[first...].reversed(), replacement[otherFirst...].reversed()).prefix { $0 == $1 }.count
        let last = original.index(original.endIndex, offsetBy: -suffix)
        return NSRange(first..<last, in: original)
    }
}
