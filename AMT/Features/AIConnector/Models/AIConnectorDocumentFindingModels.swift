import CryptoKit
import Foundation

/// A document-level diagnostic produced after the sentence review pipeline.
/// Findings never contain a replacement: they are evidence-backed review
/// items and therefore cannot enter the editor's Accept path.
nonisolated enum AIConnectorDocumentFindingKind: String, Codable, CaseIterable, Hashable, Sendable {
    case definedTerm
    case legalRisk
    case internalReference
}

nonisolated enum AIConnectorDocumentFindingDisposition: String, Codable, Hashable, Sendable {
    case flagged
    case uncertain
}

nonisolated enum AIConnectorRiskReviewDecision: String, Codable, Hashable, Sendable {
    case flag = "FLAG"
    case dismiss = "DISMISS"
    case uncertain = "UNCERTAIN"
}

/// A related source span. `original` is retained so a related evidence link
/// becomes stale when the document changes, just like the primary anchor.
nonisolated struct AIConnectorFindingEvidence: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var sourceRange: NSRange
    let original: String
    let label: String
    let sectionID: String?

    init(
        id: String,
        sourceRange: NSRange,
        original: String,
        label: String,
        sectionID: String? = nil
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.original = original
        self.label = label
        self.sectionID = sectionID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceRangeLocation = "source_range_location"
        case sourceRangeLength = "source_range_length"
        case original
        case label
        case sectionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(Int.self, forKey: .sourceRangeLocation)
        let length = try container.decode(Int.self, forKey: .sourceRangeLength)
        guard location >= 0, length > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceRangeLocation,
                in: container,
                debugDescription: "Finding evidence range must be non-negative and non-empty."
            )
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            sourceRange: NSRange(location: location, length: length),
            original: try container.decode(String.self, forKey: .original),
            label: try container.decode(String.self, forKey: .label),
            sectionID: try container.decodeIfPresent(String.self, forKey: .sectionID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceRange.location, forKey: .sourceRangeLocation)
        try container.encode(sourceRange.length, forKey: .sourceRangeLength)
        try container.encode(original, forKey: .original)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(sectionID, forKey: .sectionID)
    }

    func isAnchored(to documentText: String) -> Bool {
        guard sourceRange.location >= 0,
              sourceRange.length > 0,
              NSMaxRange(sourceRange) <= documentText.utf16.count else {
            return false
        }
        return (documentText as NSString).substring(with: sourceRange) == original
    }

    func shifted(by delta: Int) -> AIConnectorFindingEvidence {
        var shifted = self
        shifted.sourceRange = NSRange(
            location: sourceRange.location + delta,
            length: sourceRange.length
        )
        return shifted
    }
}

nonisolated struct AIConnectorDocumentFinding: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let ruleID: String
    let kind: AIConnectorDocumentFindingKind
    var sourceRange: NSRange
    let original: String
    let title: String
    let reason: String
    let origin: AIReviewOrigin
    let disposition: AIConnectorDocumentFindingDisposition
    let requiresModelReview: Bool
    let candidateID: String?
    let sectionID: String?
    var relatedEvidence: [AIConnectorFindingEvidence]

    init(
        id: UUID = UUID(),
        ruleID: String,
        kind: AIConnectorDocumentFindingKind,
        sourceRange: NSRange,
        original: String,
        title: String,
        reason: String,
        origin: AIReviewOrigin,
        disposition: AIConnectorDocumentFindingDisposition = .flagged,
        requiresModelReview: Bool = false,
        candidateID: String? = nil,
        sectionID: String? = nil,
        relatedEvidence: [AIConnectorFindingEvidence] = []
    ) {
        self.id = id
        self.ruleID = ruleID
        self.kind = kind
        self.sourceRange = sourceRange
        self.original = original
        self.title = title
        self.reason = reason
        self.origin = origin
        self.disposition = disposition
        self.requiresModelReview = requiresModelReview
        self.candidateID = candidateID
        self.sectionID = sectionID
        self.relatedEvidence = relatedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ruleID
        case kind
        case sourceRangeLocation = "source_range_location"
        case sourceRangeLength = "source_range_length"
        case original
        case title
        case reason
        case origin
        case disposition
        case requiresModelReview
        case candidateID
        case sectionID
        case relatedEvidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(Int.self, forKey: .sourceRangeLocation)
        let length = try container.decode(Int.self, forKey: .sourceRangeLength)
        guard location >= 0, length > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceRangeLocation,
                in: container,
                debugDescription: "Finding range must be non-negative and non-empty."
            )
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            ruleID: try container.decode(String.self, forKey: .ruleID),
            kind: try container.decode(AIConnectorDocumentFindingKind.self, forKey: .kind),
            sourceRange: NSRange(location: location, length: length),
            original: try container.decode(String.self, forKey: .original),
            title: try container.decode(String.self, forKey: .title),
            reason: try container.decode(String.self, forKey: .reason),
            origin: try container.decode(AIReviewOrigin.self, forKey: .origin),
            disposition: try container.decode(AIConnectorDocumentFindingDisposition.self, forKey: .disposition),
            requiresModelReview: try container.decodeIfPresent(Bool.self, forKey: .requiresModelReview) ?? false,
            candidateID: try container.decodeIfPresent(String.self, forKey: .candidateID),
            sectionID: try container.decodeIfPresent(String.self, forKey: .sectionID),
            relatedEvidence: try container.decodeIfPresent(
                [AIConnectorFindingEvidence].self,
                forKey: .relatedEvidence
            ) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ruleID, forKey: .ruleID)
        try container.encode(kind, forKey: .kind)
        try container.encode(sourceRange.location, forKey: .sourceRangeLocation)
        try container.encode(sourceRange.length, forKey: .sourceRangeLength)
        try container.encode(original, forKey: .original)
        try container.encode(title, forKey: .title)
        try container.encode(reason, forKey: .reason)
        try container.encode(origin, forKey: .origin)
        try container.encode(disposition, forKey: .disposition)
        try container.encode(requiresModelReview, forKey: .requiresModelReview)
        try container.encodeIfPresent(candidateID, forKey: .candidateID)
        try container.encodeIfPresent(sectionID, forKey: .sectionID)
        try container.encode(relatedEvidence, forKey: .relatedEvidence)
    }

    func isAnchored(to documentText: String) -> Bool {
        guard sourceRange.location >= 0,
              sourceRange.length > 0,
              NSMaxRange(sourceRange) <= documentText.utf16.count,
              (documentText as NSString).substring(with: sourceRange) == original else {
            return false
        }
        return relatedEvidence.allSatisfy { $0.isAnchored(to: documentText) }
    }

    func shifted(by delta: Int) -> AIConnectorDocumentFinding {
        var shifted = self
        shifted.sourceRange = NSRange(
            location: sourceRange.location + delta,
            length: sourceRange.length
        )
        shifted.relatedEvidence = relatedEvidence.map { $0.shifted(by: delta) }
        return shifted
    }

    func withReview(
        origin: AIReviewOrigin,
        disposition: AIConnectorDocumentFindingDisposition
    ) -> AIConnectorDocumentFinding {
        AIConnectorDocumentFinding(
            id: id,
            ruleID: ruleID,
            kind: kind,
            sourceRange: sourceRange,
            original: original,
            title: title,
            reason: reason,
            origin: origin,
            disposition: disposition,
            requiresModelReview: requiresModelReview,
            candidateID: candidateID,
            sectionID: sectionID,
            relatedEvidence: relatedEvidence
        )
    }

    static func stableID(_ material: String) -> UUID {
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let parts = [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            "5" + String(hex.dropFirst(12).prefix(3)),
            "8" + String(hex.dropFirst(15).prefix(3)),
            String(hex.dropFirst(18).prefix(12))
        ]
        return UUID(uuidString: parts.joined(separator: "-")) ?? UUID()
    }
}

struct AIConnectorRiskReviewRequest: Sendable {
    let candidateID: String
    let ruleID: String
    let kind: AIConnectorDocumentFindingKind
    let targetText: String
    let evidence: [AIConnectorFindingEvidence]
    let context: AIConnectorSegmentContext?
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile

    init(
        candidateID: String,
        ruleID: String,
        kind: AIConnectorDocumentFindingKind,
        targetText: String,
        evidence: [AIConnectorFindingEvidence],
        context: AIConnectorSegmentContext? = nil,
        modelVariant: AIConnectorModelVariant = .qwen35Base4B,
        generationProfile: AIConnectorGenerationProfile = AIConnectorGenerationProfile(
            maxTokens: 192,
            temperature: 0,
            topP: 1,
            topK: 0,
            presencePenalty: nil,
            seed: 42
        )
    ) {
        self.candidateID = candidateID
        self.ruleID = ruleID
        self.kind = kind
        self.targetText = targetText
        self.evidence = evidence
        self.context = context
        self.modelVariant = modelVariant
        self.generationProfile = generationProfile
    }
}

struct AIConnectorRiskReviewResult: Sendable {
    let candidateID: String
    let decision: AIConnectorRiskReviewDecision
    let metrics: AIConnectorGenerationMetrics
}

struct AIConnectorDocumentReviewMetrics: Hashable, Sendable {
    let findingCount: Int
    let definedTermFindingCount: Int
    let legalRiskFindingCount: Int
    let internalReferenceFindingCount: Int
    let riskCandidateCount: Int
    let riskModelCallCount: Int
    let riskFallbackCount: Int
    let riskReviewDuration: TimeInterval
    let cacheHit: Bool
    let duration: TimeInterval
    let wasCancelled: Bool

    init(
        findingCount: Int = 0,
        definedTermFindingCount: Int = 0,
        legalRiskFindingCount: Int = 0,
        internalReferenceFindingCount: Int = 0,
        riskCandidateCount: Int = 0,
        riskModelCallCount: Int = 0,
        riskFallbackCount: Int = 0,
        riskReviewDuration: TimeInterval = 0,
        cacheHit: Bool = false,
        duration: TimeInterval = 0,
        wasCancelled: Bool = false
    ) {
        self.findingCount = max(0, findingCount)
        self.definedTermFindingCount = max(0, definedTermFindingCount)
        self.legalRiskFindingCount = max(0, legalRiskFindingCount)
        self.internalReferenceFindingCount = max(0, internalReferenceFindingCount)
        self.riskCandidateCount = max(0, riskCandidateCount)
        self.riskModelCallCount = max(0, riskModelCallCount)
        self.riskFallbackCount = max(0, riskFallbackCount)
        self.riskReviewDuration = max(0, riskReviewDuration)
        self.cacheHit = cacheHit
        self.duration = max(0, duration)
        self.wasCancelled = wasCancelled
    }

    func withCacheHit() -> AIConnectorDocumentReviewMetrics {
        AIConnectorDocumentReviewMetrics(
            findingCount: findingCount,
            definedTermFindingCount: definedTermFindingCount,
            legalRiskFindingCount: legalRiskFindingCount,
            internalReferenceFindingCount: internalReferenceFindingCount,
            riskCandidateCount: riskCandidateCount,
            riskModelCallCount: 0,
            riskFallbackCount: 0,
            riskReviewDuration: 0,
            cacheHit: true,
            duration: 0,
            wasCancelled: wasCancelled
        )
    }
}

struct AIConnectorDocumentReviewResult: Sendable {
    let findings: [AIConnectorDocumentFinding]
    let metrics: AIConnectorDocumentReviewMetrics
}
