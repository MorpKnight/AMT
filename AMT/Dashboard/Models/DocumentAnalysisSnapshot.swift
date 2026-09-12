import Foundation

/// Persisted, user-facing output of a completed document analysis.
///
/// The snapshot is intentionally smaller than `AIConnectorViewModel`: it
/// stores only anchored results needed to restore the editor, together with
/// the exact document content and analysis profile that produced them.
nonisolated struct DocumentAnalysisSnapshot: Codable, Equatable, Hashable, Sendable {
    // Phase 6 adds source-backed definition resolution state. Older
    // snapshots can still be decoded for a graceful re-analysis prompt, but
    // they must never be restored as active findings.
    static let currentVersion = 7

    let version: Int
    let analyzedContentSHA256: String
    let analysisProfile: AIConnectorAnalysisProfile
    let completedAt: Date
    let runSummary: AIConnectorRunSummary?
    let editorSuggestions: [EditorSuggestion]
    let reviewAnnotations: [EditorReviewAnnotation]
    let definitionMatchAnnotations: [EditorReviewAnnotation]
    let ignoredReviewItemIDs: Set<UUID>
    let documentFindings: [AIConnectorDocumentFinding]
    let reviewedReviewItemIDs: Set<UUID>
    let definitionResolutions: [AIConnectorDefinitionResolution]

    /// Kept only so callers compiled against the Phase 2 name can decode and
    /// migrate old files. New snapshots do not use this collection as active
    /// editor output.
    let definitionDebugSuggestions: [EditorSuggestion]

    init(
        analyzedContentSHA256: String,
        analysisProfile: AIConnectorAnalysisProfile,
        completedAt: Date,
        runSummary: AIConnectorRunSummary? = nil,
        editorSuggestions: [EditorSuggestion],
        reviewAnnotations: [EditorReviewAnnotation] = [],
        definitionMatchAnnotations: [EditorReviewAnnotation] = [],
        ignoredReviewItemIDs: Set<UUID> = [],
        documentFindings: [AIConnectorDocumentFinding] = [],
        reviewedReviewItemIDs: Set<UUID> = [],
        definitionResolutions: [AIConnectorDefinitionResolution] = [],
        definitionDebugSuggestions: [EditorSuggestion] = [],
        version: Int = currentVersion
    ) {
        self.version = version
        self.analyzedContentSHA256 = analyzedContentSHA256
        self.analysisProfile = analysisProfile
        self.completedAt = completedAt
        self.runSummary = runSummary
        self.editorSuggestions = editorSuggestions
        self.reviewAnnotations = reviewAnnotations
        self.definitionMatchAnnotations = definitionMatchAnnotations
        self.ignoredReviewItemIDs = ignoredReviewItemIDs
        self.documentFindings = documentFindings
        self.reviewedReviewItemIDs = reviewedReviewItemIDs
        self.definitionResolutions = definitionResolutions
        self.definitionDebugSuggestions = definitionDebugSuggestions
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case analyzedContentSHA256
        case analysisProfile
        case completedAt
        case runSummary
        case editorSuggestions
        case reviewAnnotations
        case definitionMatchAnnotations
        case ignoredReviewItemIDs
        case documentFindings
        case reviewedReviewItemIDs
        case definitionResolutions
        case definitionDebugSuggestions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing version is legacy data, not a current snapshot. Treat it
        // as incompatible while still allowing the surrounding document to
        // load and request a fresh analysis.
        self.version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? 0
        self.analyzedContentSHA256 = try container.decode(
            String.self,
            forKey: .analyzedContentSHA256
        )
        self.analysisProfile = try container.decode(
            AIConnectorAnalysisProfile.self,
            forKey: .analysisProfile
        )
        self.completedAt = try container.decode(Date.self, forKey: .completedAt)
        self.runSummary = try container.decodeIfPresent(
            AIConnectorRunSummary.self,
            forKey: .runSummary
        )
        self.editorSuggestions = try container.decodeIfPresent(
            [EditorSuggestion].self,
            forKey: .editorSuggestions
        ) ?? []
        self.reviewAnnotations = try container.decodeIfPresent(
            [EditorReviewAnnotation].self,
            forKey: .reviewAnnotations
        ) ?? []
        self.definitionMatchAnnotations = try container.decodeIfPresent(
            [EditorReviewAnnotation].self,
            forKey: .definitionMatchAnnotations
        ) ?? []
        self.ignoredReviewItemIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .ignoredReviewItemIDs
        ) ?? []
        self.documentFindings = try container.decodeIfPresent(
            [AIConnectorDocumentFinding].self,
            forKey: .documentFindings
        ) ?? []
        self.reviewedReviewItemIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .reviewedReviewItemIDs
        ) ?? []
        self.definitionResolutions = try container.decodeIfPresent(
            [AIConnectorDefinitionResolution].self,
            forKey: .definitionResolutions
        ) ?? []
        self.definitionDebugSuggestions = try container.decodeIfPresent(
            [EditorSuggestion].self,
            forKey: .definitionDebugSuggestions
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(analyzedContentSHA256, forKey: .analyzedContentSHA256)
        try container.encode(analysisProfile, forKey: .analysisProfile)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(runSummary, forKey: .runSummary)
        try container.encode(editorSuggestions, forKey: .editorSuggestions)
        try container.encode(reviewAnnotations, forKey: .reviewAnnotations)
        try container.encode(definitionMatchAnnotations, forKey: .definitionMatchAnnotations)
        try container.encode(ignoredReviewItemIDs, forKey: .ignoredReviewItemIDs)
        try container.encode(documentFindings, forKey: .documentFindings)
        try container.encode(reviewedReviewItemIDs, forKey: .reviewedReviewItemIDs)
        try container.encode(definitionResolutions, forKey: .definitionResolutions)
        if !definitionDebugSuggestions.isEmpty {
            try container.encode(definitionDebugSuggestions, forKey: .definitionDebugSuggestions)
        }
    }

    /// Returns false when the snapshot no longer describes the current text,
    /// active analysis profile, or valid UTF-16 suggestion anchors.
    func isCompatible(
        with documentText: String,
        profile: AIConnectorAnalysisProfile
    ) -> Bool {
        guard version == Self.currentVersion,
              analyzedContentSHA256 == DocumentFingerprinting.contentSHA256(documentText),
              analysisProfile == profile else {
            return false
        }

        return editorSuggestions.allSatisfy { $0.isAnchored(to: documentText) }
            && reviewAnnotations.allSatisfy { $0.isAnchored(to: documentText) }
            && definitionMatchAnnotations.allSatisfy { $0.isAnchored(to: documentText) }
            && documentFindings.allSatisfy { $0.isAnchored(to: documentText) }
            && definitionResolutions.allSatisfy { $0.isAnchored(to: documentText) }
    }
}
