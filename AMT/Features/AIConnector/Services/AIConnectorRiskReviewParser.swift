import Foundation

enum AIConnectorRiskReviewParserError: Error, Equatable, Sendable {
    case missingToolCall
    case multipleToolCalls
    case unknownTool
    case malformedArguments
    case unexpectedText
    case candidateIDMismatch
    case invalidDecision
}

struct AIConnectorParsedRiskReview: Hashable, Sendable {
    let candidateID: String
    let decision: AIConnectorRiskReviewDecision
}

/// Strict parser for the Phase 5 risk-review tool. Free-form model reasons
/// are intentionally not accepted because UI explanations come from local
/// templates and source evidence.
struct AIConnectorRiskReviewParser: Sendable {
    static let toolName = "review_document_finding"
    private static let expectedArguments: Set<String> = ["candidate_id", "decision"]

    func parse(
        toolCalls: [AIConnectorToolDecisionPayload],
        visibleText: String,
        expectedCandidateID: String
    ) throws -> AIConnectorParsedRiskReview {
        guard visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConnectorRiskReviewParserError.unexpectedText
        }
        guard !toolCalls.isEmpty else {
            throw AIConnectorRiskReviewParserError.missingToolCall
        }
        guard toolCalls.count == 1 else {
            throw AIConnectorRiskReviewParserError.multipleToolCalls
        }
        let call = toolCalls[0]
        guard call.name == Self.toolName else {
            throw AIConnectorRiskReviewParserError.unknownTool
        }
        guard Set(call.arguments.keys) == Self.expectedArguments,
              let candidateID = call.arguments["candidate_id"],
              let decisionValue = call.arguments["decision"],
              !candidateID.isEmpty,
              !decisionValue.isEmpty,
              !candidateID.contains(where: { $0.isNewline }),
              !decisionValue.contains(where: { $0.isNewline }) else {
            throw AIConnectorRiskReviewParserError.malformedArguments
        }
        guard candidateID == expectedCandidateID else {
            throw AIConnectorRiskReviewParserError.candidateIDMismatch
        }
        guard let decision = AIConnectorRiskReviewDecision(rawValue: decisionValue) else {
            throw AIConnectorRiskReviewParserError.invalidDecision
        }
        return AIConnectorParsedRiskReview(candidateID: candidateID, decision: decision)
    }
}
