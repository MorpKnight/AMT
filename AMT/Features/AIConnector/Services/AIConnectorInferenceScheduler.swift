import Foundation

nonisolated enum AIConnectorInferencePriority: Sendable {
    case background
    case interactive
}

nonisolated enum AIConnectorInferenceContext {
    @TaskLocal static var reuseScoringCache = true
    @TaskLocal static var priority: AIConnectorInferencePriority = .background
}

/// Application-owned admission gate for MLX work. Cancelling a queued owner
/// removes only its request; an admitted operation retains its lease until exit.
actor AIConnectorInferenceScheduler {
    private struct Request {
        let id: UUID
        let priority: AIConnectorInferencePriority
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var activeID: UUID?
    private var requests: [Request] = []
    private var interactiveStreak = 0

    func acquire(priority: AIConnectorInferencePriority = AIConnectorInferenceContext.priority) async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if activeID == nil {
                    activeID = id
                    continuation.resume(returning: id)
                } else {
                    requests.append(Request(id: id, priority: priority, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelQueuedRequest(id) }
        }
    }

    func release(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
        guard !requests.isEmpty else { return }
        let background = requests.firstIndex { $0.priority == .background }
        let interactive = requests.firstIndex { $0.priority == .interactive }
        let index = interactiveStreak >= 3 ? (background ?? interactive ?? 0) : (interactive ?? background ?? 0)
        let next = requests.remove(at: index)
        interactiveStreak = next.priority == .interactive ? interactiveStreak + 1 : 0
        activeID = next.id
        next.continuation.resume(returning: next.id)
    }

#if DEBUG
    var queuedRequestCount: Int { requests.count }
#endif

    private func cancelQueuedRequest(_ id: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        requests.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
