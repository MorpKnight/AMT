#if DEBUG
import Foundation

/// Which candidate policy produced a comparison run. The report deliberately
/// stores the side as a label rather than the in-memory runner itself.
nonisolated enum AIConnectorPhaseTwoComparisonSide: String, Codable, Hashable, Sendable {
    case phaseOneCompatible = "phase1-compatible"
    case phaseTwo = "phase2"
}

nonisolated struct AIConnectorPhaseTwoRouteCounts: Codable, Hashable, Sendable {
    let deterministic: Int
    let modelReview: Int
    let needsReview: Int
    let suppressed: Int

    static let zero = AIConnectorPhaseTwoRouteCounts(
        deterministic: 0,
        modelReview: 0,
        needsReview: 0,
        suppressed: 0
    )
}

/// A privacy-safe side of the Phase 2 comparison. It contains only counts,
/// durations, version labels, and provisional accuracy summaries.
nonisolated struct AIConnectorPhaseTwoRunMetrics: Codable, Hashable, Sendable,
    Identifiable {
    let side: AIConnectorPhaseTwoComparisonSide
    let mode: AIConnectorReviewMode
    let fixtureCount: Int
    let observedFixtureCount: Int
    let totalDuration: TimeInterval
    let segmentLatencyP50: TimeInterval
    let segmentLatencyP95: TimeInterval
    let slowestStage: AIConnectorObservationStage?
    let slowestStageDuration: TimeInterval
    let modelCallCount: Int
    let fallbackCount: Int
    let repairCount: Int
    let challengeCount: Int
    let cacheHitCount: Int
    let needsReviewCount: Int
    let candidateCount: Int
    let droppedCandidateCount: Int
    let candidateConflictCount: Int
    let routeCounts: AIConnectorPhaseTwoRouteCounts
    let accuracy: [AIConnectorAccuracySummary]
    let terminalStatus: AIConnectorObservationTerminalStatus

    var id: String { side.rawValue }
}

nonisolated struct AIConnectorPhaseTwoComparisonDelta: Codable, Hashable, Sendable {
    let totalDuration: TimeInterval
    let modelCallCount: Int
    let fallbackCount: Int
    let repairCount: Int
    let challengeCount: Int
    let cacheHitCount: Int
    let candidateCount: Int
    let needsReviewCount: Int
    let suppressedCandidateCount: Int
}

nonisolated struct AIConnectorPhaseTwoComparisonReport: Codable, Hashable, Sendable {
    static let schemaVersion = "phase2-comparison-v1"

    let schemaVersion: String
    let generatedAt: Date
    let terminalStatus: AIConnectorObservationTerminalStatus
    let fixtureCount: Int
    let fixtureReviewStatus: AIConnectorFixtureReviewStatus
    let modelVariant: AIConnectorModelVariant
    let generationProfile: String
    let thinkingEnabled: Bool
    let pipelineVersion: String
    let resourcePreparation: AIConnectorObservationReport?
    let runs: [AIConnectorPhaseTwoRunMetrics]
    let delta: AIConnectorPhaseTwoComparisonDelta?
    let failureCode: String?
}

struct AIConnectorPhaseTwoRunExecution: Sendable {
    let observation: AIConnectorObservationReport
    let resultsByFixtureID: [String: AIConnectorSegmentResult]
}

struct AIConnectorPhaseTwoComparisonProgress: Sendable {
    let phase: String
    let completedPhaseCount: Int
    let totalPhaseCount: Int
    let side: AIConnectorPhaseTwoComparisonSide?
}

/// Executes the same fixture set with the Phase 1-compatible and Phase 2
/// processors. The handler boundary keeps the ordering and cancellation logic
/// testable without downloading a model in regular XCTest runs.
@MainActor
final class AIConnectorPhaseTwoComparisonRunner {
    typealias PreparationHandler = @MainActor (
        AIConnectorModelVariant,
        AIConnectorObservationCollector
    ) async throws -> Void
    typealias ExecutionHandler = @MainActor (
        AIConnectorPhaseTwoComparisonSide,
        AIConnectorReviewMode,
        AIConnectorModelVariant,
        AIConnectorGenerationProfilePreset,
        Bool,
        [AIConnectorPhaseZeroFixture],
        AIConnectorObservationCollector
    ) async throws -> AIConnectorPhaseTwoRunExecution

    private let fixtures: [AIConnectorPhaseZeroFixture]
    private let pipelineVersion: String
    private let preparationHandler: PreparationHandler?
    private let executionHandler: ExecutionHandler

    init(
        fixtures: [AIConnectorPhaseZeroFixture] = AIConnectorPhaseZeroFixtureCatalog.fixtures,
        pipelineVersion: String = "unknown",
        preparationHandler: PreparationHandler? = nil,
        executionHandler: @escaping ExecutionHandler
    ) {
        self.fixtures = fixtures
        self.pipelineVersion = pipelineVersion
        self.preparationHandler = preparationHandler
        self.executionHandler = executionHandler
    }

    convenience init(
        phaseOneRunner: AIConnectorBenchmarkRunner,
        phaseTwoRunner: AIConnectorBenchmarkRunner,
        fixtures: [AIConnectorPhaseZeroFixture] = AIConnectorPhaseZeroFixtureCatalog.fixtures,
        pipelineVersion: String = "unknown"
    ) {
        self.init(
            fixtures: fixtures,
            pipelineVersion: pipelineVersion,
            preparationHandler: { modelVariant, collector in
                try await phaseOneRunner.prepareResources(
                    modelVariant: modelVariant,
                    observationCollector: collector
                )
                try await phaseTwoRunner.prepareResources(
                    modelVariant: modelVariant,
                    observationCollector: collector
                )
            },
            executionHandler: { side, mode, modelVariant, profile, thinkingEnabled, fixtures, collector in
                let runner = side == .phaseTwo ? phaseTwoRunner : phaseOneRunner
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
                    _ = try await runner.run(
                        mode: mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        samples: samples,
                        resetCache: true,
                        generationProfilePreset: profile,
                        progress: { _, _ in },
                        observationCollector: collector,
                        resultObserver: { result in
                            resultsBySegmentID[result.segment.id] = result
                        }
                    )
                    return await Self.execution(
                        status: .completed,
                        fixtures: fixtures,
                        resultsBySegmentID: resultsBySegmentID,
                        collector: collector
                    )
                } catch is CancellationError {
                    return await Self.execution(
                        status: .cancelled,
                        fixtures: fixtures,
                        resultsBySegmentID: resultsBySegmentID,
                        collector: collector
                    )
                }
            }
        )
    }

    func run(
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        generationProfile: AIConnectorGenerationProfilePreset,
        thinkingEnabled: Bool,
        progress: @escaping @MainActor (AIConnectorPhaseTwoComparisonProgress) -> Void = { _ in }
    ) async -> AIConnectorPhaseTwoComparisonReport {
        let hasPreparation = preparationHandler != nil
        let totalPhases = hasPreparation ? 3 : 2
        var completedPhases = 0
        var resourcePreparation: AIConnectorObservationReport?
        var runs: [AIConnectorPhaseTwoRunMetrics] = []
        var terminalStatus: AIConnectorObservationTerminalStatus = .completed
        var failureCode: String?

        if let preparationHandler {
            let collector = AIConnectorObservationCollector(
                mode: mode,
                modelVariant: modelVariant,
                generationProfile: generationProfile.rawValue,
                thinkingEnabled: thinkingEnabled,
                pipelineVersion: pipelineVersion,
                rulePackVersion: AIConnectorRuleStore.currentVersion
            )
            progress(
                AIConnectorPhaseTwoComparisonProgress(
                    phase: "resourcePreparation",
                    completedPhaseCount: completedPhases,
                    totalPhaseCount: totalPhases,
                    side: nil
                )
            )
            do {
                try Task.checkCancellation()
                try await preparationHandler(modelVariant, collector)
                resourcePreparation = await collector.finish(status: .completed)
                completedPhases += 1
            } catch is CancellationError {
                resourcePreparation = await collector.finish(status: .cancelled)
                terminalStatus = .cancelled
            } catch {
                resourcePreparation = await collector.finish(
                    status: .failed,
                    failureCode: "resource-preparation-failed"
                )
                terminalStatus = .failed
                failureCode = "resource-preparation-failed"
            }
            progress(
                AIConnectorPhaseTwoComparisonProgress(
                    phase: "resourcePreparation",
                    completedPhaseCount: completedPhases,
                    totalPhaseCount: totalPhases,
                    side: nil
                )
            )
        }

        if terminalStatus == .completed {
            for side in [
                AIConnectorPhaseTwoComparisonSide.phaseOneCompatible,
                .phaseTwo
            ] {
                if Task.isCancelled {
                    terminalStatus = .cancelled
                    break
                }

                let collector = AIConnectorObservationCollector(
                    mode: mode,
                    modelVariant: modelVariant,
                    generationProfile: generationProfile.rawValue,
                    thinkingEnabled: thinkingEnabled,
                    pipelineVersion: pipelineVersion,
                    rulePackVersion: AIConnectorRuleStore.currentVersion
                )
                progress(
                    AIConnectorPhaseTwoComparisonProgress(
                        phase: side.rawValue,
                        completedPhaseCount: completedPhases,
                        totalPhaseCount: totalPhases,
                        side: side
                    )
                )
                do {
                    let execution = try await executionHandler(
                        side,
                        mode,
                        modelVariant,
                        generationProfile,
                        thinkingEnabled,
                        fixtures,
                        collector
                    )
                    let metrics = Self.metrics(
                        side: side,
                        fixtureCount: fixtures.count,
                        execution: execution
                    )
                    runs.append(metrics)
                    completedPhases += 1
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
                    runs.append(
                        Self.metrics(
                            side: side,
                            fixtureCount: fixtures.count,
                            execution: AIConnectorPhaseTwoRunExecution(
                                observation: observation,
                                resultsByFixtureID: [:]
                            )
                        )
                    )
                    terminalStatus = .cancelled
                    break
                } catch {
                    let observation = await collector.finish(
                        status: .failed,
                        failureCode: "run-failed"
                    )
                    runs.append(
                        Self.metrics(
                            side: side,
                            fixtureCount: fixtures.count,
                            execution: AIConnectorPhaseTwoRunExecution(
                                observation: observation,
                                resultsByFixtureID: [:]
                            )
                        )
                    )
                    terminalStatus = .failed
                    failureCode = "run-failed"
                    break
                }
            }
        }

        if terminalStatus == .completed, Task.isCancelled {
            terminalStatus = .cancelled
        }
        return AIConnectorPhaseTwoComparisonReport(
            schemaVersion: AIConnectorPhaseTwoComparisonReport.schemaVersion,
            generatedAt: Date(),
            terminalStatus: terminalStatus,
            fixtureCount: fixtures.count,
            fixtureReviewStatus: fixtures.allSatisfy { $0.reviewStatus == .approved }
                ? .approved
                : .pendingLawyerReview,
            modelVariant: modelVariant,
            generationProfile: generationProfile.rawValue,
            thinkingEnabled: thinkingEnabled,
            pipelineVersion: pipelineVersion,
            resourcePreparation: resourcePreparation,
            runs: runs,
            delta: Self.delta(between: runs),
            failureCode: failureCode
        )
    }

    private static func execution(
        status: AIConnectorObservationTerminalStatus,
        fixtures: [AIConnectorPhaseZeroFixture],
        resultsBySegmentID: [Int: AIConnectorSegmentResult],
        collector: AIConnectorObservationCollector
    ) async -> AIConnectorPhaseTwoRunExecution {
        let resultsByFixtureID = mapResults(
            fixtures: fixtures,
            resultsBySegmentID: resultsBySegmentID
        )
        let accuracy = AIConnectorPhaseZeroAccuracyEvaluator().summaries(
            fixtures: fixtures,
            resultsByFixtureID: resultsByFixtureID
        )
        let observation = await collector.finish(
            status: status,
            accuracy: accuracy
        )
        return AIConnectorPhaseTwoRunExecution(
            observation: observation,
            resultsByFixtureID: resultsByFixtureID
        )
    }

    private static func mapResults(
        fixtures: [AIConnectorPhaseZeroFixture],
        resultsBySegmentID: [Int: AIConnectorSegmentResult]
    ) -> [String: AIConnectorSegmentResult] {
        Dictionary(uniqueKeysWithValues: fixtures.enumerated().compactMap { index, fixture in
            guard let result = resultsBySegmentID[index + 1] else { return nil }
            return (fixture.id, result)
        })
    }

    private static func metrics(
        side: AIConnectorPhaseTwoComparisonSide,
        fixtureCount: Int,
        execution: AIConnectorPhaseTwoRunExecution
    ) -> AIConnectorPhaseTwoRunMetrics {
        let observation = execution.observation
        var routeCounts = AIConnectorPhaseTwoRouteCounts.zero
        var candidateCount = 0
        var droppedCandidateCount = 0
        var candidateConflictCount = 0
        for result in execution.resultsByFixtureID.values {
            candidateCount += result.candidates.count
            droppedCandidateCount += result.droppedCandidateCount
            candidateConflictCount += result.candidateConflictCount
            for route in result.candidateRoutes {
                switch route.route {
                case .deterministic:
                    routeCounts = AIConnectorPhaseTwoRouteCounts(
                        deterministic: routeCounts.deterministic + 1,
                        modelReview: routeCounts.modelReview,
                        needsReview: routeCounts.needsReview,
                        suppressed: routeCounts.suppressed
                    )
                case .modelReview:
                    routeCounts = AIConnectorPhaseTwoRouteCounts(
                        deterministic: routeCounts.deterministic,
                        modelReview: routeCounts.modelReview + 1,
                        needsReview: routeCounts.needsReview,
                        suppressed: routeCounts.suppressed
                    )
                case .needsReview:
                    routeCounts = AIConnectorPhaseTwoRouteCounts(
                        deterministic: routeCounts.deterministic,
                        modelReview: routeCounts.modelReview,
                        needsReview: routeCounts.needsReview + 1,
                        suppressed: routeCounts.suppressed
                    )
                case .suppressed:
                    routeCounts = AIConnectorPhaseTwoRouteCounts(
                        deterministic: routeCounts.deterministic,
                        modelReview: routeCounts.modelReview,
                        needsReview: routeCounts.needsReview,
                        suppressed: routeCounts.suppressed + 1
                    )
                }
            }
        }
        let slowestStage = observation.stageMetrics.max {
            $0.totalDuration < $1.totalDuration
        }
        return AIConnectorPhaseTwoRunMetrics(
            side: side,
            mode: observation.mode,
            fixtureCount: fixtureCount,
            observedFixtureCount: execution.resultsByFixtureID.count,
            totalDuration: observation.totalDuration,
            segmentLatencyP50: observation.segmentLatencyP50,
            segmentLatencyP95: observation.segmentLatencyP95,
            slowestStage: slowestStage?.stage,
            slowestStageDuration: slowestStage?.totalDuration ?? 0,
            modelCallCount: observation.modelCallCount,
            fallbackCount: observation.fallbackCount,
            repairCount: observation.repairCount,
            challengeCount: observation.challengeCount,
            cacheHitCount: observation.cacheHitCount,
            needsReviewCount: observation.needsReviewCount,
            candidateCount: candidateCount,
            droppedCandidateCount: droppedCandidateCount,
            candidateConflictCount: candidateConflictCount,
            routeCounts: routeCounts,
            accuracy: observation.accuracy,
            terminalStatus: observation.terminalStatus
        )
    }

    private static func delta(
        between runs: [AIConnectorPhaseTwoRunMetrics]
    ) -> AIConnectorPhaseTwoComparisonDelta? {
        guard let phaseOne = runs.first(where: { $0.side == .phaseOneCompatible }),
              let phaseTwo = runs.first(where: { $0.side == .phaseTwo }) else {
            return nil
        }
        return AIConnectorPhaseTwoComparisonDelta(
            totalDuration: phaseTwo.totalDuration - phaseOne.totalDuration,
            modelCallCount: phaseTwo.modelCallCount - phaseOne.modelCallCount,
            fallbackCount: phaseTwo.fallbackCount - phaseOne.fallbackCount,
            repairCount: phaseTwo.repairCount - phaseOne.repairCount,
            challengeCount: phaseTwo.challengeCount - phaseOne.challengeCount,
            cacheHitCount: phaseTwo.cacheHitCount - phaseOne.cacheHitCount,
            candidateCount: phaseTwo.candidateCount - phaseOne.candidateCount,
            needsReviewCount: phaseTwo.needsReviewCount - phaseOne.needsReviewCount,
            suppressedCandidateCount: phaseTwo.routeCounts.suppressed
                - phaseOne.routeCounts.suppressed
        )
    }
}
#endif
