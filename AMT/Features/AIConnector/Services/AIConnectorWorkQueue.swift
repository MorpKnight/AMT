import Foundation

struct AIConnectorModelReviewRequest: Sendable {
    let segment: AIReviewSegment
    let thinkingEnabled: Bool
    let modelVariant: AIConnectorModelVariant
    let glossaryMatches: [LegalDictionaryMatch]
    let downloadProgress: @Sendable (Double) -> Void
    let generationProgress: @MainActor @Sendable (Int) -> Void
    let repairInstruction: String?
}

typealias AIConnectorModelReviewHandler = @MainActor @Sendable (
    AIConnectorModelReviewRequest
) async throws -> QwenReviewResult

typealias AIConnectorCandidateDecisionHandler = @MainActor @Sendable (
    AIConnectorCandidateReviewRequest,
    @escaping @Sendable (Double) -> Void,
    @escaping @MainActor @Sendable (Int) -> Void
) async throws -> QwenCandidateDecisionResult

/// A small lock-protected signal lets the UI publish cancellation immediately,
/// while the queue actor still owns cancellation of its active task.
final class AIConnectorCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancelled = false

    nonisolated init() {}

    nonisolated var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    nonisolated func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Runs one segment through retrieval, model parsing, validation, and the
/// deterministic fallback boundary. The class is main-actor isolated because
/// the MLX service and its progress callbacks are UI-owned.
@MainActor
final class AIConnectorSegmentProcessor {
    private let service: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore
    private let ruleStore: AIConnectorRuleStore
    private let segmentCache: AIConnectorSegmentCache
    private let parser = AIConnectorOutputParser()
    private let canonicalizer = AIConnectorOutputCanonicalizer()
    private let validator = AIConnectorSuggestionValidator()
    private let deterministicEngine: AIConnectorDeterministicSuggestionEngine
    private let candidateBuilder: AIConnectorCandidateBuilder
    private let conflictResolver = AIConnectorSuggestionConflictResolver()
    private let protectionContextBuilder = AIConnectorDocumentProtectionContextBuilder()

    private let modelReviewHandler: AIConnectorModelReviewHandler
    private let candidateDecisionHandler: AIConnectorCandidateDecisionHandler
    private let usesLegacyModelReviewHandler: Bool

    init(
        service: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore,
        ruleStore: AIConnectorRuleStore,
        segmentCache: AIConnectorSegmentCache = AIConnectorSegmentCache(),
        modelReviewHandler: AIConnectorModelReviewHandler? = nil,
        candidateDecisionHandler: AIConnectorCandidateDecisionHandler? = nil
    ) {
        self.service = service
        self.dictionaryStore = dictionaryStore
        self.ruleStore = ruleStore
        self.segmentCache = segmentCache
        self.deterministicEngine = AIConnectorDeterministicSuggestionEngine(
            ruleStore: ruleStore
        )
        self.candidateBuilder = AIConnectorCandidateBuilder(ruleStore: ruleStore)
        self.usesLegacyModelReviewHandler = modelReviewHandler != nil
        let defaultHandler: AIConnectorModelReviewHandler = { @MainActor [service] request in
            try await service.review(
                segment: request.segment,
                thinkingEnabled: request.thinkingEnabled,
                glossaryMatches: request.glossaryMatches,
                downloadProgress: request.downloadProgress,
                generationProgress: request.generationProgress,
                modelVariant: request.modelVariant,
                repairInstruction: request.repairInstruction
            )
        }
        self.modelReviewHandler = modelReviewHandler ?? defaultHandler
        let defaultCandidateHandler: AIConnectorCandidateDecisionHandler = {
            @MainActor [service] request, downloadProgress, generationProgress in
            try await service.reviewCandidate(
                request: request,
                downloadProgress: downloadProgress,
                generationProgress: generationProgress
            )
        }
        self.candidateDecisionHandler = candidateDecisionHandler ?? defaultCandidateHandler
    }

    func protectionContext(for documentText: String) -> AIConnectorDocumentProtectionContext {
        protectionContextBuilder.build(documentText: documentText)
    }

    func clearCache() async {
        await segmentCache.removeAll()
    }

    func process(
        segment: AIReviewSegment,
        documentProtectionContext: AIConnectorDocumentProtectionContext,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        forceDeterministic: Bool,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void,
        generationProfile: AIConnectorGenerationProfile? = nil
    ) async throws -> AIConnectorSegmentResult {
        if usesLegacyModelReviewHandler {
            return try await processLegacy(
                segment: segment,
                documentProtectionContext: documentProtectionContext,
                mode: mode,
                modelVariant: modelVariant,
                thinkingEnabled: thinkingEnabled,
                forceDeterministic: forceDeterministic,
                downloadProgress: downloadProgress,
                generationProgress: generationProgress
            )
        }

        return try await processCandidateFirst(
            segment: segment,
            documentProtectionContext: documentProtectionContext,
            mode: mode,
            modelVariant: modelVariant,
            thinkingEnabled: thinkingEnabled,
            forceDeterministic: forceDeterministic,
            downloadProgress: downloadProgress,
            generationProgress: generationProgress,
            generationProfile: generationProfile
        )
    }

    private func processLegacy(
        segment: AIReviewSegment,
        documentProtectionContext: AIConnectorDocumentProtectionContext,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        forceDeterministic: Bool,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void
    ) async throws -> AIConnectorSegmentResult {
        let glossaryMatches = dictionaryStore.suggestionCandidates(
            for: segment.targetText,
            limit: 1
        )

        if segment.isTooLong {
            return AIConnectorSegmentResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                rejections: [
                    AIReviewRejection(
                        segment: segment,
                        rawOutput: "",
                        reason: "Segmen melebihi batas 512 token; dilewati tanpa dipotong.",
                        classification: .segmentTooLong
                    )
                ],
                skipped: true
            )
        }

        guard mode.usesModel, !forceDeterministic else {
            return deterministicResult(
                for: segment,
                glossaryMatches: glossaryMatches,
                origin: forceDeterministic ? .deterministicFallback : .deterministic,
                protectionContext: documentProtectionContext,
                usedFallback: forceDeterministic && mode != .deterministic
            )
        }

        let cacheKey = AIConnectorSegmentCache.key(
            from: AIConnectorCacheKeyComponents(
                segment: segment,
                reviewMode: mode,
                modelVariant: modelVariant,
                generationProfile: modelVariant.generationProfile(
                    thinkingEnabled: thinkingEnabled
                ),
                promptVersion: QwenSuggestionService.promptVersion,
                rulePackVersion: ruleStore.version,
                corpusVersion: AIConnectorLocalToolDispatcher.corpusVersion,
                validatorVersion: AIConnectorSuggestionValidator.version,
                outputSchemaVersion: QwenSuggestionService.outputSchemaVersion,
                protectionContext: documentProtectionContext
            )
        )

        if let cached = await segmentCache.value(for: cacheKey) {
            let rejections = cached.rejectionReasons.enumerated().map { index, reason in
                return AIReviewRejection(
                    segment: segment,
                    rawOutput: "",
                    reason: reason,
                    classification: index < cached.rejectionClasses.count
                        ? cached.rejectionClasses[index]
                        : .unknown
                )
            }
            return AIConnectorSegmentResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                reviews: cached.reviews.map { $0.materialize(for: segment) },
                parsedStatus: cached.parsedStatus,
                parsedCategory: cached.parsedCategory,
                rejections: rejections,
                cacheHit: true,
                modelAttempts: cached.modelAttempts,
                repairAttempted: cached.repairAttempted,
                usedFallback: cached.usedFallback,
                firstPassSucceeded: cached.firstPassSucceeded
            )
        }

        var attempts = 0
        var repairAttempted = false
        var rejections: [AIReviewRejection] = []
        do {
            attempts += 1
            let firstResult = try await modelReviewHandler(
                AIConnectorModelReviewRequest(
                    segment: segment,
                    thinkingEnabled: thinkingEnabled,
                    modelVariant: modelVariant,
                    glossaryMatches: glossaryMatches,
                    downloadProgress: downloadProgress,
                    generationProgress: generationProgress,
                    repairInstruction: nil
                )
            )
            try Task.checkCancellation()
            do {
                let evaluated = try evaluate(
                    firstResult,
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    origin: .qwen,
                    protectionContext: documentProtectionContext
                )
                return await cacheAndReturn(
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    reviews: successfulReviews(
                        modelReview: evaluated.validated,
                        mode: mode,
                        segment: segment,
                        glossaryMatches: glossaryMatches,
                        protectionContext: documentProtectionContext
                    ),
                    parsedStatus: evaluated.parsed.status,
                    parsedCategory: evaluated.parsed.category,
                    rejections: rejections,
                    cacheKey: cacheKey,
                    modelAttempts: attempts,
                    repairAttempted: false,
                    usedFallback: false,
                    firstPassSucceeded: true,
                    generationMetrics: evaluated.result.metrics,
                    repeatedSixGramRatio: evaluated.repetitionRatio
                )
            } catch let failure as ModelAttemptFailure {
                guard failure.isRepairable else { throw failure }
                repairAttempted = true
                attempts += 1
                let repairInstruction = Self.repairInstruction(
                    failure: failure
                )
                let repairedResult = try await modelReviewHandler(
                    AIConnectorModelReviewRequest(
                        segment: segment,
                        thinkingEnabled: thinkingEnabled,
                        modelVariant: modelVariant,
                        glossaryMatches: glossaryMatches,
                        downloadProgress: downloadProgress,
                        generationProgress: generationProgress,
                        repairInstruction: repairInstruction
                    )
                )
                try Task.checkCancellation()
                let evaluated = try evaluate(
                    repairedResult,
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    origin: .qwenRepaired,
                    protectionContext: documentProtectionContext
                )
                return await cacheAndReturn(
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    reviews: successfulReviews(
                        modelReview: evaluated.validated,
                        mode: mode,
                        segment: segment,
                        glossaryMatches: glossaryMatches,
                        protectionContext: documentProtectionContext
                    ),
                    parsedStatus: evaluated.parsed.status,
                    parsedCategory: evaluated.parsed.category,
                    rejections: rejections,
                    cacheKey: cacheKey,
                    modelAttempts: attempts,
                    repairAttempted: repairAttempted,
                    usedFallback: false,
                    firstPassSucceeded: false,
                    generationMetrics: evaluated.result.metrics,
                    repeatedSixGramRatio: evaluated.repetitionRatio
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let qwenError as QwenSuggestionError {
            if case .incompleteThinking = qwenError {
                throw qwenError
            }
            if case .segmentTooLong = qwenError {
                return AIConnectorSegmentResult(
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    rejections: [
                        AIReviewRejection(
                            segment: segment,
                            rawOutput: "",
                            reason: qwenError.localizedDescription,
                            classification: .segmentTooLong
                        )
                    ],
                    skipped: true
                )
            }
            rejections.append(
                AIReviewRejection(
                    segment: segment,
                    rawOutput: "",
                    reason: qwenError.localizedDescription,
                    classification: .modelFailure
                )
            )
            guard mode == .hybrid else {
                return await cacheAndReturn(
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    reviews: [],
                    rejections: rejections,
                    cacheKey: cacheKey,
                    modelAttempts: attempts,
                    repairAttempted: repairAttempted,
                    usedFallback: false,
                    firstPassSucceeded: false
                )
            }
            return await fallbackResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                rejections: rejections,
                cacheKey: cacheKey,
                modelAttempts: attempts,
                repairAttempted: repairAttempted,
                protectionContext: documentProtectionContext
            )
        } catch let failure as ModelAttemptFailure {
            let reason = failure.message
            rejections.append(
                AIReviewRejection(
                    segment: segment,
                    rawOutput: failure.diagnosticOutput,
                    reason: reason,
                    classification: failure.classification
                )
            )

            guard mode == .hybrid else {
                return await cacheAndReturn(
                    segment: segment,
                    glossaryMatches: glossaryMatches,
                    reviews: [],
                    parsedStatus: failure.parsedStatus,
                    parsedCategory: failure.parsedCategory,
                    rejections: rejections,
                    cacheKey: cacheKey,
                    modelAttempts: attempts,
                    repairAttempted: repairAttempted,
                    usedFallback: false,
                    firstPassSucceeded: false,
                    generationMetrics: failure.generationMetrics,
                    repeatedSixGramRatio: failure.repeatedSixGramRatio,
                    outputWasTruncated: failure.isTokenLimit,
                    reasoningMarkerDetected: failure.isReasoningLeak,
                    sourceClaimDetected: failure.isSourceClaim
                )
            }

            return await fallbackResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                rejections: rejections,
                parsedStatus: failure.parsedStatus,
                parsedCategory: failure.parsedCategory,
                cacheKey: cacheKey,
                modelAttempts: attempts,
                repairAttempted: repairAttempted,
                protectionContext: documentProtectionContext,
                generationMetrics: failure.generationMetrics,
                repeatedSixGramRatio: failure.repeatedSixGramRatio,
                outputWasTruncated: failure.isTokenLimit,
                reasoningMarkerDetected: failure.isReasoningLeak,
                sourceClaimDetected: failure.isSourceClaim
            )
        }
    }

    private func processCandidateFirst(
        segment: AIReviewSegment,
        documentProtectionContext: AIConnectorDocumentProtectionContext,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        forceDeterministic: Bool,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void,
        generationProfile: AIConnectorGenerationProfile? = nil
    ) async throws -> AIConnectorSegmentResult {
        let glossaryMatches = dictionaryStore.suggestionCandidates(
            for: segment.targetText,
            limit: 3
        )
        let actionableGlossaryMatches = glossaryMatches.filter {
            $0.entry.authority == .verified
        }

        if segment.isTooLong {
            return AIConnectorSegmentResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                rejections: [
                    AIReviewRejection(
                        segment: segment,
                        rawOutput: "",
                        reason: "Segmen melebihi batas 512 token; dilewati tanpa dipotong.",
                        classification: .segmentTooLong
                    )
                ],
                skipped: true
            )
        }

        let candidates = candidateBuilder.build(
            for: segment,
            glossaryMatches: actionableGlossaryMatches
        )
        let profile = generationProfile ?? AIConnectorGenerationProfilePreset.greedy.profile(
            for: modelVariant,
            thinkingEnabled: thinkingEnabled
        )
        let cacheKey = AIConnectorSegmentCache.key(
            from: AIConnectorCacheKeyComponents(
                segment: segment,
                reviewMode: mode,
                modelVariant: modelVariant,
                generationProfile: profile,
                promptVersion: QwenSuggestionService.candidatePromptVersion,
                rulePackVersion: ruleStore.version,
                corpusVersion: AIConnectorLocalToolDispatcher.corpusVersion,
                validatorVersion: AIConnectorSuggestionValidator.version,
                outputSchemaVersion: QwenSuggestionService.candidateOutputSchemaVersion,
                protectionContext: documentProtectionContext,
                candidateFingerprint: Self.candidateFingerprint(candidates)
            )
        )

        if let cached = await segmentCache.value(for: cacheKey) {
            let rejections = cached.rejectionReasons.enumerated().map { index, reason in
                AIReviewRejection(
                    segment: segment,
                    rawOutput: "",
                    reason: reason,
                    classification: index < cached.rejectionClasses.count
                        ? cached.rejectionClasses[index]
                        : .unknown
                )
            }
            return AIConnectorSegmentResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                reviews: cached.reviews.map { $0.materialize(for: segment) },
                parsedStatus: cached.parsedStatus,
                parsedCategory: cached.parsedCategory,
                rejections: rejections,
                cacheHit: true,
                modelAttempts: cached.modelAttempts,
                repairAttempted: cached.repairAttempted,
                usedFallback: cached.usedFallback,
                firstPassSucceeded: cached.firstPassSucceeded,
                generationMetrics: cached.generationMetrics,
                repeatedSixGramRatio: cached.repeatedSixGramRatio,
                outputWasTruncated: cached.outputWasTruncated,
                reasoningMarkerDetected: cached.reasoningMarkerDetected,
                sourceClaimDetected: cached.sourceClaimDetected,
                candidates: candidates,
                candidateDecisions: cached.candidateDecisions,
                modelCallCount: cached.modelCallCount,
                challengeCount: cached.challengeCount
            )
        }

        if !mode.usesModel || forceDeterministic {
            let reviews = validatedCandidateReviews(
                candidates,
                segment: segment,
                origin: forceDeterministic ? .deterministicFallback : .deterministic,
                protectionContext: documentProtectionContext
            )
            let finalReviews = reviews.isEmpty
                ? noSuggestionReview(
                    for: segment,
                    origin: forceDeterministic ? .deterministicFallback : .deterministic,
                    protectionContext: documentProtectionContext
                ).map { [$0] } ?? []
                : conflictResolver.resolve(reviews)
            return await cacheAndReturn(
                segment: segment,
                glossaryMatches: glossaryMatches,
                reviews: finalReviews,
                rejections: [],
                cacheKey: cacheKey,
                modelAttempts: 0,
                repairAttempted: false,
                usedFallback: forceDeterministic && mode != .deterministic,
                firstPassSucceeded: true,
                candidates: candidates
            )
        }

        if candidates.isEmpty {
            let noSuggestion = noSuggestionReview(
                for: segment,
                origin: .deterministic,
                protectionContext: documentProtectionContext
            )
            return await cacheAndReturn(
                segment: segment,
                glossaryMatches: glossaryMatches,
                reviews: noSuggestion.map { [$0] } ?? [],
                rejections: [],
                cacheKey: cacheKey,
                modelAttempts: 0,
                repairAttempted: false,
                usedFallback: false,
                firstPassSucceeded: true,
                candidates: candidates
            )
        }

        var reviews: [AIValidatedReview] = []
        var rejections: [AIReviewRejection] = []
        var decisions: [AIConnectorCandidateDecisionRecord] = []
        var totalAttempts = 0
        var repairAttempted = false
        var usedFallback = false
        var firstPassSucceeded = true
        var latestMetrics: AIConnectorGenerationMetrics?
        var repeatedSixGramRatio: Double?
        var outputWasTruncated = false
        var reasoningMarkerDetected = false
        var sourceClaimDetected = false

        for candidate in candidates {
            try Task.checkCancellation()
            let outcome = try await judgeCandidate(
                candidate,
                segment: segment,
                mode: mode,
                modelVariant: modelVariant,
                thinkingEnabled: thinkingEnabled,
                generationProfile: profile,
                glossaryMatches: actionableGlossaryMatches,
                protectionContext: documentProtectionContext,
                downloadProgress: downloadProgress,
                generationProgress: generationProgress
            )
            totalAttempts += outcome.attemptCount
            repairAttempted = repairAttempted || outcome.repairAttempted
            usedFallback = usedFallback || outcome.usedFallback
            firstPassSucceeded = firstPassSucceeded && outcome.firstPassSucceeded
            latestMetrics = outcome.generationMetrics ?? latestMetrics
            repeatedSixGramRatio = Self.maximum(
                repeatedSixGramRatio,
                outcome.repeatedSixGramRatio
            )
            outputWasTruncated = outputWasTruncated || outcome.outputWasTruncated
            reasoningMarkerDetected = reasoningMarkerDetected || outcome.reasoningMarkerDetected
            sourceClaimDetected = sourceClaimDetected || outcome.sourceClaimDetected
            if let review = outcome.review {
                reviews.append(review)
            }
            if let rejection = outcome.rejection {
                rejections.append(rejection)
            }
            decisions.append(outcome.diagnostic)
        }

        let resolvedReviews = conflictResolver.resolve(reviews)
        let outputReviews: [AIValidatedReview]
        if resolvedReviews.isEmpty, rejections.isEmpty {
            outputReviews = noSuggestionReview(
                for: segment,
                origin: .deterministic,
                protectionContext: documentProtectionContext
            ).map { [$0] } ?? []
        } else {
            outputReviews = resolvedReviews
        }

        return await cacheAndReturn(
            segment: segment,
            glossaryMatches: glossaryMatches,
            reviews: outputReviews,
            parsedStatus: outputReviews.first?.status,
            parsedCategory: outputReviews.first?.category,
            rejections: rejections,
            cacheKey: cacheKey,
            modelAttempts: totalAttempts,
            repairAttempted: repairAttempted,
            usedFallback: usedFallback,
            firstPassSucceeded: firstPassSucceeded,
            generationMetrics: latestMetrics,
            repeatedSixGramRatio: repeatedSixGramRatio,
            outputWasTruncated: outputWasTruncated,
            reasoningMarkerDetected: reasoningMarkerDetected,
            sourceClaimDetected: sourceClaimDetected,
            candidates: candidates,
            candidateDecisions: decisions,
            modelCallCount: totalAttempts,
            challengeCount: decisions.filter(\.challengeAttempted).count
        )
    }

    private func judgeCandidate(
        _ candidate: AIConnectorReviewCandidate,
        segment: AIReviewSegment,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        generationProfile: AIConnectorGenerationProfile,
        glossaryMatches: [LegalDictionaryMatch],
        protectionContext: AIConnectorDocumentProtectionContext,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void
    ) async throws -> CandidateProcessingOutcome {
        var attempts = 0
        var repairAttempted = false
        var challengeAttempted = false
        var firstPassSucceeded = true
        var latestMetrics: AIConnectorGenerationMetrics?

        let firstResult: QwenCandidateDecisionResult
        do {
            attempts += 1
            firstResult = try await invokeCandidate(
                candidate,
                segment: segment,
                thinkingEnabled: thinkingEnabled,
                modelVariant: modelVariant,
                generationProfile: generationProfile,
                retryInstruction: nil,
                downloadProgress: downloadProgress,
                generationProgress: generationProgress
            )
            latestMetrics = firstResult.metrics
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as AIConnectorCandidateModelFailure {
            latestMetrics = failure.metrics
            guard failure.recoverable else {
                return failureOutcome(
                    candidate: candidate,
                    segment: segment,
                    mode: mode,
                    failure: failure,
                    attempts: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    protectionContext: protectionContext,
                    glossaryMatches: glossaryMatches
                )
            }

            repairAttempted = true
            firstPassSucceeded = false
            attempts += 1
            do {
                let repaired = try await invokeCandidate(
                    candidate,
                    segment: segment,
                    thinkingEnabled: thinkingEnabled,
                    modelVariant: modelVariant,
                    generationProfile: generationProfile,
                    retryInstruction: Self.candidateRepairInstruction(failure.message),
                    downloadProgress: downloadProgress,
                    generationProgress: generationProgress
                )
                latestMetrics = repaired.metrics
                return try makeCandidateOutcome(
                    candidate: candidate,
                    segment: segment,
                    mode: mode,
                    decisionResult: repaired,
                    origin: .qwenRepaired,
                    attempts: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    firstPassSucceeded: firstPassSucceeded,
                    protectionContext: protectionContext,
                    glossaryMatches: glossaryMatches
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let retryFailure as AIConnectorCandidateModelFailure {
                latestMetrics = retryFailure.metrics ?? latestMetrics
                return failureOutcome(
                    candidate: candidate,
                    segment: segment,
                    mode: mode,
                    failure: retryFailure,
                    attempts: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    protectionContext: protectionContext,
                    glossaryMatches: glossaryMatches
                )
            } catch {
                return failureOutcome(
                    candidate: candidate,
                    segment: segment,
                    mode: mode,
                    failure: Self.genericCandidateFailure(from: error),
                    attempts: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    protectionContext: protectionContext,
                    glossaryMatches: glossaryMatches
                )
            }
        } catch {
            return failureOutcome(
                candidate: candidate,
                segment: segment,
                mode: mode,
                failure: Self.genericCandidateFailure(from: error),
                attempts: attempts,
                repairAttempted: repairAttempted,
                challengeAttempted: challengeAttempted,
                protectionContext: protectionContext,
                glossaryMatches: glossaryMatches
            )
        }

        var finalResult = firstResult
        let origin: AIReviewOrigin = .qwen
        if firstResult.decision == .reject {
            challengeAttempted = true
            attempts += 1
            do {
                let challenge = try await invokeCandidate(
                    candidate,
                    segment: segment,
                    thinkingEnabled: thinkingEnabled,
                    modelVariant: modelVariant,
                    generationProfile: generationProfile,
                    retryInstruction: Self.candidateChallengeInstruction,
                    downloadProgress: downloadProgress,
                    generationProgress: generationProgress
                )
                guard challenge.candidateID == candidate.id else {
                    // Keep the valid first-pass REJECT. A malformed recheck
                    // must not turn an explicit model decision into a
                    // deterministic fallback suggestion.
                    return try makeCandidateOutcome(
                        candidate: candidate,
                        segment: segment,
                        mode: mode,
                        decisionResult: firstResult,
                        origin: origin,
                        attempts: attempts,
                        repairAttempted: repairAttempted,
                        challengeAttempted: challengeAttempted,
                        firstPassSucceeded: firstPassSucceeded,
                        protectionContext: protectionContext,
                        glossaryMatches: glossaryMatches,
                        generationMetrics: latestMetrics
                    )
                }
                latestMetrics = challenge.metrics
                finalResult = challenge
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A valid explicit REJECT remains the decision. A failed
                // recheck must not silently turn it into a suggestion.
            }
        }

        return try makeCandidateOutcome(
            candidate: candidate,
            segment: segment,
            mode: mode,
            decisionResult: finalResult,
            origin: origin,
            attempts: attempts,
            repairAttempted: repairAttempted,
            challengeAttempted: challengeAttempted,
            firstPassSucceeded: firstPassSucceeded,
            protectionContext: protectionContext,
            glossaryMatches: glossaryMatches,
            generationMetrics: latestMetrics
        )
    }

    private func invokeCandidate(
        _ candidate: AIConnectorReviewCandidate,
        segment: AIReviewSegment,
        thinkingEnabled: Bool,
        modelVariant: AIConnectorModelVariant,
        generationProfile: AIConnectorGenerationProfile,
        retryInstruction: String?,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void
    ) async throws -> QwenCandidateDecisionResult {
        try await candidateDecisionHandler(
            AIConnectorCandidateReviewRequest(
                segment: segment,
                candidate: candidate,
                thinkingEnabled: thinkingEnabled,
                modelVariant: modelVariant,
                generationProfile: generationProfile,
                retryInstruction: retryInstruction
            ),
            downloadProgress,
            generationProgress
        )
    }

    private func makeCandidateOutcome(
        candidate: AIConnectorReviewCandidate,
        segment: AIReviewSegment,
        mode: AIConnectorReviewMode,
        decisionResult: QwenCandidateDecisionResult,
        origin: AIReviewOrigin,
        attempts: Int,
        repairAttempted: Bool,
        challengeAttempted: Bool,
        firstPassSucceeded: Bool,
        protectionContext: AIConnectorDocumentProtectionContext,
        glossaryMatches: [LegalDictionaryMatch],
        generationMetrics: AIConnectorGenerationMetrics? = nil
    ) throws -> CandidateProcessingOutcome {
        guard decisionResult.candidateID == candidate.id else {
            let failure = AIConnectorCandidateModelFailure(
                message: "Model mengembalikan kandidat yang berbeda dari kandidat aktif.",
                classification: .parserNonRecoverable,
                recoverable: false,
                metrics: decisionResult.metrics,
                reasoningMarkerDetected: decisionResult.containsReasoningMarkers,
                outputWasTruncated: decisionResult.metrics.stopReason == .length,
                repeatedSixGramRatio: decisionResult.repeatedSixGramRatio
            )
            return failureOutcome(
                candidate: candidate,
                segment: segment,
                mode: mode,
                failure: failure,
                attempts: attempts,
                repairAttempted: repairAttempted,
                challengeAttempted: challengeAttempted,
                protectionContext: protectionContext,
                glossaryMatches: glossaryMatches
            )
        }

        switch decisionResult.decision {
        case .reject:
            if mode == .hybrid,
               candidate.confidenceTier == .deterministicRule,
               (candidate.category == .spelling || candidate.category == .grammar),
               let deterministicReview = try? validator.validate(
                   AIParsedReview(
                       status: .suggestion,
                       category: candidate.category,
                       original: candidate.original,
                       replacement: candidate.replacement,
                       glossaryID: nil,
                       reason: candidate.explanation,
                       ruleID: candidate.ruleID
                   ),
                   for: segment,
                   glossaryMatches: [],
                   origin: .deterministic,
                   protectionContext: protectionContext
               ) {
                return CandidateProcessingOutcome(
                    review: deterministicReview,
                    rejection: nil,
                    diagnostic: AIConnectorCandidateDecisionRecord(
                        candidateID: candidate.id,
                        candidateCategory: candidate.category,
                        confidenceTier: candidate.confidenceTier,
                        decision: .reject,
                        attemptCount: attempts,
                        repairAttempted: repairAttempted,
                        challengeAttempted: challengeAttempted,
                        usedFallback: false,
                        rejectionClass: nil,
                        generationMetrics: generationMetrics ?? decisionResult.metrics,
                        finalOrigin: .deterministic,
                        repeatedSixGramRatio: decisionResult.repeatedSixGramRatio
                    ),
                    attemptCount: attempts,
                    repairAttempted: repairAttempted,
                    usedFallback: false,
                    firstPassSucceeded: firstPassSucceeded,
                    generationMetrics: generationMetrics ?? decisionResult.metrics,
                    outputWasTruncated: false,
                    reasoningMarkerDetected: decisionResult.containsReasoningMarkers,
                    repeatedSixGramRatio: decisionResult.repeatedSixGramRatio,
                    sourceClaimDetected: false
                )
            }

            return CandidateProcessingOutcome(
                review: nil,
                rejection: nil,
                diagnostic: AIConnectorCandidateDecisionRecord(
                    candidateID: candidate.id,
                    candidateCategory: candidate.category,
                    confidenceTier: candidate.confidenceTier,
                    decision: .reject,
                    attemptCount: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    usedFallback: false,
                    rejectionClass: nil,
                    generationMetrics: generationMetrics ?? decisionResult.metrics,
                    finalOrigin: origin,
                    repeatedSixGramRatio: decisionResult.repeatedSixGramRatio
                ),
                attemptCount: attempts,
                repairAttempted: repairAttempted,
                usedFallback: false,
                firstPassSucceeded: firstPassSucceeded,
                generationMetrics: generationMetrics ?? decisionResult.metrics,
                outputWasTruncated: false,
                reasoningMarkerDetected: decisionResult.containsReasoningMarkers,
                repeatedSixGramRatio: decisionResult.repeatedSixGramRatio,
                sourceClaimDetected: false
            )
        case .accept, .needsReview:
            let parsedReview = AIParsedReview(
                status: decisionResult.decision == .accept ? .suggestion : .needsReview,
                category: decisionResult.decision == .accept ? candidate.category : candidate.category,
                original: decisionResult.decision == .accept ? candidate.original : candidate.original,
                replacement: decisionResult.decision == .accept ? candidate.replacement : nil,
                glossaryID: decisionResult.decision == .accept && candidate.glossaryMatch != nil
                    ? "G1"
                    : nil,
                reason: decisionResult.decision == .needsReview
                    ? "Proposal memerlukan review manusia sebelum digunakan."
                    : candidate.explanation,
                ruleID: candidate.ruleID
            )
            let validationMatches = candidate.glossaryMatch.map { [$0] } ?? glossaryMatches
            do {
                let review = try validator.validate(
                    parsedReview,
                    for: segment,
                    glossaryMatches: validationMatches,
                    origin: origin,
                    protectionContext: protectionContext
                )
                return CandidateProcessingOutcome(
                    review: review,
                    rejection: nil,
                    diagnostic: AIConnectorCandidateDecisionRecord(
                        candidateID: candidate.id,
                        candidateCategory: candidate.category,
                        confidenceTier: candidate.confidenceTier,
                        decision: decisionResult.decision,
                        attemptCount: attempts,
                        repairAttempted: repairAttempted,
                        challengeAttempted: challengeAttempted,
                        usedFallback: false,
                        rejectionClass: nil,
                        generationMetrics: generationMetrics ?? decisionResult.metrics,
                        finalOrigin: origin,
                        repeatedSixGramRatio: decisionResult.repeatedSixGramRatio
                    ),
                    attemptCount: attempts,
                    repairAttempted: repairAttempted,
                    usedFallback: false,
                    firstPassSucceeded: firstPassSucceeded,
                    generationMetrics: generationMetrics ?? decisionResult.metrics,
                    outputWasTruncated: false,
                    reasoningMarkerDetected: decisionResult.containsReasoningMarkers,
                    repeatedSixGramRatio: decisionResult.repeatedSixGramRatio,
                    sourceClaimDetected: false
                )
            } catch let validationError as AIConnectorValidationError {
                let failure = AIConnectorCandidateModelFailure(
                    message: validationError.message,
                    classification: validationError == .unsupportedSourceClaim
                        ? .sourceClaim
                        : .validator,
                    recoverable: false,
                    metrics: decisionResult.metrics,
                    reasoningMarkerDetected: decisionResult.containsReasoningMarkers,
                    outputWasTruncated: false,
                    repeatedSixGramRatio: decisionResult.repeatedSixGramRatio
                )
                return failureOutcome(
                    candidate: candidate,
                    segment: segment,
                    mode: mode,
                    failure: failure,
                    attempts: attempts,
                    repairAttempted: repairAttempted,
                    challengeAttempted: challengeAttempted,
                    protectionContext: protectionContext,
                    glossaryMatches: glossaryMatches
                )
            }
        }
    }

    private func failureOutcome(
        candidate: AIConnectorReviewCandidate,
        segment: AIReviewSegment,
        mode: AIConnectorReviewMode,
        failure: AIConnectorCandidateModelFailure,
        attempts: Int,
        repairAttempted: Bool,
        challengeAttempted: Bool,
        protectionContext: AIConnectorDocumentProtectionContext,
        glossaryMatches: [LegalDictionaryMatch]
    ) -> CandidateProcessingOutcome {
        let canFallback = mode == .hybrid
            && candidate.confidenceTier == .deterministicRule
            && candidate.category != .terminology
        let fallbackReview: AIValidatedReview?
        if canFallback {
            let parsed = AIParsedReview(
                status: .suggestion,
                category: candidate.category,
                original: candidate.original,
                replacement: candidate.replacement,
                glossaryID: nil,
                reason: candidate.explanation,
                ruleID: candidate.ruleID
            )
            fallbackReview = try? validator.validate(
                parsed,
                for: segment,
                glossaryMatches: glossaryMatches,
                origin: .deterministicFallback,
                protectionContext: protectionContext
            )
        } else {
            fallbackReview = nil
        }

        let rejection = AIReviewRejection(
            segment: segment,
            rawOutput: "",
            reason: failure.message,
            classification: failure.classification
        )
        return CandidateProcessingOutcome(
            review: fallbackReview,
            rejection: rejection,
            diagnostic: AIConnectorCandidateDecisionRecord(
                candidateID: candidate.id,
                candidateCategory: candidate.category,
                confidenceTier: candidate.confidenceTier,
                decision: nil,
                attemptCount: attempts,
                repairAttempted: repairAttempted,
                challengeAttempted: challengeAttempted,
                usedFallback: fallbackReview != nil,
                rejectionClass: failure.classification,
                generationMetrics: failure.metrics,
                finalOrigin: fallbackReview == nil ? nil : .deterministicFallback,
                repeatedSixGramRatio: failure.repeatedSixGramRatio
            ),
            attemptCount: attempts,
            repairAttempted: repairAttempted,
            usedFallback: fallbackReview != nil,
            firstPassSucceeded: false,
            generationMetrics: failure.metrics,
            outputWasTruncated: failure.outputWasTruncated,
            reasoningMarkerDetected: failure.reasoningMarkerDetected,
            repeatedSixGramRatio: failure.repeatedSixGramRatio,
            sourceClaimDetected: failure.classification == .sourceClaim
        )
    }

    private func validatedCandidateReviews(
        _ candidates: [AIConnectorReviewCandidate],
        segment: AIReviewSegment,
        origin: AIReviewOrigin,
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> [AIValidatedReview] {
        candidates.compactMap { candidate in
            let parsed = AIParsedReview(
                status: .suggestion,
                category: candidate.category,
                original: candidate.original,
                replacement: candidate.replacement,
                glossaryID: candidate.glossaryMatch == nil ? nil : "G1",
                reason: candidate.explanation,
                ruleID: candidate.ruleID
            )
            let matches = candidate.glossaryMatch.map { [$0] } ?? []
            return try? validator.validate(
                parsed,
                for: segment,
                glossaryMatches: matches,
                origin: origin,
                protectionContext: protectionContext
            )
        }
    }

    private func noSuggestionReview(
        for segment: AIReviewSegment,
        origin: AIReviewOrigin,
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> AIValidatedReview? {
        try? validator.validate(
            deterministicEngine.noSuggestion(for: segment),
            for: segment,
            glossaryMatches: [],
            origin: origin,
            protectionContext: protectionContext
        )
    }

    private static func candidateFingerprint(
        _ candidates: [AIConnectorReviewCandidate]
    ) -> String {
        candidates.map { candidate in
            [
                candidate.id,
                candidate.original,
                candidate.replacement,
                candidate.category.rawValue,
                String(candidate.priority),
                candidate.ruleID ?? "-",
                candidate.glossaryMatch?.entry.id ?? "-",
                candidate.glossaryMatch?.entry.definition ?? "-",
                candidate.confidenceTier.rawValue
            ].joined(separator: "\u{1E}")
        }
        .joined(separator: "\u{1D}")
    }

    private static func maximum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return max(left, right)
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    private static let candidateChallengeInstruction = """
    RECHECK ONLY: tinjau kembali kandidat yang sama. Jangan membuat kandidat baru. Kirim tepat satu tool submit_review dengan candidate_id yang sama.
    """

    private static func candidateRepairInstruction(_ message: String) -> String {
        """
        FORMAT REPAIR ONLY: respons sebelumnya gagal dengan kode \(message). Jangan mengubah keputusan semantik dan jangan membuat kandidat baru. Kirim tepat satu tool submit_review dengan candidate_id yang sama dan tanpa teks biasa.
        """
    }

    private static func genericCandidateFailure(from error: Error) -> AIConnectorCandidateModelFailure {
        if let qwenError = error as? QwenSuggestionError {
            switch qwenError {
            case .incompleteThinking:
                return AIConnectorCandidateModelFailure(
                    message: qwenError.localizedDescription,
                    classification: .reasoningLeak,
                    recoverable: false,
                    metrics: nil,
                    reasoningMarkerDetected: true,
                    outputWasTruncated: false
                )
            case .segmentTooLong:
                return AIConnectorCandidateModelFailure(
                    message: qwenError.localizedDescription,
                    classification: .tokenLimit,
                    recoverable: false,
                    metrics: nil,
                    reasoningMarkerDetected: false,
                    outputWasTruncated: true
                )
            default:
                break
            }
        }

        return AIConnectorCandidateModelFailure(
            message: error.localizedDescription,
            classification: .modelFailure,
            recoverable: false,
            metrics: nil,
            reasoningMarkerDetected: false,
            outputWasTruncated: false
        )
    }

    private struct CandidateProcessingOutcome {
        let review: AIValidatedReview?
        let rejection: AIReviewRejection?
        let diagnostic: AIConnectorCandidateDecisionRecord
        let attemptCount: Int
        let repairAttempted: Bool
        let usedFallback: Bool
        let firstPassSucceeded: Bool
        let generationMetrics: AIConnectorGenerationMetrics?
        let outputWasTruncated: Bool
        let reasoningMarkerDetected: Bool
        let repeatedSixGramRatio: Double?
        let sourceClaimDetected: Bool
    }

    private func deterministicResult(
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        origin: AIReviewOrigin,
        protectionContext: AIConnectorDocumentProtectionContext,
        usedFallback: Bool = false
    ) -> AIConnectorSegmentResult {
        let parsedReviews = deterministicEngine.suggestions(
            for: segment,
            glossaryMatches: glossaryMatches
        )
        let validated = parsedReviews.compactMap { parsed in
            try? validator.validate(
                parsed,
                for: segment,
                glossaryMatches: glossaryMatches,
                origin: origin,
                protectionContext: protectionContext
            )
        }
        let reviews = conflictResolver.resolve(validated)
        if !reviews.isEmpty {
            return AIConnectorSegmentResult(
                segment: segment,
                glossaryMatches: glossaryMatches,
                reviews: reviews,
                usedFallback: usedFallback
            )
        }

        let noSuggestion = try? validator.validate(
            deterministicEngine.noSuggestion(for: segment),
            for: segment,
            glossaryMatches: glossaryMatches,
            origin: origin,
            protectionContext: protectionContext
        )
        return AIConnectorSegmentResult(
            segment: segment,
            glossaryMatches: glossaryMatches,
            reviews: noSuggestion.map { [$0] } ?? [],
            usedFallback: usedFallback
        )
    }

    /// Hybrid is an ensemble, not merely an error fallback. Deterministic
    /// low-risk candidates remain eligible when Qwen returns a valid
    /// NO_SUGGESTION, then the shared resolver removes overlaps and caps the
    /// segment at three reviews. Model-only stays isolated for quality gates.
    private func successfulReviews(
        modelReview: AIValidatedReview,
        mode: AIConnectorReviewMode,
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> [AIValidatedReview] {
        guard mode == .hybrid else {
            return conflictResolver.resolve([modelReview])
        }

        let deterministicReviews = deterministicResult(
            for: segment,
            glossaryMatches: glossaryMatches,
            origin: .deterministic,
            protectionContext: protectionContext
        ).reviews.filter { $0.status != .noSuggestion }
        let modelReviews = modelReview.status == .noSuggestion
            && !deterministicReviews.isEmpty
            ? []
            : [modelReview]
        return conflictResolver.resolve(deterministicReviews + modelReviews)
    }

    private func fallbackResult(
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        rejections: [AIReviewRejection],
        parsedStatus: AIReviewStatus? = nil,
        parsedCategory: AIReviewCategory? = nil,
        cacheKey: String,
        modelAttempts: Int,
        repairAttempted: Bool,
        protectionContext: AIConnectorDocumentProtectionContext,
        generationMetrics: AIConnectorGenerationMetrics? = nil,
        repeatedSixGramRatio: Double? = nil,
        outputWasTruncated: Bool = false,
        reasoningMarkerDetected: Bool = false,
        sourceClaimDetected: Bool = false,
        candidates: [AIConnectorReviewCandidate] = [],
        candidateDecisions: [AIConnectorCandidateDecisionRecord] = [],
        modelCallCount: Int = 0,
        challengeCount: Int = 0
    ) async -> AIConnectorSegmentResult {
        let result = deterministicResult(
            for: segment,
            glossaryMatches: glossaryMatches,
            origin: .deterministicFallback,
            protectionContext: protectionContext
        )
        return await cacheAndReturn(
            segment: segment,
            glossaryMatches: glossaryMatches,
            reviews: result.reviews,
            parsedStatus: parsedStatus,
            parsedCategory: parsedCategory,
            rejections: rejections,
            cacheKey: cacheKey,
            modelAttempts: modelAttempts,
            repairAttempted: repairAttempted,
            usedFallback: true,
            firstPassSucceeded: false,
            generationMetrics: generationMetrics,
            repeatedSixGramRatio: repeatedSixGramRatio,
            outputWasTruncated: outputWasTruncated,
            reasoningMarkerDetected: reasoningMarkerDetected,
            sourceClaimDetected: sourceClaimDetected
        )
    }

    private func cacheAndReturn(
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        reviews: [AIValidatedReview],
        parsedStatus: AIReviewStatus? = nil,
        parsedCategory: AIReviewCategory? = nil,
        rejections: [AIReviewRejection],
        cacheKey: String,
        modelAttempts: Int,
        repairAttempted: Bool,
        usedFallback: Bool,
        firstPassSucceeded: Bool,
        generationMetrics: AIConnectorGenerationMetrics? = nil,
        repeatedSixGramRatio: Double? = nil,
        outputWasTruncated: Bool = false,
        reasoningMarkerDetected: Bool = false,
        sourceClaimDetected: Bool = false,
        candidates: [AIConnectorReviewCandidate] = [],
        candidateDecisions: [AIConnectorCandidateDecisionRecord] = [],
        modelCallCount: Int = 0,
        challengeCount: Int = 0
    ) async -> AIConnectorSegmentResult {
        await segmentCache.insert(
            AIConnectorCachedSegmentResult(
                reviews: reviews.map(AIConnectorCachedReview.init),
                parsedStatus: parsedStatus,
                parsedCategory: parsedCategory,
                rejectionReasons: rejections.map(\.reason),
                rejectionClasses: rejections.map(\.classification),
                modelAttempts: modelAttempts,
                repairAttempted: repairAttempted,
                usedFallback: usedFallback,
                firstPassSucceeded: firstPassSucceeded,
                candidateDecisions: candidateDecisions,
                generationMetrics: generationMetrics,
                repeatedSixGramRatio: repeatedSixGramRatio,
                outputWasTruncated: outputWasTruncated,
                reasoningMarkerDetected: reasoningMarkerDetected,
                sourceClaimDetected: sourceClaimDetected,
                modelCallCount: modelCallCount,
                challengeCount: challengeCount
            ),
            for: cacheKey
        )
        return AIConnectorSegmentResult(
            segment: segment,
            glossaryMatches: glossaryMatches,
            reviews: reviews,
            parsedStatus: parsedStatus,
            parsedCategory: parsedCategory,
            rejections: rejections,
            modelAttempts: modelAttempts,
            repairAttempted: repairAttempted,
            usedFallback: usedFallback,
            firstPassSucceeded: firstPassSucceeded,
            generationMetrics: generationMetrics,
            repeatedSixGramRatio: repeatedSixGramRatio,
            outputWasTruncated: outputWasTruncated,
            reasoningMarkerDetected: reasoningMarkerDetected,
            sourceClaimDetected: sourceClaimDetected,
            candidates: candidates,
            candidateDecisions: candidateDecisions,
            modelCallCount: modelCallCount,
            challengeCount: challengeCount
        )
    }

    private func evaluate(
        _ result: QwenReviewResult,
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        origin: AIReviewOrigin,
        protectionContext: AIConnectorDocumentProtectionContext
    ) throws -> EvaluatedModelAttempt {
        if result.metrics.stopReason == .cancelled {
            throw CancellationError()
        }
        if result.metrics.stopReason == .length {
            throw ModelAttemptFailure.tokenLimit(result)
        }
        if result.containsReasoningMarkers {
            throw ModelAttemptFailure.reasoningLeak(result)
        }

        let parsed: AIParsedReview
        do {
            parsed = canonicalizer.canonicalize(try parser.parse(result.output))
        } catch let error as AIConnectorOutputParserError {
            throw ModelAttemptFailure.parser(error, result: result)
        }

        let repetitionRatio = AIConnectorGenerationDiagnostics
            .repeatedSixGramRatio(in: parsed)
        if repetitionRatio >= AIConnectorGenerationDiagnostics.repetitionThreshold {
            throw ModelAttemptFailure.repetition(
                result,
                parsed: parsed,
                ratio: repetitionRatio
            )
        }

        do {
            let validated = try validator.validate(
                parsed,
                for: segment,
                glossaryMatches: glossaryMatches,
                origin: origin,
                protectionContext: protectionContext
            )
            return EvaluatedModelAttempt(
                result: result,
                parsed: parsed,
                validated: validated,
                repetitionRatio: repetitionRatio
            )
        } catch let error as AIConnectorValidationError {
            throw ModelAttemptFailure.validation(
                error,
                result: result,
                parsed: parsed,
                repetitionRatio: repetitionRatio
            )
        }
    }

    private static func repairInstruction(
        failure: ModelAttemptFailure
    ) -> String {
        return """
        FORMAT REPAIR ONLY.
        Output sebelumnya gagal dengan kode: \(failure.message)
        Pertahankan keputusan dan isi semantiknya. Jangan menambah saran baru.
        Jangan mengambil evidence baru. Kembalikan tepat enam baris kontrak,
        tanpa Markdown, reasoning, atau teks tambahan. Jika statusnya
        NO_SUGGESTION, ORIGINAL, REPLACEMENT, dan GLOSSARY_ID harus `-`.
        Jika sarannya valid tetapi span terlalu luas, gunakan kutipan dan
        pengganti terkecil yang merepresentasikan perubahan yang sama.
        OUTPUT SEBELUMNYA:
        \(failure.diagnosticOutput)
        """
    }

    private struct EvaluatedModelAttempt {
        let result: QwenReviewResult
        let parsed: AIParsedReview
        let validated: AIValidatedReview
        let repetitionRatio: Double
    }

    private enum ModelAttemptFailure: Error {
        case tokenLimit(QwenReviewResult)
        case reasoningLeak(QwenReviewResult)
        case repetition(QwenReviewResult, parsed: AIParsedReview, ratio: Double)
        case parser(AIConnectorOutputParserError, result: QwenReviewResult)
        case validation(
            AIConnectorValidationError,
            result: QwenReviewResult,
            parsed: AIParsedReview,
            repetitionRatio: Double
        )

        var parsedStatus: AIReviewStatus? {
            switch self {
            case let .repetition(_, parsed, _), let .validation(_, _, parsed, _):
                return parsed.status
            default:
                return nil
            }
        }

        var parsedCategory: AIReviewCategory? {
            switch self {
            case let .repetition(_, parsed, _), let .validation(_, _, parsed, _):
                return parsed.category
            default:
                return nil
            }
        }

        var message: String {
            switch self {
            case .tokenLimit:
                "Model mencapai batas token; output tidak diproses."
            case .reasoningLeak:
                "Output mengandung reasoning atau token template; diagnostic di-redact."
            case .repetition:
                "Output memiliki repetisi berlebihan dan ditolak."
            case let .parser(error, _):
                error.message
            case let .validation(error, _, _, _):
                error.message
            }
        }

        var diagnosticOutput: String {
            switch self {
            case .reasoningLeak:
                "[REDACTED: reasoning atau token template terdeteksi]"
            case .tokenLimit:
                "[REDACTED: output mencapai batas token]"
            case let .repetition(result, _, _), let .parser(_, result),
                 let .validation(_, result, _, _):
                AIConnectorGenerationDiagnostics.sanitizedDiagnosticOutput(result.output)
            }
        }

        var generationMetrics: AIConnectorGenerationMetrics? {
            switch self {
            case let .tokenLimit(result), let .reasoningLeak(result),
                 let .repetition(result, _, _), let .parser(_, result),
                 let .validation(_, result, _, _):
                result.metrics
            }
        }

        var repeatedSixGramRatio: Double? {
            switch self {
            case let .repetition(_, _, ratio), let .validation(_, _, _, ratio):
                ratio
            case let .tokenLimit(result), let .reasoningLeak(result), let .parser(_, result):
                AIConnectorGenerationDiagnostics.repeatedSixGramRatio(in: result.output)
            }
        }

        var isTokenLimit: Bool {
            if case .tokenLimit = self { return true }
            return false
        }

        var isReasoningLeak: Bool {
            if case .reasoningLeak = self { return true }
            return false
        }

        var isSourceClaim: Bool {
            if case let .validation(error, _, _, _) = self,
               error == .unsupportedSourceClaim {
                return true
            }
            return false
        }

        var classification: AIConnectorRejectionClass {
            switch self {
            case .tokenLimit:
                .tokenLimit
            case .reasoningLeak:
                .reasoningLeak
            case .repetition:
                .repetition
            case let .parser(error, _):
                error.isRecoverable ? .parserRecoverable : .parserNonRecoverable
            case let .validation(error, _, _, _):
                error == .unsupportedSourceClaim ? .sourceClaim : .validator
            }
        }

        var isRepairable: Bool {
            switch self {
            case let .parser(error, _):
                error.isRecoverable
            case let .validation(error, _, _, _):
                error == .inconsistentFields || error == .nonMinimalEditSpan
            case .tokenLimit, .reasoningLeak, .repetition:
                false
            }
        }
    }
}

/// Owns queue identity and cancellation while delegating segment semantics to
/// the shared processor. Only one queue task is active at a time.
actor AIConnectorWorkQueue {
    nonisolated static func batchSizes(for segmentCount: Int) -> [Int] {
        guard segmentCount > 0 else { return [] }
        var remaining = segmentCount
        var sizes: [Int] = []
        while remaining > 0 {
            let size = min(LegalTextSegmenter.batchSize, remaining)
            sizes.append(size)
            remaining -= size
        }
        return sizes
    }

    private let processor: AIConnectorSegmentProcessor
    private let cancellationSignal = AIConnectorCancellationSignal()
    private var activeTask: Task<Void, Never>?
    private var activeRunID: UUID?
    private var activeContinuation: AsyncStream<AIConnectorWorkQueueEvent>.Continuation?
    private var advanceContinuation: CheckedContinuation<Void, Never>?

    init(processor: AIConnectorSegmentProcessor) {
        self.processor = processor
    }

    func start(
        runID: UUID,
        segments: [AIReviewSegment],
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        documentProtectionContext: AIConnectorDocumentProtectionContext,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void,
        generationProfile: AIConnectorGenerationProfile? = nil
    ) -> AsyncStream<AIConnectorWorkQueueEvent> {
        // Finish the previous stream before replacing its run identity. This
        // makes rerun deterministic for consumers that are still draining an
        // older stream, while the run-ID guard below prevents stale work from
        // publishing into the new run.
        activeContinuation?.finish()
        activeContinuation = nil
        cancellationSignal.cancel()
        resumeAdvanceWaiter()
        activeTask?.cancel()

        let (stream, continuation) = AsyncStream<AIConnectorWorkQueueEvent>.makeStream()
        activeRunID = runID
        cancellationSignal.reset()
        activeContinuation = continuation
        activeTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            await self.execute(
                runID: runID,
                segments: segments,
                mode: mode,
                modelVariant: modelVariant,
                thinkingEnabled: thinkingEnabled,
                documentProtectionContext: documentProtectionContext,
                downloadProgress: downloadProgress,
                generationProgress: generationProgress,
                generationProfile: generationProfile,
                continuation: continuation
            )
        }
        return stream
    }

    /// Publishes cancellation without waiting for the queue actor's next turn.
    /// Callers should also await `cancel()` to cancel the active generation.
    nonisolated func requestCancellation() {
        cancellationSignal.cancel()
    }

    func cancel() {
        cancellationSignal.cancel()
        resumeAdvanceWaiter()
        activeTask?.cancel()
        activeTask = nil
        activeRunID = nil
        // Leave the active continuation open so the cancelled task can publish
        // its partial summary. A subsequent start() will finish this stream
        // before replacing it.
    }

    /// A result event is an explicit back-pressure point. The consumer must
    /// acknowledge it before the serial queue is allowed to start another
    /// segment. This closes the cancellation race where an AsyncStream
    /// consumer could receive a result after the producer had already begun
    /// the next model request.
    func acknowledgeResult() {
        resumeAdvanceWaiter()
    }

    private func execute(
        runID: UUID,
        segments: [AIReviewSegment],
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        documentProtectionContext: AIConnectorDocumentProtectionContext,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void,
        generationProfile: AIConnectorGenerationProfile?,
        continuation: AsyncStream<AIConnectorWorkQueueEvent>.Continuation
    ) async {
        var results: [AIConnectorSegmentResult] = []
        var circuitBreakerActivated = false
        var modelEligibleCount = 0
        var modelFailures = 0
        var completedCount = 0

        for batch in segments.chunked(into: LegalTextSegmenter.batchSize) {
            guard isActive(runID), !Task.isCancelled, !cancellationSignal.isCancelled else {
                yieldPartialSummary(
                    runID: runID,
                    results: results,
                    total: segments.count,
                    mode: mode,
                    modelVariant: modelVariant,
                    circuitBreakerActivated: circuitBreakerActivated,
                    continuation: continuation
                )
                return
            }

            for segment in batch {
                guard isActive(runID), !Task.isCancelled, !cancellationSignal.isCancelled else {
                    yieldPartialSummary(
                        runID: runID,
                        results: results,
                        total: segments.count,
                        mode: mode,
                        modelVariant: modelVariant,
                        circuitBreakerActivated: circuitBreakerActivated,
                        continuation: continuation
                    )
                    return
                }

                continuation.yield(
                    .stateChanged(segmentID: segment.id, state: .preparing)
                )
                continuation.yield(
                    .stateChanged(segmentID: segment.id, state: .retrieving)
                )

                let useDeterministic = segment.isTooLong || mode == .deterministic
                    || (mode == .hybrid && circuitBreakerActivated)

                continuation.yield(
                    .stateChanged(
                        segmentID: segment.id,
                        state: segment.isTooLong
                            ? .skipped
                            : (useDeterministic ? .validating : .generating)
                    )
                )

                do {
                    let result = try await processor.process(
                        segment: segment,
                        documentProtectionContext: documentProtectionContext,
                        mode: mode,
                        modelVariant: modelVariant,
                        thinkingEnabled: thinkingEnabled,
                        forceDeterministic: useDeterministic && mode != .deterministic,
                        downloadProgress: downloadProgress,
                        generationProgress: generationProgress,
                        generationProfile: generationProfile
                    )
                    results.append(result)

                    if result.reviews.contains(where: { $0.status == .suggestion }) {
                        continuation.yield(
                            .stateChanged(segmentID: segment.id, state: .completed)
                        )
                    } else if result.skipped {
                        continuation.yield(
                            .stateChanged(segmentID: segment.id, state: .skipped)
                        )
                    } else if result.reviews.contains(where: { $0.status == .needsReview }) {
                        continuation.yield(
                            .stateChanged(segmentID: segment.id, state: .needsReview)
                        )
                    } else if !result.rejections.isEmpty && result.reviews.isEmpty {
                        continuation.yield(
                            .stateChanged(segmentID: segment.id, state: .rejected)
                        )
                    } else {
                        continuation.yield(
                            .stateChanged(segmentID: segment.id, state: .noSuggestion)
                        )
                    }

                    continuation.yield(.result(result))
                    completedCount += 1
                    continuation.yield(
                        .progress(completed: completedCount, total: segments.count)
                    )

                    // The P0.11 breaker is evaluated per segment that actually
                    // had candidate work. Segments without a local proposal
                    // must not make a healthy model look unreliable. The
                    // modelAttempts fallback keeps the historical injected
                    // six-line test path compatible.
                    let hadModelWork = !result.candidates.isEmpty || result.modelAttempts > 0
                    if mode.usesModel && !useDeterministic && !result.cacheHit
                        && !result.skipped && hadModelWork {
                        modelEligibleCount += 1
                        if result.repairAttempted || !result.firstPassSucceeded {
                            modelFailures += 1
                        }
                        if modelEligibleCount == 4,
                           modelFailures >= 3,
                           !circuitBreakerActivated {
                            circuitBreakerActivated = true
                            continuation.yield(.circuitBreakerActivated)
                        }
                    }

                    // Do not begin the next model request until the consumer
                    // has applied this result. Cancellation also releases
                    // this wait through `cancel()`.
                    await waitForResultAcknowledgement()
                    guard isActive(runID), !Task.isCancelled, !cancellationSignal.isCancelled else {
                        yieldPartialSummary(
                            runID: runID,
                            results: results,
                            total: segments.count,
                            mode: mode,
                            modelVariant: modelVariant,
                            circuitBreakerActivated: circuitBreakerActivated,
                            continuation: continuation
                        )
                        return
                    }
                } catch is CancellationError {
                    yieldPartialSummary(
                        runID: runID,
                        results: results,
                        total: segments.count,
                        mode: mode,
                        modelVariant: modelVariant,
                        circuitBreakerActivated: circuitBreakerActivated,
                        continuation: continuation
                    )
                    return
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                    if activeRunID == runID {
                        activeContinuation = nil
                        activeTask = nil
                        activeRunID = nil
                    }
                    return
                }
            }
        }

        let summary = makeSummary(
            results: results,
            total: segments.count,
            mode: mode,
            modelVariant: modelVariant,
            circuitBreakerActivated: circuitBreakerActivated,
            wasPartial: false
        )
        continuation.yield(.finished(summary))
        continuation.finish()
        if activeRunID == runID {
            activeContinuation = nil
            activeTask = nil
            activeRunID = nil
        }
    }

    private func isActive(_ runID: UUID) -> Bool {
        activeRunID == runID
    }

    private func waitForResultAcknowledgement() async {
        guard !cancellationSignal.isCancelled, !Task.isCancelled else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if cancellationSignal.isCancelled || Task.isCancelled {
                continuation.resume()
            } else {
                advanceContinuation = continuation
            }
        }
    }

    private func resumeAdvanceWaiter() {
        advanceContinuation?.resume()
        advanceContinuation = nil
    }

    private func yieldPartialSummary(
        runID: UUID,
        results: [AIConnectorSegmentResult],
        total: Int,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        circuitBreakerActivated: Bool,
        continuation: AsyncStream<AIConnectorWorkQueueEvent>.Continuation
    ) {
        continuation.yield(
            .finished(
                makeSummary(
                    results: results,
                    total: total,
                    mode: mode,
                    modelVariant: modelVariant,
                    circuitBreakerActivated: circuitBreakerActivated,
                    wasPartial: true
                )
            )
        )
        continuation.finish()
        if activeRunID == runID {
            activeContinuation = nil
            activeTask = nil
            activeRunID = nil
        }
    }

    private func makeSummary(
        results: [AIConnectorSegmentResult],
        total: Int,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        circuitBreakerActivated: Bool,
        wasPartial: Bool
    ) -> AIConnectorRunSummary {
        let reviews = results.flatMap(\.reviews)
        return AIConnectorRunSummary(
            reviewMode: mode,
            modelVariant: modelVariant,
            processedSegmentCount: results.filter { !$0.skipped }.count,
            suggestionCount: reviews.filter { $0.status == .suggestion }.count,
            needsReviewCount: reviews.filter { $0.status == .needsReview }.count,
            noSuggestionCount: reviews.filter { $0.status == .noSuggestion }.count,
            recoveredCount: reviews.filter { $0.origin == .deterministicFallback }.count,
            rejectedCount: results.flatMap(\.rejections).count,
            skippedSegmentCount: results.filter(\.skipped).count,
            totalSegmentCount: total,
            cacheHitCount: results.filter(\.cacheHit).count,
            firstPassSuccessCount: results.filter(\.firstPassSucceeded).count,
            repairAttemptCount: results.filter(\.repairAttempted).count,
            fallbackCount: results.filter(\.usedFallback).count,
            circuitBreakerActivated: circuitBreakerActivated,
            wasPartial: wasPartial,
            candidateCount: results.reduce(0) { $0 + $1.candidates.count },
            acceptedCandidateCount: results
                .flatMap(\.candidateDecisions)
                .filter { $0.decision == .accept }
                .count,
            modelCallCount: results.reduce(0) { $0 + $1.modelCallCount },
            challengeCount: results.reduce(0) { $0 + $1.challengeCount }
        )
    }
}

private extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let next = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
