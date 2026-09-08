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
    let languageScorerVersion: String
    let reviewPolicyVersion: String
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
        languageScorerVersion: String = AIConnectorLanguageScorerConfiguration.cacheKey,
        reviewPolicyVersion: String = AIConnectorPhaseTwoPolicy.disabledVersion,
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
        self.languageScorerVersion = languageScorerVersion
        self.reviewPolicyVersion = reviewPolicyVersion
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
    let sourceAnchor: AIConnectorReviewAnchor?

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
        sourceAnchor = review.sourceAnchor
    }

    func materialize(for segment: AIReviewSegment) -> AIValidatedReview {
        let materializedAnchor: AIConnectorReviewAnchor?
        if let sourceAnchor, let original {
            let candidate = AIConnectorReviewAnchor(
                segmentID: segment.id,
                sourceRange: sourceAnchor.range,
                original: original
            )
            materializedAnchor = candidate.isValid(
                for: segment,
                original: original
            ) ? candidate : nil
        } else {
            materializedAnchor = nil
        }

        return AIValidatedReview(
            id: id,
            segment: segment,
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            reason: reason,
            glossaryMatch: glossaryMatch,
            origin: origin,
            ruleID: ruleID,
            sourceAnchor: materializedAnchor
        )
    }
}

struct AIConnectorCachedSegmentResult: Sendable {
    /// Reviews contain segment-relative anchors. The segment itself is still
    /// reattached on cache lookup so a cache hit cannot carry an absolute
    /// document location across a different document revision.
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
    let candidateRoutes: [AIConnectorPhaseTwoCandidateRoute]
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
        candidateRoutes: [AIConnectorPhaseTwoCandidateRoute] = [],
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
        self.candidateRoutes = candidateRoutes
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
    /// Explicit namespace bump for the Phase 3 anchored result shape. This
    /// keeps any future persisted/injected cache namespace from reusing
    /// unanchored Phase 2 results even when the other inputs happen to match.
    nonisolated static let keyVersion = "segment-cache-v4-context-profile"
    nonisolated static let maximumEntriesPerDocument = 256

    private var values: [String: AIConnectorCachedSegmentResult] = [:]
    private var recency: [String] = []

    func value(for key: String) -> AIConnectorCachedSegmentResult? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ value: AIConnectorCachedSegmentResult, for key: String) {
        values[key] = value
        touch(key)
        while recency.count > Self.maximumEntriesPerDocument {
            let evicted = recency.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }

    func removeAll() {
        values.removeAll()
        recency.removeAll()
    }

    func snapshot() -> [String: AIConnectorCachedSegmentResult] {
        values
    }

    func restore(_ snapshot: [String: AIConnectorCachedSegmentResult]) {
        values = Dictionary(
            uniqueKeysWithValues: snapshot.prefix(Self.maximumEntriesPerDocument).map {
                ($0.key, $0.value)
            }
        )
        recency = Array(values.keys)
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    nonisolated static func key(from components: AIConnectorCacheKeyComponents) -> String {
        let profile = components.generationProfile
        let material = [
            Self.keyVersion,
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
            components.languageScorerVersion,
            components.reviewPolicyVersion,
            components.validatorVersion,
            components.outputSchemaVersion,
            components.candidateFingerprint,
            protectionFingerprint(components.protectionContext),
            components.segment.context?.fingerprint ?? "no-context"
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
