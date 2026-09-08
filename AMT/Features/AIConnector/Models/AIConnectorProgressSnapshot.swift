import Foundation

/// A single, UI-ready snapshot of an analysis run's progress.
///
/// `overallFraction` is nil until the segmenter has produced a known total.
/// `phaseFraction` is only populated for phases with a real determinate
/// fraction, such as a model download.
nonisolated struct AIConnectorProgressSnapshot: Equatable, Sendable {
    let stage: AIConnectorProgressStage
    let overallFraction: Double?
    let phaseFraction: Double?
    let completedSegmentCount: Int
    let totalSegmentCount: Int
    let currentSegmentID: Int?
    let generationCharacters: Int
    let startedAt: Date
    let lastActivityAt: Date
    let reusedSegmentCount: Int
    let reprocessedSegmentCount: Int
    let pendingSegmentCount: Int

    init(
        stage: AIConnectorProgressStage,
        overallFraction: Double?,
        phaseFraction: Double?,
        completedSegmentCount: Int,
        totalSegmentCount: Int,
        currentSegmentID: Int?,
        generationCharacters: Int,
        startedAt: Date,
        lastActivityAt: Date,
        reusedSegmentCount: Int = 0,
        reprocessedSegmentCount: Int = 0,
        pendingSegmentCount: Int = 0
    ) {
        self.stage = stage
        self.overallFraction = overallFraction.map(Self.clamped)
        self.phaseFraction = phaseFraction.map(Self.clamped)
        self.completedSegmentCount = completedSegmentCount
        self.totalSegmentCount = totalSegmentCount
        self.currentSegmentID = currentSegmentID
        self.generationCharacters = generationCharacters
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.reusedSegmentCount = max(reusedSegmentCount, 0)
        self.reprocessedSegmentCount = max(reprocessedSegmentCount, 0)
        self.pendingSegmentCount = max(pendingSegmentCount, 0)
    }

    var hasKnownOverallProgress: Bool {
        overallFraction != nil
    }

    var completedSegmentLabel: String? {
        guard totalSegmentCount > 0 else { return nil }
        let completed = min(
            max(completedSegmentCount, 0),
            totalSegmentCount
        )
        return "\(completed) dari \(totalSegmentCount) segmen selesai"
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
