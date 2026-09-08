import CryptoKit
import Foundation

/// The user-visible scope of a document analysis run.
nonisolated enum AIConnectorAnalysisRunScope: String, Codable, Hashable, Sendable {
    case incrementalDocument
    case section
    case fullFresh
}

/// Reasons why an otherwise reusable result is included in a new run.
nonisolated enum AIConnectorAnalysisInvalidationReason: String, Codable, Hashable, Sendable {
    case initial
    case editedSegment
    case adjacentContext
    case headingChanged
    case definitionDependency
    case partyDependency
    case referenceDependency
    case profileChanged
    case corpusChanged
    case rulePackChanged
    case ambiguousMapping
    case fullRerun
    case cancelled
}

/// A stable pairing between a segment in the previous revision and one in the
/// current revision. Segment IDs are intentionally not used as identities:
/// inserting text before a segment changes its ordinal ID.
nonisolated struct AIConnectorSegmentMapping: Codable, Hashable, Sendable {
    let oldSegmentID: Int
    let newSegmentID: Int
}

nonisolated struct AIConnectorAnalysisChangeSet: Hashable, Sendable {
    let scope: AIConnectorAnalysisRunScope
    let oldTextFingerprint: String?
    let newTextFingerprint: String
    let changedOldRanges: [NSRange]
    let changedNewRanges: [NSRange]
    let changedOldBlockIDs: Set<String>
    let changedBlockIDs: Set<String>
    let changedSectionIDs: Set<String>
    let reasons: Set<AIConnectorAnalysisInvalidationReason>
    let isAmbiguous: Bool

    var requiresFullRerun: Bool {
        reasons.contains(.fullRerun) || reasons.contains(.ambiguousMapping)
    }
}

nonisolated struct AIConnectorAnalysisPlan: Hashable, Sendable {
    let changeSet: AIConnectorAnalysisChangeSet
    let reusableSegmentIDs: Set<Int>
    let reprocessSegmentIDs: Set<Int>
    let removedSegmentIDs: Set<Int>
    let mappings: [AIConnectorSegmentMapping]
    let dependencySectionIDs: Set<String>
    let requiresProfileRebuild: Bool
    let requiresDocumentReview: Bool
    let isFullRerun: Bool

    var reusedSegmentCount: Int { reusableSegmentIDs.count }
    var reprocessedSegmentCount: Int { reprocessSegmentIDs.count }

    static func full(
        scope: AIConnectorAnalysisRunScope = .fullFresh,
        documentText: String,
        segmentation: AITextSegmentationResult
    ) -> AIConnectorAnalysisPlan {
        let ids = Set(segmentation.segments.map(\.id))
        let fingerprint = Self.sha256(documentText)
        let changeSet = AIConnectorAnalysisChangeSet(
            scope: scope,
            oldTextFingerprint: nil,
            newTextFingerprint: fingerprint,
            changedOldRanges: [],
            changedNewRanges: [],
            changedOldBlockIDs: [],
            changedBlockIDs: [],
            changedSectionIDs: [],
            reasons: [.initial, .fullRerun],
            isAmbiguous: false
        )
        return AIConnectorAnalysisPlan(
            changeSet: changeSet,
            reusableSegmentIDs: [],
            reprocessSegmentIDs: ids,
            removedSegmentIDs: [],
            mappings: [],
            dependencySectionIDs: [],
            requiresProfileRebuild: true,
            requiresDocumentReview: true,
            isFullRerun: true
        )
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// The in-memory baseline needed to compare a new revision with a completed
/// run. It is deliberately not persisted: snapshots remain a completed-run
/// restore format, not an incremental-analysis journal.
nonisolated struct AIConnectorAnalysisBaseline: Sendable {
    let documentText: String
    let structure: AIConnectorDocumentStructure
    let profile: AIConnectorDocumentContextProfile?
    let segmentation: AITextSegmentationResult
    let analysisProfile: AIConnectorAnalysisProfile
    let validatedReviews: [AIValidatedReview]
    let definitionAssessments: [AIConnectorDefinitionAssessment]
    let documentFindings: [AIConnectorDocumentFinding]
    let ignoredReviewItemIDs: Set<UUID>
    let reviewedReviewItemIDs: Set<UUID>
}

/// Privacy-safe metrics for one incremental run. No source text, evidence,
/// fingerprints, or model output belongs in this type.
nonisolated struct AIConnectorIncrementalAnalysisMetrics: Codable, Hashable, Sendable {
    let scope: AIConnectorAnalysisRunScope
    let reusedSegmentCount: Int
    let reprocessedSegmentCount: Int
    let invalidatedSegmentCount: Int
    let cacheLookupCount: Int
    let cacheHitCount: Int
    let firstResultLatency: TimeInterval?
    let totalDuration: TimeInterval?
    let wasPartial: Bool

    init(
        scope: AIConnectorAnalysisRunScope = .fullFresh,
        reusedSegmentCount: Int = 0,
        reprocessedSegmentCount: Int = 0,
        invalidatedSegmentCount: Int = 0,
        cacheLookupCount: Int = 0,
        cacheHitCount: Int = 0,
        firstResultLatency: TimeInterval? = nil,
        totalDuration: TimeInterval? = nil,
        wasPartial: Bool = false
    ) {
        self.scope = scope
        self.reusedSegmentCount = max(reusedSegmentCount, 0)
        self.reprocessedSegmentCount = max(reprocessedSegmentCount, 0)
        self.invalidatedSegmentCount = max(invalidatedSegmentCount, 0)
        self.cacheLookupCount = max(cacheLookupCount, 0)
        self.cacheHitCount = max(cacheHitCount, 0)
        self.firstResultLatency = firstResultLatency.map { max($0, 0) }
        self.totalDuration = totalDuration.map { max($0, 0) }
        self.wasPartial = wasPartial
    }
}
