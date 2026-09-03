import Foundation

enum AIConnectorGenerationDiagnostics {
    nonisolated static let repetitionThreshold = 0.2

    nonisolated private static let reasoningMarkers = [
        "<think>",
        "</think>",
        "<|im_start|>",
        "<|im_end|>"
    ]

    nonisolated static func repeatedSixGramRatio(in output: String) -> Double {
        let tokens = normalizedTokens(in: output)
        guard tokens.count >= 6 else { return 0 }

        var counts: [String: Int] = [:]
        for index in 0...(tokens.count - 6) {
            let gram = tokens[index..<(index + 6)].joined(separator: " ")
            counts[gram, default: 0] += 1
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let repeated = counts.values.reduce(0) { partialResult, count in
            partialResult + max(0, count - 1)
        }
        return Double(repeated) / Double(total)
    }

    /// Measures repetition within each contract value. ORIGINAL and
    /// REPLACEMENT intentionally share text, so combining all six lines would
    /// misclassify ordinary edits as generation loops.
    nonisolated static func repeatedSixGramRatio(in review: AIParsedReview) -> Double {
        [
            review.original,
            review.replacement,
            review.reason
        ]
        .compactMap { $0 }
        .map(repeatedSixGramRatio(in:))
        .max() ?? 0
    }

    nonisolated static func containsReasoningMarkers(in output: String) -> Bool {
        reasoningMarkers.contains { output.localizedCaseInsensitiveContains($0) }
    }

    nonisolated static func sanitizedDiagnosticOutput(_ output: String) -> String {
        if containsReasoningMarkers(in: output) {
            return "[REDACTED: reasoning atau token template terdeteksi]"
        }

        let limit = 4_000
        guard output.count > limit else { return output }
        return String(output.prefix(limit)) + "… [output dipotong untuk diagnosis]"
    }

    nonisolated private static func normalizedTokens(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
