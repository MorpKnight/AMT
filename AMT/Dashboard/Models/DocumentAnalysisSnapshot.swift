import Foundation

/// Persisted, user-facing output of a completed document analysis.
///
/// The snapshot is intentionally smaller than `AIConnectorViewModel`: it
/// stores only the suggestions needed to restore the editor, together with the
/// exact document content and analysis profile that produced them.
struct DocumentAnalysisSnapshot: Codable, Equatable, Hashable {
    static let currentVersion = 1

    let version: Int
    let analyzedContentSHA256: String
    let analysisProfile: AIConnectorAnalysisProfile
    let completedAt: Date
    let runSummary: AIConnectorRunSummary?
    let editorSuggestions: [EditorSuggestion]
    let definitionDebugSuggestions: [EditorSuggestion]

    init(
        analyzedContentSHA256: String,
        analysisProfile: AIConnectorAnalysisProfile,
        completedAt: Date,
        runSummary: AIConnectorRunSummary? = nil,
        editorSuggestions: [EditorSuggestion],
        definitionDebugSuggestions: [EditorSuggestion] = [],
        version: Int = currentVersion
    ) {
        self.version = version
        self.analyzedContentSHA256 = analyzedContentSHA256
        self.analysisProfile = analysisProfile
        self.completedAt = completedAt
        self.runSummary = runSummary
        self.editorSuggestions = editorSuggestions
        self.definitionDebugSuggestions = definitionDebugSuggestions
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

        return (editorSuggestions + definitionDebugSuggestions).allSatisfy {
            $0.isAnchored(to: documentText)
        }
    }
}
