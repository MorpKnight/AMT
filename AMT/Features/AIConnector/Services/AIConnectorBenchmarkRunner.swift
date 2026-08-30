import Foundation

/// Runs the Debug fixture set through the same segment processor used by the
/// document-wide work queue. This keeps benchmark and product decisions on a
/// single parser, validator, fallback, and cache boundary.
@MainActor
final class AIConnectorBenchmarkRunner {
    private let segmenter = LegalTextSegmenter()
    private let fixtureEvaluator = AIConnectorFixtureEvaluator()
    private let processor: AIConnectorSegmentProcessor
    private let workQueue: AIConnectorWorkQueue

    var onDownloadProgress: (@MainActor @Sendable (Double) -> Void)?
    var onGenerationProgress: (@MainActor @Sendable (Int) -> Void)?

    init(
        service: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore,
        ruleStore: AIConnectorRuleStore? = nil,
        modelReviewHandler: AIConnectorModelReviewHandler? = nil,
        candidateDecisionHandler: AIConnectorCandidateDecisionHandler? = nil
    ) {
        let cache = AIConnectorSegmentCache()
        let processor = AIConnectorSegmentProcessor(
            service: service,
            dictionaryStore: dictionaryStore,
            ruleStore: ruleStore ?? AIConnectorRuleStore(),
            segmentCache: cache,
            modelReviewHandler: modelReviewHandler,
            candidateDecisionHandler: candidateDecisionHandler
        )
        self.processor = processor
        self.workQueue = AIConnectorWorkQueue(processor: processor)
    }

    func run(
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        samples: [AIConnectorSample] = [],
        resetCache: Bool = true,
        generationProfilePreset: AIConnectorGenerationProfilePreset = .greedy,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> AIConnectorBenchmarkReport {
        let startedAt = Date()
        let samples = samples.isEmpty ? AIConnectorSample.samples : samples
        if resetCache {
            await processor.clearCache()
        }

        var queueSegments: [AIReviewSegment] = []
        var sampleBySegmentID: [Int: AIConnectorSample] = [:]
        var skippedSamples: [AIConnectorSample] = []
        var sourceLocation = 0

        for sample in samples {
            let segmentation = segmenter.segment(documentText: sample.text)
            guard let segment = segmentation.segments.first else {
                skippedSamples.append(sample)
                continue
            }

            let segmentID = queueSegments.count + 1
            let queueSegment = AIReviewSegment(
                id: segmentID,
                sourceLocation: sourceLocation,
                sourceLength: segment.sourceLength,
                targetText: segment.targetText,
                previousContext: segment.previousContext,
                nextContext: segment.nextContext,
                isTooLong: segment.isTooLong
            )
            queueSegments.append(queueSegment)
            sampleBySegmentID[segmentID] = sample
            sourceLocation += sample.text.utf16.count + 2
        }

        let runID = UUID()
        let protectionContext = processor.protectionContext(
            for: samples.map(\.text).joined(separator: "\n\n")
        )
        let generationProfile = generationProfilePreset.profile(
            for: modelVariant,
            thinkingEnabled: thinkingEnabled
        )
        let stream = await workQueue.start(
            runID: runID,
            segments: queueSegments,
            mode: mode,
            modelVariant: modelVariant,
            thinkingEnabled: thinkingEnabled,
            documentProtectionContext: protectionContext,
            downloadProgress: { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.onDownloadProgress?(value)
                }
            },
            generationProgress: { [weak self] characters in
                self?.onGenerationProgress?(characters)
            },
            generationProfile: generationProfile
        )

        var resultBySegmentID: [Int: AIConnectorSegmentResult] = [:]
        var circuitBreakerActivated = false
        var runSummary: AIConnectorRunSummary?

        do {
            try await withTaskCancellationHandler {
                for await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case let .result(result):
                        resultBySegmentID[result.segment.id] = result
                        progress(resultBySegmentID.count, samples.count)
                        await workQueue.acknowledgeResult()
                    case .circuitBreakerActivated:
                        circuitBreakerActivated = true
                    case let .finished(summary):
                        runSummary = summary
                    case let .failed(message):
                        throw AIConnectorBenchmarkRunnerError.queueFailed(message)
                    case .stateChanged, .progress:
                        break
                    }
                }
                try Task.checkCancellation()
            } onCancel: { [workQueue] in
                workQueue.requestCancellation()
            }
        } catch {
            await workQueue.cancel()
            throw error
        }

        guard let runSummary else {
            throw AIConnectorBenchmarkRunnerError.missingSummary
        }
        circuitBreakerActivated = circuitBreakerActivated
            || runSummary.circuitBreakerActivated

        var records: [AIConnectorBenchmarkRecord] = []
        var candidateRecords: [AIConnectorBenchmarkCandidateRecord] = []
        var evaluations: [AIConnectorFixtureEvaluation] = []
        for sample in samples {
            let result = sampleBySegmentID.first(where: { $0.value.id == sample.id })
                .flatMap { resultBySegmentID[$0.key] }
            let evaluation = fixtureEvaluator.evaluate(
                sample: sample,
                reviews: result?.reviews ?? []
            )
            evaluations.append(evaluation)
            candidateRecords.append(contentsOf: makeCandidateRecords(
                sample: sample,
                result: result
            ))
            records.append(
                makeRecord(
                    sample: sample,
                    result: result,
                    mode: mode,
                    modelVariant: modelVariant,
                    thinkingEnabled: thinkingEnabled,
                    generationProfile: generationProfilePreset,
                    expectedSignalPassed: evaluation.passed,
                    skipped: skippedSamples.contains(where: { $0.id == sample.id })
                )
            )
        }

        return AIConnectorBenchmarkReport(
            generatedAt: Date(),
            title: "Benchmark \(mode.title) • \(modelVariant.title)",
            reviewMode: mode,
            modelVariant: modelVariant,
            thinkingEnabled: thinkingEnabled,
            duration: Date().timeIntervalSince(startedAt),
            circuitBreakerActivated: circuitBreakerActivated,
            records: records,
            evaluations: evaluations,
            qualityGate: AIConnectorQualityGate(records: records, mode: mode),
            generationProfile: generationProfilePreset.rawValue,
            candidateRecords: candidateRecords
        )
    }

    private func makeRecord(
        sample: AIConnectorSample,
        result: AIConnectorSegmentResult?,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        generationProfile: AIConnectorGenerationProfilePreset,
        expectedSignalPassed: Bool,
        skipped: Bool = false
    ) -> AIConnectorBenchmarkRecord {
        let candidate = result?.candidates.first
        let candidateDecision = candidate.flatMap { candidate in
            result?.candidateDecisions.first(where: { $0.candidateID == candidate.id })
        }
        let review = result?.reviews.first(where: { $0.status == .suggestion })
            ?? result?.reviews.first
        let rejection = result?.rejections.first

        return AIConnectorBenchmarkRecord(
            sampleID: sample.id,
            sampleTitle: sample.title,
            expectedSignal: sample.expectedSignal,
            mode: mode.rawValue,
            modelVariant: modelVariant.rawValue,
            thinkingEnabled: thinkingEnabled,
            segmentID: result?.segment.id,
            sourceLocation: result?.segment.sourceLocation,
            targetText: result?.segment.targetText,
            candidateGlossaryID: candidate?.glossaryMatch != nil ? "G1" : nil,
            candidateGlossaryTerm: candidate?.glossaryMatch?.entry.term,
            diagnosticOutput: rejection?.rawOutput.isEmpty == false
                ? rejection?.rawOutput
                : nil,
            parsedStatus: result?.parsedStatus?.rawValue,
            validatedStatus: review?.status.rawValue,
            validatedCategory: review?.category.rawValue,
            validatedOriginal: review?.original,
            validatedReplacement: review?.replacement,
            validatedReason: review?.reason,
            origin: review?.origin.rawValue,
            rejectionReason: rejection?.reason,
            promptTokenCount: result?.generationMetrics?.promptTokenCount,
            generationTokenCount: result?.generationMetrics?.generationTokenCount,
            promptDuration: result?.generationMetrics?.promptDuration,
            generationDuration: result?.generationMetrics?.generationDuration,
            stopReason: result?.generationMetrics?.stopReason,
            repeatedSixGramRatio: result?.repeatedSixGramRatio,
            expectedSignalPassed: expectedSignalPassed,
            wasFallback: result?.usedFallback ?? false,
            outputWasRejected: !(result?.rejections.isEmpty ?? true),
            outputWasTruncated: result?.outputWasTruncated ?? false,
            reasoningMarkerDetected: result?.reasoningMarkerDetected ?? false,
            sourceClaimDetected: result?.sourceClaimDetected ?? false,
            skipped: result?.skipped ?? skipped,
            cacheHit: result?.cacheHit ?? false,
            modelAttempts: result?.modelAttempts ?? 0,
            repairAttempted: result?.repairAttempted ?? false,
            firstPassSucceeded: result?.firstPassSucceeded ?? false,
            rejectionClass: rejection?.classification,
            generationProfile: generationProfile.rawValue,
            candidateID: candidate?.id,
            candidateDecision: candidateDecision?.decision,
            candidateSource: candidate?.confidenceTier,
            modelCallCount: result?.modelCallCount ?? 0,
            challengeAttempted: (result?.challengeCount ?? 0) > 0
        )
    }

    private func makeCandidateRecords(
        sample: AIConnectorSample,
        result: AIConnectorSegmentResult?
    ) -> [AIConnectorBenchmarkCandidateRecord] {
        guard let result else { return [] }

        return result.candidates.map { candidate in
            let decision = result.candidateDecisions.first {
                $0.candidateID == candidate.id
            }
            let metrics = decision?.generationMetrics
            return AIConnectorBenchmarkCandidateRecord(
                sampleID: sample.id,
                sampleTitle: sample.title,
                expectedSignal: sample.expectedSignal,
                segmentID: result.segment.id,
                candidateID: candidate.id,
                source: candidate.confidenceTier,
                category: candidate.category,
                ruleID: candidate.ruleID,
                original: candidate.original,
                replacement: candidate.replacement,
                decision: decision?.decision,
                finalOrigin: decision?.finalOrigin,
                attemptCount: decision?.attemptCount ?? 0,
                repairAttempted: decision?.repairAttempted ?? false,
                challengeAttempted: decision?.challengeAttempted ?? false,
                usedFallback: decision?.usedFallback ?? false,
                rejectionClass: decision?.rejectionClass,
                promptTokenCount: metrics?.promptTokenCount,
                generationTokenCount: metrics?.generationTokenCount,
                promptDuration: metrics?.promptDuration,
                generationDuration: metrics?.generationDuration,
                stopReason: metrics?.stopReason,
                repeatedSixGramRatio: decision?.repeatedSixGramRatio
            )
        }
    }
}

private enum AIConnectorBenchmarkRunnerError: LocalizedError {
    case queueFailed(String)
    case missingSummary

    var errorDescription: String? {
        switch self {
        case let .queueFailed(message):
            "Work queue benchmark gagal: \(message)"
        case .missingSummary:
            "Work queue benchmark selesai tanpa ringkasan run."
        }
    }
}
