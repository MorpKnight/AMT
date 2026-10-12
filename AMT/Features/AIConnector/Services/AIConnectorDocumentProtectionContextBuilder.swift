import Foundation

struct AIConnectorDocumentProtectionContextBuilder: Sendable {
    func build(
        documentText: String,
        additionalDefinedTerms: Set<String> = []
    ) -> AIConnectorDocumentProtectionContext {
        let quotedTerms = matches(
            pattern: #"[\"“]([^\"”]+)[\"”]"#,
            in: documentText,
            captureGroup: 1
        )
        let acronyms = matches(
            pattern: #"\b[A-Z][A-Z0-9]{1,}\b"#,
            in: documentText
        )
        let identifiers = matches(
            pattern: #"\b[A-Za-z0-9]+(?:[-/_][A-Za-z0-9]+)+\b"#,
            in: documentText
        ) + matches(
            pattern: #"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"#,
            in: documentText
        ) + matches(
            pattern: #"(?i)\b(?:https?://|www\.)[^\s<>()]+"#,
            in: documentText
        ) + matches(
            pattern: #"(?i)\b(?:nomor|no\.)\s*[0-9][A-Za-z0-9./-]*\b"#,
            in: documentText
        )
        let partyNames = matches(
            pattern: #"\b(?:Pihak\s+[A-Z][\p{L}]+(?:\s+[A-Z][\p{L}]+){0,2}|Para\s+Pihak|Borrower|Lender)\b"#,
            in: documentText
        )

        let namedEntities = matches(
            pattern: #"\b(?:PT\.?|CV\.?)\s+[A-Z][\p{L}]+(?:\s+[A-Z][\p{L}]+){0,4}|(?i:produk|perusahaan|diwakili\s+oleh|atas\s+nama)\s+(?:bernama\s+)?[A-Z][\p{L}]+(?:\s+[A-Z][\p{L}]+){0,3}"#,
            in: documentText
        )
        let explicitTerms = matches(pattern: #"(?im)(?:yang\s+dimaksud\s+dengan\s+)([\p{L}][\p{L}\s]{1,100}?)\s+(?:adalah|ialah)|^[ \t]*(?:[“"]([^”"\n]+)[”"]|([\p{L}][\p{L} \t]{1,100}?))\s+(?:didefinisikan|diartikan)\s+sebagai"#,
            in: documentText, captureGroup: 1)
        let quotedDefinitions = matches(pattern: #"[“"]([^”"\n]+)[”"]\s+(?:adalah|ialah|merupakan|berarti|didefinisikan\s+sebagai|diartikan\s+sebagai)"#,
            in: documentText, captureGroup: 1)

        let namedDeclarations = matches(
            pattern: #"(?i)\b(?:yang\s+)?selanjutnya\s+disebut\s+[“\"]([^”\"]+)[”\"]"#,
            in: documentText, captureGroup: 1)
        var definedTerms = Set(quotedTerms)
        definedTerms.formUnion(namedDeclarations)
        definedTerms.formUnion(additionalDefinedTerms)

        var result = AIConnectorDocumentProtectionContext(
            definedTerms: definedTerms,
            partyNames: Set(partyNames + namedEntities),
            acronyms: Set(acronyms),
            quotedTerms: Set(quotedTerms),
            identifiers: Set(identifiers)
        )
        result.explicitDocumentTerms = Array(Set(explicitTerms + quotedDefinitions + namedDeclarations + matches(
            pattern: #"(?im)^[ \t]*([\p{L}][\p{L} \t]{1,100}?)\s+(?:didefinisikan|diartikan)\s+sebagai"#,
            in: documentText, captureGroup: 1))).sorted().filter { term in
            !namedEntities.contains(where: { $0.localizedCaseInsensitiveContains(term) })
        }
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: documentText)
        let headingTerms = structure.blocks.filter { block in
            block.headingPath.contains { $0.range(of: #"(?i)definisi|pengertian"#, options: .regularExpression) != nil }
        }.flatMap { block in
            matches(pattern: #"(?i)^\s*(?:[0-9]+[.)]\s*)?([\p{L}][\p{L} \t]{1,100}?)\s+(?:adalah|ialah|merupakan|berarti)\b"#,
                in: block.text, captureGroup: 1)
        }
        result.explicitDocumentTerms = Array(Set(result.explicitDocumentTerms + headingTerms)).sorted()
        for term in result.explicitDocumentTerms {
            let declaration = structure.blocks.first {
                $0.text.localizedCaseInsensitiveContains(term)
                    && $0.text.range(of: #"(?i)yang\s+dimaksud\s+dengan|selanjutnya\s+disebut|didefinisikan|diartikan|[“"][^”"]+[”"]\s+(?:adalah|ialah|merupakan|berarti)"#, options: .regularExpression) != nil
            }
            let section = declaration.flatMap { structure.section(for: $0.parentSectionID) }
            let isDocumentScope = section == nil || (section?.headingPath ?? []).contains {
                $0.range(of: #"(?i)definisi|pengertian|ketentuan\s+umum"#, options: .regularExpression) != nil
            }
            result.explicitTermScopes[term] = [isDocumentScope
                ? NSRange(location: 0, length: documentText.utf16.count)
                : section?.sourceRange ?? NSRange(location: 0, length: 0)]
        }
        result.revisionText = documentText
        let hardPatterns = [
            #"[“"]([^”"\n]+)[”"]"#,
            #"\b[A-Z][A-Z0-9]{1,}\b"#,
            #"\b[A-Za-z0-9]+(?:[-/_][A-Za-z0-9]+)+\b"#
        ]
        result.protectedSourceRanges = hardPatterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: documentText, range: NSRange(documentText.startIndex..<documentText.endIndex, in: documentText)).map(\.range)
        }
        let ns = documentText as NSString
        for value in partyNames + namedEntities {
            var location = 0
            while location < ns.length {
                let range = ns.range(of: value, options: [.literal, .caseInsensitive],
                    range: NSRange(location: location, length: ns.length - location))
                guard range.location != NSNotFound else { break }
                result.protectedSourceRanges.append(range)
                location = NSMaxRange(range)
            }
        }
        return result
    }

    private func matches(
        pattern: String,
        in text: String,
        captureGroup: Int? = nil
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let resultRange = match.range(at: captureGroup ?? 0)
            guard resultRange.location != NSNotFound,
                  let swiftRange = Range(resultRange, in: text) else {
                return nil
            }
            return String(text[swiftRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
