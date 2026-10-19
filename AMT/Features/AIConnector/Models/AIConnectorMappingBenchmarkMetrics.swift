import Foundation

#if DEBUG
/// Measurement-only counters. Durations overlap and must not be summed as total pipeline time.
nonisolated struct AIConnectorMappingBenchmarkMetrics: Codable, Hashable, Sendable {
    var localMappingDuration: Double = 0
    var finalMappingDuration: Double = 0
    var localApplyDuration: Double = 0
    var finalApplyDuration: Double = 0
    var fullRebuildCount: Int = 0
    var remappedSegmentCount: Int = 0
    var findingMappingCount: Int = 0
}
#endif
