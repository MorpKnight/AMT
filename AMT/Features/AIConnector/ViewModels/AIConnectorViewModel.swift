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
    var reviewMode: AIConnectorReviewMode = .deterministic
    var modelVariant: AIConnectorModelVariant = .qwen35_2b

    private(set) var state: AIConnectorRunState = .idle
    private(set) var errorMessage: String?
    private(set) var downloadProgress = 0.0
    private(set) var generationProgress = 0
    private(set) var currentSegmentPreview = ""
    private(set) var currentGlossaryMatches: [LegalDictionaryMatch] = []
    private(set) var glossarySnapshots: [AIReviewGlossarySnapshot] = []
    private(set) var segmentationResult: AITextSegmentationResult?
    private(set) var validatedReviews: [AIValidatedReview] = []
    private(set) var rejectedReviews: [AIReviewRejection] = []
    private(set) var processedSegmentCount = 0
    private(set) var skippedSegmentCount = 0
    private(set) var noSuggestionCount = 0
    private(set) var output = ""
    private(set) var runSummary: AIConnectorRunSummary?
    private(set) var fixtureEvaluation: AIConnectorFixtureEvaluation?
    private(set) var benchmarkSummary: AIConnectorBenchmarkSummary?
    private(set) var editorSuggestions: [EditorSuggestion] = []
    private(set) var selectedSuggestionID: UUID?

    private let service: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore
    private let segmenter = LegalTextSegmenter()
    private let outputParser = AIConnectorOutputParser()
    private let suggestionValidator = AIConnectorSuggestionValidator()
    private let deterministicSuggestionEngine = AIConnectorDeterministicSuggestionEngine()
    private let fixtureEvaluator = AIConnectorFixtureEvaluator()
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
        resetRunState()
        exposesEditorSuggestions = false
        state = .segmenting

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
            skippedSegmentCount: 0
        )
        state = .completed
    }

    func runBenchmark() {
        guard canRunBenchmark else { return }

        if reviewMode == .deterministic {
            runDeterministicBenchmark()
            return
        }

        cancelRunningTask()
        service.cancelLoading()
        resetRunState()
        exposesEditorSuggestions = false

        let runMode = reviewMode
        let runModelVariant = modelVariant
        let runThinkingEnabled = thinkingEnabled
        let operationID = UUID()
        let samples = AIConnectorSample.samples
        activeOperationID = operationID
        state = .segmenting

        task = Task { [weak self] in
            guard let self else { return }

            let startedAt = Date()

            do {
                var evaluations: [AIConnectorFixtureEvaluation] = []

                for (index, sample) in samples.enumerated() {
                    try Task.checkCancellation()
                    guard activeOperationID == operationID else { return }

                    let segmentation = segmenter.segment(documentText: sample.text)
                    skippedSegmentCount += segmentation.omittedSegmentCount

                    guard let segment = segmentation.segments.first else {
                        evaluations.append(fixtureEvaluator.evaluate(sample: sample, reviews: []))
                        continue
                    }

                    let current = index + 1
                    currentSegmentPreview = segment.targetText
                    let glossaryMatches = dictionaryStore.suggestionCandidates(
                        for: segment.targetText,
                        limit: 1
                    )
                    currentGlossaryMatches = glossaryMatches
                    if !glossaryMatches.isEmpty {
                        glossarySnapshots.append(
                            AIReviewGlossarySnapshot(
                                segment: segment,
                                matches: glossaryMatches
                            )
                        )
                    }
                    generationProgress = 0
                    state = .reviewing(current: current, total: samples.count)

                    let reviewCountBefore = validatedReviews.count

                    do {
                        let rawOutput = try await service.review(
                            segment: segment,
                            thinkingEnabled: runThinkingEnabled,
                            glossaryMatches: glossaryMatches,
                            downloadProgress: { [weak self] progress in
                                Task { @MainActor [weak self] in
                                    guard let self, self.activeOperationID == operationID else { return }
                                    self.downloadProgress = progress
                                    self.state = .downloading(progress)
                                }
                            },
                            generationProgress: { [weak self] tokenCount in
                                guard let self, self.activeOperationID == operationID else { return }
                                self.generationProgress = tokenCount
                                self.state = .reviewing(current: current, total: samples.count)
                            },
                            modelVariant: runModelVariant
                        )
                        try Task.checkCancellation()
                        guard activeOperationID == operationID else { return }

                        do {
                            let parsedReview = try outputParser.parse(rawOutput)

                            do {
                                let validatedReview = try suggestionValidator.validate(
                                    parsedReview,
                                    for: segment,
                                    glossaryMatches: glossaryMatches
                                )
                                accept(validatedReview)
                            } catch let validationError as AIConnectorValidationError {
                                handleRejectedModelOutput(
                                    segment: segment,
                                    rawOutput: rawOutput,
                                    reason: validationError.message,
                                    validationError: validationError,
                                    modelStatus: parsedReview.status,
                                    glossaryMatches: glossaryMatches,
                                    mode: runMode
                                )
                            }
                        } catch let parserError as AIConnectorOutputParserError {
                            handleRejectedModelOutput(
                                segment: segment,
                                rawOutput: rawOutput,
                                reason: parserError.message,
                                glossaryMatches: glossaryMatches,
                                mode: runMode
                            )
                        }
                    } catch let qwenError as QwenSuggestionError {
                        if case .segmentTooLong = qwenError {
                            skippedSegmentCount += 1
                            recordRejection(
                                segment: segment,
                                rawOutput: "",
                                reason: qwenError.localizedDescription,
                                countsAsProcessed: false
                            )
                        } else {
                            throw qwenError
                        }
                    }

                    let newReviews = Array(validatedReviews.dropFirst(reviewCountBefore))
                    evaluations.append(
                        fixtureEvaluator.evaluate(sample: sample, reviews: newReviews)
                    )
                }

                guard activeOperationID == operationID, !Task.isCancelled else { return }

                benchmarkSummary = AIConnectorBenchmarkSummary(
                    title: "Benchmark \(runMode.title)",
                    reviewMode: runMode,
                    modelVariant: runModelVariant,
                    duration: Date().timeIntervalSince(startedAt),
                    evaluations: evaluations
                )
                runSummary = AIConnectorRunSummary(
                    reviewMode: runMode,
                    modelVariant: runModelVariant,
                    processedSegmentCount: processedSegmentCount,
                    suggestionCount: acceptedSuggestionCount,
                    needsReviewCount: needsReviewCount,
                    noSuggestionCount: noSuggestionCount,
                    recoveredCount: validatedReviews.filter {
                        $0.origin == .deterministicFallback
                    }.count,
                    rejectedCount: rejectedReviews.count,
                    skippedSegmentCount: skippedSegmentCount
                )
                currentSegmentPreview = ""
                currentGlossaryMatches = []
                state = .completed
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                errorMessage = error.localizedDescription
                state = .failed(errorMessage ?? "Benchmark model gagal dijalankan.")
                task = nil
            }
        }
    }

    func run(documentText: String) {
        guard canRun(documentText: documentText) else {
            errorMessage = "Pilih atau masukkan teks sebelum menjalankan model."
            state = .failed(errorMessage ?? "Input tidak tersedia.")
            return
        }

        cancelRunningTask()
        service.cancelLoading()
        resetRunState()
        exposesEditorSuggestions = inputSource == .currentDocument

        let sourceText = sourceText(documentText: documentText)
        editorSourceText = inputSource == .currentDocument ? sourceText : ""
        let sampleForRun = inputSource == .dummy ? selectedSample : nil
        let runMode = reviewMode
        let runModelVariant = modelVariant
        let operationID = UUID()
        activeOperationID = operationID
        state = .segmenting

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let segmentation = segmenter.segment(documentText: sourceText)
                guard activeOperationID == operationID else { return }

                segmentationResult = segmentation
                skippedSegmentCount = segmentation.omittedSegmentCount
                guard !segmentation.segments.isEmpty else {
                    throw QwenSuggestionError.emptyInput
                }

                let total = segmentation.segments.count
                state = runMode.usesModel && !service.hasLoadedModel(for: runModelVariant)
                    ? .loading
                    : .reviewing(current: 1, total: total)

                for (index, segment) in segmentation.segments.enumerated() {
                    try Task.checkCancellation()
                    guard activeOperationID == operationID else { return }

                    let current = index + 1
                    currentSegmentPreview = segment.targetText
                    let glossaryMatches = dictionaryStore.suggestionCandidates(
                        for: segment.targetText,
                        limit: 1
                    )
                    currentGlossaryMatches = glossaryMatches
                    if !glossaryMatches.isEmpty {
                        glossarySnapshots.append(
                            AIReviewGlossarySnapshot(
                                segment: segment,
                                matches: glossaryMatches
                            )
                        )
                    }
                    generationProgress = 0
                    state = .reviewing(current: current, total: total)

                    if runMode == .deterministic {
                        do {
                            let parsedReview = deterministicSuggestionEngine.review(
                                for: segment,
                                glossaryMatches: glossaryMatches
                            )
                            let validatedReview = try suggestionValidator.validate(
                                parsedReview,
                                for: segment,
                                glossaryMatches: glossaryMatches,
                                origin: .deterministic
                            )
                            accept(validatedReview)
                        } catch let validationError as AIConnectorValidationError {
                            recordRejection(
                                segment: segment,
                                rawOutput: "",
                                reason: validationError.message
                            )
                        }
                        continue
                    }

                    do {
                        let rawOutput = try await service.review(
                            segment: segment,
                            thinkingEnabled: thinkingEnabled,
                            glossaryMatches: glossaryMatches,
                            downloadProgress: { [weak self] progress in
                                Task { @MainActor [weak self] in
                                    guard let self, self.activeOperationID == operationID else { return }
                                    self.downloadProgress = progress
                                    self.state = .downloading(progress)
                                }
                            },
                            generationProgress: { [weak self] tokenCount in
                                guard let self, self.activeOperationID == operationID else { return }
                                self.generationProgress = tokenCount
                                self.state = .reviewing(current: current, total: total)
                            },
                            modelVariant: runModelVariant
                        )
                        try Task.checkCancellation()
                        guard activeOperationID == operationID else { return }

                        do {
                            let parsedReview = try outputParser.parse(rawOutput)

                            do {
                                let validatedReview = try suggestionValidator.validate(
                                    parsedReview,
                                    for: segment,
                                    glossaryMatches: glossaryMatches
                                )
                                accept(validatedReview)
                            } catch let validationError as AIConnectorValidationError {
                                handleRejectedModelOutput(
                                    segment: segment,
                                    rawOutput: rawOutput,
                                    reason: validationError.message,
                                    validationError: validationError,
                                    modelStatus: parsedReview.status,
                                    glossaryMatches: glossaryMatches,
                                    mode: runMode
                                )
                            }
                        } catch let parserError as AIConnectorOutputParserError {
                            handleRejectedModelOutput(
                                segment: segment,
                                rawOutput: rawOutput,
                                reason: parserError.message,
                                glossaryMatches: glossaryMatches,
                                mode: runMode
                            )
                        }
                    } catch let qwenError as QwenSuggestionError {
                        if case .segmentTooLong = qwenError {
                            if let segmentationResult {
                                self.segmentationResult = AITextSegmentationResult(
                                    segments: segmentationResult.segments,
                                    headingCount: segmentationResult.headingCount,
                                    tooLongSegmentCount: segmentationResult.tooLongSegmentCount + 1,
                                    omittedSegmentCount: segmentationResult.omittedSegmentCount
                                )
                            }
                            skippedSegmentCount += 1
                            recordRejection(
                                segment: segment,
                                rawOutput: "",
                                reason: qwenError.localizedDescription,
                                countsAsProcessed: false
                            )
                            continue
                        }
                        throw qwenError
                    }
                }

                guard activeOperationID == operationID, !Task.isCancelled else { return }
                runSummary = AIConnectorRunSummary(
                    reviewMode: runMode,
                    modelVariant: runModelVariant,
                    processedSegmentCount: processedSegmentCount,
                    suggestionCount: acceptedSuggestionCount,
                    needsReviewCount: needsReviewCount,
                    noSuggestionCount: noSuggestionCount,
                    recoveredCount: validatedReviews.filter {
                        $0.origin == .deterministicFallback
                    }.count,
                    rejectedCount: rejectedReviews.count,
                    skippedSegmentCount: skippedSegmentCount
                )
                currentSegmentPreview = ""
                currentGlossaryMatches = []
                if let sampleForRun {
                    fixtureEvaluation = fixtureEvaluator.evaluate(
                        sample: sampleForRun,
                        reviews: validatedReviews
                    )
                }
                state = .completed
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                errorMessage = error.localizedDescription
                state = .failed(errorMessage ?? "Model gagal dijalankan.")
                task = nil
            }
        }
    }

    func resetInputMetadata() {
        cancelRunningTask()
        service.cancelLoading()
        resetRunState()
        state = .idle
    }

    func cancel() {
        guard isRunning else { return }
        activeOperationID = nil
        cancelRunningTask()
        service.cancelLoading()
        clearEditorSuggestions()
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
            String(documentText.prefix(Self.maximumDocumentCharacters))
        case .dummy:
            selectedSample.text
        }
    }

    private func cancelRunningTask() {
        task?.cancel()
        task = nil
    }

    private func resetRunState() {
        activeOperationID = nil
        errorMessage = nil
        downloadProgress = 0
        generationProgress = 0
        currentSegmentPreview = ""
        currentGlossaryMatches = []
        glossarySnapshots = []
        segmentationResult = nil
        validatedReviews = []
        rejectedReviews = []
        processedSegmentCount = 0
        skippedSegmentCount = 0
        noSuggestionCount = 0
        output = ""
        runSummary = nil
        fixtureEvaluation = nil
        benchmarkSummary = nil
        clearEditorSuggestions()
        exposesEditorSuggestions = false
        editorSourceText = ""
    }

    private func recordRejection(
        segment: AIReviewSegment,
        rawOutput: String,
        reason: String,
        countsAsProcessed: Bool = true
    ) {
        rejectedReviews.append(
            AIReviewRejection(
                segment: segment,
                rawOutput: rawOutput,
                reason: reason
            )
        )
        if countsAsProcessed {
            processedSegmentCount += 1
        }
    }

    private func handleRejectedModelOutput(
        segment: AIReviewSegment,
        rawOutput: String,
        reason: String,
        validationError: AIConnectorValidationError? = nil,
        modelStatus: AIReviewStatus? = nil,
        glossaryMatches: [LegalDictionaryMatch],
        mode: AIConnectorReviewMode
    ) {
        guard mode == .hybrid else {
            recordRejection(
                segment: segment,
                rawOutput: rawOutput,
                reason: reason
            )
            return
        }

        let fallback: AIParsedReview?
        if let deterministicSuggestion = deterministicSuggestionEngine.suggestion(
            for: segment,
            glossaryMatches: glossaryMatches
        ) {
            fallback = deterministicSuggestion
        } else if validationError == .replacementUnchanged
                    || modelStatus == .noSuggestion
                    || rawOutput
                    .components(separatedBy: .newlines)
                    .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "STATUS: NO_SUGGESTION" }) {
            fallback = deterministicSuggestionEngine.noSuggestion(for: segment)
        } else {
            fallback = nil
        }

        if let fallback,
           let validatedFallback = try? suggestionValidator.validate(
               fallback,
               for: segment,
               glossaryMatches: glossaryMatches,
               origin: .deterministicFallback
           ) {
            recordRejection(
                segment: segment,
                rawOutput: rawOutput,
                reason: reason,
                countsAsProcessed: false
            )
            accept(validatedFallback)
            return
        }

        recordRejection(
            segment: segment,
            rawOutput: rawOutput,
            reason: reason
        )
    }

    private func accept(_ review: AIValidatedReview) {
        validatedReviews.append(review)
        processedSegmentCount += 1
        if review.status == .noSuggestion {
            noSuggestionCount += 1
        }
        if exposesEditorSuggestions {
            editorSuggestions = EditorSuggestionMapper.make(
                reviews: validatedReviews,
                documentText: editorSourceText
            )
        }
        updateOutput()
    }

    private func updateOutput() {
        output = validatedReviews.map { review in
            let original = review.original ?? review.segment.targetText
            let replacement = review.replacement ?? "-"
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
