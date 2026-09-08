import Foundation

enum AIConnectorDocumentContextClassificationError: Error, Equatable, Sendable {
    case missingToolCall
    case multipleToolCalls
    case unknownTool
    case malformedArguments
    case unexpectedText
    case invalidLabel
    case invalidEvidence
    case invalidSection
}

/// Parses the bounded context-classification tool contract. Unknown labels or
/// evidence references are rejected rather than silently attached to a profile.
struct AIConnectorDocumentContextClassificationParser: Sendable {
    static let toolName = "classify_document_context"
    private static let expectedArguments: Set<String> = [
        "document_type", "domains", "evidence_ids", "section_ids", "confidence"
    ]

    func parse(
        toolCalls: [AIConnectorToolDecisionPayload],
        visibleText: String,
        allowedDocumentTypes: Set<String>,
        allowedDomains: Set<String>,
        evidenceIDs: Set<String>,
        sectionIDs: Set<String>
    ) throws -> AIConnectorDocumentContextClassificationResult {
        guard visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConnectorDocumentContextClassificationError.unexpectedText
        }
        guard !toolCalls.isEmpty else {
            throw AIConnectorDocumentContextClassificationError.missingToolCall
        }
        guard toolCalls.count == 1 else {
            throw AIConnectorDocumentContextClassificationError.multipleToolCalls
        }
        let call = toolCalls[0]
        guard call.name == Self.toolName else {
            throw AIConnectorDocumentContextClassificationError.unknownTool
        }
        guard Set(call.arguments.keys) == Self.expectedArguments,
              let typeValue = call.arguments["document_type"],
              let domainsValue = call.arguments["domains"],
              let evidenceValue = call.arguments["evidence_ids"],
              let sectionValue = call.arguments["section_ids"],
              let confidenceValue = call.arguments["confidence"] else {
            throw AIConnectorDocumentContextClassificationError.malformedArguments
        }

        let documentType: String?
        if typeValue == "-" || typeValue.isEmpty {
            documentType = nil
        } else if allowedDocumentTypes.contains(typeValue) {
            documentType = typeValue
        } else {
            throw AIConnectorDocumentContextClassificationError.invalidLabel
        }

        let domains = splitList(domainsValue)
        guard domains.allSatisfy(allowedDomains.contains) else {
            throw AIConnectorDocumentContextClassificationError.invalidLabel
        }
        let evidence = splitList(evidenceValue)
        guard evidence.allSatisfy(evidenceIDs.contains) else {
            throw AIConnectorDocumentContextClassificationError.invalidEvidence
        }
        let sections = splitList(sectionValue)
        guard sections.allSatisfy(sectionIDs.contains) else {
            throw AIConnectorDocumentContextClassificationError.invalidSection
        }
        guard let confidence = AIConnectorDocumentContextConfidence(rawValue: confidenceValue) else {
            throw AIConnectorDocumentContextClassificationError.malformedArguments
        }

        return AIConnectorDocumentContextClassificationResult(
            documentType: documentType,
            domains: domains,
            evidenceIDs: evidence,
            sectionIDs: sections,
            confidence: confidence,
            metrics: AIConnectorGenerationMetrics(
                promptTokenCount: 0,
                generationTokenCount: 0,
                promptDuration: 0,
                generationDuration: 0,
                stopReason: .stop
            )
        )
    }

    private func splitList(_ value: String) -> [String] {
        value == "-" || value.isEmpty
            ? []
            : value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
    }
}
