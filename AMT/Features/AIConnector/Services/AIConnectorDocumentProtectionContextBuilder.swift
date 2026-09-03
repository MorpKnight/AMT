import Foundation

struct AIConnectorDocumentProtectionContextBuilder: Sendable {
    func build(documentText: String) -> AIConnectorDocumentProtectionContext {
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
            pattern: #"\b[A-Za-z0-9]+(?:[-/][A-Za-z0-9]+)+\b"#,
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

        var definedTerms = Set(quotedTerms)
        definedTerms.formUnion(
            matches(
                pattern: #"(?i)\b(?:yang\s+)?selanjutnya\s+disebut\s+[“\"]([^”\"]+)[”\"]"#,
                in: documentText,
                captureGroup: 1
            )
        )

        return AIConnectorDocumentProtectionContext(
            definedTerms: definedTerms,
            partyNames: Set(partyNames),
            acronyms: Set(acronyms),
            quotedTerms: Set(quotedTerms),
            identifiers: Set(identifiers)
        )
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
