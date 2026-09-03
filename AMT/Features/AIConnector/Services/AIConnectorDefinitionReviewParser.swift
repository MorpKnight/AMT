import Foundation

enum AIConnectorDefinitionReviewParserError: Error, Equatable, Sendable {
    case missingToolCall
    case multipleToolCalls
    case unknownTool
    case malformedArguments
    case unexpectedText
    case reasoningOrTemplateToken
    case candidateIDMismatch
    case invalidDecision

    var isRecoverable: Bool {
        switch self {
        case .reasoningOrTemplateToken, .unknownTool, .multipleToolCalls:
            false
        case .missingToolCall,
             .malformedArguments,
             .unexpectedText,
             .candidateIDMismatch,
             .invalidDecision:
            true
        }
    }

    var message: String {
        switch self {
        case .missingToolCall:
            "Model tidak mengirim tool call pemeriksaan definisi."
        case .multipleToolCalls:
            "Model mengirim lebih dari satu tool call pemeriksaan definisi."
        case .unknownTool:
            "Nama tool pemeriksaan definisi tidak didukung."
        case .malformedArguments:
            "Parameter tool pemeriksaan definisi tidak sesuai schema."
        case .unexpectedText:
            "Model mengirim teks di luar tool call pemeriksaan definisi."
        case .reasoningOrTemplateToken:
            "Output pemeriksaan definisi mengandung reasoning atau token template."
        case .candidateIDMismatch:
            "Tool call menunjuk kandidat definisi yang berbeda dari kandidat aktif."
        case .invalidDecision:
            "Klasifikasi atau kesesuaian definisi tidak dikenali."
        }
    }
}

struct AIConnectorParsedDefinitionReview: Hashable, Sendable {
    let candidateID: String
    let classification: AIConnectorDefinitionClassification
    let alignment: AIConnectorDefinitionAlignment
}

/// Validates the definition-review tool contract independently from MLX.
struct AIConnectorDefinitionReviewParser: Sendable {
    static let toolName = "submit_definition_review"
    private static let expectedArguments: Set<String> = [
        "candidate_id",
        "classification",
        "alignment"
    ]

    func parse(
        toolCalls: [AIConnectorToolDecisionPayload],
        visibleText: String,
        expectedCandidateID: String
    ) throws -> AIConnectorParsedDefinitionReview {
        let trimmedText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty else {
            if AIConnectorGenerationDiagnostics.containsReasoningMarkers(in: trimmedText)
                || Self.containsTemplateMarkers(trimmedText) {
                throw AIConnectorDefinitionReviewParserError.reasoningOrTemplateToken
            }
            throw AIConnectorDefinitionReviewParserError.unexpectedText
        }

        guard !toolCalls.isEmpty else {
            throw AIConnectorDefinitionReviewParserError.missingToolCall
        }
        guard toolCalls.count == 1 else {
            throw AIConnectorDefinitionReviewParserError.multipleToolCalls
        }

        let toolCall = toolCalls[0]
        guard toolCall.name == Self.toolName else {
            throw AIConnectorDefinitionReviewParserError.unknownTool
        }
        guard Set(toolCall.arguments.keys) == Self.expectedArguments,
              let candidateID = toolCall.arguments["candidate_id"],
              let classificationValue = toolCall.arguments["classification"],
              let alignmentValue = toolCall.arguments["alignment"],
              !candidateID.isEmpty,
              !classificationValue.isEmpty,
              !alignmentValue.isEmpty,
              !candidateID.contains(where: { $0.isNewline }),
              !classificationValue.contains(where: { $0.isNewline }),
              !alignmentValue.contains(where: { $0.isNewline }) else {
            throw AIConnectorDefinitionReviewParserError.malformedArguments
        }
        guard candidateID == expectedCandidateID else {
            throw AIConnectorDefinitionReviewParserError.candidateIDMismatch
        }
        guard let classification = AIConnectorDefinitionClassification(
            rawValue: classificationValue
        ), let alignment = AIConnectorDefinitionAlignment(rawValue: alignmentValue) else {
            throw AIConnectorDefinitionReviewParserError.invalidDecision
        }

        let validPair: Bool
        switch classification {
        case .notDefinition:
            validPair = alignment == .notApplicable
        case .explicitDefinition, .implicitDefinition:
            validPair = alignment != .notApplicable
        case .needsReview:
            validPair = alignment == .needsReview
        }
        guard validPair else {
            throw AIConnectorDefinitionReviewParserError.invalidDecision
        }

        return AIConnectorParsedDefinitionReview(
            candidateID: candidateID,
            classification: classification,
            alignment: alignment
        )
    }

    private static func containsTemplateMarkers(_ text: String) -> Bool {
        ["<tool_call>", "</tool_call>", "<function=", "<parameter="].contains {
            text.localizedCaseInsensitiveContains($0)
        }
    }
}
