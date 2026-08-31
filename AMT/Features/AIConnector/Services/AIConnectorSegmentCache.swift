import CryptoKit
import Foundation

struct AIConnectorCacheKeyComponents: Hashable, Sendable {
    let segment: AIReviewSegment
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile
    let promptVersion: String
    let rulePackVersion: String
    let corpusVersion: String
    let semanticModelRevision: String
    let semanticEmbeddingSchema: String
    let semanticRetrievalProfile: String
    let validatorVersion: String
    let outputSchemaVersion: String
    let protectionContext: AIConnectorDocumentProtectionContext
    let candidateFingerprint: String

    init(
        segment: AIReviewSegment,
        reviewMode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        generationProfile: AIConnectorGenerationProfile,
        promptVersion: String,
        rulePackVersion: String,
        corpusVersion: String,
        semanticModelRevision: String = "",
        semanticEmbeddingSchema: String = "",
        semanticRetrievalProfile: String = "",
        validatorVersion: String,
        outputSchemaVersion: String,
        protectionContext: AIConnectorDocumentProtectionContext,
        candidateFingerprint: String = ""
    ) {
        self.segment = segment
        self.reviewMode = reviewMode
        self.modelVariant = modelVariant
        self.generationProfile = generationProfile
        self.promptVersion = promptVersion
        self.rulePackVersion = rulePackVersion
        self.corpusVersion = corpusVersion
        self.semanticModelRevision = semanticModelRevision
        self.semanticEmbeddingSchema = semanticEmbeddingSchema
        self.semanticRetrievalProfile = semanticRetrievalProfile
        self.validatorVersion = validatorVersion
        self.outputSchemaVersion = outputSchemaVersion
        self.protectionContext = protectionContext
        self.candidateFingerprint = candidateFingerprint
    }
}

struct AIConnectorCachedReview: Sendable {
    let id: UUID
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String?
    let replacement: String?
    let reason: String
    let glossaryMatch: LegalDictionaryMatch?
    let origin: AIReviewOrigin
    let ruleID: String?

    init(review: AIValidatedReview) {
        id = review.id
        status = review.status
        category = review.category
        original = review.original
        replacement = review.replacement
        reason = review.reason
        glossaryMatch = review.glossaryMatch
        origin = review.origin
        ruleID = review.ruleID
    }

    func materialize(for segment: AIReviewSegment) -> AIValidatedReview {
        AIValidatedReview(
            id: id,
            segment: segment,
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            reason: reason,
            glossaryMatch: glossaryMatch,
            origin: origin,
            ruleID: ruleID
        )
    }
}

struct AIConnectorCachedSegmentResult: Sendable {
    /// Reviews intentionally contain no segment or absolute source location.
    /// They are reattached to the current segment on cache lookup.
    let reviews: [AIConnectorCachedReview]
    let parsedStatus: AIReviewStatus?
    let parsedCategory: AIReviewCategory?
    let rejectionReasons: [String]
    let rejectionClasses: [AIConnectorRejectionClass]
    let modelAttempts: Int
    let repairAttempted: Bool
    let usedFallback: Bool
    let firstPassSucceeded: Bool
    let candidateDecisions: [AIConnectorCandidateDecisionRecord]
    let generationMetrics: AIConnectorGenerationMetrics?
    let repeatedSixGramRatio: Double?
    let outputWasTruncated: Bool
    let reasoningMarkerDetected: Bool
    let sourceClaimDetected: Bool
    let modelCallCount: Int
    let challengeCount: Int

    init(
        reviews: [AIConnectorCachedReview],
        parsedStatus: AIReviewStatus? = nil,
        parsedCategory: AIReviewCategory? = nil,
        rejectionReasons: [String],
        rejectionClasses: [AIConnectorRejectionClass] = [],
        modelAttempts: Int,
        repairAttempted: Bool,
        usedFallback: Bool,
        firstPassSucceeded: Bool,
        candidateDecisions: [AIConnectorCandidateDecisionRecord] = [],
        generationMetrics: AIConnectorGenerationMetrics? = nil,
        repeatedSixGramRatio: Double? = nil,
        outputWasTruncated: Bool = false,
        reasoningMarkerDetected: Bool = false,
        sourceClaimDetected: Bool = false,
        modelCallCount: Int = 0,
        challengeCount: Int = 0
    ) {
        self.reviews = reviews
        self.parsedStatus = parsedStatus
        self.parsedCategory = parsedCategory
        self.rejectionReasons = rejectionReasons
        self.rejectionClasses = rejectionClasses
        self.modelAttempts = modelAttempts
        self.repairAttempted = repairAttempted
        self.usedFallback = usedFallback
        self.firstPassSucceeded = firstPassSucceeded
        self.candidateDecisions = candidateDecisions
        self.generationMetrics = generationMetrics
        self.repeatedSixGramRatio = repeatedSixGramRatio
        self.outputWasTruncated = outputWasTruncated
        self.reasoningMarkerDetected = reasoningMarkerDetected
        self.sourceClaimDetected = sourceClaimDetected
        self.modelCallCount = modelCallCount
        self.challengeCount = challengeCount
    }
}

/// In-memory cache for validated, segment-relative results.
/// Raw model output is intentionally excluded from cache values.
actor AIConnectorSegmentCache {
    private var values: [String: AIConnectorCachedSegmentResult] = [:]

    func value(for key: String) -> AIConnectorCachedSegmentResult? {
        values[key]
    }

    func insert(_ value: AIConnectorCachedSegmentResult, for key: String) {
        values[key] = value
    }

    func removeAll() {
        values.removeAll()
    }

    nonisolated static func key(from components: AIConnectorCacheKeyComponents) -> String {
        let profile = components.generationProfile
        let material = [
            components.segment.targetText,
            components.segment.previousContext ?? "-",
            components.segment.nextContext ?? "-",
            components.reviewMode.rawValue,
            components.modelVariant.modelID,
            components.modelVariant.revision,
            "\(profile.maxTokens):\(profile.temperature):\(profile.topP):\(profile.topK):\(profile.presencePenalty.map { String($0) } ?? "nil"):" + String(describing: profile.seed),
            components.promptVersion,
            components.rulePackVersion,
            components.corpusVersion,
            components.semanticModelRevision,
            components.semanticEmbeddingSchema,
            components.semanticRetrievalProfile,
            components.validatorVersion,
            components.outputSchemaVersion,
            components.candidateFingerprint,
            protectionFingerprint(components.protectionContext)
        ].joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func protectionFingerprint(
        _ context: AIConnectorDocumentProtectionContext
    ) -> String {
        [
            context.definedTerms,
            context.partyNames,
            context.acronyms,
            context.quotedTerms,
            context.identifiers
        ]
        .map { $0.sorted().joined(separator: "\u{1E}") }
        .joined(separator: "\u{1D}")
    }
}
