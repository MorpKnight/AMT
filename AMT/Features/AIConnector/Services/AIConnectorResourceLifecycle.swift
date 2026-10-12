import Dispatch
import Foundation
import MLX

nonisolated enum AIConnectorMemoryPressure: Int, Sendable {
    case normal, warning, critical
}

/// Application-owned maintenance. All MLX releases hold the shared inference lease.
/// Document cache callbacks use weak captures and never change published results.
@MainActor
final class AIConnectorResourceLifecycle {
    private weak var service: QwenSuggestionService?
    private let scheduler: AIConnectorInferenceScheduler
    private var source: (any DispatchSourceMemoryPressure)?
    private var task: Task<Void, Never>?
    private var requested: AIConnectorMemoryPressure = .normal
    private var applied: AIConnectorMemoryPressure = .normal
    private var documentTrimmers: [UUID: @MainActor () async -> Bool] = [:]
    private var semanticRuntimes: [WeakSemanticRuntime] = []
    private(set) var maintenanceCount = 0
    private(set) var modelReleaseCount = 0
    private(set) var lastMaintenanceActiveBefore = 0
    private(set) var lastMaintenanceActiveAfter = 0
    private(set) var lastMaintenanceCacheAfter = 0
    var runtimePeakMemory: Int { Memory.peakMemory }
    private var installed = false
    static let normalBufferCacheLimit = 512 * 1_024 * 1_024

    init(service: QwenSuggestionService, scheduler: AIConnectorInferenceScheduler) {
        self.service = service; self.scheduler = scheduler
    }
    func installIfNeeded() {
        guard !installed else { return }
        installed = true
        Memory.cacheLimit = Self.normalBufferCacheLimit
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let events = self.source?.data else { return }
                let level: AIConnectorMemoryPressure = events.contains(.critical) ? .critical : (events.contains(.warning) ? .warning : .normal)
                await self.handle(level)
            }
        }
        self.source = source; source.resume()
    }
    func registerDocument(owner: UUID, trim: @escaping @MainActor () async -> Bool) {
        documentTrimmers[owner] = trim
    }
    func attach(_ retriever: LegalSemanticRetriever?) {
        guard let retriever else { return }
        semanticRuntimes.removeAll { $0.value == nil }
        if !semanticRuntimes.contains(where: { $0.value === retriever }) {
            semanticRuntimes.append(WeakSemanticRuntime(retriever))
        }
    }
    func handle(_ level: AIConnectorMemoryPressure) async {
        if level == .normal {
            requested = .normal; applied = .normal
            if installed { Memory.cacheLimit = Self.normalBufferCacheLimit }
            return
        }
        if level.rawValue > requested.rawValue { requested = level }
        if let task { await task.value; return }
        guard requested.rawValue > applied.rawValue else { return }
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.requested.rawValue > self.applied.rawValue {
                let pressure = self.requested
                self.applied = pressure
                for (owner, trim) in Array(self.documentTrimmers) {
                    if !(await trim()) { self.documentTrimmers.removeValue(forKey: owner) }
                }
                await self.service?.languageScorer.clearCachedScores()
                // Maintenance is admitted after active work; it does not cancel any owner.
                guard let lease = try? await self.scheduler.acquire(priority: .maintenance) else { return }
                self.lastMaintenanceActiveBefore = Memory.activeMemory
                if pressure == .critical {
                    self.service?.releaseResidentModelsForMaintenance()
                    await self.service?.languageScorer.releaseIdleRuntimeForMaintenance()
                    for runtime in self.semanticRuntimes { await runtime.value?.releaseIdleRuntimeForMaintenance() }
                    self.modelReleaseCount += 1
                }
                Memory.cacheLimit = pressure == .critical ? 0 : 64 * 1_024 * 1_024
                Memory.clearCache()
                self.lastMaintenanceActiveAfter = Memory.activeMemory
                self.lastMaintenanceCacheAfter = Memory.cacheMemory
                self.maintenanceCount += 1
                await self.scheduler.release(lease)
            }
        }
        task = work
        await work.value
        task = nil
        if requested == .normal { applied = .normal; Memory.cacheLimit = Self.normalBufferCacheLimit }
    }
    deinit { source?.cancel() }

    private final class WeakSemanticRuntime {
        weak var value: LegalSemanticRetriever?
        init(_ value: LegalSemanticRetriever) { self.value = value }
    }
}
