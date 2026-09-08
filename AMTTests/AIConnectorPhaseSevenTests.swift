import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseSevenTests: XCTestCase {
    func testLocalEditReusesUnchangedSectionAndReprocessesChangedSection() {
        let oldText = "BAB I\nPihak Pertama wajib menjaga data.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        let newText = "BAB I\nPihak Pertama wajib menjaga data rahasia.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        let old = makeBaseline(text: oldText)
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: newText)
        let segmentation = LegalTextSegmenter().segment(
            documentText: newText,
            structure: structure,
            profile: nil
        )

        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: old.baseline,
            documentText: newText,
            structure: structure,
            segmentation: segmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: old.baseline.analysisProfile
        )

        XCTAssertFalse(plan.isFullRerun)
        XCTAssertEqual(plan.reusedSegmentCount, 1)
        XCTAssertEqual(plan.reprocessedSegmentCount, 1)
        XCTAssertEqual(plan.changeSet.reasons, [.editedSegment])
    }

    func testSectionScopeOnlyInvalidatesSelectedSection() {
        let text = "BAB I\nPihak Pertama wajib menjaga data.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        let old = makeBaseline(text: text)
        guard let selectedSectionID = old.structure.sections.first?.id else {
            return XCTFail("Expected a heading-backed section.")
        }
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let segmentation = LegalTextSegmenter().segment(
            documentText: text,
            structure: structure,
            profile: nil
        )

        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: old.baseline,
            documentText: text,
            structure: structure,
            segmentation: segmentation,
            scope: .section,
            selectedSectionID: selectedSectionID,
            currentAnalysisProfile: old.baseline.analysisProfile
        )

        XCTAssertFalse(plan.isFullRerun)
        XCTAssertEqual(plan.reprocessedSegmentCount, 1)
        XCTAssertEqual(plan.reusedSegmentCount, 1)
        XCTAssertTrue(plan.dependencySectionIDs.isEmpty)
    }

    func testDuplicateOccurrencesMapIndependently() {
        let text = "BAB I\nPihak Pertama wajib menjaga data.\nPihak Pertama wajib menjaga data."
        let old = makeBaseline(text: text)
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let segmentation = LegalTextSegmenter().segment(
            documentText: text,
            structure: structure,
            profile: nil
        )

        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: old.baseline,
            documentText: text,
            structure: structure,
            segmentation: segmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: old.baseline.analysisProfile
        )

        XCTAssertEqual(plan.mappings.count, 2)
        XCTAssertEqual(Set(plan.mappings.map(\.oldSegmentID)).count, 2)
        XCTAssertEqual(Set(plan.mappings.map(\.newSegmentID)).count, 2)
        XCTAssertEqual(plan.reusedSegmentCount, 2)
        XCTAssertEqual(plan.reprocessedSegmentCount, 0)
    }

    func testDefinitionDependencyExpandsToEverySection() {
        let oldText = "BAB I\n\"Data\" adalah informasi umum.\nBAB II\nPihak Kedua wajib menjaga data."
        let newText = "BAB I\n\"Data\" adalah informasi pribadi.\nBAB II\nPihak Kedua wajib menjaga data."
        let old = makeBaseline(text: oldText)
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: newText)
        let segmentation = LegalTextSegmenter().segment(
            documentText: newText,
            structure: structure,
            profile: nil
        )

        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: old.baseline,
            documentText: newText,
            structure: structure,
            segmentation: segmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: old.baseline.analysisProfile
        )

        XCTAssertTrue(plan.changeSet.reasons.contains(.definitionDependency))
        XCTAssertTrue(plan.requiresDocumentReview)
        XCTAssertEqual(plan.reprocessedSegmentCount, segmentation.segments.count)
        XCTAssertEqual(plan.reusedSegmentCount, 0)
    }

    func testChangedRangeUsesUTF16OffsetsAfterEmoji() {
        let oldText = "BAB I\nEmoji 😀 tetap.\nBAB II\nData tetap."
        let newText = "BAB I\nEmoji 😀 berubah.\nBAB II\nData tetap."
        let old = makeBaseline(text: oldText)
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: newText)
        let segmentation = LegalTextSegmenter().segment(
            documentText: newText,
            structure: structure,
            profile: nil
        )

        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: old.baseline,
            documentText: newText,
            structure: structure,
            segmentation: segmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: old.baseline.analysisProfile
        )

        let expectedLocation = (newText as NSString).range(of: "berubah").location
        XCTAssertEqual(plan.changeSet.changedNewRanges.first?.location, expectedLocation)
        XCTAssertGreaterThan(expectedLocation, "Emoji ".utf16.count)
    }

    func testRematerializeShiftsUnchangedAnchoredResultAfterEarlierEdit() throws {
        let oldText = "BAB I\nPihak Pertama wajib menjaga data.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        let newText = "BAB I\nPihak Pertama wajib menjaga data yang bersifat rahasia.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        let old = makeBaseline(text: oldText)
        let oldSegment = try XCTUnwrap(old.segmentation.segments.last)
        let original = "wajib menjaga"
        let localRange = (oldSegment.targetText as NSString).range(of: original)
        let review = AIValidatedReview(
            segment: oldSegment,
            status: .suggestion,
            category: .grammar,
            original: original,
            replacement: "harus menjaga",
            reason: "Test",
            glossaryMatch: nil,
            origin: .deterministic,
            sourceAnchor: AIConnectorReviewAnchor(
                segmentID: oldSegment.id,
                sourceRange: localRange,
                original: original
            )
        )
        let baseline = AIConnectorAnalysisBaseline(
            documentText: old.baseline.documentText,
            structure: old.baseline.structure,
            profile: old.baseline.profile,
            segmentation: old.baseline.segmentation,
            analysisProfile: old.baseline.analysisProfile,
            validatedReviews: [review],
            definitionAssessments: [],
            documentFindings: [],
            ignoredReviewItemIDs: [],
            reviewedReviewItemIDs: []
        )
        let newStructure = AIConnectorDocumentStructureBuilder().build(documentText: newText)
        let newSegmentation = LegalTextSegmenter().segment(
            documentText: newText,
            structure: newStructure,
            profile: nil
        )
        let plan = AIConnectorIncrementalAnalysisPlanner().makePlan(
            previous: baseline,
            documentText: newText,
            structure: newStructure,
            segmentation: newSegmentation,
            scope: .incrementalDocument,
            currentAnalysisProfile: baseline.analysisProfile
        )

        let result = AIConnectorIncrementalAnalysisPlanner().rematerialize(
            reviews: [review],
            assessments: [],
            findings: [],
            baseline: baseline,
            plan: plan,
            newText: newText,
            newSegmentation: newSegmentation
        )
        let rematerialized = try XCTUnwrap(result.reviews.first)
        let newSegment = try XCTUnwrap(newSegmentation.segments.last)

        XCTAssertEqual(rematerialized.segment.id, newSegment.id)
        XCTAssertEqual(rematerialized.segment.sourceLocation, newSegment.sourceLocation)
        XCTAssertEqual(rematerialized.sourceAnchor?.range, localRange)
        XCTAssertTrue(
            rematerialized.sourceAnchor?.isValid(
                for: newSegment,
                original: original
            ) == true
        )
    }

    func testSegmentCacheEvictsLeastRecentlyUsedEntriesAtPerDocumentLimit() async {
        let cache = AIConnectorSegmentCache()
        let value = AIConnectorCachedSegmentResult(
            reviews: [],
            rejectionReasons: [],
            modelAttempts: 0,
            repairAttempted: false,
            usedFallback: false,
            firstPassSucceeded: true
        )

        for index in 0...AIConnectorSegmentCache.maximumEntriesPerDocument {
            await cache.insert(value, for: "key-\(index)")
        }
        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot.count, AIConnectorSegmentCache.maximumEntriesPerDocument)
        let evicted = await cache.value(for: "key-0")
        let newest = await cache.value(for: "key-256")
        XCTAssertNil(evicted)
        XCTAssertNotNil(newest)
    }

    func testProgressSnapshotClampsIncrementalCounts() {
        let snapshot = AIConnectorProgressSnapshot(
            stage: .generation,
            overallFraction: 0.5,
            phaseFraction: nil,
            completedSegmentCount: 1,
            totalSegmentCount: 4,
            currentSegmentID: 2,
            generationCharacters: 0,
            startedAt: Date(timeIntervalSince1970: 1),
            lastActivityAt: Date(timeIntervalSince1970: 2),
            reusedSegmentCount: -2,
            reprocessedSegmentCount: 3,
            pendingSegmentCount: -1
        )

        XCTAssertEqual(snapshot.reusedSegmentCount, 0)
        XCTAssertEqual(snapshot.reprocessedSegmentCount, 3)
        XCTAssertEqual(snapshot.pendingSegmentCount, 0)
    }

    func testAnalysisStageLRURefreshesRecencyBeforeEviction() {
        var cache = AIConnectorAnalysisLRUCache<String>(capacity: 2)
        cache["a"] = "A"
        cache["b"] = "B"
        XCTAssertEqual(cache["a"], "A")
        cache["c"] = "C"

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache["b"])
        XCTAssertEqual(cache["a"], "A")
        XCTAssertEqual(cache["c"], "C")
    }

    func testPlannerBenchmarkCoversColdWarmEditsAndFreshRun() {
        let report = AIConnectorIncrementalBenchmarkRunner().run(
            documentText: "BAB I\nPihak Pertama wajib menjaga Data Pribadi.\nBAB II\nPihak Kedua wajib menjaga dokumen."
        )

        XCTAssertEqual(
            report.cases.map(\.scenario),
            [.coldRun, .warmRerun, .localEdit, .definitionDependency, .fullFreshRerun]
        )
        XCTAssertTrue(report.plannerOnly)
        XCTAssertEqual(report.totalModelCallCount, 0)
        XCTAssertGreaterThan(report.cases[1].reusedSegmentCount, 0)
        XCTAssertGreaterThanOrEqual(report.p50Duration, 0)
        XCTAssertGreaterThanOrEqual(report.p95Duration, report.p50Duration)
    }

    private func makeBaseline(text: String) -> (
        structure: AIConnectorDocumentStructure,
        segmentation: AITextSegmentationResult,
        baseline: AIConnectorAnalysisBaseline
    ) {
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let segmentation = LegalTextSegmenter().segment(
            documentText: text,
            structure: structure,
            profile: nil
        )
        let analysisProfile = AIConnectorAnalysisProfile(
            pipelineVersion: "phase7-test",
            reviewMode: .deterministic,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            generationProfilePreset: .greedy,
            corpusVersion: "test-corpus",
            semanticModelRevision: "test-semantic",
            semanticEmbeddingSchema: "test-schema",
            semanticRetrievalProfile: "test-retrieval"
        )
        return (
            structure,
            segmentation,
            AIConnectorAnalysisBaseline(
                documentText: text,
                structure: structure,
                profile: nil,
                segmentation: segmentation,
                analysisProfile: analysisProfile,
                validatedReviews: [],
                definitionAssessments: [],
                documentFindings: [],
                ignoredReviewItemIDs: [],
                reviewedReviewItemIDs: []
            )
        )
    }
}
