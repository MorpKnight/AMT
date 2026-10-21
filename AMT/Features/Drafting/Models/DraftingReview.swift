import Foundation

/// Ephemeral drafting requests and read-only proposals. These types are never
/// serialized into DashboardDocument or converted into EditorSuggestion.
nonisolated enum DraftingReview {
    static let policyVersion = "drafting-review-v2"

    enum Scope: String, Codable, Hashable, Sendable {
        case verifyDocument = "verify_document"
        case rewriteTarget = "rewrite_target"
    }

    struct Clause: Codable, Hashable, Sendable {
        let id: String
        let text: String
        let sourceRange: NSRange
    }

    struct Definition: Codable, Hashable, Sendable {
        let id: String
        let term: String
        let body: String
        let sourceRange: NSRange
        var scopeClauseIDs: [String] = []
    }

    /// Eligibility here permits review of supplied evidence, not automatic
    /// replacement or a claim that the source is legally authoritative.
    struct Reference: Codable, Hashable, Sendable {
        let id: String
        let body: String
        let revision: String
        let isEligibleForReview: Bool
    }

    enum PermissionSource: Codable, Hashable, Sendable {
        case brief
        case reference(String)
    }

    struct Permission: Codable, Hashable, Sendable {
        let clauseID: String
        let original: String
        let replacement: String
        let source: PermissionSource
    }

    struct Request: Codable, Hashable, Sendable {
        let documentText: String
        let documentRevision: String
        let brief: String
        let scope: Scope
        let clauses: [Clause]
        let targetClauseIDs: [String]
        var definitions: [Definition] = []
        var references: [Reference] = []
        var requiredDefinitionIDs: [String] = []
        var requiredReferenceIDs: [String] = []
        var permissions: [Permission] = []
    }

    struct PreparedRequest: Sendable {
        let request: Request
        let definitions: [Definition]
        let references: [Reference]
        let protectionContext: AIConnectorDocumentProtectionContext
    }

    enum Decision: String, Codable, Hashable, Sendable {
        case revise, clarify
        case noChange = "no_change"
    }

    struct Finding: Codable, Equatable, Sendable {
        let clauseID: String
        let quote: String
        let category: String
        let reason: String
        let suggestedText: String?
        let clarificationQuestion: String?
        let substanceChange: String
        let referenceIDs: [String]

        enum CodingKeys: String, CodingKey {
            case clauseID = "clause_id", quote, category, reason
            case suggestedText = "suggested_text"
            case clarificationQuestion = "clarification_question"
            case substanceChange = "substance_change"
            case referenceIDs = "reference_ids"
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(clauseID, forKey: .clauseID)
            try values.encode(quote, forKey: .quote)
            try values.encode(category, forKey: .category)
            try values.encode(reason, forKey: .reason)
            try values.encode(suggestedText, forKey: .suggestedText)
            try values.encode(clarificationQuestion, forKey: .clarificationQuestion)
            try values.encode(substanceChange, forKey: .substanceChange)
            try values.encode(referenceIDs, forKey: .referenceIDs)
        }
    }

    struct Response: Codable, Equatable, Sendable {
        let decision: Decision
        let findings: [Finding]
    }

    struct Anchor: Equatable, Sendable {
        let clauseID: String
        let sourceRange: NSRange
        let original: String
    }

    enum Status: String, Sendable { case complete, incomplete, cancelled }
    enum Route: String, Sendable { case preflight, literal, model }

    struct Result: Sendable {
        let status: Status
        let route: Route
        let response: Response?
        let failures: [String]
        let anchors: [Anchor]
        let documentRevision: String
        let modelCallCount: Int
        let cacheHit: Bool
        let generationMetrics: AIConnectorGenerationMetrics?
        var formatRepairCount: Int = 0

        /// Complete means the processing contract passed, not legal approval.
        var isReadOnly: Bool { true }
        var isComplete: Bool { status == .complete }

        func isCurrent(for documentText: String) -> Bool {
            documentRevision == DocumentFingerprinting.contentSHA256(documentText)
                && anchors.allSatisfy {
                    guard let range = Range($0.sourceRange, in: documentText) else { return false }
                    return String(documentText[range]) == $0.original
                }
        }
    }
}
