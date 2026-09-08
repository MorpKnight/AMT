import Foundation

nonisolated enum AIConnectorObservationTiming {
    static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            0,
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}

/// Collects Phase 0 measurements without retaining document or model text.
/// The actor boundary keeps concurrent progress callbacks from racing while
/// `ContinuousClock` keeps durations monotonic even if wall-clock time moves.
actor AIConnectorObservationCollector {
    private struct StageSample: Sendable {
        let stage: AIConnectorObservationStage
        let resource: String?
        let duration: TimeInterval
    }

    private struct SegmentAccumulator: Sendable {
        var utf16Length = 0
        var duration: TimeInterval = 0
        var stageSamples: [StageSample] = []
        var retrievalQueryCount = 0
        var semanticQueryCount = 0
        var spellingCandidateCount = 0
        var scoredSpellingCandidateCount = 0
        var candidateCount = 0
        var suggestionCount = 0
        var needsReviewCount = 0
        var noSuggestionCount = 0
        var rejectedCount = 0
        var cacheHit = false
        var modelCallCount = 0
        var definitionModelCallCount = 0
        var repairCount = 0
        var challengeCount = 0
        var fallbackCount = 0
        var modelOriginCount = 0
    }

    private let clock: ContinuousClock
    private let startedAt: ContinuousClock.Instant
    private let runID: UUID
    private let mode: AIConnectorReviewMode
    private let modelVariant: AIConnectorModelVariant
    private let modelRevision: String
    private let generationProfile: String
    private let thinkingEnabled: Bool
    private let pipelineVersion: String
    private let rulePackVersion: String
    private let corpusVersion: String

    private var totalInputUTF16Length = 0
    private var declaredSegmentCount = 0
    private var stageSamples: [StageSample] = []
    private var segments: [Int: SegmentAccumulator] = [:]
    private var terminalStatus: AIConnectorObservationTerminalStatus = .running
    private var failureCode: String?
    private var finishedAt: ContinuousClock.Instant?
    private var accuracy: [AIConnectorAccuracySummary] = []
    private var documentFindingCount = 0
    private var riskCandidateCount = 0
    private var riskModelCallCount = 0
    private var riskFallbackCount = 0
    private var riskCacheHitCount = 0
    private var documentFindingDuration: TimeInterval = 0
    private var riskReviewDuration: TimeInterval = 0
    private var definitionResolutionCandidateCount = 0
    private var definitionResolutionQueryCount = 0
    private var definitionResolutionModelCallCount = 0
    private var definitionResolutionFallbackCount = 0
    private var definitionResolutionCacheHitCount = 0
    private var definitionResolutionDuration: TimeInterval = 0
    private var incrementalAnalysisMetrics: AIConnectorIncrementalAnalysisMetrics?

    init(
        runID: UUID = UUID(),
        mode: AIConnectorReviewMode = .deterministic,
        modelVariant: AIConnectorModelVariant = .qwen35Base4B,
        modelRevision: String? = nil,
        generationProfile: String = AIConnectorGenerationProfilePreset.greedy.rawValue,
        thinkingEnabled: Bool = false,
        pipelineVersion: String = "unknown",
        rulePackVersion: String = "unknown",
        corpusVersion: String = "unknown"
    ) {
        let clock = ContinuousClock()
        self.clock = clock
        self.startedAt = clock.now
        self.runID = runID
        self.mode = mode
        self.modelVariant = modelVariant
        self.modelRevision = modelRevision ?? modelVariant.revision
        self.generationProfile = generationProfile
        self.thinkingEnabled = thinkingEnabled
        self.pipelineVersion = pipelineVersion
        self.rulePackVersion = rulePackVersion
        self.corpusVersion = corpusVersion
    }

    func setInputMetadata(utf16Length: Int, segmentCount: Int) {
        totalInputUTF16Length = max(0, utf16Length)
        declaredSegmentCount = max(0, segmentCount)
    }

    func recordStage(
        _ stage: AIConnectorObservationStage,
        duration: TimeInterval,
        segmentID: Int? = nil,
        resource: String? = nil,
        invocationCount: Int = 1
    ) {
        let safeDuration = Self.safeDuration(duration)
        let safeInvocationCount = max(0, invocationCount)
        guard safeInvocationCount > 0 else { return }

        for _ in 0 ..< safeInvocationCount {
            let sample = StageSample(
                stage: stage,
                resource: resource,
                duration: safeDuration / Double(safeInvocationCount)
            )
            stageSamples.append(sample)
            if let segmentID {
                var segment = segments[segmentID] ?? SegmentAccumulator()
                segment.stageSamples.append(sample)
                segments[segmentID] = segment
            }
        }
    }

    func recordRetrieval(
        segmentID: Int,
        queryCount: Int,
        semanticQueryCount: Int
    ) {
        var segment = segments[segmentID] ?? SegmentAccumulator()
        segment.retrievalQueryCount += max(0, queryCount)
        segment.semanticQueryCount += max(0, semanticQueryCount)
        segments[segmentID] = segment
    }

    func recordCandidateCounts(
        segmentID: Int,
        spellingCandidateCount: Int = 0,
        scoredSpellingCandidateCount: Int = 0,
        candidateCount: Int = 0
    ) {
        var segment = segments[segmentID] ?? SegmentAccumulator()
        segment.spellingCandidateCount += max(0, spellingCandidateCount)
        segment.scoredSpellingCandidateCount += max(0, scoredSpellingCandidateCount)
        segment.candidateCount += max(0, candidateCount)
        segments[segmentID] = segment
    }

    /// Records only fields that have an explicit safe representation in the
    /// Phase 0 DTOs. The result is never retained by the collector.
    func recordSegmentResult(
        _ result: AIConnectorSegmentResult,
        duration: TimeInterval
    ) {
        var segment = segments[result.segment.id] ?? SegmentAccumulator()
        segment.utf16Length = result.segment.targetText.utf16.count
        segment.duration = Self.safeDuration(duration)
        segment.suggestionCount = result.reviews.filter {
            $0.status == .suggestion
        }.count
        segment.needsReviewCount = result.reviews.filter {
            $0.status == .needsReview
        }.count
        segment.noSuggestionCount = result.reviews.filter {
            $0.status == .noSuggestion
        }.count
        segment.rejectedCount = result.rejections.count
        segment.cacheHit = result.cacheHit
        // Cached metadata describes the result that was produced earlier,
        // not work performed by this run. Keep result-origin counts below,
        // but only count calls and recovery work when this run executed them.
        segment.modelCallCount = result.cacheHit ? 0 : max(0, result.modelCallCount)
        segment.definitionModelCallCount = result.definitionCacheHit
            ? 0
            : max(0, result.definitionModelCallCount)
        segment.repairCount = result.cacheHit || !result.repairAttempted ? 0 : 1
        segment.challengeCount = result.cacheHit ? 0 : max(0, result.challengeCount)
        segment.fallbackCount = result.cacheHit || !result.usedFallback ? 0 : 1
        segment.modelOriginCount = result.reviews.filter { review in
            review.origin == .qwen || review.origin == .qwenRepaired
        }.count
        segments[result.segment.id] = segment
    }

    func setAccuracy(_ summaries: [AIConnectorAccuracySummary]) {
        accuracy = summaries
    }

    /// Records document-wide Phase 5 diagnostics as counts and independent
    /// wall-clock spans. Finding text, evidence, and model output never cross
    /// this boundary.
    func recordDocumentReview(_ metrics: AIConnectorDocumentReviewMetrics) {
        documentFindingCount += max(0, metrics.findingCount)
        riskCandidateCount += max(0, metrics.riskCandidateCount)
        riskModelCallCount += max(0, metrics.riskModelCallCount)
        riskFallbackCount += max(0, metrics.riskFallbackCount)
        if metrics.cacheHit {
            riskCacheHitCount += 1
        }

        let detectorDuration = Self.safeDuration(metrics.duration)
        documentFindingDuration += detectorDuration
        if detectorDuration > 0 {
            recordStage(
                .documentFindingDetection,
                duration: detectorDuration,
                resource: "phase5"
            )
        }

        let reviewDuration = Self.safeDuration(metrics.riskReviewDuration)
        riskReviewDuration += reviewDuration
        if reviewDuration > 0 {
            recordStage(
                .riskReview,
                duration: reviewDuration,
                resource: "phase5",
                invocationCount: max(1, metrics.riskModelCallCount)
            )
        }
    }

    func recordDefinitionResolution(
        _ metrics: AIConnectorDefinitionResolutionMetrics
    ) {
        definitionResolutionCandidateCount += max(0, metrics.candidateCount)
        definitionResolutionQueryCount += max(0, metrics.retrievalQueryCount)
        definitionResolutionModelCallCount += max(0, metrics.modelCallCount)
        definitionResolutionFallbackCount += max(0, metrics.fallbackCount)
        if metrics.cacheHit {
            definitionResolutionCacheHitCount += 1
        }
        let duration = Self.safeDuration(metrics.duration)
        definitionResolutionDuration += duration
        if duration > 0 {
            recordStage(
                .definitionResolution,
                duration: duration,
                resource: "phase6"
            )
        }
    }

    /// Adds only privacy-safe scheduling counters to the report. No source
    /// fingerprint, anchor, evidence, or cached payload crosses this boundary.
    func setIncrementalAnalysisMetrics(_ metrics: AIConnectorIncrementalAnalysisMetrics) {
        incrementalAnalysisMetrics = metrics
    }

    func snapshot(
        terminalStatus: AIConnectorObservationTerminalStatus? = nil,
        failureCode: String? = nil
    ) -> AIConnectorObservationReport {
        makeReport(
            status: terminalStatus ?? self.terminalStatus,
            failureCode: failureCode ?? self.failureCode,
            endedAt: finishedAt ?? clock.now
        )
    }

    func finish(
        status: AIConnectorObservationTerminalStatus,
        failureCode: String? = nil,
        accuracy: [AIConnectorAccuracySummary] = []
    ) -> AIConnectorObservationReport {
        terminalStatus = status
        self.failureCode = failureCode
        if !accuracy.isEmpty {
            self.accuracy = accuracy
        }
        let endedAt = clock.now
        finishedAt = endedAt
        return makeReport(
            status: status,
            failureCode: failureCode,
            endedAt: endedAt
        )
    }

    private func makeReport(
        status: AIConnectorObservationTerminalStatus,
        failureCode: String?,
        endedAt: ContinuousClock.Instant
    ) -> AIConnectorObservationReport {
        let segmentValues = segments.keys.sorted().map { id in
            let value = segments[id] ?? SegmentAccumulator()
            return AIConnectorSegmentObservation(
                segmentID: id,
                utf16Length: max(0, value.utf16Length),
                duration: Self.safeDuration(value.duration),
                stageMetrics: Self.metrics(from: value.stageSamples),
                retrievalQueryCount: value.retrievalQueryCount,
                semanticQueryCount: value.semanticQueryCount,
                spellingCandidateCount: value.spellingCandidateCount,
                scoredSpellingCandidateCount: value.scoredSpellingCandidateCount,
                candidateCount: value.candidateCount,
                suggestionCount: value.suggestionCount,
                needsReviewCount: value.needsReviewCount,
                noSuggestionCount: value.noSuggestionCount,
                rejectedCount: value.rejectedCount,
                cacheHit: value.cacheHit,
                modelCallCount: value.modelCallCount,
                definitionModelCallCount: value.definitionModelCallCount,
                repairCount: value.repairCount,
                challengeCount: value.challengeCount,
                fallbackCount: value.fallbackCount,
                modelOriginCount: value.modelOriginCount
            )
        }

        let segmentDurations = segmentValues.map(\.duration)
        let counters = segmentValues.reduce(into: SegmentAccumulator()) { partial, value in
            partial.retrievalQueryCount += value.retrievalQueryCount
            partial.semanticQueryCount += value.semanticQueryCount
            partial.spellingCandidateCount += value.spellingCandidateCount
            partial.scoredSpellingCandidateCount += value.scoredSpellingCandidateCount
            partial.candidateCount += value.candidateCount
            partial.suggestionCount += value.suggestionCount
            partial.needsReviewCount += value.needsReviewCount
            partial.noSuggestionCount += value.noSuggestionCount
            partial.rejectedCount += value.rejectedCount
            partial.cacheHit = partial.cacheHit || value.cacheHit
            partial.modelCallCount += value.modelCallCount
            partial.definitionModelCallCount += value.definitionModelCallCount
            partial.repairCount += value.repairCount
            partial.challengeCount += value.challengeCount
            partial.fallbackCount += value.fallbackCount
            partial.modelOriginCount += value.modelOriginCount
        }

        let totalLength = totalInputUTF16Length > 0
            ? totalInputUTF16Length
            : segmentValues.reduce(0) { $0 + $1.utf16Length }
        let totalSegments = max(declaredSegmentCount, segmentValues.count)
        let totalDuration = Self.safeDuration(
            Self.seconds(startedAt.duration(to: endedAt))
        )

        return AIConnectorObservationReport(
            schemaVersion: AIConnectorObservationReport.schemaVersion,
            runID: runID,
            generatedAt: Date(),
            mode: mode,
            modelVariant: modelVariant,
            modelRevision: modelRevision,
            generationProfile: generationProfile,
            thinkingEnabled: thinkingEnabled,
            pipelineVersion: pipelineVersion,
            rulePackVersion: rulePackVersion,
            corpusVersion: corpusVersion,
            terminalStatus: status,
            failureCode: failureCode,
            totalDuration: totalDuration,
            totalInputUTF16Length: totalLength,
            totalSegmentCount: totalSegments,
            observedSegmentCount: segmentValues.count,
            segmentLatencyP50: Self.percentile(segmentDurations, 0.50),
            segmentLatencyP95: Self.percentile(segmentDurations, 0.95),
            stageMetrics: Self.metrics(from: stageSamples),
            segments: segmentValues,
            retrievalQueryCount: counters.retrievalQueryCount,
            semanticQueryCount: counters.semanticQueryCount,
            spellingCandidateCount: counters.spellingCandidateCount,
            scoredSpellingCandidateCount: counters.scoredSpellingCandidateCount,
            candidateCount: counters.candidateCount,
            suggestionCount: counters.suggestionCount,
            needsReviewCount: counters.needsReviewCount,
            noSuggestionCount: counters.noSuggestionCount,
            rejectedCount: counters.rejectedCount,
            cacheHitCount: segmentValues.filter(\.cacheHit).count,
            modelCallCount: counters.modelCallCount,
            definitionModelCallCount: counters.definitionModelCallCount,
            repairCount: counters.repairCount,
            challengeCount: counters.challengeCount,
            fallbackCount: counters.fallbackCount,
            modelOriginResultCount: counters.modelOriginCount,
            documentFindingCount: documentFindingCount,
            riskCandidateCount: riskCandidateCount,
            riskModelCallCount: riskModelCallCount,
            riskFallbackCount: riskFallbackCount,
            riskCacheHitCount: riskCacheHitCount,
            documentFindingDuration: Self.safeDuration(documentFindingDuration),
            riskReviewDuration: Self.safeDuration(riskReviewDuration),
            definitionResolutionCandidateCount: definitionResolutionCandidateCount,
            definitionResolutionQueryCount: definitionResolutionQueryCount,
            definitionResolutionModelCallCount: definitionResolutionModelCallCount,
            definitionResolutionFallbackCount: definitionResolutionFallbackCount,
            definitionResolutionCacheHitCount: definitionResolutionCacheHitCount,
            definitionResolutionDuration: Self.safeDuration(definitionResolutionDuration),
            accuracy: accuracy,
            incrementalAnalysis: incrementalAnalysisMetrics
        )
    }

    private static func metrics(from samples: [StageSample]) -> [AIConnectorStageMetric] {
        let grouped = Dictionary(grouping: samples) { sample in
            StageKey(stage: sample.stage, resource: sample.resource)
        }
        return grouped.keys.sorted { lhs, rhs in
            if lhs.stage.rawValue != rhs.stage.rawValue {
                return lhs.stage.rawValue < rhs.stage.rawValue
            }
            return (lhs.resource ?? "") < (rhs.resource ?? "")
        }.map { key in
            let durations = grouped[key, default: []].map(\.duration)
            return AIConnectorStageMetric(
                stage: key.stage,
                resource: key.resource,
                invocationCount: durations.count,
                totalDuration: durations.reduce(0, +),
                medianDuration: percentile(durations, 0.50),
                p95Duration: percentile(durations, 0.95)
            )
        }
    }

    private struct StageKey: Hashable {
        let stage: AIConnectorObservationStage
        let resource: String?
    }

    private static func percentile(_ values: [TimeInterval], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return safeDuration(sorted[0]) }
        let clampedPercentile = min(max(percentile, 0), 1)
        let position = Double(sorted.count - 1) * clampedPercentile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, sorted.count - 1)
        let fraction = position - Double(lowerIndex)
        let value = sorted[lowerIndex]
            + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
        return safeDuration(value)
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        AIConnectorObservationTiming.seconds(duration)
    }

    private static func safeDuration(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}
