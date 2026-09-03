import Foundation

/// How a segment became eligible for a definition review.
enum AIConnectorDefinitionDetection: String, Codable, Hashable, Sendable {
    case explicitPattern = "EXPLICIT_PATTERN"
    case retrievedCandidate = "RETRIEVED_CANDIDATE"

    var displayTitle: String {
        switch self {
        case .explicitPattern:
            "Pola definisi eksplisit"
        case .retrievedCandidate:
            "Kandidat dari retrieval"
        }
    }
}

enum AIConnectorDefinitionClassification: String, Codable, Hashable, Sendable {
    case notDefinition = "NOT_A_DEFINITION"
    case explicitDefinition = "EXPLICIT_DEFINITION"
    case implicitDefinition = "IMPLICIT_DEFINITION"
    case needsReview = "NEEDS_REVIEW"

    var displayTitle: String {
        switch self {
        case .notDefinition:
            "Bukan definisi"
        case .explicitDefinition:
            "Definisi eksplisit"
        case .implicitDefinition:
            "Definisi tersirat"
        case .needsReview:
            "Perlu review"
        }
    }
}

enum AIConnectorDefinitionAlignment: String, Codable, Hashable, Sendable {
    case notApplicable = "NOT_APPLICABLE"
    case matches = "MATCH"
    case mismatch = "MISMATCH"
    case needsReview = "NEEDS_REVIEW"

    var displayTitle: String {
        switch self {
        case .notApplicable:
            "Tidak berlaku"
        case .matches:
            "Selaras dengan pengertian"
        case .mismatch:
            "Tidak selaras dengan pengertian"
        case .needsReview:
            "Kesetaraan belum pasti"
        }
    }
}

/// A source-backed definition candidate. The segment text and the source
/// definition are kept separate so a model cannot silently turn evidence into
/// an edit proposal.
struct AIConnectorDefinitionCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let match: LegalDictionaryMatch
    let statementText: String
    let detection: AIConnectorDefinitionDetection

    var term: String { match.entry.term }
    var sourceDefinition: String { match.entry.definition }
}

struct AIConnectorDefinitionDetectionResult: Hashable, Sendable {
    let term: String?
    let statementText: String
    let detection: AIConnectorDefinitionDetection?
    let candidates: [AIConnectorDefinitionCandidate]
}

/// Read-only result of checking one segmented sentence. A positive match is
/// still marked as requiring human review because corpus retrieval and Qwen
/// provide evidence, not legal authority.
struct AIConnectorDefinitionAssessment: Identifiable, Hashable, Sendable {
    let segment: AIReviewSegment
    let term: String?
    let statementText: String
    let candidate: AIConnectorDefinitionCandidate?
    let candidateCount: Int
    let detection: AIConnectorDefinitionDetection?
    let classification: AIConnectorDefinitionClassification
    let alignment: AIConnectorDefinitionAlignment
    let reason: String
    let origin: AIReviewOrigin
    let modelReviewed: Bool
    let retrievalOrigin: LegalRetrievalOrigin?
    let semanticScore: Float?
    let requiresHumanReview: Bool

    var id: String { "definition-\(segment.id)" }

    var isFinding: Bool {
        candidate != nil || classification != .notDefinition
    }
}

struct AIConnectorDefinitionAnalysisResult: Hashable, Sendable {
    let assessment: AIConnectorDefinitionAssessment?
    let modelCallCount: Int

    init(
        assessment: AIConnectorDefinitionAssessment? = nil,
        modelCallCount: Int = 0
    ) {
        self.assessment = assessment
        self.modelCallCount = modelCallCount
    }
}

struct AIConnectorDefinitionReviewRequest: Sendable {
    let segment: AIReviewSegment
    let candidate: AIConnectorDefinitionCandidate
    let thinkingEnabled: Bool
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile
    let retryInstruction: String?
}

struct QwenDefinitionReviewResult: Sendable {
    let candidateID: String
    let classification: AIConnectorDefinitionClassification
    let alignment: AIConnectorDefinitionAlignment
    let metrics: AIConnectorGenerationMetrics
    let containsReasoningMarkers: Bool
}
