import Foundation

/// Optional Debug report extension; document serialization is unchanged.
nonisolated struct AIConnectorLegalReviewDiagnostics: Codable, Hashable, Sendable {
    let policy: String
    let status: String
    let failures: [String]
    let modelAttempts: Int
    let resultCacheHit: Bool
    let route: String?
    let baseUsedModel: Bool
}
