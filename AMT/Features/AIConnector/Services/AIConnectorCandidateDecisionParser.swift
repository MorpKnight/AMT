import Foundation

enum AIConnectorCandidateDecisionParserError: Error, Equatable, Sendable {
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
             .malformedArguments, .unexpectedText, .candidateIDMismatch,
             .invalidDecision:
            true
        }
    }

    var message: String {
        switch self {
        case .missingToolCall:
            "Model tidak mengirim tool call keputusan."
        case .multipleToolCalls:
            "Model mengirim lebih dari satu tool call."
        case .unknownTool:
            "Nama tool model tidak didukung."
        case .malformedArguments:
            "Parameter tool keputusan tidak sesuai schema."
        case .unexpectedText:
            "Model mengirim teks di luar tool call."
        case .reasoningOrTemplateToken:
            "Output mengandung reasoning atau token template."
        case .candidateIDMismatch:
            "Tool call menunjuk kandidat yang berbeda dari kandidat aktif."
        case .invalidDecision:
            "Keputusan kandidat tidak dikenali."
        }
    }
}

struct AIConnectorParsedCandidateDecision: Hashable, Sendable {
    let candidateID: String
    let decision: AIConnectorCandidateDecision
}

struct AIConnectorCandidateModelFailure: Error, LocalizedError, Sendable {
    let message: String
    let classification: AIConnectorRejectionClass
    let recoverable: Bool
    let metrics: AIConnectorGenerationMetrics?
    let reasoningMarkerDetected: Bool
    let outputWasTruncated: Bool
    let repeatedSixGramRatio: Double?

    init(
        message: String,
        classification: AIConnectorRejectionClass,
        recoverable: Bool,
        metrics: AIConnectorGenerationMetrics?,
        reasoningMarkerDetected: Bool,
        outputWasTruncated: Bool,
        repeatedSixGramRatio: Double? = nil
    ) {
        self.message = message
        self.classification = classification
        self.recoverable = recoverable
        self.metrics = metrics
        self.reasoningMarkerDetected = reasoningMarkerDetected
        self.outputWasTruncated = outputWasTruncated
        self.repeatedSixGramRatio = repeatedSixGramRatio
    }

    var errorDescription: String? { message }
}

/// Validates the small candidate-judge contract independently of MLX. Keeping
/// this boundary dependency-neutral makes malformed tool calls easy to test
/// without loading a model.
struct AIConnectorCandidateDecisionParser: Sendable {
    static let toolName = "submit_review"
    private static let expectedArguments: Set<String> = ["candidate_id", "decision"]

    func parse(
        toolCalls: [AIConnectorToolDecisionPayload],
        visibleText: String,
        expectedCandidateID: String
    ) throws -> AIConnectorParsedCandidateDecision {
        let trimmedText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty else {
            if AIConnectorGenerationDiagnostics.containsReasoningMarkers(in: trimmedText)
                || Self.containsTemplateMarkers(trimmedText) {
                throw AIConnectorCandidateDecisionParserError.reasoningOrTemplateToken
            }
            throw AIConnectorCandidateDecisionParserError.unexpectedText
        }

        guard !toolCalls.isEmpty else {
            throw AIConnectorCandidateDecisionParserError.missingToolCall
        }
        guard toolCalls.count == 1 else {
            throw AIConnectorCandidateDecisionParserError.multipleToolCalls
        }

        let toolCall = toolCalls[0]
        guard toolCall.name == Self.toolName else {
            throw AIConnectorCandidateDecisionParserError.unknownTool
        }
        guard Set(toolCall.arguments.keys) == Self.expectedArguments,
              let candidateID = toolCall.arguments["candidate_id"],
              let decisionValue = toolCall.arguments["decision"],
              !candidateID.isEmpty,
              !decisionValue.isEmpty,
              !candidateID.contains(where: { $0.isNewline }),
              !decisionValue.contains(where: { $0.isNewline }) else {
            throw AIConnectorCandidateDecisionParserError.malformedArguments
        }
        guard candidateID == expectedCandidateID else {
            throw AIConnectorCandidateDecisionParserError.candidateIDMismatch
        }
        guard let decision = AIConnectorCandidateDecision(rawValue: decisionValue) else {
            throw AIConnectorCandidateDecisionParserError.invalidDecision
        }

        return AIConnectorParsedCandidateDecision(
            candidateID: candidateID,
            decision: decision
        )
    }

    private static func containsTemplateMarkers(_ text: String) -> Bool {
        ["<tool_call>", "</tool_call>", "<function=", "<parameter="].contains {
            text.localizedCaseInsensitiveContains($0)
        }
    }
}
