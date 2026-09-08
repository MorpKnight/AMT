#if DEBUG
import Foundation

/// Debug-only benchmark for the incremental planner. It deliberately measures
/// local structure/segmentation planning, not Qwen inference, so it never
/// downloads a model or puts document text in an exported report.
@MainActor
final class AIConnectorIncrementalBenchmarkRunner {
    func run(
        documentText: String,
        structuredDocument: StructuredDocument? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> AIConnectorIncrementalBenchmarkReport {
        let source = documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "BAB I\nPihak Pertama wajib menjaga Data Pribadi.\nBAB II\nPihak Kedua wajib menjaga dokumen."
            : documentText
        let baselineArtifacts = artifacts(
            for: source,
            structuredDocument: structuredDocument
        )
        let baseline = AIConnectorAnalysisBaseline(
            documentText: source,
            structure: baselineArtifacts.structure,
            profile: baselineArtifacts.profile,
            segmentation: baselineArtifacts.segmentation,
            analysisProfile: analysisProfile,
            validatedReviews: [],
            definitionAssessments: [],
            documentFindings: [],
            ignoredReviewItemIDs: [],
            reviewedReviewItemIDs: []
        )

        var cases: [AIConnectorIncrementalBenchmarkCase] = []
        cases.append(measure(.coldRun) {
            .full(
                scope: .fullFresh,
                documentText: source,
                segmentation: baselineArtifacts.segmentation
            )
        })

        cases.append(measure(.warmRerun) {
            let artifacts = self.artifacts(
                for: source,
                structuredDocument: structuredDocument
            )
            return self.planner.makePlan(
                previous: baseline,
                documentText: source,
                structure: artifacts.structure,
                segmentation: artifacts.segmentation,
                scope: .incrementalDocument,
                currentAnalysisProfile: self.analysisProfile,
                currentProfile: artifacts.profile
            )
        })

        let localEdit = replacingFirst(
            "wajib",
            with: "harus",
            in: source
        )
        cases.append(measure(.localEdit) {
            let artifacts = self.artifacts(
                for: localEdit,
                structuredDocument: nil
            )
            return self.planner.makePlan(
                previous: baseline,
                documentText: localEdit,
                structure: artifacts.structure,
                segmentation: artifacts.segmentation,
                scope: .incrementalDocument,
                currentAnalysisProfile: self.analysisProfile,
                currentProfile: artifacts.profile
            )
        })

        let definitionEdit = source + "\n\"Benchmark Term\" adalah informasi yang dipakai untuk pengujian."
        cases.append(measure(.definitionDependency) {
            let artifacts = self.artifacts(
                for: definitionEdit,
                structuredDocument: nil
            )
            return self.planner.makePlan(
                previous: baseline,
                documentText: definitionEdit,
                structure: artifacts.structure,
                segmentation: artifacts.segmentation,
                scope: .incrementalDocument,
                currentAnalysisProfile: self.analysisProfile,
                currentProfile: artifacts.profile
            )
        })

        cases.append(measure(.fullFreshRerun) {
            let artifacts = self.artifacts(
                for: source,
                structuredDocument: structuredDocument
            )
            return .full(
                scope: .fullFresh,
                documentText: source,
                segmentation: artifacts.segmentation
            )
        })

        return AIConnectorIncrementalBenchmarkReport(
            generatedAt: now(),
            cases: cases
        )
    }

    private let planner = AIConnectorIncrementalAnalysisPlanner()

    private var analysisProfile: AIConnectorAnalysisProfile {
        AIConnectorAnalysisProfile(
            pipelineVersion: "phase7-planner-benchmark-v1",
            reviewMode: .deterministic,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            generationProfilePreset: .greedy,
            corpusVersion: "local",
            semanticModelRevision: "local",
            semanticEmbeddingSchema: "local",
            semanticRetrievalProfile: "local"
        )
    }

    private func artifacts(
        for text: String,
        structuredDocument: StructuredDocument?
    ) -> (
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile,
        segmentation: AITextSegmentationResult
    ) {
        let structure = AIConnectorDocumentStructureBuilder().build(
            documentText: text,
            structuredDocument: structuredDocument
        )
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        let segmentation = LegalTextSegmenter().segment(
            documentText: text,
            structure: structure,
            profile: profile
        )
        return (structure, profile, segmentation)
    }

    private func measure(
        _ scenario: AIConnectorIncrementalBenchmarkScenario,
        _ operation: () -> AIConnectorAnalysisPlan
    ) -> AIConnectorIncrementalBenchmarkCase {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let plan = operation()
        let duration = AIConnectorObservationTiming.seconds(
            startedAt.duration(to: clock.now)
        )
        return AIConnectorIncrementalBenchmarkCase(
            scenario: scenario,
            duration: duration,
            firstResultLatency: duration,
            reusedSegmentCount: plan.reusedSegmentCount,
            reprocessedSegmentCount: plan.reprocessedSegmentCount,
            invalidatedSegmentCount: plan.reprocessedSegmentCount,
            cacheLookupCount: plan.reprocessedSegmentCount,
            cacheHitCount: plan.reusedSegmentCount,
            resourcePreparationDuration: 0,
            modelCallCount: 0
        )
    }

    private func replacingFirst(
        _ original: String,
        with replacement: String,
        in text: String
    ) -> String {
        let range = (text as NSString).range(of: original)
        guard range.location != NSNotFound else { return text }
        return (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

private extension AIConnectorIncrementalBenchmarkRunner {
    nonisolated static func percentile(
        _ values: [TimeInterval],
        _ fraction: Double
    ) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let position = Double(sorted.count - 1) * min(max(fraction, 0), 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let remainder = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * remainder
    }
}

nonisolated enum AIConnectorIncrementalBenchmarkScenario: String, Codable, CaseIterable, Hashable, Sendable {
    case coldRun = "cold-run"
    case warmRerun = "warm-rerun"
    case localEdit = "local-edit"
    case definitionDependency = "definition-dependency"
    case fullFreshRerun = "full-fresh-rerun"

    var title: String {
        switch self {
        case .coldRun: "Cold run"
        case .warmRerun: "Warm rerun"
        case .localEdit: "Edit lokal"
        case .definitionDependency: "Perubahan definisi"
        case .fullFreshRerun: "Full fresh rerun"
        }
    }
}

nonisolated struct AIConnectorIncrementalBenchmarkCase: Codable, Hashable, Identifiable, Sendable {
    let scenario: AIConnectorIncrementalBenchmarkScenario
    let duration: TimeInterval
    let firstResultLatency: TimeInterval
    let reusedSegmentCount: Int
    let reprocessedSegmentCount: Int
    let invalidatedSegmentCount: Int
    let cacheLookupCount: Int
    let cacheHitCount: Int
    let resourcePreparationDuration: TimeInterval
    let modelCallCount: Int

    var id: String { scenario.rawValue }
}

nonisolated struct AIConnectorIncrementalBenchmarkReport: Codable, Hashable, Sendable {
    static let schemaVersion = "phase7-planner-benchmark-v1"

    let schema: String
    let generatedAt: Date
    let plannerOnly: Bool
    let cases: [AIConnectorIncrementalBenchmarkCase]
    let totalDuration: TimeInterval
    let p50Duration: TimeInterval
    let p95Duration: TimeInterval
    let totalResourcePreparationDuration: TimeInterval
    let totalModelCallCount: Int

    init(
        generatedAt: Date,
        cases: [AIConnectorIncrementalBenchmarkCase]
    ) {
        self.schema = Self.schemaVersion
        self.generatedAt = generatedAt
        self.plannerOnly = true
        self.cases = cases
        let durations = cases.map(\.duration)
        self.totalDuration = durations.reduce(0, +)
        self.p50Duration = AIConnectorIncrementalBenchmarkRunner.percentile(durations, 0.50)
        self.p95Duration = AIConnectorIncrementalBenchmarkRunner.percentile(durations, 0.95)
        self.totalResourcePreparationDuration = cases
            .map(\.resourcePreparationDuration)
            .reduce(0, +)
        self.totalModelCallCount = cases.map(\.modelCallCount).reduce(0, +)
    }
}
#endif
