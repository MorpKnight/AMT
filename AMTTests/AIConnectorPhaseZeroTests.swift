#if DEBUG
import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseZeroTests: XCTestCase {
    func testFixtureCatalogContainsStableSixtyPendingFixtures() {
        let fixtures = AIConnectorPhaseZeroFixtureCatalog.fixtures

        XCTAssertEqual(fixtures.count, 60)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, 60)
        XCTAssertTrue(fixtures.allSatisfy { !$0.text.isEmpty })
        XCTAssertTrue(fixtures.allSatisfy { $0.reviewStatus == .pendingLawyerReview })
        XCTAssertEqual(
            Dictionary(grouping: fixtures, by: \.category).mapValues(\.count),
            [
                .spelling: 15,
                .grammar: 15,
                .terminology: 8,
                .definition: 7,
                .hardNegative: 15
            ]
        )
    }

    func testCollectorRecordsNonNegativeDurationsCountsAndPercentiles() async throws {
        let collector = AIConnectorObservationCollector(
            runID: UUID(),
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            modelRevision: "test-revision",
            generationProfile: "greedy",
            thinkingEnabled: false,
            pipelineVersion: "test-pipeline",
            rulePackVersion: "test-rules",
            corpusVersion: "test-corpus"
        )
        await collector.setInputMetadata(utf16Length: 999, segmentCount: 2)
        await collector.recordStage(
            .candidateReview,
            duration: 1,
            segmentID: 1,
            invocationCount: 2
        )
        await collector.recordStage(
            .candidateReview,
            duration: 2,
            segmentID: 1
        )
        await collector.recordStage(
            .candidateReview,
            duration: 3,
            segmentID: 2
        )
        await collector.recordRetrieval(
            segmentID: 1,
            queryCount: 2,
            semanticQueryCount: 1
        )
        await collector.recordCandidateCounts(
            segmentID: 1,
            spellingCandidateCount: 3,
            scoredSpellingCandidateCount: 2,
            candidateCount: 4
        )

        let firstSegment = makeSegment(id: 1, target: "A😀")
        await collector.recordSegmentResult(
            AIConnectorSegmentResult(
                segment: firstSegment,
                reviews: [
                    makeReview(
                        segment: firstSegment,
                        status: .suggestion,
                        category: .grammar,
                        original: "A",
                        replacement: "B",
                        origin: .qwen
                    ),
                    makeReview(
                        segment: firstSegment,
                        status: .noSuggestion,
                        category: .none,
                        original: nil,
                        replacement: nil,
                        origin: .deterministic
                    )
                ],
                rejections: [
                    AIReviewRejection(
                        segment: firstSegment,
                        rawOutput: "raw output",
                        reason: "reason"
                    )
                ],
                cacheHit: true,
                repairAttempted: true,
                usedFallback: true,
                modelCallCount: 2,
                challengeCount: 2,
                definitionModelCallCount: 1
            ),
            duration: 2
        )

        let secondSegment = makeSegment(id: 2, target: "B")
        await collector.recordSegmentResult(
            AIConnectorSegmentResult(
                segment: secondSegment,
                reviews: [
                    makeReview(
                        segment: secondSegment,
                        status: .noSuggestion,
                        category: .none,
                        original: nil,
                        replacement: nil,
                        origin: .deterministic
                    )
                ]
            ),
            duration: 4
        )

        let report = await collector.finish(status: .completed)

        XCTAssertEqual(report.totalInputUTF16Length, 999)
        XCTAssertEqual(report.totalSegmentCount, 2)
        XCTAssertEqual(report.observedSegmentCount, 2)
        XCTAssertEqual(report.segments.first?.utf16Length, 3)
        XCTAssertEqual(report.retrievalQueryCount, 2)
        XCTAssertEqual(report.semanticQueryCount, 1)
        XCTAssertEqual(report.spellingCandidateCount, 3)
        XCTAssertEqual(report.scoredSpellingCandidateCount, 2)
        XCTAssertEqual(report.candidateCount, 4)
        XCTAssertEqual(report.suggestionCount, 1)
        XCTAssertEqual(report.noSuggestionCount, 2)
        XCTAssertEqual(report.rejectedCount, 1)
        XCTAssertEqual(report.cacheHitCount, 1)
        XCTAssertEqual(report.modelCallCount, 0)
        XCTAssertEqual(report.definitionModelCallCount, 1)
        XCTAssertEqual(report.repairCount, 0)
        XCTAssertEqual(report.challengeCount, 0)
        XCTAssertEqual(report.fallbackCount, 0)
        XCTAssertEqual(report.modelOriginResultCount, 1)
        XCTAssertEqual(report.segmentLatencyP50, 3, accuracy: 0.0001)
        XCTAssertEqual(report.segmentLatencyP95, 3.9, accuracy: 0.0001)

        let candidateMetric = try XCTUnwrap(
            report.stageMetrics.first { $0.stage == .candidateReview }
        )
        XCTAssertEqual(candidateMetric.invocationCount, 4)
        XCTAssertEqual(candidateMetric.totalDuration, 6, accuracy: 0.0001)
        XCTAssertEqual(candidateMetric.medianDuration, 1.25, accuracy: 0.0001)
        XCTAssertEqual(candidateMetric.p95Duration, 2.85, accuracy: 0.0001)
        XCTAssertTrue(report.totalDuration >= 0)
        XCTAssertTrue(report.stageMetrics.allSatisfy {
            $0.totalDuration >= 0
                && $0.medianDuration >= 0
                && $0.p95Duration >= 0
        })

        let partial = await collector.snapshot(terminalStatus: .cancelled)
        XCTAssertEqual(partial.terminalStatus, .cancelled)
        XCTAssertEqual(partial.observedSegmentCount, 2)
    }

    func testAccuracyEvaluatorCountsFindingAndNoChangeOutcomes() {
        let fixtures = [
            fixture(
                id: "tp",
                category: .spelling,
                expected: .findings([
                    AIConnectorPhaseZeroExpectedFinding(
                        category: .spelling,
                        original: "salah",
                        replacement: "benar"
                    )
                ])
            ),
            fixture(
                id: "wrong",
                category: .grammar,
                expected: .findings([
                    AIConnectorPhaseZeroExpectedFinding(
                        category: .grammar,
                        original: "salah",
                        replacement: "benar"
                    )
                ])
            ),
            fixture(
                id: "missing",
                category: .terminology,
                expected: .findings([
                    AIConnectorPhaseZeroExpectedFinding(
                        category: .terminology,
                        original: "istilah",
                        replacement: "Istilah"
                    )
                ])
            ),
            fixture(id: "no-change", category: .hardNegative, expected: .noChange),
            fixture(id: "false-positive", category: .hardNegative, expected: .noChange),
            fixture(
                id: "multiple",
                category: .grammar,
                expected: .findings([
                    AIConnectorPhaseZeroExpectedFinding(
                        category: .grammar,
                        original: "satu",
                        replacement: "dua"
                    ),
                    AIConnectorPhaseZeroExpectedFinding(
                        category: .grammar,
                        original: "tiga",
                        replacement: "empat"
                    )
                ])
            )
        ]
        let results: [String: AIConnectorSegmentResult] = [
            "tp": result(
                id: 1,
                reviews: [
                    makeReview(
                        segmentID: 1,
                        status: .suggestion,
                        category: .spelling,
                        original: "salah",
                        replacement: "benar",
                        origin: .deterministic
                    )
                ]
            ),
            "wrong": result(
                id: 2,
                reviews: [
                    makeReview(
                        segmentID: 2,
                        status: .suggestion,
                        category: .grammar,
                        original: "lain",
                        replacement: "berbeda",
                        origin: .qwen
                    )
                ]
            ),
            "no-change": result(
                id: 4,
                reviews: [
                    makeReview(
                        segmentID: 4,
                        status: .noSuggestion,
                        category: .none,
                        original: nil,
                        replacement: nil,
                        origin: .deterministic
                    )
                ]
            ),
            "false-positive": result(
                id: 5,
                reviews: [
                    makeReview(
                        segmentID: 5,
                        status: .suggestion,
                        category: .grammar,
                        original: "tak perlu",
                        replacement: "perlu",
                        origin: .qwenRepaired
                    )
                ]
            ),
            "multiple": result(
                id: 6,
                reviews: [
                    makeReview(
                        segmentID: 6,
                        status: .suggestion,
                        category: .grammar,
                        original: "satu",
                        replacement: "dua",
                        origin: .deterministic
                    ),
                    makeReview(
                        segmentID: 6,
                        status: .suggestion,
                        category: .grammar,
                        original: "ekstra",
                        replacement: "tambahan",
                        origin: .qwen
                    )
                ]
            )
        ]

        let summaries = AIConnectorPhaseZeroAccuracyEvaluator().summaries(
            fixtures: fixtures,
            resultsByFixtureID: results
        )
        let all = summaries.first { $0.scope == "all" }

        XCTAssertEqual(all?.fixtureCount, 6)
        XCTAssertEqual(all?.expectedFindingCount, 5)
        XCTAssertEqual(all?.actualFindingCount, 5)
        XCTAssertEqual(all?.truePositive, 2)
        XCTAssertEqual(all?.falsePositive, 3)
        XCTAssertEqual(all?.falseNegative, 3)
        XCTAssertEqual(all?.precision ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(all?.recall ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(all?.f1 ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(all?.exactSpanCorrectCount, 2)
        XCTAssertEqual(all?.exactSpanTotalCount, 5)
        XCTAssertEqual(all?.noChangeCorrectCount, 1)
        XCTAssertEqual(all?.noChangeTotalCount, 2)
        XCTAssertTrue(all?.provisional ?? false)
        XCTAssertEqual(all?.qualityGateDecision, .notApplicable)
        XCTAssertEqual(
            summaries.first { $0.scope == "grammar" }?.truePositive,
            1
        )
    }

    func testAccuracyEvaluatorUsesDefinitionClassificationAndAlignment() {
        let fixtures = [
            fixture(
                id: "definition-match",
                category: .definition,
                expected: .definition(
                    AIConnectorPhaseZeroExpectedDefinition(
                        classification: .explicitDefinition,
                        alignment: .matches
                    )
                )
            ),
            fixture(
                id: "definition-wrong",
                category: .definition,
                expected: .definition(
                    AIConnectorPhaseZeroExpectedDefinition(
                        classification: .explicitDefinition,
                        alignment: .mismatch
                    )
                )
            ),
            fixture(
                id: "definition-missing",
                category: .definition,
                expected: .definition(
                    AIConnectorPhaseZeroExpectedDefinition(
                        classification: .notDefinition,
                        alignment: .notApplicable
                    )
                )
            )
        ]
        let results = [
            "definition-match": result(
                id: 1,
                definitionAssessment: makeDefinitionAssessment(
                    id: 1,
                    classification: .explicitDefinition,
                    alignment: .matches
                )
            ),
            "definition-wrong": result(
                id: 2,
                definitionAssessment: makeDefinitionAssessment(
                    id: 2,
                    classification: .explicitDefinition,
                    alignment: .matches
                )
            )
        ]

        let definitionSummary = AIConnectorPhaseZeroAccuracyEvaluator()
            .summaries(fixtures: fixtures, resultsByFixtureID: results)
            .first { $0.scope == "definition" }

        XCTAssertEqual(definitionSummary?.fixtureCount, 3)
        XCTAssertEqual(definitionSummary?.expectedFindingCount, 3)
        XCTAssertEqual(definitionSummary?.actualFindingCount, 2)
        XCTAssertEqual(definitionSummary?.truePositive, 1)
        XCTAssertEqual(definitionSummary?.falsePositive, 1)
        XCTAssertEqual(definitionSummary?.falseNegative, 2)
        XCTAssertEqual(definitionSummary?.exactSpanCorrectCount, 1)
        XCTAssertEqual(definitionSummary?.exactSpanTotalCount, 3)
    }

    func testAccuracyEvaluatorMatchesExpectedReviewStatus() {
        let fixtures = [
            fixture(
                id: "needs-review",
                category: .grammar,
                expected: .findings([
                    AIConnectorPhaseZeroExpectedFinding(
                        status: .needsReview,
                        category: .grammar,
                        original: "ambigu",
                        replacement: "jelas"
                    )
                ])
            )
        ]
        let results = [
            "needs-review": result(
                id: 1,
                reviews: [
                    makeReview(
                        segmentID: 1,
                        status: .needsReview,
                        category: .grammar,
                        original: "ambigu",
                        replacement: "jelas",
                        origin: .qwen
                    )
                ]
            )
        ]

        let summary = AIConnectorPhaseZeroAccuracyEvaluator()
            .summaries(fixtures: fixtures, resultsByFixtureID: results)
            .first { $0.scope == "all" }

        XCTAssertEqual(summary?.truePositive, 1)
        XCTAssertEqual(summary?.falsePositive, 0)
        XCTAssertEqual(summary?.falseNegative, 0)
        XCTAssertEqual(summary?.exactSpanCorrectCount, 1)
    }

    func testBaselineRunnerExecutesPreparationAndFourRunsInOrder() async {
        let fixture = fixture(
            id: "runner-fixture",
            category: .hardNegative,
            expected: .noChange
        )
        var events: [String] = []
        let runner = AIConnectorPhaseZeroBaselineRunner(
            fixtures: [fixture],
            modelVariant: .qwen35Base4B,
            pipelineVersion: "test-pipeline",
            rulePackVersion: "test-rules",
            corpusVersion: "test-corpus",
            preparationHandler: { collector in
                events.append("resourcePreparation")
                await collector.recordStage(
                    .resourcePreparation,
                    duration: 0.25,
                    resource: "mock"
                )
            },
            executionHandler: { kind, fixtures, collector in
                events.append(kind.rawValue)
                await collector.setInputMetadata(
                    utf16Length: fixtures[0].text.utf16.count,
                    segmentCount: 1
                )
                let observation = await collector.finish(status: .completed)
                return AIConnectorPhaseZeroExecution(
                    observation: observation,
                    resultsByFixtureID: [:]
                )
            }
        )

        let report = await runner.run()

        XCTAssertEqual(
            events,
            [
                "resourcePreparation",
                "deterministic-cold",
                "hybrid-steady-state",
                "model-only-steady-state",
                "hybrid-warm-cache"
            ]
        )
        XCTAssertEqual(
            report.runs.map(\.kind),
            AIConnectorPhaseZeroRunKind.allCases
        )
        XCTAssertEqual(
            report.runs.map(\.cacheResetBeforeRun),
            [true, true, true, false]
        )
        XCTAssertEqual(report.terminalStatus, .completed)
        XCTAssertEqual(report.fixtureCount, 1)
        XCTAssertEqual(report.fixtureReviewStatus, .pendingLawyerReview)
        XCTAssertEqual(report.comparison.modes.count, 3)
        XCTAssertEqual(
            report.comparison.modes.first { $0.mode == .hybrid }?.runKinds,
            [.hybridSteadyState, .hybridWarmCache]
        )
    }

    func testBaselineRunnerReturnsPartialReportAfterCancellation() async {
        let fixture = fixture(
            id: "cancel-fixture",
            category: .hardNegative,
            expected: .noChange
        )
        var executedKinds: [AIConnectorPhaseZeroRunKind] = []
        let runner = AIConnectorPhaseZeroBaselineRunner(
            fixtures: [fixture],
            executionHandler: { kind, _, collector in
                executedKinds.append(kind)
                if kind == .hybridSteadyState {
                    throw CancellationError()
                }
                let observation = await collector.finish(status: .completed)
                return AIConnectorPhaseZeroExecution(
                    observation: observation,
                    resultsByFixtureID: [:]
                )
            }
        )

        let report = await runner.run()

        XCTAssertEqual(
            executedKinds,
            [.deterministicCold, .hybridSteadyState]
        )
        XCTAssertEqual(report.terminalStatus, .cancelled)
        XCTAssertEqual(report.runs.count, 2)
        XCTAssertEqual(report.runs.last?.observation.terminalStatus, .cancelled)
        XCTAssertEqual(report.fixtureCount, 1)
    }

    func testSafeExportIsStableAndDoesNotContainInputOrModelText() async throws {
        let sentinel = "SECRET_DOCUMENT_SENTINEL"
        let sourceURL = try XCTUnwrap(
            URL(string: "https://\(sentinel).invalid")
        )
        let officialDocumentURL = try XCTUnwrap(
            URL(string: "https://official.invalid/\(sentinel)")
        )
        let sourcePassageURL = try XCTUnwrap(
            URL(string: "https://source.invalid/\(sentinel)")
        )
        let entry = LegalDictionaryEntry(
            id: sentinel,
            term: sentinel,
            definition: sentinel,
            regulation: sentinel,
            regulationTitle: sentinel,
            sourceURL: sourceURL,
            officialDocumentURL: officialDocumentURL,
            sources: [sentinel],
            sourceURLs: [sourcePassageURL],
            referenceID: sentinel,
            authority: .verified,
            corpusVersion: "safe-test-v1",
            applicabilityStatus: .inForce,
            sourcePassageID: sentinel,
            articleLocator: sentinel,
            isActionable: true
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 0.9,
            rank: 1,
            matchedDefinitionTokenCount: 1,
            isDirectTermMatch: true,
            semanticScore: 0.8,
            fusionScore: 0.7,
            retrievalOrigin: .hybrid
        )
        let segment = makeSegment(id: 1, target: sentinel)
        let result = AIConnectorSegmentResult(
            segment: segment,
            glossaryMatches: [match],
            reviews: [
                makeReview(
                    segment: segment,
                    status: .suggestion,
                    category: .terminology,
                    original: sentinel,
                    replacement: sentinel,
                    origin: .qwen,
                    glossaryMatch: match
                )
            ],
            rejections: [
                AIReviewRejection(
                    segment: segment,
                    rawOutput: sentinel,
                    reason: sentinel
                )
            ],
            definitionAssessment: makeDefinitionAssessment(
                id: 1,
                classification: .needsReview,
                alignment: .needsReview,
                term: sentinel,
                statementText: sentinel,
                reason: sentinel
            ),
            definitionModelCallCount: 1
        )
        let collector = AIConnectorObservationCollector(
            runID: UUID(),
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            pipelineVersion: "test-pipeline",
            rulePackVersion: "test-rules",
            corpusVersion: "test-corpus"
        )
        await collector.setInputMetadata(
            utf16Length: sentinel.utf16.count,
            segmentCount: 1
        )
        await collector.recordSegmentResult(result, duration: 0.5)
        await collector.setIncrementalAnalysisMetrics(
            AIConnectorIncrementalAnalysisMetrics(
                scope: .incrementalDocument,
                reusedSegmentCount: 2,
                reprocessedSegmentCount: 1,
                invalidatedSegmentCount: 1,
                cacheLookupCount: 1,
                cacheHitCount: 1,
                firstResultLatency: 0.25,
                totalDuration: 0.5
            )
        )
        let observation = await collector.finish(status: .completed)
        let suite = AIConnectorBaselineSuiteReport(
            schemaVersion: AIConnectorBaselineSuiteReport.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 0),
            terminalStatus: .completed,
            fixtureCount: 60,
            fixtureReviewStatus: .pendingLawyerReview,
            modelVariant: .qwen35Base4B,
            modelRevision: "test-revision",
            generationProfile: "greedy",
            thinkingEnabled: false,
            pipelineVersion: "test-pipeline",
            rulePackVersion: "test-rules",
            corpusVersion: "test-corpus",
            resourcePreparation: nil,
            runs: [
                AIConnectorBaselineRunReport(
                    kind: .hybridSteadyState,
                    mode: .hybrid,
                    cacheResetBeforeRun: true,
                    observation: observation
                )
            ],
            comparison: AIConnectorBaselineComparisonSummary(modes: []),
            failureCode: nil
        )

        let firstEncoding = try AIConnectorObservationExporter.encode(suite)
        let secondEncoding = try AIConnectorObservationExporter.encode(suite)
        XCTAssertEqual(firstEncoding, secondEncoding)
        let json = try XCTUnwrap(String(data: firstEncoding, encoding: .utf8))
        XCTAssertTrue(json.contains("phase0-observability-v1"))
        XCTAssertFalse(json.contains(sentinel))
        XCTAssertFalse(json.contains("https://"))
        XCTAssertFalse(json.contains("rawOutput"))
        XCTAssertFalse(json.contains("sourceWindow"))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amt-phase0-export-\(UUID().uuidString).json")
        let writtenURL = try AIConnectorObservationExporter.write(
            suite,
            to: outputURL
        )
        XCTAssertEqual(writtenURL, outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(try Data(contentsOf: outputURL), firstEncoding)
        try FileManager.default.removeItem(at: outputURL)
    }

    func testSafeExportReportsTypedWriteFailure() async throws {
        let collector = AIConnectorObservationCollector()
        let observation = await collector.finish(status: .completed)
        let suite = AIConnectorBaselineSuiteReport(
            schemaVersion: AIConnectorBaselineSuiteReport.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 0),
            terminalStatus: .completed,
            fixtureCount: 0,
            fixtureReviewStatus: .pendingLawyerReview,
            modelVariant: .qwen35Base4B,
            modelRevision: "test-revision",
            generationProfile: "greedy",
            thinkingEnabled: false,
            pipelineVersion: "test-pipeline",
            rulePackVersion: "test-rules",
            corpusVersion: "test-corpus",
            resourcePreparation: nil,
            runs: [],
            comparison: AIConnectorBaselineComparisonSummary(modes: []),
            failureCode: nil
        )

        let directoryURL = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(
            try AIConnectorObservationExporter.write(suite, to: directoryURL)
        ) { error in
            XCTAssertEqual(
                error as? AIConnectorObservationExportError,
                .writeFailed
            )
        }
        XCTAssertEqual(observation.terminalStatus, .completed)
    }

    private func fixture(
        id: String,
        category: AIConnectorPhaseZeroFixtureCategory,
        expected: AIConnectorPhaseZeroFixtureExpectation
    ) -> AIConnectorPhaseZeroFixture {
        AIConnectorPhaseZeroFixture(
            id: id,
            category: category,
            text: "Fixture \(id)",
            expected: expected,
            difficulty: "test"
        )
    }

    private func result(
        id: Int,
        reviews: [AIValidatedReview] = [],
        definitionAssessment: AIConnectorDefinitionAssessment? = nil
    ) -> AIConnectorSegmentResult {
        AIConnectorSegmentResult(
            segment: makeSegment(id: id, target: "Fixture \(id)"),
            reviews: reviews,
            definitionAssessment: definitionAssessment
        )
    }

    private func makeSegment(
        id: Int,
        target: String
    ) -> AIReviewSegment {
        AIReviewSegment(
            id: id,
            sourceLocation: id * 10,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }

    private func makeReview(
        segmentID: Int,
        status: AIReviewStatus,
        category: AIReviewCategory,
        original: String?,
        replacement: String?,
        origin: AIReviewOrigin
    ) -> AIValidatedReview {
        makeReview(
            segment: makeSegment(id: segmentID, target: "Fixture \(segmentID)"),
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            origin: origin
        )
    }

    private func makeReview(
        segment: AIReviewSegment,
        status: AIReviewStatus,
        category: AIReviewCategory,
        original: String?,
        replacement: String?,
        origin: AIReviewOrigin,
        glossaryMatch: LegalDictionaryMatch? = nil
    ) -> AIValidatedReview {
        AIValidatedReview(
            segment: segment,
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            reason: "test reason",
            glossaryMatch: glossaryMatch,
            origin: origin
        )
    }

    private func makeDefinitionAssessment(
        id: Int,
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment,
        term: String = "Term",
        statementText: String = "Statement",
        reason: String = "test reason"
    ) -> AIConnectorDefinitionAssessment {
        let segment = makeSegment(id: id, target: statementText)
        return AIConnectorDefinitionAssessment(
            segment: segment,
            term: term,
            statementText: statementText,
            candidate: nil,
            candidateCount: 0,
            detection: .explicitPattern,
            classification: classification,
            alignment: alignment,
            reason: reason,
            origin: .qwen,
            modelReviewed: true,
            retrievalOrigin: nil,
            semanticScore: nil,
            requiresHumanReview: true
        )
    }
}
#endif
