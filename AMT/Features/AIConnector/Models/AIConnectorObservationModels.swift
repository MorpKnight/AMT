import Foundation

/// The stages exposed by the Phase 0 diagnostic report. These names describe
/// work spans, not percentages: some spans intentionally overlap because a
/// model preparation span can contain the first retrieval or review call.
nonisolated enum AIConnectorObservationStage: String, Codable, CaseIterable, Hashable, Sendable {
    case segmenting
    case documentStructure
    case contextExtraction
    case contextClassification
    case contextSegmentation
    case protectionContext
    case suggestionRetrieval
    case spellingCandidateGeneration
    case tataKataScoring
    case candidateBuilding
    case candidateReview
    case candidateRepair
    case candidateChallenge
    case definitionDetection
    case definitionRetrieval
    case definitionReview
    case validationConflictResolution
    case editorMapping
    case resultAcknowledgement
    case resourcePreparation
    case modelLoading
    case documentFindingDetection
    case riskReview
    case definitionResolution
}

nonisolated enum AIConnectorObservationTerminalStatus: String, Codable, Hashable, Sendable {
    case running
    case completed
    case cancelled
    case failed
}

nonisolated enum AIConnectorPhaseZeroRunKind: String, Codable, CaseIterable, Hashable, Sendable {
    case deterministicCold = "deterministic-cold"
    case hybridSteadyState = "hybrid-steady-state"
    case modelOnlySteadyState = "model-only-steady-state"
    case hybridWarmCache = "hybrid-warm-cache"

    var mode: AIConnectorReviewMode {
        switch self {
        case .deterministicCold:
            .deterministic
        case .hybridSteadyState, .hybridWarmCache:
            .hybrid
        case .modelOnlySteadyState:
            .modelOnly
        }
    }

    var resetsCache: Bool {
        self != .hybridWarmCache
    }
}

nonisolated enum AIConnectorPhaseZeroFixtureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case spelling
    case grammar
    case terminology
    case definition
    case hardNegative = "hard-negative"
}

nonisolated enum AIConnectorFixtureReviewStatus: String, Codable, Hashable, Sendable {
    case pendingLawyerReview = "pendingLawyerReview"
    case approved
}

/// A finding expectation is kept only inside the benchmark evaluator. It is
/// never copied into the safe JSON report.
nonisolated struct AIConnectorPhaseZeroExpectedFinding: Codable, Hashable, Sendable {
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String
    let replacement: String

    init(
        status: AIReviewStatus = .suggestion,
        category: AIReviewCategory,
        original: String,
        replacement: String
    ) {
        self.status = status
        self.category = category
        self.original = original
        self.replacement = replacement
    }
}

nonisolated struct AIConnectorPhaseZeroExpectedDefinition: Codable, Hashable, Sendable {
    let classification: AIConnectorDefinitionClassification
    let alignment: AIConnectorDefinitionAlignment

    init(
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment
    ) {
        self.classification = classification
        self.alignment = alignment
    }
}

nonisolated enum AIConnectorPhaseZeroFixtureExpectation: Codable, Hashable, Sendable {
    case findings([AIConnectorPhaseZeroExpectedFinding])
    case definition(AIConnectorPhaseZeroExpectedDefinition)
    case noChange
}

/// A synthetic, stable fixture. `text` is deliberately an input to the local
/// test harness only; no safe report type contains it.
nonisolated struct AIConnectorPhaseZeroFixture: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let category: AIConnectorPhaseZeroFixtureCategory
    let text: String
    let expected: AIConnectorPhaseZeroFixtureExpectation
    let difficulty: String
    let reviewStatus: AIConnectorFixtureReviewStatus

    init(
        id: String,
        category: AIConnectorPhaseZeroFixtureCategory,
        text: String,
        expected: AIConnectorPhaseZeroFixtureExpectation,
        difficulty: String,
        reviewStatus: AIConnectorFixtureReviewStatus = .pendingLawyerReview
    ) {
        self.id = id
        self.category = category
        self.text = text
        self.expected = expected
        self.difficulty = difficulty
        self.reviewStatus = reviewStatus
    }
}

/// One aggregated stage. Durations are seconds and are always non-negative.
nonisolated struct AIConnectorStageMetric: Codable, Hashable, Sendable {
    let stage: AIConnectorObservationStage
    let resource: String?
    let invocationCount: Int
    let totalDuration: TimeInterval
    let medianDuration: TimeInterval
    let p95Duration: TimeInterval
}

/// Privacy-safe per-segment telemetry. It contains shape and count metadata,
/// never the segment text or any model/document content.
nonisolated struct AIConnectorSegmentObservation: Codable, Identifiable, Hashable, Sendable {
    let segmentID: Int
    let utf16Length: Int
    let duration: TimeInterval
    let stageMetrics: [AIConnectorStageMetric]
    let retrievalQueryCount: Int
    let semanticQueryCount: Int
    let spellingCandidateCount: Int
    let scoredSpellingCandidateCount: Int
    let candidateCount: Int
    let suggestionCount: Int
    let needsReviewCount: Int
    let noSuggestionCount: Int
    let rejectedCount: Int
    let cacheHit: Bool
    let modelCallCount: Int
    let definitionModelCallCount: Int
    let repairCount: Int
    let challengeCount: Int
    let fallbackCount: Int
    let modelOriginCount: Int

    var id: Int { segmentID }
}

/// Accuracy for one scope (`all`, a fixture category, or `definition`).
/// Values are provisional until all fixtures are approved by a lawyer.
nonisolated struct AIConnectorAccuracySummary: Codable, Hashable, Sendable {
    let scope: String
    let fixtureCount: Int
    let expectedFindingCount: Int
    let actualFindingCount: Int
    let truePositive: Int
    let falsePositive: Int
    let falseNegative: Int
    let precision: Double
    let recall: Double
    let f1: Double
    let exactSpanCorrectCount: Int
    let exactSpanTotalCount: Int
    let exactSpanAccuracy: Double
    let noChangeCorrectCount: Int
    let noChangeTotalCount: Int
    let noChangeAccuracy: Double
    let safetyViolationCount: Int
    let modelOriginResultCount: Int
    let fallbackOriginResultCount: Int
    let provisional: Bool
    let qualityGateDecision: AIConnectorQualityGateDecision

    init(
        scope: String,
        fixtureCount: Int,
        expectedFindingCount: Int,
        actualFindingCount: Int,
        truePositive: Int,
        falsePositive: Int,
        falseNegative: Int,
        exactSpanCorrectCount: Int,
        exactSpanTotalCount: Int,
        noChangeCorrectCount: Int,
        noChangeTotalCount: Int,
        safetyViolationCount: Int,
        modelOriginResultCount: Int,
        fallbackOriginResultCount: Int,
        reviewStatus: AIConnectorFixtureReviewStatus
    ) {
        self.scope = scope
        self.fixtureCount = fixtureCount
        self.expectedFindingCount = expectedFindingCount
        self.actualFindingCount = actualFindingCount
        self.truePositive = truePositive
        self.falsePositive = falsePositive
        self.falseNegative = falseNegative
        self.precision = Self.ratio(truePositive, truePositive + falsePositive)
        self.recall = Self.ratio(truePositive, truePositive + falseNegative)
        self.f1 = Self.f1(precision: precision, recall: recall)
        self.exactSpanCorrectCount = exactSpanCorrectCount
        self.exactSpanTotalCount = exactSpanTotalCount
        self.exactSpanAccuracy = Self.ratio(exactSpanCorrectCount, exactSpanTotalCount)
        self.noChangeCorrectCount = noChangeCorrectCount
        self.noChangeTotalCount = noChangeTotalCount
        self.noChangeAccuracy = Self.ratio(noChangeCorrectCount, noChangeTotalCount)
        self.safetyViolationCount = safetyViolationCount
        self.modelOriginResultCount = modelOriginResultCount
        self.fallbackOriginResultCount = fallbackOriginResultCount
        self.provisional = reviewStatus != .approved
        // Phase 0 records a baseline only; it deliberately has no pass/fail
        // performance gate, even after a fixture review status changes.
        self.qualityGateDecision = .notApplicable
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func f1(precision: Double, recall: Double) -> Double {
        guard precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }
}

/// A single mode run in the baseline suite. `observation` is safe by
/// construction; the legacy benchmark report is intentionally absent.
nonisolated struct AIConnectorBaselineRunReport: Codable, Identifiable, Hashable, Sendable {
    let kind: AIConnectorPhaseZeroRunKind
    let mode: AIConnectorReviewMode
    let cacheResetBeforeRun: Bool
    let observation: AIConnectorObservationReport

    var id: String { kind.rawValue }
}

nonisolated struct AIConnectorModeComparison: Codable, Hashable, Sendable {
    let mode: AIConnectorReviewMode
    let runKinds: [AIConnectorPhaseZeroRunKind]
    let totalDuration: TimeInterval
    let segmentLatencyP50: TimeInterval
    let segmentLatencyP95: TimeInterval
    let modelCallCount: Int
    let fallbackCount: Int
    let repairCount: Int
    let challengeCount: Int
    let cacheHitCount: Int
}

nonisolated struct AIConnectorBaselineComparisonSummary: Codable, Hashable, Sendable {
    let modes: [AIConnectorModeComparison]
}

nonisolated struct AIConnectorBaselineSuiteReport: Codable, Hashable, Sendable {
    static let schemaVersion = "phase0-observability-v1"

    let schemaVersion: String
    let generatedAt: Date
    let terminalStatus: AIConnectorObservationTerminalStatus
    let fixtureCount: Int
    let fixtureReviewStatus: AIConnectorFixtureReviewStatus
    let modelVariant: AIConnectorModelVariant
    let modelRevision: String
    let generationProfile: String
    let thinkingEnabled: Bool
    let pipelineVersion: String
    let rulePackVersion: String
    let corpusVersion: String
    let resourcePreparation: AIConnectorObservationReport?
    let runs: [AIConnectorBaselineRunReport]
    let comparison: AIConnectorBaselineComparisonSummary
    let failureCode: String?
}

/// A safe report for one analysis run. All input-derived values are counts or
/// lengths; no target, replacement, reason, definition, URL, or raw output is
/// represented here.
nonisolated struct AIConnectorObservationReport: Codable, Hashable, Sendable {
    static let schemaVersion = "phase0-observability-v1"

    let schemaVersion: String
    let runID: UUID
    let generatedAt: Date
    let mode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let modelRevision: String
    let generationProfile: String
    let thinkingEnabled: Bool
    let pipelineVersion: String
    let rulePackVersion: String
    let corpusVersion: String
    let terminalStatus: AIConnectorObservationTerminalStatus
    let failureCode: String?
    let totalDuration: TimeInterval
    let totalInputUTF16Length: Int
    let totalSegmentCount: Int
    let observedSegmentCount: Int
    let segmentLatencyP50: TimeInterval
    let segmentLatencyP95: TimeInterval
    let stageMetrics: [AIConnectorStageMetric]
    let segments: [AIConnectorSegmentObservation]
    let retrievalQueryCount: Int
    let semanticQueryCount: Int
    let spellingCandidateCount: Int
    let scoredSpellingCandidateCount: Int
    let candidateCount: Int
    let suggestionCount: Int
    let needsReviewCount: Int
    let noSuggestionCount: Int
    let rejectedCount: Int
    let cacheHitCount: Int
    let modelCallCount: Int
    let definitionModelCallCount: Int
    let repairCount: Int
    let challengeCount: Int
    let fallbackCount: Int
    let modelOriginResultCount: Int
    let documentFindingCount: Int
    let riskCandidateCount: Int
    let riskModelCallCount: Int
    let riskFallbackCount: Int
    let riskCacheHitCount: Int
    let documentFindingDuration: TimeInterval
    let riskReviewDuration: TimeInterval
    let definitionResolutionCandidateCount: Int
    let definitionResolutionQueryCount: Int
    let definitionResolutionModelCallCount: Int
    let definitionResolutionFallbackCount: Int
    let definitionResolutionCacheHitCount: Int
    let definitionResolutionDuration: TimeInterval
    let accuracy: [AIConnectorAccuracySummary]
    let incrementalAnalysis: AIConnectorIncrementalAnalysisMetrics?
}
