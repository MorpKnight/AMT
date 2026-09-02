import Foundation
import Observation

@MainActor
@Observable
final class AIConnectorViewModel {
    private static let previewCharacters = 2_000
    static let maximumDocumentCharacters = 4_000

    var inputSource: AIConnectorInputSource = .currentDocument
    var selectedSampleID = "redundant-wajib-untuk"
    var thinkingEnabled = false
    var reviewMode: AIConnectorReviewMode = .hybrid
    var modelVariant: AIConnectorModelVariant = .qwen35Base4B
    var generationProfilePreset: AIConnectorGenerationProfilePreset = .greedy

    private(set) var state: AIConnectorRunState = .idle
    private(set) var progressStage: AIConnectorProgressStage = .idle
    private(set) var errorMessage: String?
    private(set) var downloadProgress = 0.0
    private(set) var generationProgress = 0
    private(set) var latestGenerationMetrics: AIConnectorGenerationMetrics?
    private(set) var currentSegmentPreview = ""
    private(set) var currentGlossaryMatches: [LegalDictionaryMatch] = []
    private(set) var currentCandidates: [AIConnectorReviewCandidate] = []
    private(set) var currentCandidateDecisions: [AIConnectorCandidateDecisionRecord] = []
    private(set) var currentQueueState: AIConnectorQueueState?
    private(set) var currentBatchIndex: Int?
    private(set) var currentBatchSize: Int?
    private(set) var queueBatchSizes: [Int] = []
    private(set) var glossarySnapshots: [AIReviewGlossarySnapshot] = []
    private(set) var segmentationResult: AITextSegmentationResult?
    private(set) var validatedReviews: [AIValidatedReview] = []
    private(set) var rejectedReviews: [AIReviewRejection] = []
    private(set) var definitionAssessments: [AIConnectorDefinitionAssessment] = []
    private(set) var definitionModelCallCount = 0
    private(set) var processedSegmentCount = 0
    private(set) var skippedSegmentCount = 0
    private(set) var noSuggestionCount = 0
    private(set) var cacheHitCount = 0
    private(set) var firstPassSuccessCount = 0
    private(set) var repairAttemptCount = 0
    private(set) var fallbackCount = 0
    private(set) var candidateCount = 0
    private(set) var acceptedCandidateCount = 0
    private(set) var modelCallCount = 0
    private(set) var challengeCount = 0
    private(set) var circuitBreakerActivated = false
    private(set) var output = ""
    private(set) var runSummary: AIConnectorRunSummary?
    private(set) var fixtureEvaluation: AIConnectorFixtureEvaluation?
    private(set) var benchmarkSummary: AIConnectorBenchmarkSummary?
    private(set) var benchmarkReport: AIConnectorBenchmarkReport?
    private(set) var editorSuggestions: [EditorSuggestion] = []
    private(set) var selectedSuggestionID: UUID?

    private let service: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore
    private let segmenter = LegalTextSegmenter()
    private let fixtureEvaluator = AIConnectorFixtureEvaluator()
    private let benchmarkRunner: AIConnectorBenchmarkRunner
    private let workQueue: AIConnectorWorkQueue
    private let segmentProcessor: AIConnectorSegmentProcessor
    private var task: Task<Void, Never>?
    private var activeOperationID: UUID?
    private var exposesEditorSuggestions = false
    private var editorSourceText = ""

    init(
        service: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore
    ) {
        self.service = service
        self.dictionaryStore = dictionaryStore
        let segmentCache = AIConnectorSegmentCache()
        let processor = AIConnectorSegmentProcessor(
            service: service,
            dictionaryStore: dictionaryStore,
            ruleStore: AIConnectorRuleStore(),
            segmentCache: segmentCache
        )
        self.segmentProcessor = processor
        self.workQueue = AIConnectorWorkQueue(processor: processor)
        self.benchmarkRunner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: dictionaryStore
        )
    }

    var isRunning: Bool {
        state.isRunning
    }

    var selectedSample: AIConnectorSample {
        AIConnectorSample.samples.first(where: { $0.id == selectedSampleID })
            ?? AIConnectorSample.samples[0]
    }

    var acceptedSuggestionCount: Int {
        validatedReviews.filter { $0.status == .suggestion }.count
    }

    var needsReviewCount: Int {
        validatedReviews.filter { $0.status == .needsReview }.count
    }

    var glossaryCandidateCount: Int {
        glossarySnapshots.reduce(0) { count, snapshot in
            count + snapshot.matches.count
        }
    }

    var definitionMatchCount: Int {
        definitionAssessments.filter { $0.alignment == .matches }.count
    }

    var definitionMismatchCount: Int {
        definitionAssessments.filter { $0.alignment == .mismatch }.count
    }

    var definitionNeedsReviewCount: Int {
        definitionAssessments.filter { $0.alignment == .needsReview }.count
    }

    var activeCorpusVersion: String {
        dictionaryStore.activeCorpusVersion
    }

    var semanticModelRevision: String {
        dictionaryStore.semanticModelRevision
    }

    var semanticRetrievalConfiguration: LegalCorpusRetrievalConfiguration? {
        dictionaryStore.semanticRetrievalConfiguration
    }

    func inputPreview(documentText: String) -> String {
        let text = sourceText(documentText: documentText)
        let preview = String(text.prefix(Self.previewCharacters))
        return text.count > Self.previewCharacters ? preview + "…" : preview
    }

    func inputWasTruncated(documentText: String) -> Bool {
        inputSource == .currentDocument && documentText.count > Self.maximumDocumentCharacters
    }

    func canRun(documentText: String) -> Bool {
        guard !isRunning else { return false }
        return !sourceText(documentText: documentText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var canRunBenchmark: Bool {
        !isRunning
    }

    func runDeterministicBenchmark() {
        guard canRunBenchmark else { return }

        cancelRunningTask()
        service.cancelLoading()
        clearBenchmarkCallbacks()
        resetRunState()
        exposesEditorSuggestions = false
        state = .segmenting
        progressStage = .segmenting

        let summary = fixtureEvaluator.runDeterministicBaseline(
            dictionaryStore: dictionaryStore,
            modelVariant: modelVariant
        )
        benchmarkSummary = summary
        runSummary = AIConnectorRunSummary(
            reviewMode: .deterministic,
            modelVariant: modelVariant,
            processedSegmentCount: summary.totalCount,
            suggestionCount: summary.evaluations.filter {
                $0.actualStatus == .suggestion
            }.count,
            needsReviewCount: summary.evaluations.filter {
                $0.actualStatus == .needsReview
            }.count,
            noSuggestionCount: summary.evaluations.filter {
                $0.actualStatus == .noSuggestion
            }.count,
            recoveredCount: 0,
            rejectedCount: summary.evaluations.filter { !$0.passed }.count,
            skippedSegmentCount: 0,
            totalSegmentCount: summary.totalCount
        )
        progressStage = .completed
        state = .completed
    }

    func runBenchmark() {
        guard canRunBenchmark else { return }

        cancelRunningTask()
        service.cancelLoading()
        clearBenchmarkCallbacks()
        resetRunState()
        exposesEditorSuggestions = false

        let runMode = reviewMode
        let runModelVariant = modelVariant
        let runThinkingEnabled = thinkingEnabled
        let runGenerationProfilePreset = generationProfilePreset
        let operationID = UUID()
        let samples = AIConnectorSample.samples
        activeOperationID = operationID
        state = .segmenting
        progressStage = .segmenting
        benchmarkRunner.onSemanticProgress = { [weak self] progress in
            guard let self, self.activeOperationID == operationID else { return }
            self.downloadProgress = progress
            self.progressStage = progress < 1
                ? .semanticModelDownload
                : .semanticRetrieval
            self.state = progress < 1
                ? .downloading(progress)
                : .reviewing(
                    current: self.currentReviewIndex(
                        fallback: max(self.processedSegmentCount + 1, 1)
                    ),
                    total: samples.count
                )
        }
        benchmarkRunner.onDownloadProgress = { [weak self] progress in
            guard let self, self.activeOperationID == operationID else { return }
            self.downloadProgress = progress
            self.progressStage = .modelDownload
            self.state = .downloading(progress)
        }
        benchmarkRunner.onProgressStage = { [weak self] stage in
            guard let self, self.activeOperationID == operationID else { return }
            self.progressStage = stage
            switch stage {
            case .semanticModelDownload:
                self.state = .downloading(self.downloadProgress)
            case .semanticRetrieval, .modelLoading, .generation:
                self.state = .reviewing(
                    current: self.currentReviewIndex(
                        fallback: max(self.processedSegmentCount + 1, 1)
                    ),
                    total: samples.count
                )
            default:
                break
            }
        }
        benchmarkRunner.onGenerationProgress = { [weak self] characters in
            guard let self, self.activeOperationID == operationID else { return }
            self.generationProgress = characters
            self.progressStage = .generation
            self.state = .reviewing(
                current: self.currentReviewIndex(
                    fallback: max(self.processedSegmentCount + 1, 1)
                ),
                total: samples.count
            )
        }

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let report = try await benchmarkRunner.run(
                    mode: runMode,
                    modelVariant: runModelVariant,
                    thinkingEnabled: runThinkingEnabled,
                    samples: samples,
                    generationProfilePreset: runGenerationProfilePreset,
                    progress: { [weak self] current, total in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.state = .reviewing(current: current, total: total)
                    }
                )
                try Task.checkCancellation()
                guard activeOperationID == operationID else { return }

                benchmarkReport = report
                benchmarkSummary = report.legacySummary
                runSummary = makeRunSummary(from: report)
                latestGenerationMetrics = latestMetrics(from: report.records)
                currentSegmentPreview = ""
                currentGlossaryMatches = []
                clearBenchmarkCallbacks()
                progressStage = .completed
                state = .completed
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                clearBenchmarkCallbacks()
                progressStage = .cancelled
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                clearBenchmarkCallbacks()
                progressStage = .failed
                errorMessage = error.localizedDescription
                state = .failed(errorMessage ?? "Benchmark model gagal dijalankan.")
                task = nil
            }
        }
    }

    func run(documentText: String) {
        guard canRun(documentText: documentText) else {
            errorMessage = "Pilih atau masukkan teks sebelum menjalankan model."
            progressStage = .failed
            state = .failed(errorMessage ?? "Input tidak tersedia.")
            return
        }

        cancelRunningTask()
        service.cancelLoading()
        clearBenchmarkCallbacks()
        resetRunState()
        exposesEditorSuggestions = inputSource == .currentDocument

        let sourceText = sourceText(documentText: documentText)
        editorSourceText = inputSource == .currentDocument ? sourceText : ""
        let sampleForRun = inputSource == .dummy ? selectedSample : nil
        let runMode = reviewMode
        let runModelVariant = modelVariant
        let runThinkingEnabled = thinkingEnabled
        let runGenerationProfilePreset = generationProfilePreset
        let operationID = UUID()
        activeOperationID = operationID
        state = .segmenting
        progressStage = .segmenting

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let segmentation = segmenter.segment(documentText: sourceText)
                guard activeOperationID == operationID else { return }

                segmentationResult = segmentation
                queueBatchSizes = AIConnectorWorkQueue.batchSizes(
                    for: segmentation.segments.count
                )
                skippedSegmentCount = 0
                guard !segmentation.segments.isEmpty else {
                    throw QwenSuggestionError.emptyInput
                }

                let total = segmentation.segments.count

                let protectionContext = segmentProcessor.protectionContext(
                    for: sourceText
                )
                let stream = await workQueue.start(
                    runID: operationID,
                    segments: segmentation.segments,
                    mode: runMode,
                    modelVariant: runModelVariant,
                    thinkingEnabled: runThinkingEnabled,
                    documentProtectionContext: protectionContext,
                    downloadProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeOperationID == operationID else { return }
                            self.downloadProgress = progress
                            self.progressStage = .modelDownload
                            self.state = .downloading(progress)
                        }
                    },
                    generationProgress: { [weak self] characters in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.generationProgress = characters
                        self.progressStage = .generation
                        self.state = .reviewing(
                            current: self.currentReviewIndex(
                                fallback: max(
                                    self.processedSegmentCount + self.skippedSegmentCount + 1,
                                    1
                                )
                            ),
                            total: total
                        )
                    },
                    semanticProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeOperationID == operationID else { return }
                            self.downloadProgress = progress
                            self.progressStage = progress < 1
                                ? .semanticModelDownload
                                : .semanticRetrieval
                            self.state = progress < 1
                                ? .downloading(progress)
                                : .reviewing(
                                    current: self.currentReviewIndex(
                                        fallback: max(
                                            self.processedSegmentCount + self.skippedSegmentCount + 1,
                                            1
                                        )
                                    ),
                                    total: total
                                )
                        }
                    },
                    progressStage: { [weak self] stage in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.progressStage = stage
                        switch stage {
                        case .semanticModelDownload:
                            self.state = .downloading(self.downloadProgress)
                        case .semanticRetrieval, .modelLoading, .generation:
                            self.state = .reviewing(
                                current: self.currentReviewIndex(
                                    fallback: max(
                                        self.processedSegmentCount + self.skippedSegmentCount + 1,
                                        1
                                    )
                                ),
                                total: total
                            )
                        default:
                            break
                        }
                    },
                    generationProfile: runGenerationProfilePreset.profile(
                        for: runModelVariant,
                        thinkingEnabled: runThinkingEnabled
                    )
                )

                for await event in stream {
                    try Task.checkCancellation()
                    guard activeOperationID == operationID else { return }

                    switch event {
                    case let .stateChanged(segmentID, segmentState):
                        currentQueueState = segmentState
                        let zeroBasedSegmentIndex = max(segmentID - 1, 0)
                        currentBatchIndex = zeroBasedSegmentIndex / LegalTextSegmenter.batchSize + 1
                        currentBatchSize = queueBatchSizes.indices.contains(
                            zeroBasedSegmentIndex / LegalTextSegmenter.batchSize
                        )
                            ? queueBatchSizes[zeroBasedSegmentIndex / LegalTextSegmenter.batchSize]
                            : nil
                        if let segment = segmentation.segments.first(where: { $0.id == segmentID }) {
                            currentSegmentPreview = segment.targetText
                        }
                        switch segmentState {
                        case .generating, .parsing, .validating, .preparing, .retrieving:
                            if segmentState == .preparing || segmentState == .retrieving {
                                progressStage = .semanticRetrieval
                            } else if progressStage != .modelDownload {
                                progressStage = .modelLoading
                            }
                            state = .reviewing(
                                current: max(processedSegmentCount + skippedSegmentCount + 1, 1),
                                total: total
                            )
                        case .skipped, .completed, .noSuggestion, .needsReview, .rejected,
                             .failed, .cancelled, .pending:
                            break
                        }

                    case let .result(result):
                        apply(result: result)
                        await workQueue.acknowledgeResult()

                    case let .progress(current, total):
                        state = .reviewing(current: min(current + 1, total), total: total)

                    case .circuitBreakerActivated:
                        circuitBreakerActivated = true
                        errorMessage = "Model dialihkan ke pemulihan deterministik untuk sisa dokumen."

                    case let .finished(summary):
                        runSummary = summary
                        currentQueueState = summary.wasPartial ? .cancelled : .completed
                        currentSegmentPreview = summary.wasPartial ? currentSegmentPreview : ""
                        if let sampleForRun {
                            fixtureEvaluation = fixtureEvaluator.evaluate(
                                sample: sampleForRun,
                                reviews: validatedReviews
                            )
                        }
                        progressStage = summary.wasPartial ? .cancelled : .completed
                        state = summary.wasPartial ? .cancelled : .completed

                    case let .failed(message):
                        errorMessage = message
                        progressStage = .failed
                        state = .failed(message)
                    }
                }
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                progressStage = .cancelled
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                errorMessage = error.localizedDescription
                progressStage = .failed
                state = .failed(errorMessage ?? "Model gagal dijalankan.")
                task = nil
            }
        }
    }

    func resetInputMetadata() {
        cancelRunningTask()
        service.cancelLoading()
        workQueue.requestCancellation()
        Task { await workQueue.cancel() }
        clearBenchmarkCallbacks()
        resetRunState()
        progressStage = .idle
        state = .idle
    }

    func cancel() {
        guard isRunning else { return }
        activeOperationID = nil
        cancelRunningTask()
        service.cancelLoading()
        workQueue.requestCancellation()
        Task { await workQueue.cancel() }
        clearBenchmarkCallbacks()
        runSummary = currentPartialSummary()
        progressStage = .cancelled
        state = .cancelled
    }

    func selectSuggestion(_ id: UUID?) {
        guard let id,
              editorSuggestions.contains(where: { $0.id == id })
        else {
            selectedSuggestionID = nil
            return
        }

        selectedSuggestionID = id
    }

    func dismissSuggestion(_ id: UUID) {
        editorSuggestions.removeAll { $0.id == id }
        if selectedSuggestionID == id {
            selectedSuggestionID = nil
        }
    }

    func reconcileAfterAccept(_ id: UUID, replacementDelta: Int) {
        editorSuggestions = EditorSuggestionReconciler.afterAccept(
            suggestions: editorSuggestions,
            acceptedID: id,
            replacementDelta: replacementDelta
        )
        selectedSuggestionID = nil
    }

    func clearEditorSuggestions() {
        editorSuggestions = []
        selectedSuggestionID = nil
    }

    private func sourceText(documentText: String) -> String {
        switch inputSource {
        case .currentDocument:
            // The old 4,000-character limit is now preview-only. Queueing
            // receives the complete document so later segments are not lost.
            documentText
        case .dummy:
            selectedSample.text
        }
    }

    private func cancelRunningTask() {
        task?.cancel()
        task = nil
    }

    private func currentReviewIndex(fallback: Int) -> Int {
        if case let .reviewing(current, _) = state {
            return current
        }
        return fallback
    }

    private func clearBenchmarkCallbacks() {
        benchmarkRunner.onDownloadProgress = nil
        benchmarkRunner.onSemanticProgress = nil
        benchmarkRunner.onGenerationProgress = nil
        benchmarkRunner.onProgressStage = nil
    }

    private func apply(result: AIConnectorSegmentResult) {
        currentSegmentPreview = result.segment.targetText
        currentGlossaryMatches = result.glossaryMatches
        currentCandidates = result.candidates
        currentCandidateDecisions = result.candidateDecisions
        if let generationMetrics = result.generationMetrics {
            latestGenerationMetrics = generationMetrics
        }

        if !result.glossaryMatches.isEmpty {
            glossarySnapshots.append(
                AIReviewGlossarySnapshot(
                    segment: result.segment,
                    matches: result.glossaryMatches
                )
            )
        }

        validatedReviews.append(contentsOf: result.reviews)
        rejectedReviews.append(contentsOf: result.rejections)
        if let definitionAssessment = result.definitionAssessment {
            definitionAssessments.append(definitionAssessment)
        }
        definitionModelCallCount += result.definitionModelCallCount
        if result.skipped {
            skippedSegmentCount += 1
        } else {
            processedSegmentCount += 1
        }
        if result.cacheHit { cacheHitCount += 1 }
        if result.firstPassSucceeded { firstPassSuccessCount += 1 }
        if result.repairAttempted { repairAttemptCount += 1 }
        if result.usedFallback { fallbackCount += 1 }
        candidateCount += result.candidates.count
        acceptedCandidateCount += result.candidateDecisions.filter {
            $0.decision == .accept
        }.count
        modelCallCount += result.modelCallCount
        challengeCount += result.challengeCount
        noSuggestionCount += result.reviews.filter {
            $0.status == .noSuggestion
        }.count

        if exposesEditorSuggestions {
            editorSuggestions = EditorSuggestionMapper.make(
                reviews: validatedReviews,
                documentText: editorSourceText
            )
        }
        updateOutput()
        runSummary = currentPartialSummary()
    }

    private func currentPartialSummary() -> AIConnectorRunSummary {
        AIConnectorRunSummary(
            reviewMode: reviewMode,
            modelVariant: modelVariant,
            processedSegmentCount: processedSegmentCount,
            suggestionCount: acceptedSuggestionCount,
            needsReviewCount: needsReviewCount,
            noSuggestionCount: noSuggestionCount,
            recoveredCount: validatedReviews.filter {
                $0.origin == .deterministicFallback
            }.count,
            rejectedCount: rejectedReviews.count,
            skippedSegmentCount: skippedSegmentCount,
            totalSegmentCount: segmentationResult?.segments.count ?? processedSegmentCount,
            cacheHitCount: cacheHitCount,
            firstPassSuccessCount: firstPassSuccessCount,
            repairAttemptCount: repairAttemptCount,
            fallbackCount: fallbackCount,
            circuitBreakerActivated: circuitBreakerActivated,
            wasPartial: true,
            candidateCount: candidateCount,
            acceptedCandidateCount: acceptedCandidateCount,
            modelCallCount: modelCallCount,
            challengeCount: challengeCount
        )
    }

    private func resetRunState() {
        activeOperationID = nil
        progressStage = .idle
        errorMessage = nil
        downloadProgress = 0
        generationProgress = 0
        latestGenerationMetrics = nil
        currentSegmentPreview = ""
        currentGlossaryMatches = []
        currentCandidates = []
        currentCandidateDecisions = []
        currentQueueState = nil
        currentBatchIndex = nil
        currentBatchSize = nil
        queueBatchSizes = []
        glossarySnapshots = []
        segmentationResult = nil
        validatedReviews = []
        rejectedReviews = []
        definitionAssessments = []
        definitionModelCallCount = 0
        processedSegmentCount = 0
        skippedSegmentCount = 0
        noSuggestionCount = 0
        cacheHitCount = 0
        firstPassSuccessCount = 0
        repairAttemptCount = 0
        fallbackCount = 0
        candidateCount = 0
        acceptedCandidateCount = 0
        modelCallCount = 0
        challengeCount = 0
        circuitBreakerActivated = false
        output = ""
        runSummary = nil
        fixtureEvaluation = nil
        benchmarkSummary = nil
        benchmarkReport = nil
        clearEditorSuggestions()
        exposesEditorSuggestions = false
        editorSourceText = ""
    }

    private func makeRunSummary(
        from report: AIConnectorBenchmarkReport
    ) -> AIConnectorRunSummary {
        let records = report.records
        let candidateRecords = report.candidateRecords
        let statusCount: (AIReviewStatus) -> Int = { status in
            records.filter { $0.validatedStatus == status.rawValue }.count
        }

        let candidateCount = candidateRecords.isEmpty
            ? records.reduce(0) { $0 + ($1.candidateID == nil ? 0 : 1) }
            : candidateRecords.count
        let acceptedCandidateCount = candidateRecords.isEmpty
            ? records.filter { $0.candidateDecision == .accept }.count
            : candidateRecords.filter { $0.decision == .accept }.count
        let modelCallCount = candidateRecords.isEmpty
            ? records.reduce(0) { $0 + $1.modelCallCount }
            : candidateRecords.reduce(0) { $0 + $1.attemptCount }
        let challengeCount = candidateRecords.isEmpty
            ? records.filter(\.challengeAttempted).count
            : candidateRecords.filter(\.challengeAttempted).count

        return AIConnectorRunSummary(
            reviewMode: report.reviewMode,
            modelVariant: report.modelVariant,
            processedSegmentCount: records.filter { !$0.skipped }.count,
            suggestionCount: statusCount(.suggestion),
            needsReviewCount: statusCount(.needsReview),
            noSuggestionCount: statusCount(.noSuggestion),
            recoveredCount: records.filter(\.wasFallback).count,
            rejectedCount: records.filter(\.outputWasRejected).count,
            skippedSegmentCount: records.filter(\.skipped).count,
            totalSegmentCount: records.count,
            cacheHitCount: records.filter(\.cacheHit).count,
            firstPassSuccessCount: records.filter(\.firstPassSucceeded).count,
            repairAttemptCount: records.filter(\.repairAttempted).count,
            fallbackCount: records.filter(\.wasFallback).count,
            candidateCount: candidateCount,
            acceptedCandidateCount: acceptedCandidateCount,
            modelCallCount: modelCallCount,
            challengeCount: challengeCount
        )
    }

    private func latestMetrics(
        from records: [AIConnectorBenchmarkRecord]
    ) -> AIConnectorGenerationMetrics? {
        for record in records.reversed() {
            guard let promptTokenCount = record.promptTokenCount,
                  let generationTokenCount = record.generationTokenCount,
                  let promptDuration = record.promptDuration,
                  let generationDuration = record.generationDuration,
                  let stopReason = record.stopReason else {
                continue
            }
            return AIConnectorGenerationMetrics(
                promptTokenCount: promptTokenCount,
                generationTokenCount: generationTokenCount,
                promptDuration: promptDuration,
                generationDuration: generationDuration,
                stopReason: stopReason
            )
        }
        return nil
    }

    private func updateOutput() {
        output = validatedReviews
            .compactMap { review in
                guard review.status == .suggestion,
                      let original = review.original,
                      let replacement = review.replacement,
                      !original.isEmpty,
                      !replacement.isEmpty,
                      original != replacement else {
                    return nil
                }

                let category = review.category.displayTitle.isEmpty
                    ? nil
                    : review.category.displayTitle
                let heading = category.map {
                    "[\(review.status.displayTitle) • \($0)]"
                } ?? "[\(review.status.displayTitle)]"
                return """
                \(heading)
                Original: \(original)
                Replacement: \(replacement)
                Alasan: \(review.reason)
                Sumber: \(review.origin.displayTitle)
                """
            }
            .joined(separator: "\n\n")
    }
}
