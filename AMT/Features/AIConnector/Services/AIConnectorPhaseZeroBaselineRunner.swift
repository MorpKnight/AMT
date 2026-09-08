#if DEBUG
import Foundation

struct AIConnectorPhaseZeroProgress: Sendable {
    let phase: String
    let completedPhaseCount: Int
    let totalPhaseCount: Int
    let runKind: AIConnectorPhaseZeroRunKind?
}

struct AIConnectorPhaseZeroExecution: Sendable {
    let observation: AIConnectorObservationReport
    let resultsByFixtureID: [String: AIConnectorSegmentResult]
}

/// Runs the opt-in Phase 0 suite serially. The execution and preparation
/// handlers make the ordering/cache contract testable without downloading
/// Qwen, E5, or TataKata in regular XCTest runs.
@MainActor
final class AIConnectorPhaseZeroBaselineRunner {
    typealias PreparationHandler = @MainActor (
        AIConnectorObservationCollector
    ) async throws -> Void
    typealias ExecutionHandler = @MainActor (
        AIConnectorPhaseZeroRunKind,
        [AIConnectorPhaseZeroFixture],
        AIConnectorObservationCollector
    ) async throws -> AIConnectorPhaseZeroExecution

    private let fixtures: [AIConnectorPhaseZeroFixture]
    private let modelVariant: AIConnectorModelVariant
    private let generationProfile: AIConnectorGenerationProfilePreset
    private let thinkingEnabled: Bool
    private let pipelineVersion: String
    private let rulePackVersion: String
    private let corpusVersion: String
    private let preparationHandler: PreparationHandler?
    private let executionHandler: ExecutionHandler

    init(
        fixtures: [AIConnectorPhaseZeroFixture] = AIConnectorPhaseZeroFixtureCatalog.fixtures,
        modelVariant: AIConnectorModelVariant = .qwen35Base4B,
        generationProfile: AIConnectorGenerationProfilePreset = .greedy,
        thinkingEnabled: Bool = false,
        pipelineVersion: String = "unknown",
        rulePackVersion: String = AIConnectorRuleStore.currentVersion,
        corpusVersion: String = "unknown",
        preparationHandler: PreparationHandler? = nil,
        executionHandler: @escaping ExecutionHandler
    ) {
        self.fixtures = fixtures
        self.modelVariant = modelVariant
        self.generationProfile = generationProfile
        self.thinkingEnabled = thinkingEnabled
        self.pipelineVersion = pipelineVersion
        self.rulePackVersion = rulePackVersion
        self.corpusVersion = corpusVersion
        self.preparationHandler = preparationHandler
        self.executionHandler = executionHandler
    }

    convenience init(
        benchmarkRunner: AIConnectorBenchmarkRunner,
        fixtures: [AIConnectorPhaseZeroFixture] = AIConnectorPhaseZeroFixtureCatalog.fixtures,
        modelVariant: AIConnectorModelVariant = .qwen35Base4B,
        generationProfile: AIConnectorGenerationProfilePreset = .greedy,
        thinkingEnabled: Bool = false,
        pipelineVersion: String = "unknown",
        rulePackVersion: String = AIConnectorRuleStore.currentVersion,
        corpusVersion: String = "unknown"
    ) {
        var hybridCacheSnapshot: [String: AIConnectorCachedSegmentResult]?
        self.init(
            fixtures: fixtures,
            modelVariant: modelVariant,
            generationProfile: generationProfile,
            thinkingEnabled: thinkingEnabled,
            pipelineVersion: pipelineVersion,
            rulePackVersion: rulePackVersion,
            corpusVersion: corpusVersion,
            preparationHandler: { collector in
                try await benchmarkRunner.prepareResources(
                    modelVariant: modelVariant,
                    observationCollector: collector
                )
            },
            executionHandler: { kind, fixtures, collector in
                var resultsBySegmentID: [Int: AIConnectorSegmentResult] = [:]
                let samples = fixtures.map { fixture in
                    AIConnectorSample(
                        id: fixture.id,
                        title: fixture.id,
                        text: fixture.text,
                        expectedSignal: fixture.category.rawValue
                    )
                }

                do {
                    let report = try await benchmarkRunner.run(
                        mode: kind.mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        samples: samples,
                        resetCache: kind.resetsCache,
                        generationProfilePreset: generationProfile,
                        progress: { _, _ in },
                        observationCollector: collector,
                        resultObserver: { result in
                            resultsBySegmentID[result.segment.id] = result
                        }
                    )
                    if kind == .hybridSteadyState {
                        hybridCacheSnapshot = await benchmarkRunner.cacheSnapshot()
                    } else if kind == .modelOnlySteadyState,
                              let hybridCacheSnapshot {
                        await benchmarkRunner.restoreCache(hybridCacheSnapshot)
                    }
                    let resultsByFixtureID = Self.mapResults(
                        report: report,
                        resultsBySegmentID: resultsBySegmentID,
                        fixtures: fixtures
                    )
                    let accuracy = AIConnectorPhaseZeroAccuracyEvaluator().summaries(
                        fixtures: fixtures,
                        resultsByFixtureID: resultsByFixtureID
                    )
                    let observation = await collector.finish(
                        status: .completed,
                        accuracy: accuracy
                    )
                    return AIConnectorPhaseZeroExecution(
                        observation: observation,
                        resultsByFixtureID: resultsByFixtureID
                    )
                } catch is CancellationError {
                    if kind == .modelOnlySteadyState,
                       let hybridCacheSnapshot {
                        await benchmarkRunner.restoreCache(hybridCacheSnapshot)
                    }
                    let resultsByFixtureID = Self.mapResults(
                        resultsBySegmentID: resultsBySegmentID,
                        fixtures: fixtures
                    )
                    let accuracy = AIConnectorPhaseZeroAccuracyEvaluator().summaries(
                        fixtures: fixtures,
                        resultsByFixtureID: resultsByFixtureID
                    )
                    let observation = await collector.finish(
                        status: .cancelled,
                        accuracy: accuracy
                    )
                    return AIConnectorPhaseZeroExecution(
                        observation: observation,
                        resultsByFixtureID: resultsByFixtureID
                    )
                }
            }
        )
    }

    func run(
        progress: @escaping @MainActor (AIConnectorPhaseZeroProgress) -> Void = { _ in }
    ) async -> AIConnectorBaselineSuiteReport {
        let totalPhases = AIConnectorPhaseZeroRunKind.allCases.count + 1
        var completedPhases = 0
        var resourceReport: AIConnectorObservationReport?
        var runReports: [AIConnectorBaselineRunReport] = []
        var terminalStatus: AIConnectorObservationTerminalStatus = .completed
        var failureCode: String?

        let resourceCollector = makeCollector(mode: .hybrid)
        progress(
            AIConnectorPhaseZeroProgress(
                phase: "resourcePreparation",
                completedPhaseCount: completedPhases,
                totalPhaseCount: totalPhases,
                runKind: nil
            )
        )
        do {
            try Task.checkCancellation()
            try await preparationHandler?(resourceCollector)
            resourceReport = await resourceCollector.finish(status: .completed)
            completedPhases += 1
            progress(
                AIConnectorPhaseZeroProgress(
                    phase: "resourcePreparation",
                    completedPhaseCount: completedPhases,
                    totalPhaseCount: totalPhases,
                    runKind: nil
                )
            )
        } catch is CancellationError {
            resourceReport = await resourceCollector.finish(status: .cancelled)
            terminalStatus = .cancelled
            return makeSuite(
                status: terminalStatus,
                resourceReport: resourceReport,
                runs: runReports,
                failureCode: nil
            )
        } catch {
            resourceReport = await resourceCollector.finish(
                status: .failed,
                failureCode: "resource-preparation-failed"
            )
            terminalStatus = .failed
            failureCode = "resource-preparation-failed"
            return makeSuite(
                status: terminalStatus,
                resourceReport: resourceReport,
                runs: runReports,
                failureCode: failureCode
            )
        }

        for kind in AIConnectorPhaseZeroRunKind.allCases {
            if Task.isCancelled {
                terminalStatus = .cancelled
                break
            }

            let collector = makeCollector(mode: kind.mode)
            progress(
                AIConnectorPhaseZeroProgress(
                    phase: kind.rawValue,
                    completedPhaseCount: completedPhases,
                    totalPhaseCount: totalPhases,
                    runKind: kind
                )
            )
            do {
                let execution = try await executionHandler(kind, fixtures, collector)
                runReports.append(
                    AIConnectorBaselineRunReport(
                        kind: kind,
                        mode: kind.mode,
                        cacheResetBeforeRun: kind.resetsCache,
                        observation: execution.observation
                    )
                )
                completedPhases += 1
                progress(
                    AIConnectorPhaseZeroProgress(
                        phase: kind.rawValue,
                        completedPhaseCount: completedPhases,
                        totalPhaseCount: totalPhases,
                        runKind: kind
                    )
                )
                if execution.observation.terminalStatus == .cancelled {
                    terminalStatus = .cancelled
                    break
                } else if execution.observation.terminalStatus == .failed {
                    terminalStatus = .failed
                    failureCode = execution.observation.failureCode ?? "run-failed"
                    break
                }
            } catch is CancellationError {
                let observation = await collector.finish(status: .cancelled)
                runReports.append(
                    AIConnectorBaselineRunReport(
                        kind: kind,
                        mode: kind.mode,
                        cacheResetBeforeRun: kind.resetsCache,
                        observation: observation
                    )
                )
                terminalStatus = .cancelled
                break
            } catch {
                let observation = await collector.finish(
                    status: .failed,
                    failureCode: "run-failed"
                )
                runReports.append(
                    AIConnectorBaselineRunReport(
                        kind: kind,
                        mode: kind.mode,
                        cacheResetBeforeRun: kind.resetsCache,
                        observation: observation
                    )
                )
                terminalStatus = .failed
                failureCode = "run-failed"
                break
            }
        }

        if terminalStatus == .completed, Task.isCancelled {
            terminalStatus = .cancelled
        }
        return makeSuite(
            status: terminalStatus,
            resourceReport: resourceReport,
            runs: runReports,
            failureCode: failureCode
        )
    }

    private func makeCollector(mode: AIConnectorReviewMode) -> AIConnectorObservationCollector {
        AIConnectorObservationCollector(
            mode: mode,
            modelVariant: modelVariant,
            generationProfile: generationProfile.rawValue,
            thinkingEnabled: thinkingEnabled,
            pipelineVersion: pipelineVersion,
            rulePackVersion: rulePackVersion,
            corpusVersion: corpusVersion
        )
    }

    private func makeSuite(
        status: AIConnectorObservationTerminalStatus,
        resourceReport: AIConnectorObservationReport?,
        runs: [AIConnectorBaselineRunReport],
        failureCode: String?
    ) -> AIConnectorBaselineSuiteReport {
        AIConnectorBaselineSuiteReport(
            schemaVersion: AIConnectorBaselineSuiteReport.schemaVersion,
            generatedAt: Date(),
            terminalStatus: status,
            fixtureCount: fixtures.count,
            fixtureReviewStatus: fixtures.allSatisfy {
                $0.reviewStatus == .approved
            } ? .approved : .pendingLawyerReview,
            modelVariant: modelVariant,
            modelRevision: modelVariant.revision,
            generationProfile: generationProfile.rawValue,
            thinkingEnabled: thinkingEnabled,
            pipelineVersion: pipelineVersion,
            rulePackVersion: rulePackVersion,
            corpusVersion: corpusVersion,
            resourcePreparation: resourceReport,
            runs: runs,
            comparison: comparison(for: runs),
            failureCode: failureCode
        )
    }

    private func comparison(
        for runs: [AIConnectorBaselineRunReport]
    ) -> AIConnectorBaselineComparisonSummary {
        let modeComparisons: [AIConnectorModeComparison] = AIConnectorReviewMode.allCases.compactMap { mode in
            let modeRuns = runs.filter { $0.mode == mode }
            guard !modeRuns.isEmpty else { return nil }
            let durations = modeRuns.flatMap {
                $0.observation.segments.map(\.duration)
            }
            return AIConnectorModeComparison(
                mode: mode,
                runKinds: modeRuns.map(\.kind),
                totalDuration: modeRuns.reduce(0) {
                    $0 + $1.observation.totalDuration
                },
                segmentLatencyP50: Self.percentile(durations, 0.50),
                segmentLatencyP95: Self.percentile(durations, 0.95),
                modelCallCount: modeRuns.reduce(0) {
                    $0 + $1.observation.modelCallCount
                },
                fallbackCount: modeRuns.reduce(0) {
                    $0 + $1.observation.fallbackCount
                },
                repairCount: modeRuns.reduce(0) {
                    $0 + $1.observation.repairCount
                },
                challengeCount: modeRuns.reduce(0) {
                    $0 + $1.observation.challengeCount
                },
                cacheHitCount: modeRuns.reduce(0) {
                    $0 + $1.observation.cacheHitCount
                }
            )
        }
        return AIConnectorBaselineComparisonSummary(modes: modeComparisons)
    }

    private static func mapResults(
        report: AIConnectorBenchmarkReport,
        resultsBySegmentID: [Int: AIConnectorSegmentResult],
        fixtures: [AIConnectorPhaseZeroFixture]
    ) -> [String: AIConnectorSegmentResult] {
        let fixtureIDs = Set(fixtures.map(\.id))
        return report.records.reduce(into: [:]) { result, record in
            guard fixtureIDs.contains(record.sampleID),
                  let segmentID = record.segmentID,
                  let segmentResult = resultsBySegmentID[segmentID] else {
                return
            }
            result[record.sampleID] = segmentResult
        }
    }

    private static func mapResults(
        resultsBySegmentID: [Int: AIConnectorSegmentResult],
        fixtures: [AIConnectorPhaseZeroFixture]
    ) -> [String: AIConnectorSegmentResult] {
        fixtures.enumerated().reduce(into: [:]) { result, item in
            let segmentID = item.offset + 1
            if let segmentResult = resultsBySegmentID[segmentID] {
                result[item.element.id] = segmentResult
            }
        }
    }

    private static func percentile(_ values: [TimeInterval], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return max(0, sorted[0]) }
        let position = Double(sorted.count - 1) * min(max(percentile, 0), 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return max(0, sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower)))
    }
}
#endif
