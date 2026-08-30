import Foundation

enum AIConnectorOutputParserError: Error, Equatable {
    case reasoningOrTemplateToken
    case wrongLineCount
    case malformedLine
    case unexpectedKey
    case invalidValue
    case emptyReason
    case reasonTooLong

    var message: String {
        switch self {
        case .reasoningOrTemplateToken:
            "Output mengandung reasoning atau token template."
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
