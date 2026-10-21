import Foundation

/// Binds complete evidence to the current document before inference. Definition
/// closure is literal and scope-aware; it does not infer unstated dependencies.
@MainActor
enum DraftingReviewPreparation {
    static func failures(_ request: DraftingReview.Request) -> [String] {
        validateAndPrepare(request).failures
    }

    static func validateAndPrepare(_ request: DraftingReview.Request) -> (prepared: DraftingReview.PreparedRequest?, failures: [String]) {
        var failures: [String] = []
        if request.documentRevision != DocumentFingerprinting.contentSHA256(request.documentText) {
            failures.append("staleDocumentRevision")
        }
        if normalized(request.brief).isEmpty { failures.append("missingBrief") }
        let clauseIDs = Set(request.clauses.map(\.id))
        if request.clauses.isEmpty || clauseIDs.count != request.clauses.count
            || request.clauses.contains(where: { $0.id.isEmpty }) { failures.append("invalidClauseIDs") }
        if request.targetClauseIDs.isEmpty || Set(request.targetClauseIDs).count != request.targetClauseIDs.count
            || !Set(request.targetClauseIDs).isSubset(of: clauseIDs) { failures.append("invalidTargets") }
        for clause in request.clauses {
            if normalized(clause.text).isEmpty || !isAnchored(clause.text, range: clause.sourceRange, in: request.documentText) {
                failures.append("invalidClauseAnchor")
            }
        }
        let ranges = request.clauses.map(\.sourceRange).sorted { $0.location < $1.location }
        for (first, second) in zip(ranges, ranges.dropFirst()) {
            if NSIntersectionRange(first, second).length > 0 { failures.append("overlappingClauses") }
        }
        let definitionIDs = Set(request.definitions.map(\.id))
        if definitionIDs.count != request.definitions.count { failures.append("duplicateDefinitionID") }
        if !Set(request.requiredDefinitionIDs).isSubset(of: definitionIDs) { failures.append("missingRequiredDefinition") }
        let applicable = request.definitions.filter {
            $0.scopeClauseIDs.isEmpty || !Set($0.scopeClauseIDs).isDisjoint(with: clauseIDs)
        }
        for definition in request.definitions {
            if definition.id.isEmpty || normalized(definition.term).isEmpty || normalized(definition.body).isEmpty
                || !isAnchored(definition.body, range: definition.sourceRange, in: request.documentText) {
                failures.append("invalidDefinitionEvidence")
            }
            if !Set(definition.scopeClauseIDs).isSubset(of: clauseIDs) { failures.append("unknownDefinitionScope") }
        }
        if !Set(request.requiredDefinitionIDs).isSubset(of: Set(applicable.map(\.id))) {
            failures.append("definitionOutsideScope")
        }
        if Set(request.references.map(\.id)).count != request.references.count { failures.append("duplicateReferenceID") }
        if request.references.contains(where: { $0.id.isEmpty || $0.revision.isEmpty || normalized($0.body).isEmpty }) {
            failures.append("invalidReferenceEvidence")
        }
        let eligible = request.references.filter(\.isEligibleForReview)
        if !Set(request.requiredReferenceIDs).isSubset(of: Set(eligible.map(\.id))) {
            failures.append("missingEligibleReference")
        }
        if !failures.isEmpty { return (nil, Array(Set(failures)).sorted()) }
        let prepared = prepare(request)
        if Set(prepared.definitions.map { normalized($0.term) }).count != prepared.definitions.count {
            failures.append("ambiguousDefinitionTerm")
        }
        failures += permissionFailures(prepared)
        return (prepared, Array(Set(failures)).sorted())
    }

    static func prepare(_ request: DraftingReview.Request) -> DraftingReview.PreparedRequest {
        let clauseIDs = Set(request.clauses.map(\.id))
        let applicable = request.definitions.filter {
            $0.scopeClauseIDs.isEmpty || !Set($0.scopeClauseIDs).isDisjoint(with: clauseIDs)
        }
        let references = request.references.filter {
            request.requiredReferenceIDs.contains($0.id) && $0.isEligibleForReview
        }
        var selected = Set(request.requiredDefinitionIDs)
        var text = request.brief + " " + request.clauses.map(\.text).joined(separator: " ")
            + " " + references.map(\.body).joined(separator: " ")
            + " " + applicable.filter { selected.contains($0.id) }.map(\.body).joined(separator: " ")
        while true {
            let next = Set(applicable.filter { mentions($0.term, in: text) }.map(\.id)).union(selected)
            if next == selected { break }
            selected = next
            text += " " + applicable.filter { selected.contains($0.id) }.map(\.body).joined(separator: " ")
        }
        var protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: request.documentText)
        // Reuse the production entity inventory and also protect quoted/code
        // containers and complete identifiers (URLs, email, document numbers).
        let ns = request.documentText as NSString
        for identifier in protection.identifiers {
            var location = 0
            while location < ns.length {
                let range = ns.range(of: identifier, options: .literal,
                                     range: NSRange(location: location, length: ns.length - location))
                guard range.location != NSNotFound else { break }
                protection.protectedSourceRanges.append(range)
                location = NSMaxRange(range)
            }
        }
        for pattern in [#"'[^'\n]+'|‘[^’\n]+’|«[^»\n]+»"#, #"(?s)```.*?```|`[^`\n]+`"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                protection.protectedSourceRanges += regex.matches(in: request.documentText,
                    range: NSRange(location: 0, length: ns.length)).map(\.range)
            }
        }
        return .init(request: request, definitions: applicable.filter { selected.contains($0.id) }, references: references,
                     protectionContext: protection)
    }

    static func permissionFailures(_ prepared: DraftingReview.PreparedRequest) -> [String] {
        let request = prepared.request
        var failures: [String] = []
        var used: [String: [NSRange]] = [:]
        if request.scope == .verifyDocument && !request.permissions.isEmpty { failures.append("verifyHasPermissions") }
        if Set(request.permissions.map(\.clauseID)).count > 4 { failures.append("tooManyPermissionTargets") }
        for permission in request.permissions {
            guard request.targetClauseIDs.contains(permission.clauseID),
                  let clause = request.clauses.first(where: { $0.id == permission.clauseID }),
                  let range = permissionRange(of: permission.original, in: clause.text),
                  permission.original != permission.replacement else {
                failures.append("invalidPermissionAnchor"); continue
            }
            if used[clause.id, default: []].contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                failures.append("overlappingPermissions")
            }
            used[clause.id, default: []].append(range)
            let absolute = NSRange(location: clause.sourceRange.location + range.location, length: range.length)
            if prepared.protectionContext.protectedSourceRanges.contains(where: { NSIntersectionRange($0, absolute).length > 0 }) {
                failures.append("protectedPermissionAnchor")
            }
            let evidence: String?
            switch permission.source {
            case .brief: evidence = request.brief
            case .reference(let id): evidence = prepared.references.first(where: { $0.id == id })?.body
            }
            guard let evidence else { failures.append("invalidPermissionSource"); continue }
            let value = permission.replacement.isEmpty ? permission.original : permission.replacement
            if !mentions(value, in: evidence) { failures.append("permissionValueNotInSource") }
        }
        return failures
    }

    static func expectedText(for clause: DraftingReview.Clause, request: DraftingReview.Request) -> String {
        let edits = request.permissions.filter { $0.clauseID == clause.id }.compactMap { permission -> (NSRange, String)? in
            guard let range = permissionRange(of: permission.original, in: clause.text) else { return nil }
            return (range, permission.replacement)
        }.sorted { $0.0.location > $1.0.location }
        return edits.reduce(clause.text) { ($0 as NSString).replacingCharacters(in: $1.0, with: $1.1) }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "id_ID"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func mentions(_ phrase: String, in text: String) -> Bool {
        guard !normalized(phrase).isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: normalized(phrase)) + "(?![\\p{L}\\p{N}_])"
        return normalized(text).range(of: pattern, options: .regularExpression) != nil
    }

    static func uniqueRange(of original: String, in text: String) -> NSRange? {
        guard !original.isEmpty else { return nil }
        let ns = text as NSString
        let first = ns.range(of: original, options: .literal)
        guard first.location != NSNotFound, Range(first, in: text) != nil else { return nil }
        // Start one UTF-16 unit later to also detect overlapping occurrences.
        let remaining = NSRange(location: first.location + 1, length: ns.length - first.location - 1)
        guard ns.range(of: original, options: .literal, range: remaining).location == NSNotFound else { return nil }
        return first
    }

    private static func permissionRange(of original: String, in text: String) -> NSRange? {
        guard let range = uniqueRange(of: original, in: text) else { return nil }
        let startsWithAtom = original.unicodeScalars.first.map { CharacterSet.alphanumerics.contains($0) } ?? false
        let endsWithAtom = original.unicodeScalars.last.map { CharacterSet.alphanumerics.contains($0) } ?? false
        let pattern = (startsWithAtom ? "(?<![\\p{L}\\p{N}_])" : "")
            + NSRegularExpression.escapedPattern(for: original)
            + (endsWithAtom ? "(?![\\p{L}\\p{N}_])" : "")
        guard let expression = try? NSRegularExpression(pattern: pattern),
              expression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).contains(where: { $0.range == range }) else { return nil }
        return range
    }

    static func isAnchored(_ original: String, range: NSRange, in text: String) -> Bool {
        guard let swiftRange = Range(range, in: text) else { return false }
        return String(text[swiftRange]) == original
    }
}
