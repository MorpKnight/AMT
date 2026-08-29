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
    let validatorVersion: String
    let outputSchemaVersion: String
    let protectionContext: AIConnectorDocumentProtectionContext
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

    init(
        reviews: [AIConnectorCachedReview],
        parsedStatus: AIReviewStatus? = nil,
        parsedCategory: AIReviewCategory? = nil,
        rejectionReasons: [String],
        rejectionClasses: [AIConnectorRejectionClass] = [],
        modelAttempts: Int,
        repairAttempted: Bool,
        usedFallback: Bool,
        firstPassSucceeded: Bool
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
            components.validatorVersion,
            components.outputSchemaVersion,
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
