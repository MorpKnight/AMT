import Foundation

enum AIConnectorDefinitionResolutionParserError: Error, Equatable, Sendable {
    case missingToolCall
    case multipleToolCalls
    case unknownTool
    case malformedArguments
    case unexpectedText
    case candidateIDMismatch
    case invalidDecision
}

struct AIConnectorParsedDefinitionResolution: Hashable, Sendable {
    let candidateID: String
    let decision: AIConnectorDefinitionResolutionDecision
}

/// Accepts only the bounded resolution decision. The model cannot return a
/// term, definition, source, or free-form reason.
struct AIConnectorDefinitionResolutionParser: Sendable {
    static let toolName = "review_definition_resolution"
    private static let expectedArguments: Set<String> = ["candidate_id", "decision"]

    func parse(
        toolCalls: [AIConnectorToolDecisionPayload],
        visibleText: String,
        expectedCandidateID: String
    ) throws -> AIConnectorParsedDefinitionResolution {
        guard visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConnectorDefinitionResolutionParserError.unexpectedText
        }
        guard !toolCalls.isEmpty else {
            throw AIConnectorDefinitionResolutionParserError.missingToolCall
        }
        guard toolCalls.count == 1 else {
            throw AIConnectorDefinitionResolutionParserError.multipleToolCalls
        }
        let call = toolCalls[0]
        guard call.name == Self.toolName else {
            throw AIConnectorDefinitionResolutionParserError.unknownTool
        }
        guard Set(call.arguments.keys) == Self.expectedArguments,
              let candidateID = call.arguments["candidate_id"],
              let decisionValue = call.arguments["decision"],
              !candidateID.isEmpty,
              !decisionValue.isEmpty,
              !candidateID.contains(where: { $0.isNewline }),
              !decisionValue.contains(where: { $0.isNewline }) else {
            throw AIConnectorDefinitionResolutionParserError.malformedArguments
        }
        guard candidateID == expectedCandidateID else {
            throw AIConnectorDefinitionResolutionParserError.candidateIDMismatch
        }
        guard let decision = AIConnectorDefinitionResolutionDecision(rawValue: decisionValue) else {
            throw AIConnectorDefinitionResolutionParserError.invalidDecision
        }
        return AIConnectorParsedDefinitionResolution(candidateID: candidateID, decision: decision)
    }
}
