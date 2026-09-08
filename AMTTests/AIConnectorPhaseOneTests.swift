import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseOneTests: XCTestCase {
    func testProductionCandidatePathDoesNotChallengeAnExplicitRejection() async throws {
        let calls = CallBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor [calls] request, _, _ in
            calls.requests.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .reject,
                metrics: AIConnectorGenerationMetrics(
                    promptTokenCount: 8,
                    generationTokenCount: 4,
                    promptDuration: 0.01,
                    generationDuration: 0.01,
                    stopReason: .stop
                ),
                containsReasoningMarkers: false
            )
        }

        let processor = AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: AIConnectorRuleStore(),
            candidateDecisionHandler: handler,
            enableCandidateChallenge: false
        )

        let result = try await processor.process(
            segment: AIReviewSegment(
                id: 1,
                sourceLocation: 0,
                sourceLength: "Pihak Kedua wajib untuk menyerahkan laporan.".utf16.count,
                targetText: "Pihak Kedua wajib untuk menyerahkan laporan.",
                previousContext: nil,
                nextContext: nil
            ),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(calls.requests.count, 1)
        XCTAssertNil(calls.requests.first?.retryInstruction)
        XCTAssertFalse(result.candidateDecisions.first?.challengeAttempted ?? true)
        XCTAssertEqual(result.challengeCount, 0)
        XCTAssertEqual(result.reviews.first?.status, .noSuggestion)
    }

    private final class CallBox: @unchecked Sendable {
        var requests: [AIConnectorCandidateReviewRequest] = []
    }
}
