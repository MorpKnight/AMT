import Foundation

enum AIConnectorOutputParserError: Error, Equatable, Sendable {
    case reasoningOrTemplateToken
    case codeFence
    case wrongLineCount
    case malformedLine
    case unexpectedKey
    case invalidValue
    case emptyReason
    case reasonTooLong

    /// Only shape errors may be sent through the one-shot repair prompt.
    /// Semantic and safety failures must never be repaired by asking the model
    /// to reinterpret the text.
    var isRecoverable: Bool {
        switch self {
        case .reasoningOrTemplateToken, .reasonTooLong:
            false
        case .codeFence, .wrongLineCount, .malformedLine, .unexpectedKey,
             .invalidValue, .emptyReason:
            true
        }
    }

    var message: String {
        switch self {
        case .reasoningOrTemplateToken:
            "Output mengandung reasoning atau token template."
        case .codeFence:
            "Output menggunakan code fence yang tidak diizinkan."
        case .wrongLineCount:
            "Output tidak memiliki tepat enam baris."
        case .malformedLine:
            "Ada baris output yang tidak memiliki format KEY: VALUE."
        case .unexpectedKey:
            "Key output hilang, berulang, salah urutan, atau bernilai kosong."
        case .invalidValue:
            "Status, kategori, atau alasan output tidak valid."
        case .emptyReason:
            "Alasan output kosong."
        case .reasonTooLong:
            "Alasan output melebihi 240 karakter."
        }
    }
}

struct AIConnectorOutputParser: Sendable {
    private static let expectedKeys = [
        "STATUS",
        "CATEGORY",
        "ORIGINAL",
        "REPLACEMENT",
        "GLOSSARY_ID",
        "REASON"
    ]

    func parse(_ output: String) throws -> AIParsedReview {
        let normalizedOutput = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !AIConnectorGenerationDiagnostics.containsReasoningMarkers(in: normalizedOutput) else {
            throw AIConnectorOutputParserError.reasoningOrTemplateToken
        }

        guard !normalizedOutput.contains("```") else {
            throw AIConnectorOutputParserError.codeFence
        }

        let lines = normalizedOutput.components(separatedBy: "\n")
        guard lines.count == Self.expectedKeys.count else {
            throw AIConnectorOutputParserError.wrongLineCount
        }

        var values: [String: String] = [:]
        for (index, line) in lines.enumerated() {
            guard let separator = line.firstIndex(of: ":") else {
                throw AIConnectorOutputParserError.malformedLine
            }

            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            guard key == Self.expectedKeys[index],
                  values[key] == nil,
                  !value.isEmpty else {
                throw AIConnectorOutputParserError.unexpectedKey
            }

            values[key] = value
        }

        guard let statusValue = values["STATUS"],
              let status = AIReviewStatus(rawValue: statusValue),
              let categoryValue = values["CATEGORY"],
              let category = AIReviewCategory(rawValue: categoryValue),
              let reason = values["REASON"],
              !reason.isEmpty else {
            throw AIConnectorOutputParserError.invalidValue
        }

        guard reason.count <= 240 else {
            throw AIConnectorOutputParserError.reasonTooLong
        }

        let original = Self.optionalValue(values["ORIGINAL"])
        let replacement = Self.optionalValue(values["REPLACEMENT"])
        let glossaryID = Self.optionalValue(values["GLOSSARY_ID"])

        return AIParsedReview(
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            glossaryID: glossaryID,
            reason: reason
        )
    }

    private static func optionalValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "-" else { return nil }
        return value
    }
}

/// Repairs only a decision-preserving representation mistake after parsing.
/// It never invents a suggestion, replacement, category, or glossary link.
struct AIConnectorOutputCanonicalizer: Sendable {
    func canonicalize(_ review: AIParsedReview) -> AIParsedReview {
        guard review.status == .noSuggestion,
              review.category == .none,
              review.replacement == nil,
              review.glossaryID == nil else {
            return review
        }

        return AIParsedReview(
            status: .noSuggestion,
            category: .none,
            original: nil,
            replacement: nil,
            glossaryID: nil,
            reason: review.reason,
            ruleID: review.ruleID
        )
    }
}
