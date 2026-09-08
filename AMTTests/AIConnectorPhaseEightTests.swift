#if DEBUG
import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseEightTests: XCTestCase {
    func testCatalogIncludesPhaseZeroAdaptationAndDocumentScenarios() {
        let fixtures = AIConnectorQualityFixtureCatalog.fixtures

        XCTAssertGreaterThanOrEqual(fixtures.count, 65)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
        XCTAssertTrue(fixtures.contains { $0.id.hasPrefix("phase8-") && $0.category == .spelling })
        XCTAssertTrue(fixtures.contains { $0.scenarioID == "defined-term-casing" })
        XCTAssertTrue(fixtures.contains { $0.scenarioID == "internal-reference-missing" })
        XCTAssertTrue(fixtures.contains { $0.scenarioID == "isolated-modal-hard-negative" })
        XCTAssertTrue(fixtures.contains { $0.scenarioID == "definition-resolution-source" })
        XCTAssertTrue(fixtures.contains { $0.scenarioID == "incremental-definition-change" })
        XCTAssertTrue(fixtures.allSatisfy { $0.reviewStatus == .pending })
    }

    func testReviewPackageRoundTripAndGuideContainsFixtureText() throws {
        let fixture = makeFixture(
            id: "phase8-package-fixture",
            category: .spelling,
            text: "Sentinel legal text untuk review lokal."
        )
        let package = try AIConnectorQualityReviewPackageService.makePackage(fixtures: [fixture])
        XCTAssertTrue(package.reviewGuideMarkdown.contains(fixture.text))
        XCTAssertTrue(package.reviewGuideMarkdown.contains(fixture.id))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("amt-phase8-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = root.appendingPathComponent("review.amtquality", isDirectory: true)
        _ = try AIConnectorQualityReviewPackageService.export(package, to: destination)
        let loaded = try AIConnectorQualityReviewPackageService.load(from: destination)
        XCTAssertEqual(loaded.fixtures, package.fixtures)
        XCTAssertEqual(loaded.reviews, package.reviews)
        XCTAssertEqual(loaded.manifest.packageID, package.manifest.packageID)
        XCTAssertEqual(loaded.manifest.fixtureJSONDigest, package.manifest.fixtureJSONDigest)
        XCTAssertEqual(loaded.manifest.reviewGuideDigest, package.manifest.reviewGuideDigest)
    }

    func testReviewPackageRejectsStaleAndDuplicateReviews() throws {
        let fixture = makeFixture(id: "phase8-review-validation", category: .grammar)
        let stale = AIConnectorLawyerReviewRecord(
            fixtureID: fixture.id,
            fixtureRevision: fixture.revision,
            fixtureDigest: "stale",
            reviewerID: "lawyer-local",
            reviewedAt: Date(),
            status: .approved,
            classificationApproved: true,
            replacementApproved: true,
            sourceApproved: true,
            applicabilityApproved: true,
            hardNegativeApproved: true,
            safetyApproved: true,
            notes: nil
        )
        XCTAssertThrowsError(
            try AIConnectorQualityReviewPackageService.makePackage(
                fixtures: [fixture],
                reviews: [stale]
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorQualityPackageError, .staleReview(fixture.id))
        }

        let approved = approvedReview(for: fixture)
        let duplicatePackage = AIConnectorQualityReviewPackage(
            manifest: AIConnectorQualityReviewPackageManifest(
                schemaVersion: AIConnectorQualityReviewPackageManifest.schemaVersion,
                packageID: UUID(),
                generatedAt: Date(),
                fixtureCatalogVersion: AIConnectorQualityFixtureCatalog.version,
                fixtureCount: 1,
                fixtureJSONDigest: "invalid",
                reviewGuideDigest: "invalid",
                includedFiles: [
                    AIConnectorQualityReviewPackageService.manifestFileName,
                    AIConnectorQualityReviewPackageService.fixturesFileName,
                    AIConnectorQualityReviewPackageService.reviewsFileName,
                    AIConnectorQualityReviewPackageService.guideFileName
                ]
            ),
            fixtures: [fixture],
            reviews: [approved, approved],
            reviewGuideMarkdown: "invalid"
        )
        XCTAssertThrowsError(try AIConnectorQualityReviewPackageService.validate(duplicatePackage)) { error in
            XCTAssertEqual(error as? AIConnectorQualityPackageError, .invalidManifest)
        }
    }

    func testPackageRejectsUnverifiedAnonymizedFixtureAndSplitLeakage() {
        let anonymized = AIConnectorQualityFixture(
            id: "phase8-anonymized-without-check",
            scenarioID: "anonymized-without-check",
            category: .spelling,
            split: .calibration,
            provenance: .anonymized,
            text: "Teks anonim.",
            expected: AIConnectorQualityExpectation(noChange: true),
            question: "Hak penggunaan?"
        )
        XCTAssertThrowsError(try AIConnectorQualityReviewPackageService.makePackage(fixtures: [anonymized])) { error in
            XCTAssertEqual(error as? AIConnectorQualityPackageError, .invalidFixture(anonymized.id))
        }

        let first = makeFixture(id: "phase8-same-scenario-a", category: .spelling)
        let second = AIConnectorQualityFixture(
            id: "phase8-same-scenario-b",
            scenarioID: first.scenarioID,
            category: .spelling,
            split: .holdout,
            text: first.text,
            expected: first.expected,
            question: first.question
        )
        XCTAssertThrowsError(try AIConnectorQualityReviewPackageService.makePackage(fixtures: [first, second])) { error in
            XCTAssertEqual(error as? AIConnectorQualityPackageError, .invalidFixture(second.id))
        }
    }

    func testFixtureStoreRemovesApprovalWhenFixtureRevisionChanges() throws {
        let fixture = makeFixture(id: "phase8-store-revision", category: .terminology)
        let approved = approvedReview(for: fixture)
        let store = AIConnectorQualityFixtureStore(fixtures: [fixture], reviews: [approved])
        XCTAssertEqual(store.approvedFixtureCount, 1)

        let revised = AIConnectorQualityFixture(
            id: fixture.id,
            revision: fixture.revision + 1,
            scenarioID: fixture.scenarioID,
            category: fixture.category,
            split: fixture.split,
            text: fixture.text + " revised",
            expected: fixture.expected,
            sources: fixture.sources,
            question: fixture.question
        )
        let package = try AIConnectorQualityReviewPackageService.makePackage(fixtures: [revised])
        _ = try store.apply(package)
        XCTAssertEqual(store.approvedFixtureCount, 0)
        XCTAssertNil(store.review(for: fixture.id))
    }

    func testEvaluatorCountsDuplicateOccurrencesAndGrounding() {
        let source = AIConnectorQualityExpectedSource(
            id: "source-1",
            corpusEntryID: "entry-1",
            referenceID: "UU-1",
            evidenceID: "passage-1",
            applicabilityStatus: "in_force",
            verified: true,
            isActionable: true
        )
        let fixture = AIConnectorQualityFixture(
            id: "phase8-evaluator-duplicate",
            scenarioID: "duplicate-occurrence",
            category: .terminology,
            split: .calibration,
            text: "Data pribadi dan data pribadi.",
            expected: AIConnectorQualityExpectation(findings: [
                AIConnectorQualityExpectedFinding(
                    occurrence: 0,
                    category: .terminology,
                    status: "SUGGESTION",
                    original: "data pribadi",
                    replacement: "Data Pribadi",
                    sourceID: source.id
                ),
                AIConnectorQualityExpectedFinding(
                    occurrence: 1,
                    category: .terminology,
                    status: "SUGGESTION",
                    original: "data pribadi",
                    replacement: "Data Pribadi",
                    sourceID: source.id
                )
            ]),
            sources: [source],
            question: "duplicate occurrence"
        )
        let observed = AIConnectorQualityObservedOutput(
            fixtureID: fixture.id,
            complete: true,
            findings: [
                observedFinding(occurrence: 0, category: .terminology, sourceID: source.id),
                observedFinding(occurrence: 1, category: .terminology, sourceID: source.id)
            ],
            safety: .zero,
            firstResultLatency: 0.2,
            totalDuration: 1,
            stageDurations: ["review": 1],
            reusedSegmentCount: 0,
            recomputedSegmentCount: 1,
            modelCallCount: 0,
            resourcePreparationDuration: 0,
            incrementalEquivalentToFresh: nil
        )
        let policy = passingPolicy(for: .terminology)
        let report = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: policy,
            candidateManifest: makeManifest(fixtures: [fixture], policy: policy),
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: observed]) })
        )
        let summary = report.modes.first { $0.mode == .hybrid }?.categories.first { $0.category == .terminology }
        XCTAssertEqual(summary?.truePositive, 2)
        XCTAssertEqual(summary?.falsePositive, 0)
        XCTAssertEqual(summary?.falseNegative, 0)
        XCTAssertEqual(summary?.groundingRate, 1.0)
    }

    func testEvaluatorSafetyViolationFailsAndUncalibratedPolicyIsInsufficient() {
        let fixture = makeFixture(id: "phase8-safety", category: .spelling)
        let safeOutput = observedOutput(for: fixture)
        let unsafeOutput = AIConnectorQualityObservedOutput(
            fixtureID: safeOutput.fixtureID,
            complete: safeOutput.complete,
            findings: safeOutput.findings,
            safety: AIConnectorQualitySafetyObservation(
                staleApplyAttempts: 1,
                outOfRangeApplyAttempts: 0,
                readOnlyApplyAttempts: 0,
                ungroundedReplacementAttempts: 0
            ),
            firstResultLatency: safeOutput.firstResultLatency,
            totalDuration: safeOutput.totalDuration,
            stageDurations: safeOutput.stageDurations,
            reusedSegmentCount: safeOutput.reusedSegmentCount,
            recomputedSegmentCount: safeOutput.recomputedSegmentCount,
            modelCallCount: safeOutput.modelCallCount,
            resourcePreparationDuration: safeOutput.resourcePreparationDuration,
            incrementalEquivalentToFresh: safeOutput.incrementalEquivalentToFresh
        )
        let policy = passingPolicy(for: .spelling)
        let manifest = makeManifest(fixtures: [fixture], policy: policy)
        let failed = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: policy,
            candidateManifest: manifest,
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: unsafeOutput]) })
        )
        XCTAssertEqual(failed.overallStatus, .fail)
        XCTAssertTrue(failed.statusReasons.contains("safety-violation"))

        let insufficient = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: .uncalibrated,
            candidateManifest: AIConnectorQualityCandidateManifestFactory.make(
                fixtures: [fixture],
                policy: .uncalibrated,
                corpusVersion: "test-corpus"
            ),
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: safeOutput]) })
        )
        XCTAssertEqual(insufficient.overallStatus, .insufficientEvidence)

        let dirtyManifest = AIConnectorQualityCandidateManifestFactory.make(
            fixtures: [fixture],
            policy: policy,
            corpusVersion: "test-corpus",
            modelVariants: [.qwen35Base4B]
        )
        let dirtyReport = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: policy,
            candidateManifest: dirtyManifest,
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: safeOutput]) })
        )
        XCTAssertEqual(dirtyReport.overallStatus, .insufficientEvidence)
        XCTAssertTrue(dirtyReport.statusReasons.contains("candidate-worktree-dirty"))
    }

    func testSafeJSONDoesNotContainSentinelFromFixtureOrReviewer() throws {
        let fixture = makeFixture(
            id: "phase8-privacy",
            category: .definition,
            text: "SECRET_FIXTURE_TEXT"
        )
        let policy = passingPolicy(for: .definition)
        let report = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture, reviewerID: "SECRET_REVIEWER")],
            policy: policy,
            candidateManifest: makeManifest(fixtures: [fixture], policy: policy),
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: observedOutput(for: fixture)]) })
        )
        let data = try AIConnectorQualitySafeJSONExporter.encode(report)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET_FIXTURE_TEXT"))
        XCTAssertFalse(json.contains("SECRET_REVIEWER"))
        XCTAssertFalse(json.contains("SECRET_REPLACEMENT"))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("amt-phase8-safe-json-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("report.json")
        XCTAssertEqual(try AIConnectorQualitySafeJSONExporter.write(report, to: destination), destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try AIConnectorQualitySafeJSONExporter.encode(report), try Data(contentsOf: destination))
    }

    func testEmptyMetricDenominatorsRemainUnavailable() {
        let fixture = makeFixture(
            id: "phase8-no-change-metrics",
            category: .hardNegative,
            expected: AIConnectorQualityExpectation(noChange: true)
        )
        let output = observedOutput(for: fixture)
        let policy = passingPolicy(for: .hardNegative)
        let report = AIConnectorQualityEvaluator().evaluate(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: policy,
            candidateManifest: makeManifest(fixtures: [fixture], policy: policy),
            outputsByMode: Dictionary(uniqueKeysWithValues: AIConnectorReviewMode.allCases.map { ($0, [fixture.id: output]) })
        )
        let summary = report.modes.first { $0.mode == .hybrid }?.categories.first { $0.category == .hardNegative }
        XCTAssertNil(summary?.precision)
        XCTAssertNil(summary?.recall)
        XCTAssertEqual(summary?.noChangeAccuracy, 1)
    }

    func testRunnerStopsWithPartialReportAfterCancellation() async {
        let fixture = makeFixture(id: "phase8-runner", category: .spelling)
        let policy = passingPolicy(for: .spelling)
        let manifest = makeManifest(fixtures: [fixture], policy: policy)
        let runner = AIConnectorQualityRunner()
        var calls: [AIConnectorReviewMode] = []
        let report = await runner.run(
            fixtures: [fixture],
            reviews: [approvedReview(for: fixture)],
            policy: policy,
            candidateManifest: manifest,
            execution: { mode, fixture in
                calls.append(mode)
                throw CancellationError()
            }
        )
        XCTAssertEqual(calls, [.deterministic])
        XCTAssertEqual(report.terminalStatus, .partial)
        XCTAssertEqual(report.overallStatus, .insufficientEvidence)
    }

    private func makeFixture(
        id: String,
        category: AIConnectorQualityCategory,
        text: String = "teh Pihak wajib menjaga dokumen.",
        expected: AIConnectorQualityExpectation? = nil
    ) -> AIConnectorQualityFixture {
        AIConnectorQualityFixture(
            id: id,
            scenarioID: id,
            category: category,
            split: .calibration,
            text: text,
            expected: expected ?? AIConnectorQualityExpectation(findings: [
                AIConnectorQualityExpectedFinding(
                    occurrence: 0,
                    category: category,
                    status: "SUGGESTION",
                    original: "teh",
                    replacement: "the"
                )
            ]),
            question: "quality gate test"
        )
    }

    private func approvedReview(
        for fixture: AIConnectorQualityFixture,
        reviewerID: String = "lawyer-local"
    ) -> AIConnectorLawyerReviewRecord {
        AIConnectorLawyerReviewRecord(
            fixtureID: fixture.id,
            fixtureRevision: fixture.revision,
            fixtureDigest: fixture.fixtureDigest,
            reviewerID: reviewerID,
            reviewedAt: Date(),
            status: .approved,
            classificationApproved: true,
            replacementApproved: true,
            sourceApproved: true,
            applicabilityApproved: true,
            hardNegativeApproved: true,
            safetyApproved: true,
            notes: "SECRET_REPLACEMENT"
        )
    }

    private func observedFinding(
        occurrence: Int,
        category: AIConnectorQualityCategory,
        sourceID: String? = nil
    ) -> AIConnectorQualityObservedFinding {
        AIConnectorQualityObservedFinding(
            occurrence: occurrence,
            category: category,
            status: "SUGGESTION",
            original: "data pribadi",
            replacement: "Data Pribadi",
            classification: nil,
            sourceID: sourceID,
            sourceEvidenceID: sourceID == nil ? nil : "passage-1",
            sourceVerified: sourceID != nil,
            sourceActionable: sourceID != nil,
            readOnly: false,
            anchorValid: true
        )
    }

    private func observedOutput(for fixture: AIConnectorQualityFixture) -> AIConnectorQualityObservedOutput {
        AIConnectorQualityObservedOutput(
            fixtureID: fixture.id,
            complete: true,
            findings: fixture.expected.findings.map {
                AIConnectorQualityObservedFinding(
                    occurrence: $0.occurrence,
                    category: $0.category,
                    status: $0.status,
                    original: $0.original,
                    replacement: $0.replacement,
                    classification: $0.classification,
                    sourceID: $0.sourceID,
                    sourceEvidenceID: nil,
                    sourceVerified: false,
                    sourceActionable: false,
                    readOnly: $0.readOnly,
                    anchorValid: true
                )
            },
            safety: .zero,
            firstResultLatency: 0.1,
            totalDuration: 0.5,
            stageDurations: ["review": 0.5],
            reusedSegmentCount: 0,
            recomputedSegmentCount: 1,
            modelCallCount: 0,
            resourcePreparationDuration: 0,
            incrementalEquivalentToFresh: nil
        )
    }

    private func passingPolicy(for category: AIConnectorQualityCategory) -> AIConnectorQualityPolicy {
        AIConnectorQualityPolicy(
            policyID: "test-policy",
            revision: 1,
            approved: true,
            approvedBy: "lawyer-local",
            approvedAt: Date(),
            releaseMode: .hybrid,
            requiredCategories: [category],
            minimumSamplesByCategory: [category.rawValue: 1],
            thresholdsByCategory: [category.rawValue: AIConnectorQualityThreshold(
                minimumPrecision: 0,
                minimumRecall: 0,
                minimumF1: 0,
                maximumHardNegativeFalsePositiveRate: 1,
                minimumGroundingRate: 0,
                minimumExactSpanAccuracy: 0
            )],
            requiredFixtureSplits: [.calibration],
            requiredCoverageFraction: 1,
            hardwareProfile: nil
        )
    }

    private func makeManifest(
        fixtures: [AIConnectorQualityFixture],
        policy: AIConnectorQualityPolicy
    ) -> AIConnectorQualityCandidateManifest {
        AIConnectorQualityCandidateManifestFactory.make(
            fixtures: fixtures,
            policy: policy,
            corpusVersion: "test-corpus",
            modelVariants: [.qwen35Base4B],
            sourceRevision: "release-commit"
        )
    }
}
#endif
