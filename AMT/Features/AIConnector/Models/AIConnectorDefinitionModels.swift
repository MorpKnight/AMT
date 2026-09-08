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
    let candidates: [AIConnectorDefinitionCandidate]
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

    init(
        segment: AIReviewSegment,
        term: String?,
        statementText: String,
        candidate: AIConnectorDefinitionCandidate?,
        candidateCount: Int,
        detection: AIConnectorDefinitionDetection?,
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment,
        reason: String,
        origin: AIReviewOrigin,
        modelReviewed: Bool,
        retrievalOrigin: LegalRetrievalOrigin?,
        semanticScore: Float?,
        requiresHumanReview: Bool,
        candidates: [AIConnectorDefinitionCandidate] = []
    ) {
        self.segment = segment
        self.term = term
        self.statementText = statementText
        self.candidate = candidate
        self.candidates = candidates.isEmpty
            ? candidate.map { [$0] } ?? []
            : candidates
        self.candidateCount = candidateCount
        self.detection = detection
        self.classification = classification
        self.alignment = alignment
        self.reason = reason
        self.origin = origin
        self.modelReviewed = modelReviewed
        self.retrievalOrigin = retrievalOrigin
        self.semanticScore = semanticScore
        self.requiresHumanReview = requiresHumanReview
    }

    var id: String { "definition-\(segment.id)" }

    var isFinding: Bool {
        candidate != nil || classification != .notDefinition
    }
}

struct AIConnectorDefinitionAnalysisResult: Hashable, Sendable {
    let assessment: AIConnectorDefinitionAssessment?
    let modelCallCount: Int
    let cacheHit: Bool

    init(
        assessment: AIConnectorDefinitionAssessment? = nil,
        modelCallCount: Int = 0,
        cacheHit: Bool = false
    ) {
        self.assessment = assessment
        self.modelCallCount = modelCallCount
        self.cacheHit = cacheHit
    }

    func asCacheHit() -> Self {
        Self(
            assessment: assessment,
            modelCallCount: 0,
            cacheHit: true
        )
    }
}

struct AIConnectorDefinitionReviewRequest: Sendable {
    let segment: AIReviewSegment
    let candidate: AIConnectorDefinitionCandidate
    let thinkingEnabled: Bool
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile
    let retryInstruction: String?
    let context: AIConnectorSegmentContext?

    init(
        segment: AIReviewSegment,
        candidate: AIConnectorDefinitionCandidate,
        thinkingEnabled: Bool,
        modelVariant: AIConnectorModelVariant,
        generationProfile: AIConnectorGenerationProfile,
        retryInstruction: String?,
        context: AIConnectorSegmentContext? = nil
    ) {
        self.segment = segment
        self.candidate = candidate
        self.thinkingEnabled = thinkingEnabled
        self.modelVariant = modelVariant
        self.generationProfile = generationProfile
        self.retryInstruction = retryInstruction
        self.context = context
    }
}

struct QwenDefinitionReviewResult: Sendable {
    let candidateID: String
    let classification: AIConnectorDefinitionClassification
    let alignment: AIConnectorDefinitionAlignment
    let metrics: AIConnectorGenerationMetrics
    let containsReasoningMarkers: Bool
}
