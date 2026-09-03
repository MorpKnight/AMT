import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorLivenessTests: XCTestCase {
    func testAnalysisProgressTrackerNeverMovesBackWhenStageResetsForNextSegment() {
        var tracker = AIConnectorProgressTracker()

        tracker.advance(to: 0.66)
        tracker.advance(to: 0.32)

        XCTAssertEqual(
            tracker.value,
            0.66,
            "Stage berikutnya tidak boleh mengurangi progress yang sudah tercapai."
        )

        tracker.advance(to: 0.74)
        XCTAssertEqual(tracker.value, 0.74)
    }

    func testAnalysisProgressTrackerClampsNonFiniteValues() {
        var tracker = AIConnectorProgressTracker()

        tracker.advance(to: .infinity)
        XCTAssertEqual(tracker.value, 0)

        tracker.advance(to: 0.4)
        tracker.advance(to: .nan)
        XCTAssertEqual(tracker.value, 0.4)
    }

    func testProgressSnapshotSeparatesDocumentAndPhaseProgress() {
        let startDate = Date(timeIntervalSince1970: 3_000)
        let snapshot = AIConnectorProgressSnapshot(
            stage: .modelDownload,
            overallFraction: 0.25,
            phaseFraction: 0.42,
            completedSegmentCount: 2,
            totalSegmentCount: 8,
            currentSegmentID: 3,
            generationCharacters: 120,
            startedAt: startDate,
            lastActivityAt: startDate.addingTimeInterval(2)
        )

        XCTAssertTrue(snapshot.hasKnownOverallProgress)
        XCTAssertEqual(snapshot.overallFraction, 0.25)
        XCTAssertEqual(snapshot.phaseFraction, 0.42)
        XCTAssertEqual(snapshot.completedSegmentLabel, "2 dari 8 segmen selesai")
    }

    func testDeterministicRunReachesOneFromCompletedSegments() async {
        let startDate = Date(timeIntervalSince1970: 4_000)
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            now: { startDate }
        )
        viewModel.reviewMode = .deterministic
        viewModel.run(documentText: "Kalimat pertama.\n\nKalimat kedua.")

        for _ in 0..<500 {
            if !viewModel.isRunning { break }
            await Task.yield()
        }

        XCTAssertEqual(viewModel.totalSegmentCount, 2)
        XCTAssertEqual(viewModel.completedSegmentCount, 2)
        XCTAssertEqual(viewModel.analysisProgress, 1)
        XCTAssertEqual(viewModel.progressSnapshot.overallFraction, 1)
    }

    func testAnalysisLivenessIsNotStalledBeforeSixtySecondsAndIsStalledAtSixty() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            now: { startDate }
        )
        viewModel.reviewMode = .deterministic
        viewModel.run(documentText: "Kalimat untuk menguji liveness.")

        XCTAssertEqual(viewModel.analysisStartedAt, startDate)
        XCTAssertEqual(
            viewModel.analysisDuration(at: startDate.addingTimeInterval(59)),
            59
        )
        XCTAssertFalse(
            viewModel.isProgressStalled(at: startDate.addingTimeInterval(59)),
            "Peringatan tidak boleh muncul sebelum 60 detik tanpa heartbeat."
        )
        XCTAssertTrue(
            viewModel.isProgressStalled(at: startDate.addingTimeInterval(60)),
            "Batas 60 detik termasuk sebagai stalled state."
        )

        viewModel.cancel()
    }

    func testQueueAndResultActivityRefreshHeartbeatDuringDeterministicRun() async {
        let startDate = Date(timeIntervalSince1970: 2_000)
        var currentDate = startDate
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            now: { currentDate }
        )
        viewModel.reviewMode = .deterministic
        viewModel.run(documentText: "Kalimat pertama.\n\nKalimat kedua.")

        let activityDate = startDate.addingTimeInterval(1)
        currentDate = activityDate

        for _ in 0..<100 {
            if viewModel.lastProgressActivityAt >= activityDate {
                break
            }
            await Task.yield()
        }

        XCTAssertGreaterThanOrEqual(
            viewModel.lastProgressActivityAt,
            activityDate,
            "Event queue/result harus memperbarui heartbeat."
        )
        viewModel.cancel()
    }
}
