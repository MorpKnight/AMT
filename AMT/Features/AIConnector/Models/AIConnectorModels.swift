import Foundation

struct AIReviewSegment: Hashable, Sendable {
    let id: Int
    let sourceLocation: Int
    let sourceLength: Int
    let targetText: String
    let previousContext: String?
    let nextContext: String?
    let isTooLong: Bool

    init(
        id: Int,
        sourceLocation: Int,
        sourceLength: Int,
        targetText: String,
        previousContext: String?,
        nextContext: String?,
        isTooLong: Bool = false
    ) {
        self.id = id
        self.sourceLocation = sourceLocation
        self.sourceLength = sourceLength
        self.targetText = targetText
        self.previousContext = previousContext
        self.nextContext = nextContext
        self.isTooLong = isTooLong
    }
}

struct AITextSegmentationResult: Hashable, Sendable {
    let segments: [AIReviewSegment]
    let headingCount: Int
    let tooLongSegmentCount: Int
    /// Retained for report compatibility. Segmentation is now document-wide,
    /// so this value is always zero; queue limits are reported separately.
    let omittedSegmentCount: Int

    var queuedSegmentCount: Int { segments.count }
}

enum AIReviewStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case noSuggestion = "NO_SUGGESTION"
    case suggestion = "SUGGESTION"
    case needsReview = "NEEDS_REVIEW"

    var displayTitle: String {
        switch self {
        case .noSuggestion:
            "Tidak ada saran"
        case .suggestion:
            "Saran bahasa"
        case .needsReview:
            "Perlu review"
        }
    }
}

enum AIReviewCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case none = "NONE"
    case spelling = "SPELLING"
    case grammar = "GRAMMAR"
    case clarity = "CLARITY"
    case terminology = "TERMINOLOGY"

    var displayTitle: String {
        switch self {
        case .none:
            ""
        case .spelling:
            "Ejaan"
        case .grammar:
            "Tata bahasa"
        case .clarity:
            "Kejelasan"
        case .terminology:
            "Terminologi hukum"
        }
    }
}

enum AIReviewOrigin: String, Codable, Hashable, Sendable {
    case qwen = "Qwen"
    case qwenRepaired = "Qwen (repaired)"
    case deterministic = "Deterministic rules"
    case deterministicFallback = "Deterministic fallback"

    var displayTitle: String {
        switch self {
        case .qwen:
            "Model Qwen"
        case .qwenRepaired:
            "Model Qwen (format diperbaiki)"
        case .deterministic:
            "Aturan deterministik"
        case .deterministicFallback:
            "Pemulihan deterministik"
        }
    }
}

enum AIConnectorRejectionClass: String, Codable, Hashable, Sendable {
    case unknown
    case modelFailure
    case tokenLimit
    case repetition
    case reasoningLeak
    case parserRecoverable
    case parserNonRecoverable
    case validator
    case sourceClaim
    case segmentTooLong
    case cancelled
}

enum AIConnectorReviewMode: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case deterministic = "deterministic"
    case hybrid = "hybrid"
    case modelOnly = "modelOnly"

    var id: Self { self }

    var title: String {
        switch self {
        case .deterministic:
            "Baseline aman"
        case .hybrid:
            "Hybrid: model + guard"
        case .modelOnly:
            "Qwen langsung"
        }
    }

    var detail: String {
        switch self {
        case .deterministic:
            "Tanpa download model; hanya koreksi yang sudah dibatasi."
        case .hybrid:
            "Qwen dicoba, lalu aturan deterministik memulihkan kasus aman."
        case .modelOnly:
            "Untuk membandingkan kualitas output Qwen tanpa pemulihan."
        }
    }

    nonisolated var usesModel: Bool {
        self != .deterministic
    }
}

enum AIConnectorModelVariant: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case qwen35_2b = "qwen35-2b"
    case qwen35Legal4B = "qwen35-legal-4b"
    case qwen35Base4B = "qwen35-base-4b"

    var id: Self { self }

    var title: String {
        switch self {
        case .qwen35_2b:
            "Qwen3.5 2B (baseline)"
        case .qwen35Legal4B:
            "Qwen3.5 Legal 4B (pembanding domain)"
        case .qwen35Base4B:
            "Qwen3.5 4B Base (utama sementara)"
        }
    }

    nonisolated var modelID: String {
        switch self {
        case .qwen35_2b:
            "mlx-community/Qwen3.5-2B-4bit"
        case .qwen35Legal4B:
            "morpknight/qwen3.5-4b-indonesian-legal-mlx-4bit"
        case .qwen35Base4B:
            "mlx-community/Qwen3.5-4B-MLX-4bit"
        }
    }

    nonisolated var revision: String {
        switch self {
        case .qwen35_2b:
            "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
        case .qwen35Legal4B:
            "2517cc7962517b85d97aff8988785cdb02c8fea1"
        case .qwen35Base4B:
            "32f3e8ecf65426fc3306969496342d504bfa13f3"
        }
    }

    nonisolated var downloadEstimate: String {
        switch self {
        case .qwen35_2b:
            "sekitar 1,6 GB"
        case .qwen35Legal4B:
            "sekitar 2,39 GB"
        case .qwen35Base4B:
            "sekitar 3,1 GB"
        }
    }

    nonisolated var shortRevision: String {
        String(revision.prefix(12))
    }

    nonisolated func generationProfile(thinkingEnabled: Bool) -> AIConnectorGenerationProfile {
        if thinkingEnabled {
            return AIConnectorGenerationProfile(
                maxTokens: 768,
                temperature: 0.6,
                topP: 0.95,
                topK: 20,
                presencePenalty: 0,
                seed: 42
            )
        }

        if self == .qwen35Base4B {
            return AIConnectorGenerationProfile(
                maxTokens: 256,
                temperature: 0,
                topP: 1,
                topK: 0,
                presencePenalty: nil,
                seed: 42
            )
        }

        if self == .qwen35Legal4B {
            return AIConnectorGenerationProfile(
                maxTokens: 256,
                temperature: 0,
                topP: 1,
                topK: 0,
                presencePenalty: nil,
                seed: 42
            )
        }

        return AIConnectorGenerationProfile(
            maxTokens: 256,
            temperature: 0.2,
            topP: 0.9,
            topK: 20,
            presencePenalty: 0,
            seed: 42
        )
    }
}

struct AIConnectorGenerationProfile: Hashable, Sendable {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let presencePenalty: Float?
    let seed: UInt64

    var isGreedy: Bool {
        temperature == 0
    }
}

enum AIConnectorGenerationProfilePreset: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case greedy
    case lowVariance = "low-variance"
    case officialInstruct = "official-instruct"

    var id: Self { self }

    var title: String {
        switch self {
        case .greedy:
            "Greedy"
        case .lowVariance:
            "Low variance"
        case .officialInstruct:
            "Official instruct"
        }
    }

    var detail: String {
        switch self {
        case .greedy:
            "Temperature 0; pilihan paling stabil untuk aplikasi."
        case .lowVariance:
            "Sampling ringan untuk pembanding benchmark."
        case .officialInstruct:
            "Parameter non-thinking dari rekomendasi model card."
        }
    }

    func profile(
        for modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool
    ) -> AIConnectorGenerationProfile {
        if thinkingEnabled {
            return AIConnectorGenerationProfile(
                maxTokens: 512,
                temperature: 0.6,
                topP: 0.95,
                topK: 20,
                presencePenalty: 0,
                seed: 42
            )
        }

        switch self {
        case .greedy:
            return AIConnectorGenerationProfile(
                maxTokens: 128,
                temperature: 0,
                topP: 1,
                topK: 0,
                presencePenalty: nil,
                seed: 42
            )
        case .lowVariance:
            return AIConnectorGenerationProfile(
                maxTokens: 128,
                temperature: 0.2,
                topP: 0.9,
                topK: 20,
                presencePenalty: 0,
                seed: 42
            )
        case .officialInstruct:
            return AIConnectorGenerationProfile(
                maxTokens: 128,
                temperature: 0.7,
                topP: 0.8,
                topK: 20,
                presencePenalty: 1.5,
                seed: 42
            )
        }
    }
}

enum AIConnectorGenerationStopReason: String, Codable, Hashable, Sendable {
    case stop
    case length
    case cancelled
}

struct AIConnectorGenerationMetrics: Codable, Hashable, Sendable {
    let promptTokenCount: Int
    let generationTokenCount: Int
    let promptDuration: TimeInterval
    let generationDuration: TimeInterval
    let stopReason: AIConnectorGenerationStopReason
}

struct QwenReviewResult: Sendable {
    let output: String
    let metrics: AIConnectorGenerationMetrics
    let containsReasoningMarkers: Bool
}

enum AIConnectorCandidateConfidence: String, Codable, Hashable, Sendable {
    case deterministicRule
    case verifiedGlossary

    var displayTitle: String {
        switch self {
        case .deterministicRule:
            "rule lokal"
        case .verifiedGlossary:
            "glossary verified"
        }
    }
}

/// A proposal created entirely by local rules or verified glossary data.
/// Qwen receives this value only to judge it; it is never allowed to invent
/// an original span, replacement, or source.
struct AIConnectorReviewCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let segmentID: Int
    let original: String
    let replacement: String
    let category: AIReviewCategory
    let priority: Int
    let ruleID: String?
    let glossaryMatch: LegalDictionaryMatch?
    let explanation: String
    let confidenceTier: AIConnectorCandidateConfidence
}

enum AIConnectorCandidateDecision: String, Codable, Hashable, Sendable {
    case accept = "ACCEPT"
    case reject = "REJECT"
    case needsReview = "NEEDS_REVIEW"
}

struct AIConnectorCandidateReviewRequest: Sendable {
    let segment: AIReviewSegment
    let candidate: AIConnectorReviewCandidate
    let thinkingEnabled: Bool
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile
    let retryInstruction: String?
}

struct QwenCandidateDecisionResult: Sendable {
    let candidateID: String
    let decision: AIConnectorCandidateDecision
    let metrics: AIConnectorGenerationMetrics
    let containsReasoningMarkers: Bool
    let repeatedSixGramRatio: Double?

    init(
        candidateID: String,
        decision: AIConnectorCandidateDecision,
        metrics: AIConnectorGenerationMetrics,
        containsReasoningMarkers: Bool,
        repeatedSixGramRatio: Double? = nil
    ) {
        self.candidateID = candidateID
        self.decision = decision
        self.metrics = metrics
        self.containsReasoningMarkers = containsReasoningMarkers
        self.repeatedSixGramRatio = repeatedSixGramRatio
    }
}

/// A small, dependency-neutral representation used by the candidate tool
/// parser. The MLX ToolCall is converted to this shape at the service edge.
struct AIConnectorToolDecisionPayload: Hashable, Sendable {
    let name: String
    let arguments: [String: String]
}

struct AIConnectorCandidateDecisionRecord: Hashable, Sendable {
    let candidateID: String
    let candidateCategory: AIReviewCategory
    let confidenceTier: AIConnectorCandidateConfidence
    let decision: AIConnectorCandidateDecision?
    let attemptCount: Int
    let repairAttempted: Bool
    let challengeAttempted: Bool
    let usedFallback: Bool
    let rejectionClass: AIConnectorRejectionClass?
    let generationMetrics: AIConnectorGenerationMetrics?
    let finalOrigin: AIReviewOrigin?
    let repeatedSixGramRatio: Double?

    init(
        candidateID: String,
        candidateCategory: AIReviewCategory,
        confidenceTier: AIConnectorCandidateConfidence,
        decision: AIConnectorCandidateDecision?,
        attemptCount: Int,
        repairAttempted: Bool,
        challengeAttempted: Bool,
        usedFallback: Bool,
        rejectionClass: AIConnectorRejectionClass?,
        generationMetrics: AIConnectorGenerationMetrics?,
        finalOrigin: AIReviewOrigin? = nil,
        repeatedSixGramRatio: Double? = nil
    ) {
        self.candidateID = candidateID
        self.candidateCategory = candidateCategory
        self.confidenceTier = confidenceTier
        self.decision = decision
        self.attemptCount = attemptCount
        self.repairAttempted = repairAttempted
        self.challengeAttempted = challengeAttempted
        self.usedFallback = usedFallback
        self.rejectionClass = rejectionClass
        self.generationMetrics = generationMetrics
        self.finalOrigin = finalOrigin
        self.repeatedSixGramRatio = repeatedSixGramRatio
    }
}

struct AIParsedReview: Hashable, Sendable {
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String?
    let replacement: String?
    let glossaryID: String?
    let reason: String
    let ruleID: String?

    init(
        status: AIReviewStatus,
        category: AIReviewCategory,
        original: String?,
        replacement: String?,
        glossaryID: String?,
        reason: String,
        ruleID: String? = nil
    ) {
        self.status = status
        self.category = category
        self.original = original
        self.replacement = replacement
        self.glossaryID = glossaryID
        self.reason = reason
        self.ruleID = ruleID
    }
}

struct AIValidatedReview: Identifiable, Hashable, Sendable {
    let id: UUID
    let segment: AIReviewSegment
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String?
    let replacement: String?
    let reason: String
    let glossaryMatch: LegalDictionaryMatch?
    let origin: AIReviewOrigin
    let ruleID: String?

    init(
        id: UUID = UUID(),
        segment: AIReviewSegment,
        status: AIReviewStatus,
        category: AIReviewCategory,
        original: String?,
        replacement: String?,
        reason: String,
        glossaryMatch: LegalDictionaryMatch?,
        origin: AIReviewOrigin,
        ruleID: String? = nil
    ) {
        self.id = id
        self.segment = segment
        self.status = status
        self.category = category
        self.original = original
        self.replacement = replacement
        self.reason = reason
        self.glossaryMatch = glossaryMatch
        self.origin = origin
        self.ruleID = ruleID
    }

    var segmentID: Int { segment.id }
}

struct AIReviewGlossarySnapshot: Identifiable, Hashable, Sendable {
    let segment: AIReviewSegment
    let matches: [LegalDictionaryMatch]

    var id: Int { segment.id }
}

struct AIReviewRejection: Identifiable, Hashable, Sendable {
    let id: UUID
    let segment: AIReviewSegment
    let rawOutput: String
    let reason: String
    let classification: AIConnectorRejectionClass

    init(
        id: UUID = UUID(),
        segment: AIReviewSegment,
        rawOutput: String,
        reason: String,
        classification: AIConnectorRejectionClass = .unknown
    ) {
        self.id = id
        self.segment = segment
        self.rawOutput = rawOutput
        self.reason = reason
        self.classification = classification
    }

    var segmentID: Int { segment.id }
}

struct AIConnectorRunSummary: Hashable, Sendable {
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let processedSegmentCount: Int
    let suggestionCount: Int
    let needsReviewCount: Int
    let noSuggestionCount: Int
    let recoveredCount: Int
    let rejectedCount: Int
    let skippedSegmentCount: Int
    let totalSegmentCount: Int
    let cacheHitCount: Int
    let firstPassSuccessCount: Int
    let repairAttemptCount: Int
    let fallbackCount: Int
    let circuitBreakerActivated: Bool
    let wasPartial: Bool
    let candidateCount: Int
    let acceptedCandidateCount: Int
    let modelCallCount: Int
    let challengeCount: Int

    nonisolated init(
        reviewMode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        processedSegmentCount: Int,
        suggestionCount: Int,
        needsReviewCount: Int,
        noSuggestionCount: Int,
        recoveredCount: Int,
        rejectedCount: Int,
        skippedSegmentCount: Int,
        totalSegmentCount: Int? = nil,
        cacheHitCount: Int = 0,
        firstPassSuccessCount: Int = 0,
        repairAttemptCount: Int = 0,
        fallbackCount: Int = 0,
        circuitBreakerActivated: Bool = false,
        wasPartial: Bool = false,
        candidateCount: Int = 0,
        acceptedCandidateCount: Int = 0,
        modelCallCount: Int = 0,
        challengeCount: Int = 0
    ) {
        self.reviewMode = reviewMode
        self.modelVariant = modelVariant
        self.processedSegmentCount = processedSegmentCount
        self.suggestionCount = suggestionCount
        self.needsReviewCount = needsReviewCount
        self.noSuggestionCount = noSuggestionCount
        self.recoveredCount = recoveredCount
        self.rejectedCount = rejectedCount
        self.skippedSegmentCount = skippedSegmentCount
        self.totalSegmentCount = totalSegmentCount ?? processedSegmentCount + skippedSegmentCount
        self.cacheHitCount = cacheHitCount
        self.firstPassSuccessCount = firstPassSuccessCount
        self.repairAttemptCount = repairAttemptCount
        self.fallbackCount = fallbackCount
        self.circuitBreakerActivated = circuitBreakerActivated
        self.wasPartial = wasPartial
        self.candidateCount = candidateCount
        self.acceptedCandidateCount = acceptedCandidateCount
        self.modelCallCount = modelCallCount
        self.challengeCount = challengeCount
    }
}

enum AIConnectorQueueState: String, Hashable, Sendable {
    case pending
    case preparing
    case retrieving
    case generating
    case parsing
    case validating
    case completed
    case noSuggestion
    case needsReview
    case rejected
    case skipped
    case failed
    case cancelled
}

struct AIConnectorSegmentResult: Sendable {
    let segment: AIReviewSegment
    let glossaryMatches: [LegalDictionaryMatch]
    let reviews: [AIValidatedReview]
    /// Status/category parsed from the model before validation. It is kept
    /// separately from validated reviews so diagnostics can distinguish a
    /// well-formed but unsafe answer from malformed output.
    let parsedStatus: AIReviewStatus?
    let parsedCategory: AIReviewCategory?
    let rejections: [AIReviewRejection]
    let cacheHit: Bool
    let modelAttempts: Int
    let repairAttempted: Bool
    let usedFallback: Bool
    let firstPassSucceeded: Bool
    let skipped: Bool
    let generationMetrics: AIConnectorGenerationMetrics?
    let repeatedSixGramRatio: Double?
    let outputWasTruncated: Bool
    let reasoningMarkerDetected: Bool
    let sourceClaimDetected: Bool
    let candidates: [AIConnectorReviewCandidate]
    let candidateDecisions: [AIConnectorCandidateDecisionRecord]
    let modelCallCount: Int
    let challengeCount: Int
    let definitionAssessment: AIConnectorDefinitionAssessment?
    let definitionModelCallCount: Int

    init(
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch] = [],
        reviews: [AIValidatedReview] = [],
        parsedStatus: AIReviewStatus? = nil,
        parsedCategory: AIReviewCategory? = nil,
        rejections: [AIReviewRejection] = [],
        cacheHit: Bool = false,
        modelAttempts: Int = 0,
        repairAttempted: Bool = false,
        usedFallback: Bool = false,
        firstPassSucceeded: Bool = false,
        skipped: Bool = false,
        generationMetrics: AIConnectorGenerationMetrics? = nil,
        repeatedSixGramRatio: Double? = nil,
        outputWasTruncated: Bool = false,
        reasoningMarkerDetected: Bool = false,
        sourceClaimDetected: Bool = false,
        candidates: [AIConnectorReviewCandidate] = [],
        candidateDecisions: [AIConnectorCandidateDecisionRecord] = [],
        modelCallCount: Int = 0,
        challengeCount: Int = 0,
        definitionAssessment: AIConnectorDefinitionAssessment? = nil,
        definitionModelCallCount: Int = 0
    ) {
        self.segment = segment
        self.glossaryMatches = glossaryMatches
        self.reviews = reviews
        self.parsedStatus = parsedStatus
        self.parsedCategory = parsedCategory
        self.rejections = rejections
        self.cacheHit = cacheHit
        self.modelAttempts = modelAttempts
        self.repairAttempted = repairAttempted
        self.usedFallback = usedFallback
        self.firstPassSucceeded = firstPassSucceeded
        self.skipped = skipped
        self.generationMetrics = generationMetrics
        self.repeatedSixGramRatio = repeatedSixGramRatio
        self.outputWasTruncated = outputWasTruncated
        self.reasoningMarkerDetected = reasoningMarkerDetected
        self.sourceClaimDetected = sourceClaimDetected
        self.candidates = candidates
        self.candidateDecisions = candidateDecisions
        self.modelCallCount = modelCallCount
        self.challengeCount = challengeCount
        self.definitionAssessment = definitionAssessment
        self.definitionModelCallCount = definitionModelCallCount
    }

    func withDefinitionAnalysis(
        _ analysis: AIConnectorDefinitionAnalysisResult
    ) -> AIConnectorSegmentResult {
        AIConnectorSegmentResult(
            segment: segment,
            glossaryMatches: glossaryMatches,
            reviews: reviews,
            parsedStatus: parsedStatus,
            parsedCategory: parsedCategory,
            rejections: rejections,
            cacheHit: cacheHit,
            modelAttempts: modelAttempts,
            repairAttempted: repairAttempted,
            usedFallback: usedFallback,
            firstPassSucceeded: firstPassSucceeded,
            skipped: skipped,
            generationMetrics: generationMetrics,
            repeatedSixGramRatio: repeatedSixGramRatio,
            outputWasTruncated: outputWasTruncated,
            reasoningMarkerDetected: reasoningMarkerDetected,
            sourceClaimDetected: sourceClaimDetected,
            candidates: candidates,
            candidateDecisions: candidateDecisions,
            modelCallCount: modelCallCount,
            challengeCount: challengeCount,
            definitionAssessment: analysis.assessment,
            definitionModelCallCount: analysis.modelCallCount
        )
    }
}

enum AIConnectorWorkQueueEvent: Sendable {
    case stateChanged(segmentID: Int, state: AIConnectorQueueState)
    case result(AIConnectorSegmentResult)
    case progress(completed: Int, total: Int)
    case circuitBreakerActivated
    case finished(AIConnectorRunSummary)
    case failed(String)
}

struct AIConnectorDocumentProtectionContext: Hashable, Sendable {
    let definedTerms: Set<String>
    let partyNames: Set<String>
    let acronyms: Set<String>
    let quotedTerms: Set<String>
    let identifiers: Set<String>

    static let empty = AIConnectorDocumentProtectionContext(
        definedTerms: [],
        partyNames: [],
        acronyms: [],
        quotedTerms: [],
        identifiers: []
    )
}

enum AIConnectorLocalToolName: String, Codable, CaseIterable, Hashable, Sendable {
    case searchLegalConcepts
    case getLegalDefinition
    case getSourcePassage
    case getRegulationStatus
    case getRegulationRelations
}

struct AIConnectorLocalToolRequest: Hashable, Sendable {
    let name: AIConnectorLocalToolName
    let query: String?
    let entryID: String?
    let limit: Int
    let passageID: String?
    let referenceID: String?

    init(
        name: AIConnectorLocalToolName,
        query: String? = nil,
        entryID: String? = nil,
        limit: Int = 5,
        passageID: String? = nil,
        referenceID: String? = nil
    ) {
        self.name = name
        self.query = query
        self.entryID = entryID
        self.limit = limit
        self.passageID = passageID
        self.referenceID = referenceID
    }
}

struct AIConnectorLocalToolResponse: Hashable, Sendable {
    let name: AIConnectorLocalToolName
    let payload: String
    let corpusVersion: String
    let isAuthoritative: Bool
}

struct AIConnectorLocalToolBudget: Hashable, Sendable {
    let maxCalls: Int
    let maxResultsPerCall: Int
    let timeout: TimeInterval

    nonisolated static let `default` = AIConnectorLocalToolBudget(
        maxCalls: 4,
        maxResultsPerCall: 5,
        timeout: 1
    )
}

enum AIConnectorFixtureExpectation: Codable, Hashable, Sendable {
    case suggestion(
        original: String,
        replacement: String,
        category: AIReviewCategory
    )
    case preserveDefinedTerms
    case noReplacement
}

struct AIConnectorFixtureEvaluation: Codable, Identifiable, Hashable, Sendable {
    let sample: AIConnectorSample
    let expectation: AIConnectorFixtureExpectation
    let actualStatus: AIReviewStatus?
    let actualOriginal: String?
    let actualReplacement: String?
    let passed: Bool
    let detail: String

    var id: String { sample.id }
}

struct AIConnectorBenchmarkSummary: Codable, Hashable, Sendable {
    let title: String
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let duration: TimeInterval
    let evaluations: [AIConnectorFixtureEvaluation]

    var passedCount: Int {
        evaluations.filter(\.passed).count
    }

    var totalCount: Int {
        evaluations.count
    }
}

struct AIConnectorBenchmarkRecord: Codable, Hashable, Identifiable, Sendable {
    let sampleID: String
    let sampleTitle: String
    let expectedSignal: String
    let mode: String
    let modelVariant: String
    let thinkingEnabled: Bool
    let segmentID: Int?
    let sourceLocation: Int?
    let targetText: String?
    let candidateGlossaryID: String?
    let candidateGlossaryTerm: String?
    let diagnosticOutput: String?
    let parsedStatus: String?
    let validatedStatus: String?
    let validatedCategory: String?
    let validatedOriginal: String?
    let validatedReplacement: String?
    let validatedReason: String?
    let origin: String?
    let rejectionReason: String?
    let promptTokenCount: Int?
    let generationTokenCount: Int?
    let promptDuration: TimeInterval?
    let generationDuration: TimeInterval?
    let stopReason: AIConnectorGenerationStopReason?
    let repeatedSixGramRatio: Double?
    let expectedSignalPassed: Bool
    let wasFallback: Bool
    let outputWasRejected: Bool
    let outputWasTruncated: Bool
    let reasoningMarkerDetected: Bool
    let sourceClaimDetected: Bool
    let skipped: Bool
    let cacheHit: Bool
    let modelAttempts: Int
    let repairAttempted: Bool
    let firstPassSucceeded: Bool
    let rejectionClass: AIConnectorRejectionClass?
    let generationProfile: String?
    let candidateID: String?
    let candidateDecision: AIConnectorCandidateDecision?
    let candidateSource: AIConnectorCandidateConfidence?
    let modelCallCount: Int
    let challengeAttempted: Bool

    var id: String { sampleID }
}

/// Candidate-level benchmark evidence. The existing sample-level record is
/// retained for backwards-compatible fixture summaries, while this record
/// keeps every local proposal and every model decision separately diagnosable.
struct AIConnectorBenchmarkCandidateRecord: Codable, Hashable, Identifiable, Sendable {
    let sampleID: String
    let sampleTitle: String
    let expectedSignal: String
    let segmentID: Int?
    let candidateID: String
    let source: AIConnectorCandidateConfidence
    let category: AIReviewCategory
    let ruleID: String?
    let original: String
    let replacement: String
    let decision: AIConnectorCandidateDecision?
    let finalOrigin: AIReviewOrigin?
    let attemptCount: Int
    let repairAttempted: Bool
    let challengeAttempted: Bool
    let usedFallback: Bool
    let rejectionClass: AIConnectorRejectionClass?
    let promptTokenCount: Int?
    let generationTokenCount: Int?
    let promptDuration: TimeInterval?
    let generationDuration: TimeInterval?
    let stopReason: AIConnectorGenerationStopReason?
    let repeatedSixGramRatio: Double?

    var id: String {
        let segment = segmentID.map(String.init) ?? "-"
        return sampleID + "#" + segment + "#" + candidateID
    }
}

enum AIConnectorQualityGateDecision: String, Codable, Hashable, Sendable {
    case go = "GO"
    case noGo = "NO_GO"
    case notApplicable = "NOT_APPLICABLE"
}

struct AIConnectorQualityGate: Codable, Hashable, Sendable {
    let languagePassCount: Int
    let languageTotal: Int
    let neutralSafetyPassCount: Int
    let neutralSafetyTotal: Int
    /// Output that reached the six-field schema after any bounded format
    /// repair. This is deliberately separate from semantic correctness.
    let schemaCompliantCount: Int
    let schemaTotal: Int
    /// A model answer is contained when it either becomes a validated result
    /// or is explicitly rejected with a diagnostic reason.
    let safetyContainedCount: Int
    let safetyTotal: Int
    let safetyContainmentPassed: Bool
    /// Includes validated NO_SUGGESTION decisions. Exact fixture utility is
    /// represented separately by `exactExpectationPassCount`.
    let usableValidatedOutputCount: Int
    let exactExpectationPassCount: Int
    let parserBoundaryPassed: Bool
    let truncatedCount: Int
    let repetitionCount: Int
    let reasoningLeakCount: Int
    let sourceClaimCount: Int
    let cancellationPassed: Bool
    /// Final product utility after the selected mode has applied any allowed
    /// deterministic fallback. This is not a model quality result.
    let utilityPassed: Bool
    /// The release-style model gate is meaningful only for a genuine
    /// model-only benchmark whose records were produced in model-only mode.
    let modelGateEligible: Bool
    let modelOriginResultCount: Int
    let fallbackCount: Int
    let passed: Bool
    let decision: AIConnectorQualityGateDecision

    init(
        records: [AIConnectorBenchmarkRecord],
        mode: AIConnectorReviewMode,
        cancellationPassed: Bool = true,
        repetitionThreshold: Double = 0.2
    ) {
        let utilityIDs: Set<String> = [
            "redundant-wajib-untuk",
            "spelling-ditanda-tangani",
            "terminology-data-pribadi"
        ]
        let utilityRecords = records.filter { utilityIDs.contains($0.sampleID) }
        let neutralSafetyRecords = records.filter { !utilityIDs.contains($0.sampleID) }

        languagePassCount = utilityRecords.filter(\.expectedSignalPassed).count
        languageTotal = utilityRecords.count
        neutralSafetyPassCount = neutralSafetyRecords.filter(\.expectedSignalPassed).count
        neutralSafetyTotal = neutralSafetyRecords.count
        let modelAttemptRecords = records.filter { $0.modelAttempts > 0 }
        schemaCompliantCount = modelAttemptRecords.filter {
            $0.parsedStatus != nil
        }.count
        schemaTotal = modelAttemptRecords.count
        safetyContainedCount = records.filter { record in
            if record.skipped || record.mode == AIConnectorReviewMode.deterministic.rawValue {
                return true
            }

            return record.validatedStatus != nil
                || (record.outputWasRejected && record.rejectionReason != nil)
        }.count
        safetyTotal = records.count
        safetyContainmentPassed = safetyContainedCount == safetyTotal
        usableValidatedOutputCount = records.filter { $0.validatedStatus != nil }.count
        exactExpectationPassCount = records.filter(\.expectedSignalPassed).count
        // Kept for report compatibility. The old name described containment,
        // not literal parser conformance.
        parserBoundaryPassed = safetyContainmentPassed
        truncatedCount = records.filter(\.outputWasTruncated).count
        repetitionCount = records.filter {
            ($0.repeatedSixGramRatio ?? 0) >= repetitionThreshold
        }.count
        reasoningLeakCount = records.filter(\.reasoningMarkerDetected).count
        sourceClaimCount = records.filter(\.sourceClaimDetected).count
        self.cancellationPassed = cancellationPassed

        utilityPassed = languageTotal == 3
            && languagePassCount >= 2
            && neutralSafetyTotal == 5
            && neutralSafetyPassCount == neutralSafetyTotal
        modelOriginResultCount = records.filter { record in
            record.origin == AIReviewOrigin.qwen.rawValue
                || record.origin == AIReviewOrigin.qwenRepaired.rawValue
        }.count
        fallbackCount = records.filter(\.wasFallback).count
        modelGateEligible = mode == .modelOnly
            && records.allSatisfy { $0.mode == AIConnectorReviewMode.modelOnly.rawValue }

        let gatePassed = modelGateEligible
            && utilityPassed
            && safetyContainmentPassed
            && truncatedCount == 0
            && repetitionCount == 0
            && reasoningLeakCount == 0
            && sourceClaimCount == 0
            && cancellationPassed
        passed = gatePassed
        if !modelGateEligible {
            decision = .notApplicable
        } else {
            decision = gatePassed ? .go : .noGo
        }
    }
}

struct AIConnectorBenchmarkReport: Codable, Hashable, Sendable {
    let generatedAt: Date
    let title: String
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let thinkingEnabled: Bool
    let duration: TimeInterval
    let circuitBreakerActivated: Bool
    let records: [AIConnectorBenchmarkRecord]
    let evaluations: [AIConnectorFixtureEvaluation]
    let qualityGate: AIConnectorQualityGate
    let generationProfile: String
    let candidateRecords: [AIConnectorBenchmarkCandidateRecord]

    init(
        generatedAt: Date,
        title: String,
        reviewMode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        duration: TimeInterval,
        circuitBreakerActivated: Bool,
        records: [AIConnectorBenchmarkRecord],
        evaluations: [AIConnectorFixtureEvaluation],
        qualityGate: AIConnectorQualityGate,
        generationProfile: String,
        candidateRecords: [AIConnectorBenchmarkCandidateRecord] = []
    ) {
        self.generatedAt = generatedAt
        self.title = title
        self.reviewMode = reviewMode
        self.modelVariant = modelVariant
        self.thinkingEnabled = thinkingEnabled
        self.duration = duration
        self.circuitBreakerActivated = circuitBreakerActivated
        self.records = records
        self.evaluations = evaluations
        self.qualityGate = qualityGate
        self.generationProfile = generationProfile
        self.candidateRecords = candidateRecords
    }

    var passedCount: Int {
        evaluations.filter(\.passed).count
    }

    var totalCount: Int {
        evaluations.count
    }

    var legacySummary: AIConnectorBenchmarkSummary {
        AIConnectorBenchmarkSummary(
            title: title,
            reviewMode: reviewMode,
            modelVariant: modelVariant,
            duration: duration,
            evaluations: evaluations
        )
    }
}

enum AIConnectorInputSource: String, CaseIterable, Identifiable {
    case currentDocument
    case dummy

    var id: Self { self }

    var title: String {
        switch self {
        case .currentDocument:
            "Dokumen saat ini"
        case .dummy:
            "Contoh dummy"
        }
    }
}

struct AIConnectorSample: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let text: String
    let expectedSignal: String

    static let samples: [AIConnectorSample] = [
        AIConnectorSample(
            id: "redundant-wajib-untuk",
            title: "Redundansi: wajib untuk",
            text: "Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.",
            expectedSignal: "Sarankan 'wajib menyerahkan'."
        ),
        AIConnectorSample(
            id: "spelling-ditanda-tangani",
            title: "Ejaan: ditanda tangani",
            text: "Perjanjian ini telah ditanda tangani oleh Para Pihak pada tanggal 10 Agustus 2026.",
            expectedSignal: "Sarankan 'ditandatangani'."
        ),
        AIConnectorSample(
            id: "no-issue-governing-law",
            title: "Tanpa masalah: governing law",
            text: "Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.",
            expectedSignal: "Tidak memaksakan perubahan."
        ),
        AIConnectorSample(
            id: "terminology-data-pribadi",
            title: "Terminologi: Data Pribadi",
            text: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
            expectedSignal: "Usulkan istilah canonical 'Data Pribadi' jika kandidat glossary cocok."
        ),
        AIConnectorSample(
            id: "substantive-termination-clause",
            title: "Sensitif: hak pengakhiran",
            text: "Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua.",
            expectedSignal: "Tidak menulis ulang substansi; minta review manusia bila perlu."
        ),
        AIConnectorSample(
            id: "preserve-deadline",
            title: "Preservasi: tenggat 30 hari",
            text: "Pihak Kedua wajib menyampaikan pemberitahuan tertulis sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.",
            expectedSignal: "Pertahankan angka dan tenggat."
        ),
        AIConnectorSample(
            id: "mixed-defined-terms",
            title: "Istilah campuran: Borrower/Lender",
            text: "Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja.",
            expectedSignal: "Tandai konsistensi istilah tanpa menerjemahkan defined terms sembarang."
        ),
        AIConnectorSample(
            id: "no-source-claim",
            title: "Tanpa sumber: peraturan berlaku",
            text: "Perusahaan wajib mematuhi seluruh peraturan yang berlaku.",
            expectedSignal: "Jangan mengarang peraturan atau kutipan."
        ),
    ]

    var expectation: AIConnectorFixtureExpectation {
        switch id {
        case "redundant-wajib-untuk":
            .suggestion(
                original: "wajib untuk",
                replacement: "wajib",
                category: .grammar
            )
        case "spelling-ditanda-tangani":
            .suggestion(
                original: "ditanda tangani",
                replacement: "ditandatangani",
                category: .spelling
            )
        case "terminology-data-pribadi":
            .suggestion(
                original: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik",
                replacement: "Data Pribadi",
                category: .terminology
            )
        case "mixed-defined-terms":
            .preserveDefinedTerms
        default:
            .noReplacement
        }
    }
}

enum AIConnectorRunState: Equatable {
    case idle
    case segmenting
    case loading
    case downloading(Double)
    case reviewing(current: Int, total: Int)
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .segmenting, .loading, .downloading, .reviewing:
            true
        case .idle, .completed, .cancelled, .failed:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Siap"
        case .segmenting:
            "Menyiapkan teks..."
        case .loading:
            "Memuat model..."
        case .downloading:
            "Mengunduh model..."
        case let .reviewing(current, total):
            "Meninjau segmen \(current) dari \(total)..."
        case .completed:
            "Selesai"
        case .cancelled:
            "Dibatalkan"
        case .failed:
            "Gagal"
        }
    }
}

nonisolated enum AIConnectorProgressStage: String, Hashable, Sendable {
    case idle
    case segmenting
    case semanticModelDownload
    case semanticRetrieval
    case modelDownload
    case modelLoading
    case generation
    case definitionReview
    case deterministicReview
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .idle:
            "Siap"
        case .segmenting:
            "Menyiapkan teks"
        case .semanticModelDownload:
            "Mengunduh model pencarian semantik"
        case .semanticRetrieval:
            "Mencari evidence yang relevan"
        case .modelDownload:
            "Mengunduh model Qwen"
        case .modelLoading:
            "Memuat model Qwen"
        case .generation:
            "Menilai rekomendasi"
        case .definitionReview:
            "Memeriksa definisi istilah"
        case .deterministicReview:
            "Memeriksa aturan lokal"
        case .completed:
            "Selesai"
        case .cancelled:
            "Dibatalkan"
        case .failed:
            "Gagal"
        }
    }
}
