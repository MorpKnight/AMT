import Foundation

/// Runs the bounded Debug fixture set with the same parser, validator, and
/// fallback boundary used by the document review flow.
@MainActor
final class AIConnectorBenchmarkRunner {
    private let service: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore
    private let segmenter = LegalTextSegmenter()
    private let outputParser = AIConnectorOutputParser()
    private let suggestionValidator = AIConnectorSuggestionValidator()
    private let deterministicSuggestionEngine = AIConnectorDeterministicSuggestionEngine()
    private let fixtureEvaluator = AIConnectorFixtureEvaluator()

    var onDownloadProgress: (@MainActor @Sendable (Double) -> Void)?
    var onGenerationProgress: (@MainActor @Sendable (Int) -> Void)?

    init(
        service: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore
    ) {
        self.service = service
        self.dictionaryStore = dictionaryStore
    }

    func run(
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        samples: [AIConnectorSample] = [],
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> AIConnectorBenchmarkReport {
        let startedAt = Date()
        let samples = samples.isEmpty ? AIConnectorSample.samples : samples
        var records: [AIConnectorBenchmarkRecord] = []
        var evaluations: [AIConnectorFixtureEvaluation] = []

        for (index, sample) in samples.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, samples.count)

            let segmentation = segmenter.segment(documentText: sample.text)
            guard let segment = segmentation.segments.first else {
                records.append(
                    makeRecord(
                        sample: sample,
                        segment: nil,
                        matches: [],
                        mode: mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        expectedSignalPassed: false,
                        skipped: true
                    )
                )
                evaluations.append(fixtureEvaluator.evaluate(sample: sample, reviews: []))
                continue
            }

            let matches = dictionaryStore.suggestionCandidates(
                for: segment.targetText,
                limit: 1
            )

            if mode == .deterministic {
                let review = try deterministicReview(
                    for: segment,
                    matches: matches,
                    origin: .deterministic
                )
                let reviews = review.map { [$0] } ?? []
                evaluations.append(fixtureEvaluator.evaluate(sample: sample, reviews: reviews))
                records.append(
                    makeRecord(
                        sample: sample,
                        segment: segment,
                        matches: matches,
                        mode: mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        review: review,
                        expectedSignalPassed: evaluations.last?.passed ?? false
                    )
                )
                continue
            }

            do {
                let result = try await service.review(
                    segment: segment,
                    thinkingEnabled: thinkingEnabled,
                    glossaryMatches: matches,
                    downloadProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.onDownloadProgress?(progress)
                        }
                    },
                    generationProgress: { [weak self] characters in
                        self?.onGenerationProgress?(characters)
                    },
                    modelVariant: modelVariant
                )
                try Task.checkCancellation()

                if result.metrics.stopReason == .cancelled {
                    throw CancellationError()
                }

                let attempt = attempt(
                    result: result,
                    segment: segment,
                    matches: matches
                )
                let finalReview = try fallbackIfNeeded(
                    attempt: attempt,
                    segment: segment,
                    matches: matches,
                    mode: mode
                )
                let reviews = finalReview.map { [$0] } ?? []
                evaluations.append(fixtureEvaluator.evaluate(sample: sample, reviews: reviews))
                records.append(
                    makeRecord(
                        sample: sample,
                        segment: segment,
                        matches: matches,
                        mode: mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        result: result,
                        attempt: attempt,
                        review: finalReview,
                        wasFallback: finalReview?.origin == .deterministicFallback,
                        expectedSignalPassed: evaluations.last?.passed ?? false
                    )
                )
            } catch let error as QwenSuggestionError {
                if case .segmentTooLong = error {
                    evaluations.append(fixtureEvaluator.evaluate(sample: sample, reviews: []))
                    records.append(
                        makeRecord(
                            sample: sample,
                            segment: segment,
                            matches: matches,
                            mode: mode,
                            modelVariant: modelVariant,
                            thinkingEnabled: thinkingEnabled,
                            expectedSignalPassed: false,
                            rejectionReason: error.localizedDescription,
                            skipped: true
                        )
                    )
                    continue
                }
                throw error
            }
        }

        return AIConnectorBenchmarkReport(
            generatedAt: Date(),
            title: "Benchmark \(mode.title) • \(modelVariant.title)",
            reviewMode: mode,
            modelVariant: modelVariant,
            thinkingEnabled: thinkingEnabled,
            duration: Date().timeIntervalSince(startedAt),
            records: records,
            evaluations: evaluations,
            qualityGate: AIConnectorQualityGate(records: records, mode: mode)
        )
    }

    private func deterministicReview(
        for segment: AIReviewSegment,
        matches: [LegalDictionaryMatch],
        origin: AIReviewOrigin
    ) throws -> AIValidatedReview? {
        let parsed = deterministicSuggestionEngine.review(
            for: segment,
            glossaryMatches: matches
        )
        return try suggestionValidator.validate(
            parsed,
            for: segment,
            glossaryMatches: matches,
            origin: origin
        )
    }

    private func attempt(
        result: QwenReviewResult,
        segment: AIReviewSegment,
        matches: [LegalDictionaryMatch]
    ) -> ModelAttempt {
        let diagnosticOutput = AIConnectorGenerationDiagnostics.sanitizedDiagnosticOutput(
            result.output
        )
        let repeatedSixGramRatio = AIConnectorGenerationDiagnostics.repeatedSixGramRatio(
            in: result.output
        )

        if result.metrics.stopReason == .length {
            return ModelAttempt(
                result: result,
                diagnosticOutput: diagnosticOutput,
                repeatedSixGramRatio: repeatedSixGramRatio,
                rejectionReason: "Model mencapai batas token dan output tidak diproses.",
                reasoningMarkerDetected: result.containsReasoningMarkers,
                sourceClaimDetected: false
            )
        }

        if result.containsReasoningMarkers {
            return ModelAttempt(
                result: result,
                diagnosticOutput: diagnosticOutput,
                repeatedSixGramRatio: repeatedSixGramRatio,
                rejectionReason: "Output mengandung reasoning atau token template; diagnostic di-redact.",
                reasoningMarkerDetected: true,
                sourceClaimDetected: false
            )
        }

        do {
            let parsed = try outputParser.parse(result.output)
            do {
                let validated = try suggestionValidator.validate(
                    parsed,
                    for: segment,
                    glossaryMatches: matches
                )
                return ModelAttempt(
                    result: result,
                    diagnosticOutput: diagnosticOutput,
                    parsed: parsed,
                    validated: validated,
                    repeatedSixGramRatio: repeatedSixGramRatio,
                    reasoningMarkerDetected: false,
                    sourceClaimDetected: false
                )
            } catch let error as AIConnectorValidationError {
                return ModelAttempt(
                    result: result,
                    diagnosticOutput: diagnosticOutput,
                    parsed: parsed,
                    repeatedSixGramRatio: repeatedSixGramRatio,
                    rejectionReason: error.message,
                    reasoningMarkerDetected: false,
                    sourceClaimDetected: error == .unsupportedSourceClaim
                )
            }
        } catch let error as AIConnectorOutputParserError {
            return ModelAttempt(
                result: result,
                diagnosticOutput: diagnosticOutput,
                repeatedSixGramRatio: repeatedSixGramRatio,
                rejectionReason: error.message,
                reasoningMarkerDetected: false,
                sourceClaimDetected: false
            )
        } catch {
            return ModelAttempt(
                result: result,
                diagnosticOutput: diagnosticOutput,
                repeatedSixGramRatio: repeatedSixGramRatio,
                rejectionReason: error.localizedDescription,
                reasoningMarkerDetected: false,
                sourceClaimDetected: false
            )
        }
    }

    private func fallbackIfNeeded(
        attempt: ModelAttempt,
        segment: AIReviewSegment,
        matches: [LegalDictionaryMatch],
        mode: AIConnectorReviewMode
    ) throws -> AIValidatedReview? {
        if let validated = attempt.validated {
            return validated
        }
        guard mode == .hybrid else { return nil }

        return try deterministicReview(
            for: segment,
            matches: matches,
            origin: .deterministicFallback
        )
    }

    private func makeRecord(
        sample: AIConnectorSample,
        segment: AIReviewSegment?,
        matches: [LegalDictionaryMatch],
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        result: QwenReviewResult? = nil,
        attempt: ModelAttempt? = nil,
        review: AIValidatedReview? = nil,
        wasFallback: Bool = false,
        expectedSignalPassed: Bool,
        rejectionReason: String? = nil,
        skipped: Bool = false
    ) -> AIConnectorBenchmarkRecord {
        AIConnectorBenchmarkRecord(
            sampleID: sample.id,
            sampleTitle: sample.title,
            expectedSignal: sample.expectedSignal,
            mode: mode.rawValue,
            modelVariant: modelVariant.rawValue,
            thinkingEnabled: thinkingEnabled,
            segmentID: segment?.id,
            sourceLocation: segment?.sourceLocation,
            targetText: segment?.targetText,
            candidateGlossaryID: matches.isEmpty ? nil : "G1",
            candidateGlossaryTerm: matches.first?.entry.term,
            diagnosticOutput: result.map {
                AIConnectorGenerationDiagnostics.sanitizedDiagnosticOutput($0.output)
            },
            parsedStatus: attempt?.parsed?.status.rawValue,
            validatedStatus: review?.status.rawValue,
            validatedCategory: review?.category.rawValue,
            validatedOriginal: review?.original,
            validatedReplacement: review?.replacement,
            validatedReason: review?.reason,
            origin: review?.origin.rawValue,
            rejectionReason: rejectionReason ?? attempt?.rejectionReason,
            promptTokenCount: result?.metrics.promptTokenCount,
            generationTokenCount: result?.metrics.generationTokenCount,
            promptDuration: result?.metrics.promptDuration,
            generationDuration: result?.metrics.generationDuration,
            stopReason: result?.metrics.stopReason,
            repeatedSixGramRatio: attempt?.repeatedSixGramRatio,
            expectedSignalPassed: expectedSignalPassed,
            wasFallback: wasFallback,
            outputWasRejected: attempt?.rejectionReason != nil || rejectionReason != nil,
            outputWasTruncated: result?.metrics.stopReason == .length,
            reasoningMarkerDetected: attempt?.reasoningMarkerDetected ?? false,
            sourceClaimDetected: attempt?.sourceClaimDetected ?? false,
            skipped: skipped
        )
    }

    private struct ModelAttempt {
        let result: QwenReviewResult
        let diagnosticOutput: String
        let parsed: AIParsedReview?
        let validated: AIValidatedReview?
        let repeatedSixGramRatio: Double
        let rejectionReason: String?
        let reasoningMarkerDetected: Bool
        let sourceClaimDetected: Bool

        init(
            result: QwenReviewResult,
            diagnosticOutput: String,
            parsed: AIParsedReview? = nil,
            validated: AIValidatedReview? = nil,
            repeatedSixGramRatio: Double,
            rejectionReason: String? = nil,
            reasoningMarkerDetected: Bool,
            sourceClaimDetected: Bool
        ) {
            self.result = result
            self.diagnosticOutput = diagnosticOutput
            self.parsed = parsed
            self.validated = validated
            self.repeatedSixGramRatio = repeatedSixGramRatio
            self.rejectionReason = rejectionReason
            self.reasoningMarkerDetected = reasoningMarkerDetected
            self.sourceClaimDetected = sourceClaimDetected
        }
    }
}
