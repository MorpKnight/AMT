import Foundation

/// Additional read/edit boundary for quotations and code, shared by discovery and validation.
@MainActor
struct LegalReviewProtection {
    static func ranges(in text: String) -> [NSRange] {
        let patterns = [#"[“\"][^”\"\n]+[”\"]"#, #"‘[^’\n]+’|«[^»\n]+»"#,
                        #"(?<![\p{L}\p{N}])'[^'\n]+'(?![\p{L}\p{N}])"#,
                        #"(?s)```.*?(?:```|$)"#, #"`[^`\n]+(?:`|$)"#]
        return patterns.flatMap { pattern in
            (try? NSRegularExpression(pattern: pattern))?.matches(in: text,
                range: NSRange(location: 0, length: text.utf16.count)).map(\.range) ?? []
        }
    }
    static func contains(_ range: NSRange, in text: String) -> Bool {
        ranges(in: text).contains { NSIntersectionRange($0, range).length > 0 }
    }
}
