import Foundation

/// Phase 2 routing is deliberately explicit so a candidate can be suppressed
/// or escalated without pretending that a weak signal is a valid suggestion.
nonisolated enum AIConnectorPhaseTwoRoute: String, Codable, Hashable, Sendable {
    case deterministic
    case modelReview = "model-review"
    case needsReview = "needs-review"
    case suppressed
}

nonisolated enum AIConnectorPhaseTwoRouteReason: String, Codable, Hashable, Sendable {
    case exactRule
    case scoredSpelling
    case verifiedGlossary
    case semanticGlossary
    case modelRequired
    case protectedContent
    case ambiguousSpan
    case weakEvidence
    case unsupportedCandidate
    case conflict

    var displayTitle: String {
        switch self {
        case .exactRule:
            "Rule exact"
        case .scoredSpelling:
            "TataKata scored"
        case .verifiedGlossary:
            "Glossary terverifikasi"
        case .semanticGlossary:
            "Glossary semantic"
        case .modelRequired:
            "Perlu review model"
        case .protectedContent:
            "Konten terproteksi"
        case .ambiguousSpan:
            "Span ambigu"
        case .weakEvidence:
            "Evidence lemah"
        case .unsupportedCandidate:
            "Kandidat tidak didukung"
        case .conflict:
            "Konflik kandidat"
        }
    }
}

nonisolated enum AIConnectorPhaseTwoEvidenceTier: Int, Codable, Hashable, Sendable {
    case unknown = 0
    case semanticGlossary = 1
    case scoredSpelling = 2
    case verifiedGlossary = 3
    case exactRule = 4

    var displayTitle: String {
        switch self {
        case .unknown:
            "unknown"
        case .semanticGlossary:
            "semantic glossary"
        case .scoredSpelling:
            "TataKata"
        case .verifiedGlossary:
            "verified glossary"
        case .exactRule:
            "exact rule"
        }
    }
}

/// Count-only evidence attached to a local candidate. It intentionally avoids
/// storing target text, source URLs, or model output so it can safely appear in
/// debug diagnostics and cache fingerprints.
nonisolated struct AIConnectorCandidateEvidence: Codable, Hashable, Sendable {
    let tier: AIConnectorPhaseTwoEvidenceTier
    let sourceLocation: Int
    let spanLength: Int
    let rulePriority: Int
    let sourceRank: Int
    let matchedDefinitionTokenCount: Int
    let semanticScore: Double?
    let languageScoreDelta: Double?
    let isDirectTermMatch: Bool
    let hasSourceAnchor: Bool
    let isUniqueSpan: Bool

    static let unknown = AIConnectorCandidateEvidence(
        tier: .unknown,
        sourceLocation: -1,
        spanLength: 0,
        rulePriority: Int.max,
        sourceRank: Int.max,
        matchedDefinitionTokenCount: 0,
        semanticScore: nil,
        languageScoreDelta: nil,
        isDirectTermMatch: false,
        hasSourceAnchor: false,
        isUniqueSpan: false
    )

    init(
        tier: AIConnectorPhaseTwoEvidenceTier,
        sourceLocation: Int,
        spanLength: Int,
        rulePriority: Int,
        sourceRank: Int,
        matchedDefinitionTokenCount: Int,
        semanticScore: Double?,
        languageScoreDelta: Double?,
        isDirectTermMatch: Bool,
        hasSourceAnchor: Bool,
        isUniqueSpan: Bool
    ) {
        self.tier = tier
        self.sourceLocation = sourceLocation
        self.spanLength = max(0, spanLength)
        self.rulePriority = rulePriority
        self.sourceRank = sourceRank
        self.matchedDefinitionTokenCount = max(0, matchedDefinitionTokenCount)
        self.semanticScore = semanticScore?.isFinite == true ? semanticScore : nil
        self.languageScoreDelta = languageScoreDelta?.isFinite == true ? languageScoreDelta : nil
        self.isDirectTermMatch = isDirectTermMatch
        self.hasSourceAnchor = hasSourceAnchor
        self.isUniqueSpan = isUniqueSpan
    }
}

nonisolated struct AIConnectorPhaseTwoCandidateRoute: Codable, Hashable, Sendable,
    Identifiable {
    let candidateID: String
    let route: AIConnectorPhaseTwoRoute
    let reason: AIConnectorPhaseTwoRouteReason
    let modelCallRequired: Bool

    var id: String { candidateID }
}

struct AIConnectorCandidateBuildResult: Hashable, Sendable {
    let candidates: [AIConnectorReviewCandidate]
    let droppedCandidateCount: Int
    let conflictCount: Int
}

/// The Phase 2 policy is intentionally conservative. It optimizes model-call
/// routing for narrow, exact local rules while keeping legal terminology and
/// semantic matches behind model/human review.
struct AIConnectorPhaseTwoPolicy: Sendable {
    static let version = "phase2-policy-v1"
    static let disabledVersion = "phase1-compatible"
    static let minimumSemanticScore: Double = 0.70

    func route(
        candidate: AIConnectorReviewCandidate,
        in segment: AIReviewSegment,
        protectionContext: AIConnectorDocumentProtectionContext,
        mode: AIConnectorReviewMode,
        forceDeterministic: Bool
    ) -> AIConnectorPhaseTwoCandidateRoute {
        let evidence = candidate.evidence
        guard evidence.tier != .unknown else {
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .suppressed,
                reason: .weakEvidence,
                modelCallRequired: false
            )
        }

        if !evidence.isUniqueSpan {
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .needsReview,
                reason: .ambiguousSpan,
                modelCallRequired: false
            )
        }

        if touchesProtectedContent(
            candidate.original,
            protectionContext: protectionContext
        ) {
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .needsReview,
                reason: .protectedContent,
                modelCallRequired: false
            )
        }

        if mode == .deterministic || forceDeterministic {
            guard evidence.tier == .exactRule,
                  candidate.category == .spelling || candidate.category == .grammar else {
                return AIConnectorPhaseTwoCandidateRoute(
                    candidateID: candidate.id,
                    route: .needsReview,
                    reason: .modelRequired,
                    modelCallRequired: false
                )
            }
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .deterministic,
                reason: .exactRule,
                modelCallRequired: false
            )
        }

        switch evidence.tier {
        case .exactRule:
            if candidate.category == .spelling || candidate.category == .grammar {
                return AIConnectorPhaseTwoCandidateRoute(
                    candidateID: candidate.id,
                    route: .deterministic,
                    reason: .exactRule,
                    modelCallRequired: false
                )
            }
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .modelReview,
                reason: .modelRequired,
                modelCallRequired: true
            )

        case .scoredSpelling:
            guard let delta = evidence.languageScoreDelta,
                  delta >= AIConnectorLanguageScorerConfiguration.minimumImprovementInNats else {
                return AIConnectorPhaseTwoCandidateRoute(
                    candidateID: candidate.id,
                    route: .suppressed,
                    reason: .weakEvidence,
                    modelCallRequired: false
                )
            }
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .modelReview,
                reason: .scoredSpelling,
                modelCallRequired: true
            )

        case .verifiedGlossary:
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .modelReview,
                reason: .verifiedGlossary,
                modelCallRequired: true
            )

        case .semanticGlossary:
            guard let score = evidence.semanticScore,
                  score >= Self.minimumSemanticScore,
                  evidence.matchedDefinitionTokenCount > 0 else {
                return AIConnectorPhaseTwoCandidateRoute(
                    candidateID: candidate.id,
                    route: .needsReview,
                    reason: .weakEvidence,
                    modelCallRequired: false
                )
            }
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .modelReview,
                reason: .semanticGlossary,
                modelCallRequired: true
            )

        case .unknown:
            return AIConnectorPhaseTwoCandidateRoute(
                candidateID: candidate.id,
                route: .suppressed,
                reason: .unsupportedCandidate,
                modelCallRequired: false
            )
        }
    }

    private func touchesProtectedContent(
        _ original: String,
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> Bool {
        let protectedValues = protectionContext.definedTerms
            .union(protectionContext.partyNames)
            .union(protectionContext.acronyms)
            .union(protectionContext.quotedTerms)
            .union(protectionContext.identifiers)

        return protectedValues.contains { value in
            !value.isEmpty && original.localizedCaseInsensitiveContains(value)
        }
    }
}

/// Ranks local candidates using explicit evidence before the model is called.
/// It preserves a stable maximum while making the tie-breaking rule auditable.
struct AIConnectorPhaseTwoCandidateRanker: Sendable {
    static let maximumCandidates = 3

    func select(
        _ candidates: [AIConnectorReviewCandidate]
    ) -> AIConnectorCandidateBuildResult {
        var seen: Set<String> = []
        var unique: [AIConnectorReviewCandidate] = []
        var droppedCount = 0

        for candidate in candidates {
            let key = [
                candidate.category.rawValue,
                candidate.original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
                candidate.replacement.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
                String(candidate.evidence.sourceLocation),
                String(candidate.evidence.spanLength)
            ].joined(separator: "\u{1E}")
            if seen.insert(key).inserted {
                unique.append(candidate)
            } else {
                droppedCount += 1
            }
        }

        let ordered = unique.sorted(by: isHigherPriority)
        var selected: [AIConnectorReviewCandidate] = []
        var conflictCount = 0

        for candidate in ordered {
            guard selected.count < Self.maximumCandidates else {
                droppedCount += 1
                continue
            }

            let overlaps = selected.filter { existing in
                rangesOverlap(candidate.evidence, existing.evidence)
            }
            if overlaps.isEmpty {
                selected.append(candidate)
                continue
            }

            conflictCount += 1
            droppedCount += 1
        }

        let normalized = selected.enumerated().map { index, candidate in
            candidate.withID("C\(index + 1)")
        }
        return AIConnectorCandidateBuildResult(
            candidates: normalized,
            droppedCandidateCount: droppedCount,
            conflictCount: conflictCount
        )
    }

    private func isHigherPriority(
        _ lhs: AIConnectorReviewCandidate,
        _ rhs: AIConnectorReviewCandidate
    ) -> Bool {
        if lhs.evidence.tier != rhs.evidence.tier {
            return lhs.evidence.tier.rawValue > rhs.evidence.tier.rawValue
        }
        if lhs.evidence.isDirectTermMatch != rhs.evidence.isDirectTermMatch {
            return lhs.evidence.isDirectTermMatch
        }
        if lhs.evidence.hasSourceAnchor != rhs.evidence.hasSourceAnchor {
            return lhs.evidence.hasSourceAnchor
        }
        if lhs.evidence.matchedDefinitionTokenCount
            != rhs.evidence.matchedDefinitionTokenCount {
            return lhs.evidence.matchedDefinitionTokenCount
                > rhs.evidence.matchedDefinitionTokenCount
        }
        if lhs.evidence.languageScoreDelta != rhs.evidence.languageScoreDelta {
            return (lhs.evidence.languageScoreDelta ?? -.greatestFiniteMagnitude)
                > (rhs.evidence.languageScoreDelta ?? -.greatestFiniteMagnitude)
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.evidence.spanLength != rhs.evidence.spanLength {
            return lhs.evidence.spanLength < rhs.evidence.spanLength
        }
        if lhs.evidence.sourceLocation != rhs.evidence.sourceLocation {
            return lhs.evidence.sourceLocation < rhs.evidence.sourceLocation
        }
        return (lhs.ruleID ?? "") < (rhs.ruleID ?? "")
    }

    private func rangesOverlap(
        _ lhs: AIConnectorCandidateEvidence,
        _ rhs: AIConnectorCandidateEvidence
    ) -> Bool {
        guard lhs.sourceLocation >= 0, rhs.sourceLocation >= 0,
              lhs.spanLength > 0, rhs.spanLength > 0 else {
            return false
        }
        return NSIntersectionRange(
            NSRange(location: lhs.sourceLocation, length: lhs.spanLength),
            NSRange(location: rhs.sourceLocation, length: rhs.spanLength)
        ).length > 0
    }
}
