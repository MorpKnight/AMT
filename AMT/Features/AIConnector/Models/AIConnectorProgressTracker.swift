import Foundation

/// Keeps the displayed analysis progress from moving backwards when a queue
/// starts the next segment and reports an earlier processing stage again.
struct AIConnectorProgressTracker: Equatable, Sendable {
    private(set) var value: Double

    init(value: Double = 0) {
        self.value = Self.clamped(value)
    }

    mutating func reset() {
        value = 0
    }

    mutating func advance(to candidate: Double) {
        value = max(value, Self.clamped(candidate))
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
