import Foundation
import Observation

@MainActor
@Observable
final class AIConnectorViewModel {
    private static let previewCharacters = 2_000
    static let maximumDocumentCharacters = 4_000
    private static let analysisPipelineVersion = [
        "document-analysis-v1",
        "phase7-incremental-analysis-v1",
        "review-pipeline-phase4-context-profile-v1",
        AIConnectorDocumentReviewDetector.version,
        AIConnectorPhaseTwoPolicy.version,
        "fingerprint-v\(DocumentFingerprint.currentVersion)",
        "snapshot-v\(DocumentAnalysisSnapshot.currentVersion)",
        QwenSuggestionService.promptVersion,
        QwenSuggestionService.outputSchemaVersion,
        QwenSuggestionService.candidatePromptVersion,
        QwenSuggestionService.candidateOutputSchemaVersion,
        QwenSuggestionService.definitionPromptVersion,
        QwenSuggestionService.definitionOutputSchemaVersion,
        QwenSuggestionService.contextPromptVersion,
        QwenSuggestionService.contextOutputSchemaVersion,
        QwenSuggestionService.riskPromptVersion,
        QwenSuggestionService.riskOutputSchemaVersion,
        QwenSuggestionService.definitionResolutionPromptVersion,
        QwenSuggestionService.definitionResolutionOutputSchemaVersion,
        AIConnectorDefinitionResolution.version,
        AIConnectorDocumentStructure.currentVersion,
        AIConnectorDocumentContextProfile.extractorVersion,
        AIConnectorDocumentContextProfile.classifierVersion,
        AIConnectorSuggestionValidator.version,
        AIConnectorRuleStore.currentVersion,
        AIConnectorLanguageScorerConfiguration.pipelineVersion
    ].joined(separator: "|")
    private static let phaseZeroBaselinePipelineVersion = [
        "document-analysis-v1",
        "phase7-incremental-analysis-v1",
        "review-pipeline-phase4-context-profile-v1",
        AIConnectorDocumentReviewDetector.version,
        AIConnectorPhaseTwoPolicy.disabledVersion,
        "fingerprint-v\(DocumentFingerprint.currentVersion)",
        "snapshot-v\(DocumentAnalysisSnapshot.currentVersion)",
        QwenSuggestionService.promptVersion,
        QwenSuggestionService.outputSchemaVersion,
        QwenSuggestionService.candidatePromptVersion,
        QwenSuggestionService.candidateOutputSchemaVersion,
        QwenSuggestionService.definitionPromptVersion,
        QwenSuggestionService.definitionOutputSchemaVersion,
        QwenSuggestionService.contextPromptVersion,
        QwenSuggestionService.contextOutputSchemaVersion,
        QwenSuggestionService.riskPromptVersion,
        QwenSuggestionService.riskOutputSchemaVersion,
        QwenSuggestionService.definitionResolutionPromptVersion,
        QwenSuggestionService.definitionResolutionOutputSchemaVersion,
        AIConnectorDefinitionResolution.version,
        AIConnectorDocumentStructure.currentVersion,
        AIConnectorDocumentContextProfile.extractorVersion,
        AIConnectorDocumentContextProfile.classifierVersion,
        AIConnectorSuggestionValidator.version,
        AIConnectorRuleStore.currentVersion,
        AIConnectorLanguageScorerConfiguration.pipelineVersion
    ].joined(separator: "|")

    var inputSource: AIConnectorInputSource = .currentDocument
    var selectedSampleID = "redundant-wajib-untuk"
    var thinkingEnabled = false
    var reviewMode: AIConnectorReviewMode = .hybrid
    var modelVariant: AIConnectorModelVariant = .qwen35Base4B
    var generationProfilePreset: AIConnectorGenerationProfilePreset = .greedy

    private(set) var state: AIConnectorRunState = .idle
    private(set) var progressStage: AIConnectorProgressStage = .idle
    private(set) var analysisStartedAt: Date
    private(set) var lastProgressActivityAt: Date
    private(set) var errorMessage: String?
    private(set) var downloadProgress = 0.0
    private(set) var semanticDownloadProgress = 0.0
    private(set) var modelDownloadProgress = 0.0
    private(set) var languageModelProgress = 0.0
    private(set) var generationProgress = 0
    private(set) var analysisProgress = 0.0
    private(set) var latestGenerationMetrics: AIConnectorGenerationMetrics?
    private(set) var currentSegmentPreview = ""
    private(set) var currentSegmentID: Int? = nil
    private(set) var currentGlossaryMatches: [LegalDictionaryMatch] = []
    private(set) var currentCandidates: [AIConnectorReviewCandidate] = []
    private(set) var currentCandidateDecisions: [AIConnectorCandidateDecisionRecord] = []
    private(set) var currentCandidateRoutes: [AIConnectorPhaseTwoCandidateRoute] = []
    private(set) var currentQueueState: AIConnectorQueueState?
    private(set) var currentBatchIndex: Int?
    private(set) var currentBatchSize: Int?
    private(set) var queueBatchSizes: [Int] = []
    private(set) var glossarySnapshots: [AIReviewGlossarySnapshot] = []
    private(set) var segmentationResult: AITextSegmentationResult?
    private(set) var documentStructure: AIConnectorDocumentStructure?
    private(set) var documentContextProfile: AIConnectorDocumentContextProfile?
    private(set) var contextStructureDuration: TimeInterval = 0
    private(set) var contextExtractionDuration: TimeInterval = 0
    private(set) var contextSegmentationDuration: TimeInterval = 0
    private(set) var contextPreparationDuration: TimeInterval = 0
    private(set) var contextClassificationDuration: TimeInterval = 0
    private(set) var contextPreparationCacheHit = false
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
#if DEBUG
    private(set) var phaseZeroBaselineReport: AIConnectorBaselineSuiteReport?
    private(set) var phaseZeroBaselineProgress: AIConnectorPhaseZeroProgress?
    private(set) var phaseTwoComparisonReport: AIConnectorPhaseTwoComparisonReport?
    private(set) var phaseTwoComparisonProgress: AIConnectorPhaseTwoComparisonProgress?
    private(set) var incrementalBenchmarkReport: AIConnectorIncrementalBenchmarkReport?
    let phaseEightQualityPolicy = AIConnectorQualityPolicy.diagnosticDefault()
    let phaseEightFixtureStore = AIConnectorQualityFixtureStore()
    var phaseEightQualityReport: AIConnectorQualityEvaluationReport?
    var phaseEightQualityProgress: AIConnectorQualityRunProgress?
    var phaseEightQualityNotice: String?
#endif
    private(set) var editorSuggestions: [EditorSuggestion] = []
    private(set) var reviewAnnotations: [EditorReviewAnnotation] = []
    private(set) var definitionMatchAnnotations: [EditorReviewAnnotation] = []
    private(set) var definitionResolutions: [UUID: AIConnectorDefinitionResolution] = [:]
    private(set) var definitionResolutionMetrics: [UUID: AIConnectorDefinitionResolutionMetrics] = [:]
    private(set) var definitionResolutionLoadingIDs: Set<UUID> = []
    private(set) var ignoredReviewItemIDs: Set<UUID> = []
    private(set) var documentFindings: [AIConnectorDocumentFinding] = []
    private(set) var reviewedReviewItemIDs: Set<UUID> = []
    var showReviewedFindings = false
    private(set) var documentFindingMetrics = AIConnectorDocumentReviewMetrics()
    private(set) var definitionDebugSuggestions: [EditorSuggestion] = []
    private(set) var selectedReviewItemID: UUID?
    private(set) var caretUTF16Location: Int?
    private(set) var analysisRunScope: AIConnectorAnalysisRunScope = .fullFresh
    private(set) var pendingAnalysisPlan: AIConnectorAnalysisPlan?
    private(set) var incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics()
    private(set) var reusedSegmentCount = 0
    private(set) var reprocessedSegmentCount = 0
    private(set) var hasPendingAnalysisChanges = false

    private let service: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore
    private let segmenter = LegalTextSegmenter()
    private let documentContextCoordinator: AIConnectorDocumentContextCoordinator
    private let documentReviewDetector = AIConnectorDocumentReviewDetector()
    private let definitionResolutionService: AIConnectorDefinitionResolutionService
    private let incrementalPlanner = AIConnectorIncrementalAnalysisPlanner()
    private let fixtureEvaluator = AIConnectorFixtureEvaluator()
    private let benchmarkRunner: AIConnectorBenchmarkRunner
#if DEBUG
    private let phaseZeroBaselineRunner: AIConnectorPhaseZeroBaselineRunner
    private let phaseTwoComparisonRunner: AIConnectorPhaseTwoComparisonRunner
#endif
    private let workQueue: AIConnectorWorkQueue
    private let segmentProcessor: AIConnectorSegmentProcessor
    private let now: () -> Date
    private var task: Task<Void, Never>?
#if DEBUG
    private var phaseZeroBaselineTask: Task<Void, Never>?
    private var phaseZeroOperationID: UUID?
    private var phaseTwoComparisonTask: Task<Void, Never>?
    private var phaseTwoOperationID: UUID?
    private var observationCollector: AIConnectorObservationCollector?
    private(set) var observationReport: AIConnectorObservationReport?
    var phaseEightQualityTask: Task<Void, Never>?
#endif
    private var activeOperationID: UUID?
    private var lastQueueSegmentID: Int?
    private var lastQueueState: AIConnectorQueueState?
    private var lastQueueProgressCurrent: Int?
    private var lastQueueProgressTotal: Int?
    private var progressTracker = AIConnectorProgressTracker()
    private static let generationProgressUpdateInterval: TimeInterval = 0.1
    private var lastGenerationProgressPublicationAt: Date?
    private var exposesEditorSuggestions = false
    private var analysisSnapshotEligible = false
    private var editorSourceText = ""
    private var contextPreparationCache = AIConnectorAnalysisLRUCache<AIConnectorDocumentContextPreparation>()
    private var documentReviewCache = AIConnectorAnalysisLRUCache<AIConnectorDocumentReviewResult>()
    private var definitionResolutionCache = AIConnectorAnalysisLRUCache<AIConnectorDefinitionResolutionResult>()
    private var definitionResolutionOperationIDs: [UUID: UUID] = [:]
    private var analysisBaseline: AIConnectorAnalysisBaseline?
    private var activeAnalysisPlan: AIConnectorAnalysisPlan?
    private var activeAnalysisRunStartedAt: Date?
    private var firstIncrementalResultAt: Date?
    private var completedRunSegmentIDs: Set<Int> = []
    private var incrementalCacheLookupCount = 0

    init(
        service: QwenSuggestionService,
        dictionaryStore: LegalDictionaryStore,
        now: @escaping () -> Date = { Date() },
        contextClassifier: AIConnectorDocumentContextClassificationHandler? = nil
    ) {
        let initialDate = now()
        self.now = now
        self.analysisStartedAt = initialDate
        self.lastProgressActivityAt = initialDate
        self.service = service
        self.dictionaryStore = dictionaryStore
        self.definitionResolutionService = AIConnectorDefinitionResolutionService(
            dictionaryStore: dictionaryStore
        )
        self.documentContextCoordinator = AIConnectorDocumentContextCoordinator(
            service: service,
            classifier: contextClassifier
        )
        let segmentCache = AIConnectorSegmentCache()
        let processor = AIConnectorSegmentProcessor(
            service: service,
            dictionaryStore: dictionaryStore,
            ruleStore: AIConnectorRuleStore(),
            segmentCache: segmentCache,
            enableCandidateChallenge: false,
            enablePhaseTwo: true
        )
        self.segmentProcessor = processor
        self.workQueue = AIConnectorWorkQueue(processor: processor)
        let benchmarkRunner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: dictionaryStore
        )
        self.benchmarkRunner = benchmarkRunner
#if DEBUG
        let phaseTwoBenchmarkRunner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: dictionaryStore,
            enablePhaseTwo: true
        )
        self.phaseZeroBaselineRunner = AIConnectorPhaseZeroBaselineRunner(
            benchmarkRunner: benchmarkRunner,
            modelVariant: .qwen35Base4B,
            pipelineVersion: Self.phaseZeroBaselinePipelineVersion,
            corpusVersion: dictionaryStore.activeCorpusVersion
        )
        self.phaseTwoComparisonRunner = AIConnectorPhaseTwoComparisonRunner(
            phaseOneRunner: benchmarkRunner,
            phaseTwoRunner: phaseTwoBenchmarkRunner,
            pipelineVersion: Self.analysisPipelineVersion
        )
#endif
    }

    var isRunning: Bool {
        state.isRunning
    }

    /// Compatibility read-only alias for the pre-Phase-3 editor surface.
    var selectedSuggestionID: UUID? {
        selectedReviewItemID
    }

    var completedSegmentCount: Int {
        reusedSegmentCount + processedSegmentCount + skippedSegmentCount
    }

    var totalSegmentCount: Int {
        segmentationResult?.segments.count ?? 0
    }

    var progressSnapshot: AIConnectorProgressSnapshot {
        let phaseFraction: Double?
        switch progressStage {
        case .semanticModelDownload:
            phaseFraction = clamped(semanticDownloadProgress)
        case .modelDownload:
            phaseFraction = clamped(modelDownloadProgress)
        case .languageModelDownload, .languageModelLoading, .languageScoring:
            phaseFraction = clamped(languageModelProgress)
        default:
            phaseFraction = nil
        }

        return AIConnectorProgressSnapshot(
            stage: progressStage,
            overallFraction: totalSegmentCount > 0 ? analysisProgress : nil,
            phaseFraction: phaseFraction,
            completedSegmentCount: completedSegmentCount,
            totalSegmentCount: totalSegmentCount,
            currentSegmentID: currentSegmentID,
            generationCharacters: generationProgress,
            startedAt: analysisStartedAt,
            lastActivityAt: lastProgressActivityAt,
            reusedSegmentCount: reusedSegmentCount,
            reprocessedSegmentCount: reprocessedSegmentCount,
            pendingSegmentCount: max(
                totalSegmentCount - completedSegmentCount,
                0
            )
        )
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

    var definitionMatchCount: Int {
        definitionAssessments.filter { $0.alignment == .matches }.count
    }

    var definitionMismatchCount: Int {
        definitionAssessments.filter { $0.alignment == .mismatch }.count
    }

    var definitionNeedsReviewCount: Int {
        definitionAssessments.filter { $0.alignment == .needsReview }.count
    }

    var reviewItems: [EditorReviewItem] {
        reviewItems(includeDefinitionMatches: false)
    }

    func reviewItems(includeDefinitionMatches: Bool) -> [EditorReviewItem] {
        var items = editorSuggestions
            .filter { !ignoredReviewItemIDs.contains($0.id) }
            .map(EditorReviewItem.suggestion)
            + reviewAnnotations
                .filter {
                    !ignoredReviewItemIDs.contains($0.id)
                        && shouldDisplay(annotation: $0)
                }
                .map(EditorReviewItem.annotation)

        if includeDefinitionMatches {
            items += definitionMatchAnnotations
                .filter {
                    !ignoredReviewItemIDs.contains($0.id)
                        && shouldDisplay(annotation: $0)
                }
                .map(EditorReviewItem.annotation)
        }

        return items.sorted { lhs, rhs in
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            let lhsPriority = reviewItemPriority(lhs)
            let rhsPriority = reviewItemPriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.sourceRange.length != rhs.sourceRange.length {
                return lhs.sourceRange.length < rhs.sourceRange.length
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var selectedReviewIndex: Int? {
        guard let selectedReviewItemID,
              let index = reviewItems.firstIndex(where: { $0.id == selectedReviewItemID }) else {
            return nil
        }
        return index
    }

    func selectReviewItem(_ id: UUID?) {
        guard let id,
              reviewItems(includeDefinitionMatches: true).contains(where: { $0.id == id }) else {
            selectedReviewItemID = nil
            return
        }
        selectedReviewItemID = id
    }

    /// Tracks the editor caret so a section rerun can be requested even when
    /// no review item is active at that location.
    func updateCaretLocation(_ location: Int?) {
        guard let location, location >= 0 else {
            caretUTF16Location = nil
            return
        }
        caretUTF16Location = location
    }

    func selectNextReviewItem(includeDefinitionMatches: Bool = false) {
        selectRelativeReviewItem(offset: 1, includeDefinitionMatches: includeDefinitionMatches)
    }

    func selectPreviousReviewItem(includeDefinitionMatches: Bool = false) {
        selectRelativeReviewItem(offset: -1, includeDefinitionMatches: includeDefinitionMatches)
    }

    private func selectRelativeReviewItem(
        offset: Int,
        includeDefinitionMatches: Bool
    ) {
        let items = reviewItems(includeDefinitionMatches: includeDefinitionMatches)
        guard !items.isEmpty else {
            selectedReviewItemID = nil
            return
        }

        guard let selectedReviewItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedReviewItemID }) else {
            selectedReviewItemID = offset > 0 ? items.first?.id : items.last?.id
            return
        }

        let nextIndex = currentIndex + offset
        guard items.indices.contains(nextIndex) else { return }
        self.selectedReviewItemID = items[nextIndex].id
    }

    private func reviewItemPriority(_ item: EditorReviewItem) -> Int {
        switch item {
        case .suggestion:
            1
        case let .annotation(annotation):
            annotation.definitionDiagnosticStatus == .matches ? 2 : 0
        }
    }

    private func shouldDisplay(annotation: EditorReviewAnnotation) -> Bool {
        guard reviewedReviewItemIDs.contains(annotation.id) else { return true }
        guard annotation.kind == .definedTerm || annotation.kind == .legalRisk else {
            return true
        }
        return showReviewedFindings
    }

    func setShowReviewedFindings(_ isShown: Bool) {
        showReviewedFindings = isShown
        if !isShown,
           let selectedReviewItemID,
           !reviewItems(includeDefinitionMatches: true).contains(where: {
               $0.id == selectedReviewItemID
           }) {
            self.selectedReviewItemID = nil
        }
    }

    func markReviewItemReviewed(_ id: UUID) {
        guard let annotation = reviewAnnotations.first(where: { $0.id == id }),
              annotation.kind == .definedTerm || annotation.kind == .legalRisk,
              !ignoredReviewItemIDs.contains(id) else { return }
        reviewedReviewItemIDs.insert(id)
        if selectedReviewItemID == id {
            selectedReviewItemID = nil
        }
    }

    func reopenReviewItem(_ id: UUID) {
        reviewedReviewItemIDs.remove(id)
    }

    var activeDocumentFindingCount: Int {
        documentFindings.filter {
            !ignoredReviewItemIDs.contains($0.id)
                && !reviewedReviewItemIDs.contains($0.id)
        }.count
    }

    var reviewedDocumentFindingCount: Int {
        documentFindings.filter {
            !ignoredReviewItemIDs.contains($0.id)
                && reviewedReviewItemIDs.contains($0.id)
        }.count
    }

    var totalReviewItemCount: Int {
        editorSuggestions.count
            + reviewAnnotations.count
            + definitionMatchAnnotations.count
    }

    var allReviewItemsIgnored: Bool {
        !ignoredReviewItemIDs.isEmpty && totalReviewItemCount == 0
    }

    func visibleReviewAnnotations(includeDefinitionMatches: Bool) -> [EditorReviewAnnotation] {
        let base = reviewAnnotations.filter {
            !ignoredReviewItemIDs.contains($0.id) && shouldDisplay(annotation: $0)
        }
        guard includeDefinitionMatches else { return base }
        return base + definitionMatchAnnotations.filter {
            !ignoredReviewItemIDs.contains($0.id) && shouldDisplay(annotation: $0)
        }
    }

    var glossaryCandidateCount: Int {
        glossarySnapshots.reduce(0) { count, snapshot in
            count + snapshot.matches.count
        }
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

    var currentAnalysisProfile: AIConnectorAnalysisProfile {
        AIConnectorAnalysisProfile(
            pipelineVersion: Self.analysisPipelineVersion,
            reviewMode: reviewMode,
            modelVariant: modelVariant,
            thinkingEnabled: thinkingEnabled,
            generationProfilePreset: generationProfilePreset,
            corpusVersion: dictionaryStore.activeCorpusVersion,
            semanticModelRevision: dictionaryStore.semanticModelRevision,
            semanticEmbeddingSchema: dictionaryStore.semanticEmbeddingSchema,
            semanticRetrievalProfile: dictionaryStore.semanticRetrievalProfile
        )
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
#if DEBUG
        guard phaseZeroBaselineTask == nil,
              phaseTwoComparisonTask == nil else { return false }
#endif
        return !sourceText(documentText: documentText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// Marks the current editor revision as stale without starting a new
    /// analysis. Typing is intentionally cheap; the user chooses when the
    /// potentially expensive rerun begins.
    func markDocumentEdited(
        documentText: String,
        structuredDocument: StructuredDocument? = nil
    ) {
        guard inputSource == .currentDocument else { return }

        if isRunning {
            cancel()
        }

        guard documentText != editorSourceText || !hasPendingAnalysisChanges else {
            return
        }

        let oldBaseline = analysisBaseline
        editorSourceText = documentText
        analysisSnapshotEligible = false
        selectedReviewItemID = nil
        invalidateDefinitionResolutionState()

        guard let oldBaseline else {
            invalidateResultsForUnplannedEdit()
            return
        }

        let currentStructure = AIConnectorDocumentStructureBuilder().build(
            documentText: documentText,
            structuredDocument: structuredDocument
        )
        let currentSegmentation = segmenter.segment(
            documentText: documentText,
            structure: currentStructure,
            profile: oldBaseline.profile
        )
        let plan = incrementalPlanner.makePlan(
            previous: oldBaseline,
            documentText: documentText,
            structure: currentStructure,
            segmentation: currentSegmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: currentAnalysisProfile
        )
        let preserved = incrementalPlanner.rematerialize(
            reviews: validatedReviews,
            assessments: definitionAssessments,
            findings: documentFindings,
            baseline: oldBaseline,
            plan: plan,
            newText: documentText,
            newSegmentation: currentSegmentation
        )

        documentStructure = currentStructure
        documentContextProfile = nil
        segmentationResult = currentSegmentation
        validatedReviews = preserved.reviews
        definitionAssessments = preserved.assessments
        documentFindings = preserved.findings
        let preservedIDs = Set(
            validatedReviews.map(\.id)
                + definitionAssessments.map { EditorSuggestionMapper.definitionAnnotationID(for: $0) }
                + documentFindings.map(\.id)
        )
        ignoredReviewItemIDs = ignoredReviewItemIDs.intersection(preservedIDs)
        reviewedReviewItemIDs = reviewedReviewItemIDs.intersection(preservedIDs)
        rejectedReviews = []
        glossarySnapshots = []
        rebuildEditorMappings()
        resetTransientAnalysisState(keepDocumentContext: true)
        updateOutput()

        pendingAnalysisPlan = plan
        activeAnalysisPlan = nil
        analysisRunScope = .incrementalDocument
        hasPendingAnalysisChanges = true
        reusedSegmentCount = plan.reusedSegmentCount
        reprocessedSegmentCount = plan.reprocessedSegmentCount
        incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(
            scope: .incrementalDocument,
            reusedSegmentCount: plan.reusedSegmentCount,
            reprocessedSegmentCount: plan.reprocessedSegmentCount,
            invalidatedSegmentCount: plan.reprocessedSegmentCount,
            wasPartial: false
        )

        // Keep a baseline for the current revision so another edit before a
        // rerun can be planned from the already materialized anchors. Profile
        // extraction remains outside the typing path and is refreshed when
        // the user starts the expensive rerun.
        analysisBaseline = AIConnectorAnalysisBaseline(
            documentText: documentText,
            structure: currentStructure,
            profile: oldBaseline.profile,
            segmentation: currentSegmentation,
            analysisProfile: currentAnalysisProfile,
            validatedReviews: validatedReviews,
            definitionAssessments: definitionAssessments,
            documentFindings: documentFindings,
            ignoredReviewItemIDs: ignoredReviewItemIDs,
            reviewedReviewItemIDs: reviewedReviewItemIDs
        )
        setProgressStage(.idle)
        state = .idle
    }

    /// Reruns only the changed parts and their proven dependencies.
    func rerunIncrementally(
        documentText: String,
        structuredDocument: StructuredDocument? = nil
    ) {
        run(
            documentText: documentText,
            structuredDocument: structuredDocument,
            scope: .incrementalDocument
        )
    }

    /// Reruns the selected section. A section request is expanded by the
    /// planner when a document-level dependency makes that necessary.
    func rerunSelectedSection(
        documentText: String,
        structuredDocument: StructuredDocument? = nil
    ) {
        guard let sectionID = selectedSectionID() else { return }
        run(
            documentText: documentText,
            structuredDocument: structuredDocument,
            scope: .section,
            selectedSectionID: sectionID
        )
    }

    /// Discards all reusable results and performs a fresh full-document run.
    func rerunFullFresh(
        documentText: String,
        structuredDocument: StructuredDocument? = nil
    ) {
        run(
            documentText: documentText,
            structuredDocument: structuredDocument,
            scope: .fullFresh
        )
    }

    var canRerunSelectedSection: Bool {
        selectedSectionID() != nil && !isRunning
    }

    var canRerunAnalysis: Bool {
        !isRunning
            && !editorSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func selectedSectionID() -> String? {
        guard let structure = documentStructure else { return nil }

        if let selectedReviewItemID,
           let item = reviewItems(includeDefinitionMatches: true)
               .first(where: { $0.id == selectedReviewItemID }),
           let block = structure.blocks
               .filter({
                   item.sourceRange.location >= $0.sourceRange.location
                       && NSMaxRange(item.sourceRange) <= NSMaxRange($0.sourceRange)
               })
               .min(by: { $0.sourceRange.length < $1.sourceRange.length }) {
            return block.kind == .heading ? block.id : block.parentSectionID
        }

        guard let caretUTF16Location,
              caretUTF16Location >= 0,
              caretUTF16Location <= editorSourceText.utf16.count,
              let block = structure.blocks
                  .filter({
                      caretUTF16Location >= $0.sourceRange.location
                          && caretUTF16Location <= NSMaxRange($0.sourceRange)
                  })
                  .min(by: { $0.sourceRange.length < $1.sourceRange.length }) else {
            return nil
        }
        return block.kind == .heading ? block.id : block.parentSectionID
    }

    private func invalidateResultsForUnplannedEdit() {
        analysisBaseline = nil
        pendingAnalysisPlan = nil
        activeAnalysisPlan = nil
        hasPendingAnalysisChanges = true
        reusedSegmentCount = 0
        reprocessedSegmentCount = 0
        clearEditorSuggestions()
        resetTransientAnalysisState(keepDocumentContext: false)
        documentStructure = nil
        documentContextProfile = nil
        segmentationResult = nil
        setProgressStage(.idle)
        state = .idle
    }

    private func invalidateDefinitionResolutionState() {
        definitionResolutions = [:]
        definitionResolutionMetrics = [:]
        definitionResolutionLoadingIDs = []
        definitionResolutionOperationIDs.removeAll()
        definitionResolutionCache.removeAll()
    }

    var canRunBenchmark: Bool {
        guard !isRunning else { return false }
#if DEBUG
        guard phaseZeroBaselineTask == nil,
              phaseTwoComparisonTask == nil else { return false }
#endif
        return true
    }

    func runDeterministicBenchmark() {
        guard canRunBenchmark else { return }

        cancelRunningTask()
        service.cancelLoading()
        clearBenchmarkCallbacks()
        resetRunState()
        exposesEditorSuggestions = false
        state = .segmenting
        setProgressStage(.segmenting)

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
        setProgressStage(.completed)
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
        service.releaseIdleModels(except: runModelVariant)
        let operationID = UUID()
        let samples = AIConnectorSample.samples
        activeOperationID = operationID
        state = .segmenting
        beginProgressTracking()
        setProgressStage(.segmenting)
        benchmarkRunner.onSemanticProgress = { [weak self] progress in
            guard let self, self.activeOperationID == operationID else { return }
            self.updateSemanticDownloadProgress(progress)
            self.state = self.progressStage == .semanticModelDownload
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
            self.updateModelDownloadProgress(progress)
            if self.progressStage != .definitionReview {
                self.setProgressStage(.modelDownload)
                self.state = .downloading(progress)
            } else {
                self.state = .reviewing(
                    current: self.currentReviewIndex(
                        fallback: max(self.processedSegmentCount + 1, 1)
                    ),
                    total: samples.count
                )
            }
        }
        benchmarkRunner.onProgressStage = { [weak self] stage in
            guard let self, self.activeOperationID == operationID else { return }
            self.setProgressStage(stage)
            switch stage {
            case .semanticModelDownload:
                self.state = .downloading(self.downloadProgress)
            case .languageModelDownload, .languageModelLoading, .languageScoring:
                self.state = .loading
            case .semanticRetrieval, .modelLoading, .generation,
                 .definitionReview, .deterministicReview:
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
            self.publishGenerationProgress(
                characters: characters,
                total: samples.count,
                fallback: max(self.processedSegmentCount + 1, 1)
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
                setProgressStage(.completed)
                state = .completed
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                clearBenchmarkCallbacks()
                setProgressStage(.cancelled)
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
                clearBenchmarkCallbacks()
                setProgressStage(.failed)
                errorMessage = error.localizedDescription
                state = .failed(errorMessage ?? "Benchmark model gagal dijalankan.")
                task = nil
            }
        }
    }

#if DEBUG
    var isPhaseZeroBaselineRunning: Bool {
        phaseZeroBaselineTask != nil
    }

    func runPhaseZeroBaseline() {
        guard canRunBenchmark else { return }

        phaseZeroBaselineTask?.cancel()
        phaseZeroBaselineReport = nil
        phaseZeroBaselineProgress = AIConnectorPhaseZeroProgress(
            phase: "resourcePreparation",
            completedPhaseCount: 0,
            totalPhaseCount: AIConnectorPhaseZeroRunKind.allCases.count + 1,
            runKind: nil
        )
        let operationID = UUID()
        phaseZeroOperationID = operationID
        let runner = phaseZeroBaselineRunner
        phaseZeroBaselineTask = Task { @MainActor [weak self] in
            let report = await runner.run { [weak self] progress in
                guard let self, self.phaseZeroOperationID == operationID else { return }
                self.phaseZeroBaselineProgress = progress
            }
            guard let self, self.phaseZeroOperationID == operationID else { return }
            self.phaseZeroBaselineReport = report
            self.phaseZeroBaselineProgress = AIConnectorPhaseZeroProgress(
                phase: report.terminalStatus.rawValue,
                completedPhaseCount: report.runs.count
                    + (report.resourcePreparation == nil ? 0 : 1),
                totalPhaseCount: AIConnectorPhaseZeroRunKind.allCases.count + 1,
                runKind: report.runs.last?.kind
            )
            self.phaseZeroBaselineTask = nil
            self.phaseZeroOperationID = nil
        }
    }

    func cancelPhaseZeroBaseline() {
        phaseZeroBaselineTask?.cancel()
        service.cancelLoading()
    }

    var isPhaseTwoComparisonRunning: Bool {
        phaseTwoComparisonTask != nil
    }

    func runPhaseTwoComparison() {
        guard canRunBenchmark else { return }

        phaseTwoComparisonTask?.cancel()
        phaseTwoComparisonReport = nil
        phaseTwoComparisonProgress = AIConnectorPhaseTwoComparisonProgress(
            phase: "resourcePreparation",
            completedPhaseCount: 0,
            totalPhaseCount: 3,
            side: nil
        )
        let operationID = UUID()
        phaseTwoOperationID = operationID
        let runner = phaseTwoComparisonRunner
        let runMode = reviewMode
        let runModelVariant = modelVariant
        let runGenerationProfile = generationProfilePreset
        let runThinkingEnabled = thinkingEnabled
        phaseTwoComparisonTask = Task { @MainActor [weak self] in
            let report = await runner.run(
                mode: runMode,
                modelVariant: runModelVariant,
                generationProfile: runGenerationProfile,
                thinkingEnabled: runThinkingEnabled
            ) { [weak self] progress in
                guard let self, self.phaseTwoOperationID == operationID else { return }
                self.phaseTwoComparisonProgress = progress
            }
            guard let self, self.phaseTwoOperationID == operationID else { return }
            self.phaseTwoComparisonReport = report
            self.phaseTwoComparisonProgress = AIConnectorPhaseTwoComparisonProgress(
                phase: report.terminalStatus.rawValue,
                completedPhaseCount: report.runs.count
                    + (report.resourcePreparation == nil ? 0 : 1),
                totalPhaseCount: report.resourcePreparation == nil ? 2 : 3,
                side: report.runs.last?.side
            )
            self.phaseTwoComparisonTask = nil
            self.phaseTwoOperationID = nil
        }
    }

    func cancelPhaseTwoComparison() {
        phaseTwoComparisonTask?.cancel()
        service.cancelLoading()
    }

    func runIncrementalPlannerBenchmark(documentText: String) {
        incrementalBenchmarkReport = AIConnectorIncrementalBenchmarkRunner().run(
            documentText: documentText
        )
    }
#endif

    func run(
        documentText: String,
        structuredDocument: StructuredDocument? = nil,
        scope: AIConnectorAnalysisRunScope = .fullFresh,
        selectedSectionID: String? = nil
    ) {
        guard canRun(documentText: documentText) else {
            errorMessage = "Pilih atau masukkan teks sebelum menjalankan model."
            setProgressStage(.failed)
            state = .failed(errorMessage ?? "Input tidak tersedia.")
            return
        }

        cancelRunningTask()
        service.cancelLoading()
        clearBenchmarkCallbacks()

        let sourceText = sourceText(documentText: documentText)
        let sourceStructuredDocument = inputSource == .currentDocument ? structuredDocument : nil
        let sampleForRun = inputSource == .dummy ? selectedSample : nil
        let runMode = reviewMode
        let runModelVariant = modelVariant
        let runThinkingEnabled = thinkingEnabled
        let runGenerationProfilePreset = generationProfilePreset
        let structureSeed = AIConnectorDocumentStructureBuilder().build(
            documentText: sourceText,
            structuredDocument: sourceStructuredDocument
        )
        let profileSeed = AIConnectorDocumentContextProfileBuilder().build(
            documentText: sourceText,
            structure: structureSeed
        )
        let seedSegmentation = segmenter.segment(
            documentText: sourceText,
            structure: structureSeed,
            profile: profileSeed
        )
        let proposedPlan: AIConnectorAnalysisPlan?
        if scope == .fullFresh {
            proposedPlan = nil
        } else if let pendingAnalysisPlan,
                  pendingAnalysisPlan.changeSet.newTextFingerprint
                    == DocumentFingerprinting.contentSHA256(sourceText) {
            proposedPlan = pendingAnalysisPlan
        } else if let baseline = analysisBaseline {
            proposedPlan = incrementalPlanner.makePlan(
                previous: baseline,
                documentText: sourceText,
                structure: structureSeed,
                segmentation: seedSegmentation,
                scope: scope,
                selectedSectionID: selectedSectionID,
                currentAnalysisProfile: currentAnalysisProfile,
                currentProfile: profileSeed
            )
        } else {
            proposedPlan = nil
        }

        let canUseIncrementalPlan = proposedPlan.map { !$0.isFullRerun } ?? false
        if canUseIncrementalPlan, let plan = proposedPlan, let baseline = analysisBaseline {
            let preserved = incrementalPlanner.rematerialize(
                reviews: validatedReviews,
                assessments: definitionAssessments,
                findings: documentFindings,
                baseline: baseline,
                plan: plan,
                newText: sourceText,
                newSegmentation: seedSegmentation
            )
            validatedReviews = preserved.reviews
            definitionAssessments = preserved.assessments
            documentFindings = preserved.findings
            ignoredReviewItemIDs = ignoredReviewItemIDs.intersection(
                Set(validatedReviews.map(\.id)
                    + definitionAssessments.map { EditorSuggestionMapper.definitionAnnotationID(for: $0) }
                    + documentFindings.map(\.id))
            )
            reviewedReviewItemIDs = reviewedReviewItemIDs.intersection(
                Set(validatedReviews.map(\.id)
                    + definitionAssessments.map { EditorSuggestionMapper.definitionAnnotationID(for: $0) }
                    + documentFindings.map(\.id))
            )
            rebuildEditorMappings()
            resetTransientAnalysisState(keepDocumentContext: true)
            updateOutput()
            pendingAnalysisPlan = plan
            activeAnalysisPlan = plan
            reusedSegmentCount = plan.reusedSegmentCount
            reprocessedSegmentCount = plan.reprocessedSegmentCount
            incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(
                scope: scope,
                reusedSegmentCount: plan.reusedSegmentCount,
                reprocessedSegmentCount: plan.reprocessedSegmentCount,
                invalidatedSegmentCount: plan.reprocessedSegmentCount
            )
        } else {
            resetRunState()
            activeAnalysisPlan = nil
            pendingAnalysisPlan = nil
            reusedSegmentCount = 0
            reprocessedSegmentCount = 0
            incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(scope: scope)
        }

        exposesEditorSuggestions = inputSource == .currentDocument
        editorSourceText = inputSource == .currentDocument ? sourceText : ""
        analysisRunScope = scope
        hasPendingAnalysisChanges = false
        activeAnalysisRunStartedAt = now()
        firstIncrementalResultAt = nil
        let contextCacheKey = Self.contextPreparationCacheKey(
            documentText: sourceText,
            structure: structureSeed,
            modelVariant: runModelVariant,
            mode: runMode
        )
        let operationID = UUID()
        activeOperationID = operationID
        state = .segmenting
        beginProgressTracking()
        setProgressStage(.segmenting)
#if DEBUG
        let runObservationCollector = AIConnectorObservationCollector(
            runID: operationID,
            mode: runMode,
            modelVariant: runModelVariant,
            generationProfile: runGenerationProfilePreset.rawValue,
            thinkingEnabled: runThinkingEnabled,
            pipelineVersion: Self.analysisPipelineVersion,
            rulePackVersion: AIConnectorRuleStore.currentVersion,
            corpusVersion: dictionaryStore.activeCorpusVersion
        )
        observationCollector = runObservationCollector
        observationReport = nil
#endif

        let riskReviewer: AIConnectorDocumentReviewDetector.RiskReviewer?
        if runMode.usesModel {
            riskReviewer = { [service] request in
                try await service.reviewDocumentFinding(
                    request: request,
                    downloadProgress: { _ in },
                    generationProgress: { _ in }
                )
            }
        } else {
            riskReviewer = nil
        }

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let observationClock = ContinuousClock()
                let preparation: AIConnectorDocumentContextPreparation
                if let cachedPreparation = contextPreparationCache[contextCacheKey] {
                    preparation = cachedPreparation
                    contextPreparationCacheHit = true
                } else {
                    contextPreparationCacheHit = false
                    preparation = try await documentContextCoordinator.prepare(
                        documentText: sourceText,
                        structuredDocument: sourceStructuredDocument,
                        mode: runMode,
                        modelVariant: runModelVariant,
                        generationProfile: AIConnectorGenerationProfile(
                            maxTokens: 384,
                            temperature: 0,
                            topP: 1,
                            topK: 0,
                            presencePenalty: nil,
                            seed: 42
                        ),
                        downloadProgress: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                guard let self,
                                      self.activeOperationID == operationID else { return }
                                self.updateModelDownloadProgress(progress)
                                self.setProgressStage(.modelLoading)
                                self.state = .downloading(progress)
                            }
                        },
                        generationProgress: { [weak self] characters in
                            guard let self,
                                  self.activeOperationID == operationID else { return }
                            self.publishGenerationProgress(
                                characters: characters,
                                total: 1,
                                fallback: 1
                            )
                        },
                        stage: { [weak self] stage in
                            guard let self,
                                  self.activeOperationID == operationID else { return }
                            if stage == .classification {
                                self.setProgressStage(.modelLoading)
                            } else if stage == .segmentation {
                                self.setProgressStage(.segmenting)
                            }
                        }
                    )
                    contextPreparationCache[contextCacheKey] = preparation
                }
                guard activeOperationID == operationID else { return }

                documentStructure = preparation.structure
                documentContextProfile = preparation.profile
                contextStructureDuration = preparation.structureDuration
                contextExtractionDuration = preparation.extractionDuration
                contextSegmentationDuration = preparation.segmentationDuration
                contextPreparationDuration = preparation.preparationDuration
                contextClassificationDuration = preparation.classificationDuration
                let segmentation = preparation.segmentation
                guard activeOperationID == operationID else { return }

                segmentationResult = segmentation
                skippedSegmentCount = 0
                guard !segmentation.segments.isEmpty else {
                    throw QwenSuggestionError.emptyInput
                }

                let runPlan: AIConnectorAnalysisPlan
                if let activeAnalysisPlan {
                    runPlan = activeAnalysisPlan
                } else {
                    runPlan = .full(
                        scope: analysisRunScope,
                        documentText: sourceText,
                        segmentation: segmentation
                    )
                    activeAnalysisPlan = runPlan
                    pendingAnalysisPlan = runPlan
                }
                let segmentsToProcess = segmentation.segments.filter {
                    runPlan.reprocessSegmentIDs.contains($0.id)
                }
                queueBatchSizes = AIConnectorWorkQueue.batchSizes(
                    for: segmentsToProcess.count
                )
                reusedSegmentCount = runPlan.reusedSegmentCount
                reprocessedSegmentCount = runPlan.reprocessedSegmentCount
                incrementalCacheLookupCount = segmentsToProcess.count

                let documentFindingCacheKey = Self.documentReviewCacheKey(
                    documentText: sourceText,
                    structure: preparation.structure,
                    profile: preparation.profile,
                    mode: runMode,
                    modelVariant: runModelVariant
                )
                let documentReviewResult: AIConnectorDocumentReviewResult
                if !runPlan.requiresDocumentReview,
                   !runPlan.isFullRerun {
                    documentReviewResult = AIConnectorDocumentReviewResult(
                        findings: documentFindings,
                        metrics: documentFindingMetrics
                    )
                } else if let cachedFindingResult = documentReviewCache[documentFindingCacheKey] {
                    documentReviewResult = AIConnectorDocumentReviewResult(
                        findings: cachedFindingResult.findings,
                        metrics: cachedFindingResult.metrics.withCacheHit()
                    )
                } else {
                    let computedFindingResult = await documentReviewDetector.analyze(
                        documentText: sourceText,
                        structure: preparation.structure,
                        profile: preparation.profile,
                        mode: runMode,
                        modelVariant: runModelVariant,
                        riskReviewer: riskReviewer
                    )
                    guard activeOperationID == operationID else { return }
                    documentReviewResult = computedFindingResult
                    if !computedFindingResult.metrics.wasCancelled {
                        documentReviewCache[documentFindingCacheKey] = computedFindingResult
                    }
                }
                guard activeOperationID == operationID else { return }
                documentFindings = documentReviewResult.findings
                documentFindingMetrics = documentReviewResult.metrics
                if exposesEditorSuggestions {
                    rebuildEditorMappings()
                }

#if DEBUG
                await runObservationCollector.recordDocumentReview(
                    documentReviewResult.metrics
                )
                await runObservationCollector.setInputMetadata(
                    utf16Length: sourceText.utf16.count,
                    segmentCount: segmentation.segments.count
                )
                await runObservationCollector.recordStage(
                    .documentStructure,
                    duration: preparation.structureDuration
                )
                await runObservationCollector.recordStage(
                    .contextExtraction,
                    duration: preparation.extractionDuration
                )
                await runObservationCollector.recordStage(
                    .contextSegmentation,
                    duration: preparation.segmentationDuration
                )
                if preparation.classificationDuration > 0 {
                    await runObservationCollector.recordStage(
                        .contextClassification,
                        duration: preparation.classificationDuration
                    )
                }
#endif

                let total = max(segmentsToProcess.count, 1)

                let protectionStartedAt = observationClock.now
                let protectionContext = segmentProcessor.protectionContext(
                    for: sourceText,
                    additionalDefinedTerms: Set(
                        preparation.profile.definedTerms.map(\.value)
                    )
                )
#if DEBUG
                await runObservationCollector.recordStage(
                    .protectionContext,
                    duration: AIConnectorObservationTiming.seconds(
                        protectionStartedAt.duration(to: observationClock.now)
                    )
                )
#endif
#if DEBUG
                let activeObservationCollector = runObservationCollector
#else
                let activeObservationCollector: AIConnectorObservationCollector? = nil
#endif
                let stream = await workQueue.start(
                    runID: operationID,
                    segments: segmentsToProcess,
                    mode: runMode,
                    modelVariant: runModelVariant,
                    thinkingEnabled: runThinkingEnabled,
                    documentProtectionContext: protectionContext,
                    downloadProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeOperationID == operationID else { return }
                            self.updateModelDownloadProgress(progress)
                            if self.progressStage != .definitionReview {
                                self.setProgressStage(.modelDownload)
                                self.state = .downloading(progress)
                            } else {
                                self.state = .reviewing(
                                    current: self.currentReviewIndex(
                                        fallback: max(
                                            self.processedSegmentCount
                                                + self.skippedSegmentCount
                                                + 1,
                                            1
                                        )
                                    ),
                                    total: total
                                )
                            }
                        }
                    },
                    generationProgress: { [weak self] characters in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.publishGenerationProgress(
                            characters: characters,
                            total: total,
                            fallback: max(
                                self.processedSegmentCount + self.skippedSegmentCount + 1,
                                1
                            )
                        )
                    },
                    semanticProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeOperationID == operationID else { return }
                            self.updateSemanticDownloadProgress(progress)
                            self.state = self.progressStage == .semanticModelDownload
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
                    languageProgress: { [weak self] progress in
                        guard let self,
                              self.activeOperationID == operationID,
                              self.progressStage == .languageModelDownload
                                || self.progressStage == .languageModelLoading
                                || self.progressStage == .languageScoring else {
                            return
                        }
                        self.updateLanguageModelProgress(progress)
                    },
                    progressStage: { [weak self] stage in
                        guard let self, self.activeOperationID == operationID else { return }
                        self.setProgressStage(stage)
                        switch stage {
                        case .semanticModelDownload:
                            self.state = .downloading(self.downloadProgress)
                        case .languageModelDownload, .languageModelLoading, .languageScoring:
                            self.state = .loading
                        case .semanticRetrieval, .modelLoading, .generation,
                             .definitionReview, .deterministicReview:
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
                    ),
                    observationCollector: activeObservationCollector
                )

                for await event in stream {
                    try Task.checkCancellation()
                    guard activeOperationID == operationID else { return }

                    switch event {
                    case let .stateChanged(segmentID, segmentState):
                        let queueStateChanged = lastQueueSegmentID != segmentID
                            || lastQueueState != segmentState
                        lastQueueSegmentID = segmentID
                        lastQueueState = segmentState
                        currentSegmentID = segmentID
                        currentQueueState = segmentState
                        if queueStateChanged {
                            recordProgressActivity()
                        }
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
                        case .preparing, .retrieving:
                            setProgressStage(
                                runMode == .deterministic || circuitBreakerActivated
                                    ? .deterministicReview
                                    : .semanticRetrieval
                            )
                            state = .reviewing(
                                current: max(processedSegmentCount + skippedSegmentCount + 1, 1),
                                total: total
                            )
                        case .validating:
                            setProgressStage(.deterministicReview)
                            state = .reviewing(
                                current: max(processedSegmentCount + skippedSegmentCount + 1, 1),
                                total: total
                            )
                        case .generating, .parsing:
                            // The processor reports model loading/generation
                            // through the dedicated callbacks. Queue states
                            // must not overwrite those more precise phases.
                            state = .reviewing(
                                current: max(processedSegmentCount + skippedSegmentCount + 1, 1),
                                total: total
                            )
                        case .skipped, .completed, .noSuggestion, .needsReview, .rejected,
                             .failed, .cancelled, .pending:
                            break
                        }

                    case let .result(result):
                        await apply(result: result)
                        let acknowledgementClock = ContinuousClock()
                        let acknowledgementStartedAt = acknowledgementClock.now
                        await workQueue.acknowledgeResult()
#if DEBUG
                        if let observationCollector {
                            await observationCollector.recordStage(
                                .resultAcknowledgement,
                                duration: AIConnectorObservationTiming.seconds(
                                    acknowledgementStartedAt.duration(
                                        to: acknowledgementClock.now
                                    )
                                ),
                                segmentID: result.segment.id
                            )
                        }
#endif

                    case let .progress(current, total):
                        let queueProgressChanged = lastQueueProgressCurrent != current
                            || lastQueueProgressTotal != total
                        lastQueueProgressCurrent = current
                        lastQueueProgressTotal = total
                        if queueProgressChanged {
                            recordProgressActivity()
                        }
                        updateAnalysisProgressForCompletedSegments()
                        state = .reviewing(current: min(current + 1, total), total: total)

                    case .circuitBreakerActivated:
                        circuitBreakerActivated = true
                        errorMessage = "Model dialihkan ke pemulihan deterministik untuk sisa dokumen."

                    case let .finished(summary):
                        recordProgressActivity()
                        runSummary = currentSummary(wasPartial: summary.wasPartial)
                        currentQueueState = summary.wasPartial ? .cancelled : .completed
                        currentSegmentPreview = summary.wasPartial ? currentSegmentPreview : ""
                        currentSegmentID = summary.wasPartial ? currentSegmentID : nil
                        if let sampleForRun {
                            fixtureEvaluation = fixtureEvaluator.evaluate(
                                sample: sampleForRun,
                                reviews: validatedReviews
                            )
                        }
                        if !summary.wasPartial, exposesEditorSuggestions {
                            do {
                                try await prepareDefinitionResolutions(
                                    documentText: sourceText,
                                    mode: runMode,
                                    modelVariant: runModelVariant,
                                    operationID: operationID
                                )
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                // A resolution choice is an enhancement to a
                                // completed analysis. If its local anchor
                                // preparation fails, keep the normal review
                                // results and let the popover report that no
                                // resolution is currently available.
                                definitionResolutions = [:]
                                definitionResolutionMetrics = [:]
                            }
                        }
                        setProgressStage(summary.wasPartial ? .cancelled : .completed)
                        state = summary.wasPartial ? .cancelled : .completed
                        analysisSnapshotEligible = !summary.wasPartial
                        if summary.wasPartial {
                            let completed = completedRunSegmentIDs
                            let remaining = runPlan.reprocessSegmentIDs.subtracting(completed)
                            let nextChangeSet = AIConnectorAnalysisChangeSet(
                                scope: runPlan.changeSet.scope,
                                oldTextFingerprint: runPlan.changeSet.oldTextFingerprint,
                                newTextFingerprint: runPlan.changeSet.newTextFingerprint,
                                changedOldRanges: runPlan.changeSet.changedOldRanges,
                                changedNewRanges: runPlan.changeSet.changedNewRanges,
                                changedOldBlockIDs: runPlan.changeSet.changedOldBlockIDs,
                                changedBlockIDs: runPlan.changeSet.changedBlockIDs,
                                changedSectionIDs: runPlan.changeSet.changedSectionIDs,
                                reasons: runPlan.changeSet.reasons.union([.cancelled]),
                                isAmbiguous: runPlan.changeSet.isAmbiguous
                            )
                            let nextPlan = AIConnectorAnalysisPlan(
                                changeSet: nextChangeSet,
                                reusableSegmentIDs: runPlan.reusableSegmentIDs.union(completed),
                                reprocessSegmentIDs: remaining,
                                removedSegmentIDs: runPlan.removedSegmentIDs,
                                mappings: runPlan.mappings,
                                dependencySectionIDs: runPlan.dependencySectionIDs,
                                requiresProfileRebuild: runPlan.requiresProfileRebuild,
                                requiresDocumentReview: runPlan.requiresDocumentReview,
                                isFullRerun: runPlan.isFullRerun
                            )
                            pendingAnalysisPlan = nextPlan
                            activeAnalysisPlan = nil
                            hasPendingAnalysisChanges = !remaining.isEmpty
                            analysisBaseline = makeAnalysisBaseline()
                            incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(
                                scope: analysisRunScope,
                                reusedSegmentCount: nextPlan.reusedSegmentCount,
                                reprocessedSegmentCount: nextPlan.reprocessedSegmentCount,
                                invalidatedSegmentCount: nextPlan.reprocessedSegmentCount,
                                cacheLookupCount: incrementalCacheLookupCount,
                                cacheHitCount: cacheHitCount,
                                firstResultLatency: firstIncrementalResultAt.map {
                                    $0.timeIntervalSince(self.activeAnalysisRunStartedAt ?? $0)
                                },
                                totalDuration: activeAnalysisRunStartedAt.map {
                                    self.now().timeIntervalSince($0)
                                },
                                wasPartial: true
                            )
                        } else {
                            pendingAnalysisPlan = nil
                            activeAnalysisPlan = nil
                            hasPendingAnalysisChanges = false
                            analysisBaseline = makeAnalysisBaseline()
                            incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(
                                scope: analysisRunScope,
                                reusedSegmentCount: reusedSegmentCount,
                                reprocessedSegmentCount: reprocessedSegmentCount,
                                invalidatedSegmentCount: runPlan.reprocessSegmentIDs.count,
                                cacheLookupCount: incrementalCacheLookupCount,
                                cacheHitCount: cacheHitCount,
                                firstResultLatency: firstIncrementalResultAt.map {
                                    $0.timeIntervalSince(self.activeAnalysisRunStartedAt ?? $0)
                                },
                                totalDuration: activeAnalysisRunStartedAt.map {
                                    self.now().timeIntervalSince($0)
                                },
                                wasPartial: false
                            )
                        }
#if DEBUG
                        await runObservationCollector.setIncrementalAnalysisMetrics(
                            incrementalRunMetrics
                        )
                        if let observationCollector {
                            observationReport = await observationCollector.finish(
                                status: summary.wasPartial ? .cancelled : .completed
                            )
                        }
#endif

                    case let .failed(message):
                        errorMessage = message
                        setProgressStage(.failed)
                        state = .failed(message)
                    }
                }
                task = nil
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
#if DEBUG
                await runObservationCollector.setIncrementalAnalysisMetrics(
                    incrementalRunMetrics
                )
                if let observationCollector {
                    observationReport = await observationCollector.finish(status: .cancelled)
                }
#endif
                setProgressStage(.cancelled)
                state = .cancelled
                task = nil
            } catch {
                guard activeOperationID == operationID else { return }
#if DEBUG
                await runObservationCollector.setIncrementalAnalysisMetrics(
                    incrementalRunMetrics
                )
                if let observationCollector {
                    observationReport = await observationCollector.finish(
                        status: .failed,
                        failureCode: "analysis-failed"
                    )
                }
#endif
                errorMessage = error.localizedDescription
                setProgressStage(.failed)
                state = .failed(errorMessage ?? "Model gagal dijalankan.")
                task = nil
            }
        }
    }

    /// Creates the compact result that can be restored without loading Qwen.
    /// A snapshot is only valid after a complete current-document run.
    func makeAnalysisSnapshot(
        documentText: String,
        completedAt: Date? = nil
    ) -> DocumentAnalysisSnapshot? {
        guard inputSource == .currentDocument,
              exposesEditorSuggestions,
              analysisSnapshotEligible,
              state == .completed else {
            return nil
        }

        return DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(documentText),
            analysisProfile: currentAnalysisProfile,
            completedAt: completedAt ?? now(),
            runSummary: runSummary,
            editorSuggestions: editorSuggestions,
            reviewAnnotations: reviewAnnotations,
            definitionMatchAnnotations: definitionMatchAnnotations,
            ignoredReviewItemIDs: ignoredReviewItemIDs,
            documentFindings: documentFindings,
            reviewedReviewItemIDs: reviewedReviewItemIDs,
            definitionResolutions: Array(definitionResolutions.values)
                .sorted { $0.id < $1.id }
        )
    }

    /// Restores user-facing analysis output when the document and pipeline
    /// still match the snapshot. This method never starts a model run.
    @discardableResult
    func restoreAnalysisSnapshot(
        _ snapshot: DocumentAnalysisSnapshot,
        documentText: String
    ) -> Bool {
        guard snapshot.isCompatible(
            with: documentText,
            profile: currentAnalysisProfile
        ) else {
            resetInputMetadata()
            return false
        }

        resetInputMetadata()
        editorSourceText = documentText
        exposesEditorSuggestions = true
        analysisSnapshotEligible = true
        editorSuggestions = snapshot.editorSuggestions
        reviewAnnotations = snapshot.reviewAnnotations
        definitionMatchAnnotations = snapshot.definitionMatchAnnotations
        definitionResolutions = Dictionary(
            uniqueKeysWithValues: snapshot.definitionResolutions.compactMap { resolution in
                guard let annotationID = resolution.annotationID else { return nil }
                return (annotationID, resolution)
            }
        )
        definitionResolutionMetrics = [:]
        definitionResolutionLoadingIDs = []
        definitionResolutionCache.removeAll()
        ignoredReviewItemIDs = snapshot.ignoredReviewItemIDs
        documentFindings = snapshot.documentFindings
        reviewedReviewItemIDs = snapshot.reviewedReviewItemIDs
        showReviewedFindings = false
        documentFindingMetrics = AIConnectorDocumentReviewMetrics(
            findingCount: documentFindings.count,
            definedTermFindingCount: documentFindings.filter { $0.kind == .definedTerm }.count,
            legalRiskFindingCount: documentFindings.filter { $0.kind == .legalRisk }.count,
            internalReferenceFindingCount: documentFindings.filter { $0.kind == .internalReference }.count
        )
        definitionDebugSuggestions = []
        runSummary = snapshot.runSummary
        progressStage = .completed
        analysisProgress = 1
        state = .completed
        return true
    }

    func resetInputMetadata() {
#if DEBUG
        cancelPhaseTwoComparison()
#endif
        cancelRunningTask()
        service.cancelLoading()
        workQueue.requestCancellation()
        Task { await workQueue.cancel() }
        clearBenchmarkCallbacks()
        resetRunState()
        contextPreparationCache.removeAll()
        documentReviewCache.removeAll()
        definitionResolutionCache.removeAll()
        definitionResolutionOperationIDs.removeAll()
        setProgressStage(.idle)
        state = .idle
    }

    func cancel() {
#if DEBUG
        cancelPhaseTwoComparison()
#endif
        guard isRunning else { return }
        activeOperationID = nil
        cancelRunningTask()
        service.cancelLoading()
        workQueue.requestCancellation()
        Task { await workQueue.cancel() }
        clearBenchmarkCallbacks()
        preservePartialAnalysisForResume()
#if DEBUG
        if let collector = observationCollector {
            let metrics = incrementalRunMetrics
            Task { @MainActor [weak self] in
                await collector.setIncrementalAnalysisMetrics(metrics)
                let report = await collector.finish(status: .cancelled)
                self?.observationReport = report
            }
        }
#endif
        runSummary = currentPartialSummary()
        setProgressStage(.cancelled)
        state = .cancelled
    }

    func selectSuggestion(_ id: UUID?) {
        selectReviewItem(id)
    }

    func dismissSuggestion(_ id: UUID) {
        dismissReviewItem(id)
    }

    func dismissReviewItem(_ id: UUID) {
        guard reviewItems(includeDefinitionMatches: true).contains(where: { $0.id == id }) else {
            return
        }
        ignoredReviewItemIDs.insert(id)
        reviewedReviewItemIDs.remove(id)
        editorSuggestions.removeAll { $0.id == id }
        reviewAnnotations.removeAll { $0.id == id }
        definitionMatchAnnotations.removeAll { $0.id == id }
        definitionResolutions.removeValue(forKey: id)
        definitionResolutionMetrics.removeValue(forKey: id)
        definitionResolutionLoadingIDs.remove(id)
        definitionResolutionOperationIDs.removeValue(forKey: id)
        if selectedReviewItemID == id {
            selectedReviewItemID = nil
        }
    }

    /// Reconciles a single accepted edit against the still-current review
    /// session. The pre-edit text is required so a stale callback cannot move
    /// ranges or mutate the persisted review state.
    @discardableResult
    func reconcileAfterAccept(
        _ suggestion: EditorSuggestion,
        previousText: String,
        updatedText: String
    ) -> Bool {
        guard suggestion.kind == .language,
              suggestion.isAnchored(to: previousText) else {
            return false
        }

        let acceptedRange = suggestion.sourceRange
        let delta = suggestion.replacement.utf16.count - suggestion.original.utf16.count
        editorSuggestions = editorSuggestions.compactMap { item in
            guard item.id != suggestion.id else { return nil }
            if NSIntersectionRange(item.sourceRange, acceptedRange).length > 0 {
                return nil
            }
            guard item.sourceRange.location >= NSMaxRange(acceptedRange) else {
                return item
            }
            var shifted = item
            shifted.sourceRange = NSRange(
                location: item.sourceRange.location + delta,
                length: item.sourceRange.length
            )
            return shifted
        }
        reviewAnnotations = reconcileAnnotations(
            reviewAnnotations,
            acceptedRange: acceptedRange,
            delta: delta
        )
        definitionMatchAnnotations = reconcileAnnotations(
            definitionMatchAnnotations,
            acceptedRange: acceptedRange,
            delta: delta
        )
        documentFindings = reconcileFindings(
            documentFindings,
            acceptedRange: acceptedRange,
            delta: delta
        )
        reviewedReviewItemIDs = reviewedReviewItemIDs.filter { id in
            documentFindings.contains { $0.id == id }
        }
        ignoredReviewItemIDs.remove(suggestion.id)
        selectedReviewItemID = nil
        editorSourceText = updatedText
        contextPreparationCache.removeAll()
        documentReviewCache.removeAll()
        documentStructure = nil
        documentContextProfile = nil
        contextStructureDuration = 0
        contextExtractionDuration = 0
        contextSegmentationDuration = 0
        contextPreparationDuration = 0
        contextClassificationDuration = 0
        contextPreparationCacheHit = false
        analysisSnapshotEligible = false
        return true
    }

    /// Applies the same anchored reconciliation used by Accept, but for a
    /// source-backed definition option. The option is accepted only while its
    /// resolution, term/body anchors, and document fingerprint still match
    /// the text in the editor.
    @discardableResult
    func reconcileAfterDefinitionResolution(
        _ option: AIConnectorDefinitionResolutionOption,
        previousText: String,
        updatedText: String
    ) -> Bool {
        guard option.isActionable,
              let resolutionEntry = definitionResolutions.first(where: {
                  $0.value.options.contains(where: { $0.id == option.id })
              }),
              resolutionEntry.value.sourceFingerprint
                == DocumentFingerprinting.contentSHA256(previousText),
              resolutionEntry.value.corpusVersion == dictionaryStore.activeCorpusVersion,
              resolutionEntry.value.isAnchored(to: previousText),
              option.isAnchored(to: previousText),
              let replacement = option.replacement else {
            return false
        }

        let acceptedRange = option.targetRange
        let delta = replacement.utf16.count - option.original.utf16.count
        editorSuggestions = editorSuggestions.compactMap { item in
            guard NSIntersectionRange(item.sourceRange, acceptedRange).length == 0 else {
                return nil
            }
            guard item.sourceRange.location >= NSMaxRange(acceptedRange) else {
                return item
            }
            var shifted = item
            shifted.sourceRange.location += delta
            return shifted
        }
        reviewAnnotations = reconcileAnnotations(
            reviewAnnotations,
            acceptedRange: acceptedRange,
            delta: delta
        )
        definitionMatchAnnotations = reconcileAnnotations(
            definitionMatchAnnotations,
            acceptedRange: acceptedRange,
            delta: delta
        )
        documentFindings = reconcileFindings(
            documentFindings,
            acceptedRange: acceptedRange,
            delta: delta
        )
        reviewedReviewItemIDs = reviewedReviewItemIDs.filter { id in
            documentFindings.contains { $0.id == id }
        }
        ignoredReviewItemIDs.remove(resolutionEntry.key)
        selectedReviewItemID = nil
        editorSourceText = updatedText
        definitionAssessments = []
        definitionModelCallCount = 0
        definitionResolutions = [:]
        definitionResolutionMetrics = [:]
        definitionResolutionCache.removeAll()
        definitionResolutionOperationIDs.removeAll()
        definitionResolutionLoadingIDs = []
        contextPreparationCache.removeAll()
        documentReviewCache.removeAll()
        documentStructure = nil
        documentContextProfile = nil
        contextStructureDuration = 0
        contextExtractionDuration = 0
        contextSegmentationDuration = 0
        contextPreparationDuration = 0
        contextClassificationDuration = 0
        contextPreparationCacheHit = false
        analysisSnapshotEligible = false
        return true
    }

    private func reconcileAnnotations(
        _ annotations: [EditorReviewAnnotation],
        acceptedRange: NSRange,
        delta: Int
    ) -> [EditorReviewAnnotation] {
        annotations.compactMap { annotation in
            guard NSIntersectionRange(annotation.sourceRange, acceptedRange).length == 0 else {
                return nil
            }
            var reconciled = annotation
            if annotation.sourceRange.location >= NSMaxRange(acceptedRange) {
                reconciled.sourceRange = NSRange(
                    location: annotation.sourceRange.location + delta,
                    length: annotation.sourceRange.length
                )
            }
            reconciled.relatedEvidence = annotation.relatedEvidence.compactMap { evidence in
                guard NSIntersectionRange(evidence.sourceRange, acceptedRange).length == 0 else {
                    return nil
                }
                return evidence.sourceRange.location >= NSMaxRange(acceptedRange)
                    ? evidence.shifted(by: delta)
                    : evidence
            }
            return reconciled
        }
    }

    private func reconcileFindings(
        _ findings: [AIConnectorDocumentFinding],
        acceptedRange: NSRange,
        delta: Int
    ) -> [AIConnectorDocumentFinding] {
        findings.compactMap { finding in
            guard NSIntersectionRange(finding.sourceRange, acceptedRange).length == 0,
                  finding.relatedEvidence.allSatisfy({ evidence in
                      NSIntersectionRange(evidence.sourceRange, acceptedRange).length == 0
                  }) else {
                return nil
            }
            var reconciled = finding
            if finding.sourceRange.location >= NSMaxRange(acceptedRange) {
                reconciled.sourceRange = NSRange(
                    location: finding.sourceRange.location + delta,
                    length: finding.sourceRange.length
                )
            }
            reconciled.relatedEvidence = finding.relatedEvidence.map { evidence in
                evidence.sourceRange.location >= NSMaxRange(acceptedRange)
                    ? evidence.shifted(by: delta)
                    : evidence
            }
            return reconciled
        }
    }

    func clearEditorSuggestions() {
        editorSuggestions = []
        reviewAnnotations = []
        definitionMatchAnnotations = []
        definitionResolutions = [:]
        definitionResolutionMetrics = [:]
        definitionResolutionLoadingIDs = []
        definitionResolutionOperationIDs.removeAll()
        definitionResolutionCache.removeAll()
        ignoredReviewItemIDs = []
        documentFindings = []
        reviewedReviewItemIDs = []
        showReviewedFindings = false
        documentFindingMetrics = AIConnectorDocumentReviewMetrics()
        definitionDebugSuggestions = []
        selectedReviewItemID = nil
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

    /// Keeps already applied results available after an explicit cancellation.
    /// The next run receives a plan whose completed segments are reusable and
    /// whose remaining segments are still pending. If preparation had not
    /// produced a structure yet, the next run safely falls back to a fresh
    /// analysis because no baseline can be proven.
    private func preservePartialAnalysisForResume() {
        guard inputSource == .currentDocument,
              let segmentation = segmentationResult,
              documentStructure != nil else {
            pendingAnalysisPlan = nil
            activeAnalysisPlan = nil
            analysisBaseline = nil
            hasPendingAnalysisChanges = true
            return
        }

        let basePlan = activeAnalysisPlan ?? .full(
            scope: analysisRunScope,
            documentText: editorSourceText,
            segmentation: segmentation
        )
        let completed = completedRunSegmentIDs.intersection(
            basePlan.reprocessSegmentIDs
        )
        let remaining = basePlan.reprocessSegmentIDs.subtracting(completed)
        let cancelledChangeSet = AIConnectorAnalysisChangeSet(
            scope: basePlan.changeSet.scope,
            oldTextFingerprint: basePlan.changeSet.oldTextFingerprint,
            newTextFingerprint: basePlan.changeSet.newTextFingerprint,
            changedOldRanges: basePlan.changeSet.changedOldRanges,
            changedNewRanges: basePlan.changeSet.changedNewRanges,
            changedOldBlockIDs: basePlan.changeSet.changedOldBlockIDs,
            changedBlockIDs: basePlan.changeSet.changedBlockIDs,
            changedSectionIDs: basePlan.changeSet.changedSectionIDs,
            reasons: basePlan.changeSet.reasons.union([.cancelled]),
            isAmbiguous: basePlan.changeSet.isAmbiguous
        )
        let nextPlan = AIConnectorAnalysisPlan(
            changeSet: cancelledChangeSet,
            reusableSegmentIDs: basePlan.reusableSegmentIDs.union(completed),
            reprocessSegmentIDs: remaining,
            removedSegmentIDs: basePlan.removedSegmentIDs,
            mappings: basePlan.mappings,
            dependencySectionIDs: basePlan.dependencySectionIDs,
            requiresProfileRebuild: basePlan.requiresProfileRebuild,
            requiresDocumentReview: basePlan.requiresDocumentReview,
            isFullRerun: false
        )
        pendingAnalysisPlan = nextPlan
        activeAnalysisPlan = nil
        analysisBaseline = makeAnalysisBaseline()
        hasPendingAnalysisChanges = !remaining.isEmpty
        reusedSegmentCount = nextPlan.reusedSegmentCount
        reprocessedSegmentCount = nextPlan.reprocessedSegmentCount
        incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics(
            scope: analysisRunScope,
            reusedSegmentCount: nextPlan.reusedSegmentCount,
            reprocessedSegmentCount: nextPlan.reprocessedSegmentCount,
            invalidatedSegmentCount: nextPlan.reprocessedSegmentCount,
            cacheLookupCount: incrementalCacheLookupCount,
            cacheHitCount: cacheHitCount,
            firstResultLatency: firstIncrementalResultAt.map {
                $0.timeIntervalSince(activeAnalysisRunStartedAt ?? $0)
            },
            totalDuration: activeAnalysisRunStartedAt.map {
                now().timeIntervalSince($0)
            },
            wasPartial: true
        )
        analysisSnapshotEligible = false
    }

    private func currentReviewIndex(fallback: Int) -> Int {
        if case let .reviewing(current, _) = state {
            return current
        }
        return fallback
    }

    func analysisDuration(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(analysisStartedAt))
    }

    func isProgressStalled(
        at date: Date,
        threshold: TimeInterval = 60
    ) -> Bool {
        guard isRunning else { return false }
        return date.timeIntervalSince(lastProgressActivityAt) >= threshold
    }

    private func beginProgressTracking() {
        let startDate = now()
        analysisStartedAt = startDate
        lastProgressActivityAt = startDate
        lastGenerationProgressPublicationAt = nil
    }

    private func recordProgressActivity(at date: Date? = nil) {
        lastProgressActivityAt = date ?? now()
    }

    private func setProgressStage(_ stage: AIConnectorProgressStage) {
        if progressStage != stage {
            progressStage = stage
            if stage == .languageModelDownload
                || stage == .languageModelLoading
                || stage == .languageScoring {
                languageModelProgress = 0
            }
            recordProgressActivity()
        }
        updateAnalysisProgressForCompletedSegments()
    }

    private func updateAnalysisProgressForCompletedSegments() {
        let candidate: Double
        if progressStage == .completed {
            candidate = 1
        } else {
            guard totalSegmentCount > 0 else { return }
            let completed = min(
                max(completedSegmentCount, 0),
                totalSegmentCount
            )
            candidate = Double(completed) / Double(totalSegmentCount)
        }

        let previousValue = progressTracker.value
        progressTracker.advance(to: candidate)
        guard progressTracker.value != previousValue else { return }
        analysisProgress = progressTracker.value
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private func updateSemanticDownloadProgress(_ progress: Double) {
        let nextProgress = max(semanticDownloadProgress, clamped(progress))
        guard semanticDownloadProgress != nextProgress else { return }
        semanticDownloadProgress = nextProgress
        downloadProgress = nextProgress
        recordProgressActivity()
    }

    private func updateModelDownloadProgress(_ progress: Double) {
        let nextProgress = max(modelDownloadProgress, clamped(progress))
        guard modelDownloadProgress != nextProgress else { return }
        modelDownloadProgress = nextProgress
        downloadProgress = nextProgress
        recordProgressActivity()
    }

    private func updateLanguageModelProgress(_ progress: Double) {
        let nextProgress = max(languageModelProgress, clamped(progress))
        guard languageModelProgress != nextProgress else { return }
        languageModelProgress = nextProgress
        recordProgressActivity()
    }

    private func publishGenerationProgress(
        characters: Int,
        total: Int,
        fallback: Int
    ) {
        let nextCharacters = max(characters, 0)
        guard generationProgress != nextCharacters else { return }

        let timestamp = now()
        let isNewGeneration = nextCharacters < generationProgress
        if !isNewGeneration,
           let lastPublication = lastGenerationProgressPublicationAt,
           timestamp.timeIntervalSince(lastPublication)
            < Self.generationProgressUpdateInterval {
            return
        }

        generationProgress = nextCharacters
        lastGenerationProgressPublicationAt = timestamp
        recordProgressActivity(at: timestamp)
        if progressStage != .definitionReview {
            setProgressStage(.generation)
        } else {
            updateAnalysisProgressForCompletedSegments()
        }
        state = .reviewing(
            current: currentReviewIndex(fallback: fallback),
            total: total
        )
    }

    private func clearBenchmarkCallbacks() {
        benchmarkRunner.onDownloadProgress = nil
        benchmarkRunner.onSemanticProgress = nil
        benchmarkRunner.onGenerationProgress = nil
        benchmarkRunner.onProgressStage = nil
    }

    private func apply(result: AIConnectorSegmentResult) async {
        recordProgressActivity()
        completedRunSegmentIDs.insert(result.segment.id)
        if firstIncrementalResultAt == nil, analysisRunScope != .fullFresh {
            firstIncrementalResultAt = now()
        }
        currentSegmentPreview = result.segment.targetText
        currentGlossaryMatches = result.glossaryMatches
        currentCandidates = result.candidates
        currentCandidateDecisions = result.candidateDecisions
        currentCandidateRoutes = result.candidateRoutes
        if !result.cacheHit, let generationMetrics = result.generationMetrics {
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
        if !result.definitionCacheHit {
            definitionModelCallCount += result.definitionModelCallCount
        }
        if result.skipped {
            skippedSegmentCount += 1
        } else {
            processedSegmentCount += 1
        }
        if result.cacheHit { cacheHitCount += 1 }
        if !result.cacheHit, result.firstPassSucceeded {
            firstPassSuccessCount += 1
        }
        if !result.cacheHit, result.repairAttempted {
            repairAttemptCount += 1
        }
        if !result.cacheHit, result.usedFallback {
            fallbackCount += 1
        }
        candidateCount += result.candidates.count
        acceptedCandidateCount += result.candidateDecisions.filter {
            $0.decision == .accept
        }.count
        if !result.cacheHit {
            modelCallCount += result.modelCallCount
            challengeCount += result.challengeCount
        }
        noSuggestionCount += result.reviews.filter {
            $0.status == .noSuggestion
        }.count

        if exposesEditorSuggestions {
            let mappingClock = ContinuousClock()
            let mappingStartedAt = mappingClock.now
            rebuildEditorMappings()
            definitionDebugSuggestions = []
#if DEBUG
            if let observationCollector {
                await observationCollector.recordStage(
                    .editorMapping,
                    duration: AIConnectorObservationTiming.seconds(
                        mappingStartedAt.duration(to: mappingClock.now)
                    ),
                    segmentID: result.segment.id
                )
            }
#endif
        }
        updateOutput()
        runSummary = currentPartialSummary()
        updateAnalysisProgressForCompletedSegments()
    }

    private func rebuildEditorMappings() {
        editorSuggestions = EditorSuggestionMapper.make(
            reviews: validatedReviews,
            definitionAssessments: definitionAssessments,
            documentText: editorSourceText
        )
        reviewAnnotations = EditorSuggestionMapper.makeReviewAnnotations(
            reviews: validatedReviews,
            definitionAssessments: definitionAssessments,
            documentText: editorSourceText
        ) + EditorSuggestionMapper.makeFindingAnnotations(
            findings: documentFindings,
            documentText: editorSourceText
        )
        definitionMatchAnnotations = EditorSuggestionMapper.makeDefinitionMatchAnnotations(
            assessments: definitionAssessments,
            documentText: editorSourceText
        )
    }

    private func prepareDefinitionResolutions(
        documentText: String,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        operationID: UUID
    ) async throws {
        guard activeOperationID == operationID else { return }

        definitionResolutions = [:]
        definitionResolutionMetrics = [:]
        for assessment in definitionAssessments {
            try Task.checkCancellation()
            guard activeOperationID == operationID,
                  assessment.alignment == .mismatch
                    || assessment.alignment == .needsReview else {
                continue
            }

            let result = try await definitionResolutionService.resolve(
                assessment: assessment,
                documentText: documentText,
                mode: mode,
                modelVariant: modelVariant,
                includeReverseTermCandidates: false
            )
            guard activeOperationID == operationID else { return }
            let annotationID = result.resolution.annotationID
                ?? EditorSuggestionMapper.definitionAnnotationID(for: assessment)
            definitionResolutions[annotationID] = result.resolution
            definitionResolutionMetrics[annotationID] = result.metrics
#if DEBUG
            if let observationCollector {
                await observationCollector.recordDefinitionResolution(result.metrics)
            }
#endif
        }
    }

    func definitionResolution(for annotationID: UUID) -> AIConnectorDefinitionResolution? {
        definitionResolutions[annotationID]
    }

    /// Starts the lazy reverse lookup used by the definition popover. The
    /// initial document run only prepares source-backed definition options;
    /// semantic term candidates are retrieved after an explicit user request.
    func requestDefinitionResolution(for annotationID: UUID) {
        guard !definitionResolutionLoadingIDs.contains(annotationID),
              let assessment = definitionAssessments.first(where: {
                  EditorSuggestionMapper.definitionAnnotationID(for: $0) == annotationID
              }),
              assessment.alignment == .mismatch else {
            return
        }

        let operationID = UUID()
        definitionResolutionOperationIDs[annotationID] = operationID
        definitionResolutionLoadingIDs.insert(annotationID)
        let documentText = editorSourceText
        let mode = reviewMode
        let modelVariant = self.modelVariant
        let cacheKey = Self.definitionResolutionCacheKey(
            documentText: documentText,
            assessment: assessment,
            structure: documentStructure,
            mode: mode,
            modelVariant: modelVariant
        )

        if let cached = definitionResolutionCache[cacheKey] {
            definitionResolutions[annotationID] = cached.resolution
            definitionResolutionMetrics[annotationID] = cached.metrics.cacheHitMetrics()
            definitionResolutionLoadingIDs.remove(annotationID)
            definitionResolutionOperationIDs.removeValue(forKey: annotationID)
            selectedReviewItemID = annotationID
            return
        }

        let resolver = definitionResolutionService
        let service = self.service
        let reviewer: AIConnectorDefinitionResolutionService.Reviewer?
        if mode.usesModel {
            reviewer = { request in
                try await service.reviewDefinitionResolution(
                    request: request,
                    downloadProgress: { _ in },
                    generationProgress: { _ in }
                )
            }
        } else {
            reviewer = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await resolver.resolve(
                    assessment: assessment,
                    documentText: documentText,
                    mode: mode,
                    modelVariant: modelVariant,
                    includeReverseTermCandidates: true,
                    reviewer: reviewer
                )
                guard self.definitionResolutionOperationIDs[annotationID] == operationID,
                      DocumentFingerprinting.contentSHA256(self.editorSourceText)
                        == DocumentFingerprinting.contentSHA256(documentText) else {
                    return
                }
                self.definitionResolutionCache[cacheKey] = result
                self.definitionResolutions[annotationID] = result.resolution
                self.definitionResolutionMetrics[annotationID] = result.metrics
#if DEBUG
                if let observationCollector = self.observationCollector {
                    await observationCollector.recordDefinitionResolution(result.metrics)
                }
#endif
                self.definitionResolutionLoadingIDs.remove(annotationID)
                self.definitionResolutionOperationIDs.removeValue(forKey: annotationID)
                self.selectedReviewItemID = annotationID
            } catch is CancellationError {
                guard self.definitionResolutionOperationIDs[annotationID] == operationID else {
                    return
                }
                self.definitionResolutionLoadingIDs.remove(annotationID)
                self.definitionResolutionOperationIDs.removeValue(forKey: annotationID)
            } catch {
                guard self.definitionResolutionOperationIDs[annotationID] == operationID else {
                    return
                }
                self.definitionResolutionLoadingIDs.remove(annotationID)
                self.definitionResolutionOperationIDs.removeValue(forKey: annotationID)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func currentPartialSummary() -> AIConnectorRunSummary {
        currentSummary(wasPartial: true)
    }

    private func currentSummary(wasPartial: Bool) -> AIConnectorRunSummary {
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
            wasPartial: wasPartial,
            candidateCount: candidateCount,
            acceptedCandidateCount: acceptedCandidateCount,
            modelCallCount: modelCallCount,
            challengeCount: challengeCount
        )
    }

    private func makeAnalysisBaseline() -> AIConnectorAnalysisBaseline? {
        guard let structure = documentStructure,
              let segmentation = segmentationResult else { return nil }
        return AIConnectorAnalysisBaseline(
            documentText: editorSourceText,
            structure: structure,
            profile: documentContextProfile,
            segmentation: segmentation,
            analysisProfile: currentAnalysisProfile,
            validatedReviews: validatedReviews,
            definitionAssessments: definitionAssessments,
            documentFindings: documentFindings,
            ignoredReviewItemIDs: ignoredReviewItemIDs,
            reviewedReviewItemIDs: reviewedReviewItemIDs
        )
    }

    private func resetTransientAnalysisState(keepDocumentContext: Bool) {
        activeOperationID = nil
        progressStage = .idle
        progressTracker.reset()
        analysisProgress = progressTracker.value
        lastQueueSegmentID = nil
        lastQueueState = nil
        lastQueueProgressCurrent = nil
        lastQueueProgressTotal = nil
        let resetDate = now()
        analysisStartedAt = resetDate
        lastProgressActivityAt = resetDate
        lastGenerationProgressPublicationAt = nil
        errorMessage = nil
        downloadProgress = 0
        semanticDownloadProgress = 0
        modelDownloadProgress = 0
        languageModelProgress = 0
        generationProgress = 0
        latestGenerationMetrics = nil
        currentSegmentPreview = ""
        currentSegmentID = nil
        currentGlossaryMatches = []
        currentCandidates = []
        currentCandidateDecisions = []
        currentCandidateRoutes = []
        currentQueueState = nil
        currentBatchIndex = nil
        currentBatchSize = nil
        queueBatchSizes = []
        glossarySnapshots = []
        rejectedReviews = []
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
        completedRunSegmentIDs = []
        incrementalCacheLookupCount = 0
        if !keepDocumentContext {
            segmentationResult = nil
            documentStructure = nil
            documentContextProfile = nil
        }
#if DEBUG
        observationCollector = nil
        observationReport = nil
#endif
        analysisSnapshotEligible = false
    }

    private func resetRunState() {
        activeOperationID = nil
        progressStage = .idle
        progressTracker.reset()
        analysisProgress = progressTracker.value
        lastQueueSegmentID = nil
        lastQueueState = nil
        lastQueueProgressCurrent = nil
        lastQueueProgressTotal = nil
        let resetDate = now()
        analysisStartedAt = resetDate
        lastProgressActivityAt = resetDate
        lastGenerationProgressPublicationAt = nil
        errorMessage = nil
        downloadProgress = 0
        semanticDownloadProgress = 0
        modelDownloadProgress = 0
        languageModelProgress = 0
        generationProgress = 0
        latestGenerationMetrics = nil
        currentSegmentPreview = ""
        currentSegmentID = nil
        currentGlossaryMatches = []
        currentCandidates = []
        currentCandidateDecisions = []
        currentCandidateRoutes = []
        currentQueueState = nil
        currentBatchIndex = nil
        currentBatchSize = nil
        queueBatchSizes = []
        glossarySnapshots = []
        segmentationResult = nil
        documentStructure = nil
        documentContextProfile = nil
        contextStructureDuration = 0
        contextExtractionDuration = 0
        contextSegmentationDuration = 0
        contextPreparationDuration = 0
        contextClassificationDuration = 0
        contextPreparationCacheHit = false
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
#if DEBUG
        observationCollector = nil
        observationReport = nil
#endif
        clearEditorSuggestions()
        analysisSnapshotEligible = false
        exposesEditorSuggestions = false
        editorSourceText = ""
        analysisRunScope = .fullFresh
        pendingAnalysisPlan = nil
        activeAnalysisPlan = nil
        analysisBaseline = nil
        incrementalRunMetrics = AIConnectorIncrementalAnalysisMetrics()
        reusedSegmentCount = 0
        reprocessedSegmentCount = 0
        hasPendingAnalysisChanges = false
        activeAnalysisRunStartedAt = nil
        firstIncrementalResultAt = nil
        completedRunSegmentIDs = []
        incrementalCacheLookupCount = 0
    }

    private static func contextPreparationCacheKey(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        modelVariant: AIConnectorModelVariant,
        mode: AIConnectorReviewMode
    ) -> String {
        [
            DocumentFingerprinting.contentSHA256(documentText),
            structure.fingerprint,
            AIConnectorDocumentStructure.currentVersion,
            AIConnectorDocumentContextProfile.extractorVersion,
            AIConnectorDocumentContextProfile.classifierVersion,
            modelVariant.rawValue,
            mode.rawValue
        ].joined(separator: "|")
    }

    private static func documentReviewCacheKey(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant
    ) -> String {
        [
            DocumentFingerprinting.contentSHA256(documentText),
            structure.fingerprint,
            profile.fingerprint,
            AIConnectorDocumentReviewDetector.version,
            QwenSuggestionService.riskPromptVersion,
            modelVariant.rawValue,
            mode.rawValue
        ].joined(separator: "|")
    }

    private static func definitionResolutionCacheKey(
        documentText: String,
        assessment: AIConnectorDefinitionAssessment,
        structure: AIConnectorDocumentStructure?,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant
    ) -> String {
        [
            DocumentFingerprinting.contentSHA256(documentText),
            structure?.fingerprint ?? "no-structure",
            assessment.id,
            AIConnectorDefinitionResolution.version,
            QwenSuggestionService.definitionResolutionPromptVersion,
            dictionaryCacheVersion,
            mode.rawValue,
            modelVariant.rawValue
        ].joined(separator: "|")
    }

    private static let dictionaryCacheVersion = "definition-resolution-cache-v1"

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
