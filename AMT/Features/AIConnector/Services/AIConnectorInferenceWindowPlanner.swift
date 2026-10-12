import Foundation

nonisolated struct AIConnectorInputCoverage: Codable, Hashable, Sendable {
    let windowRanges: [NSRange]
    let omittedRanges: [NSRange]
    let tokenCounts: [Int]
    let reason: String?
    var rangeScope: String = "segment"
    var reviewedRanges: [NSRange]? = nil
    var isComplete: Bool { omittedRanges.isEmpty }
}

nonisolated struct AIConnectorInputBudgetError: Error, LocalizedError, Sendable {
    let coverage: AIConnectorInputCoverage
    var errorDescription: String? { coverage.reason ?? "Input wajib tidak muat dalam anggaran token; perlu review manusia." }
}

/// Windows contain complete independent clauses. Ambiguous condition scope remains whole.
/// Range offsets always refer to the unchanged parent's UTF-16 text.
nonisolated enum AIConnectorInferenceWindowPlanner {
    static let maximumWindows = 16
    static let maximumTargetTokens = 512
    static let maximumPromptTokens = 4_096
    static let version = "bounded-input-v1-complete-evidence"

    static func plan(_ text: String, countTokens: (String) async throws -> Int) async throws -> AIConnectorInputCoverage {
        let full = NSRange(location: 0, length: text.utf16.count)
        let fullTokens = try await countTokens(text)
        if fullTokens <= maximumTargetTokens {
            return AIConnectorInputCoverage(windowRanges: [full], omittedRanges: [], tokenCounts: [fullTokens], reason: nil)
        }
        // A condition/exception can govern a preceding enumeration or following obligation.
        // Do not infer its scope from punctuation alone.
        let scopePattern = #"(?i)\b(jika|apabila|kecuali|sepanjang|asalkan|hanya|tanpa)\b"#
        if text.range(of: scopePattern, options: .regularExpression) != nil {
            return AIConnectorInputCoverage(windowRanges: [], omittedRanges: [full], tokenCounts: [], reason: "Lingkup syarat atau pengecualian pada klausa panjang tidak dapat dipisahkan dengan aman.")
        }
        let source = text as NSString
        let units = independentRanges(text)
        var windows: [NSRange] = [], omitted: [NSRange] = [], counts: [Int] = []
        var pending: NSRange?
        func joined(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
            NSRange(location: lhs.location, length: NSMaxRange(rhs) - lhs.location)
        }
        func append(_ range: NSRange, tokens: Int) {
            if windows.count < maximumWindows { windows.append(range); counts.append(tokens) }
            else { omitted.append(range) }
        }
        var pendingCount = 0
        for range in units {
            try Task.checkCancellation()
            let count = try await countTokens(source.substring(with: range))
            if count > maximumTargetTokens {
                if let current = pending { append(current, tokens: pendingCount); pending = nil }
                omitted.append(range); continue
            }
            if let current = pending {
                let combined = joined(current, range)
                let combinedCount = try await countTokens(source.substring(with: combined))
                if combinedCount <= maximumTargetTokens { pending = combined; pendingCount = combinedCount }
                else { append(current, tokens: pendingCount); pending = range; pendingCount = count }
            } else { pending = range; pendingCount = count }
        }
        if let current = pending { append(current, tokens: pendingCount) }
        return AIConnectorInputCoverage(windowRanges: windows, omittedRanges: omitted, tokenCounts: counts,
                                       reason: omitted.isEmpty ? nil : "Sebagian klausa melebihi batas token atau batas 16 window.")
    }

    private static func independentRanges(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = [], start = text.startIndex
        var quote: Character?
        let closing: [Character: Character] = ["'": "'", "\"": "\"", "“": "”", "‘": "’", "«": "»"]
        for index in text.indices {
            let character = text[index]
            if let active = quote {
                if character == active { quote = nil }
            } else if let end = closing[character] { quote = end }
            guard quote == nil, [",", ";", "\n", ".", "!", "?"].contains(character) else { continue }
            let next = text.index(after: index)
            if character == ",", index > text.startIndex, next < text.endIndex,
               text[text.index(before: index)].isNumber, text[next].isNumber { continue }
            // Comma-separated fragments are not independently interpretable unless
            // the next clause has its own explicit actor; semicolon/list items are units.
            if [",", ".", "!", "?"].contains(character) {
                guard next < text.endIndex, text[next].isWhitespace else { continue }
                if character == "." {
                    let preceding = text[start..<index].split(whereSeparator: { $0.isWhitespace }).last?.lowercased() ?? ""
                    if ["pt", "cv", "no", "dr", "prof", "sdr", "jl"].contains(preceding) { continue }
                }
                let suffix = text[next...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard ["pihak ", "pembeli ", "penjual ", "perusahaan "].contains(where: suffix.hasPrefix) else { continue }
            }
            ranges.append(NSRange(start..<next, in: text)); start = next
        }
        if start < text.endIndex { ranges.append(NSRange(start..<text.endIndex, in: text)) }
        return ranges
    }
}
