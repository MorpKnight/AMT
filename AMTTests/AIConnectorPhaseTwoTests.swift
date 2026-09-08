#if DEBUG
import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseTwoTests: XCTestCase {
    func testPolicyRoutesExactRuleWithoutModelAndProtectsDefinedContent() {
        let policy = AIConnectorPhaseTwoPolicy()
        let segment = makeSegment(target: "wajib untuk")
        let exact = makeCandidate(
            id: "C1",
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            evidence: AIConnectorCandidateEvidence(
                tier: .exactRule,
                sourceLocation: 0,
                spanLength: "wajib untuk".utf16.count,
                rulePriority: 10,
                sourceRank: 0,
                matchedDefinitionTokenCount: 0,
                semanticScore: nil,
                languageScoreDelta: nil,
                isDirectTermMatch: false,
                hasSourceAnchor: false,
                isUniqueSpan: true
            )
        )

        let exactRoute = policy.route(
            candidate: exact,
            in: segment,
            protectionContext: .empty,
            mode: .hybrid,
            forceDeterministic: false
        )
        XCTAssertEqual(exactRoute.route, .deterministic)
        XCTAssertEqual(exactRoute.reason, .exactRule)
        XCTAssertFalse(exactRoute.modelCallRequired)

        let protectedRoute = policy.route(
            candidate: exact,
            in: segment,
            protectionContext: AIConnectorDocumentProtectionContext(
                definedTerms: [],
                partyNames: ["wajib untuk"],
                acronyms: [],
                quotedTerms: [],
                identifiers: []
            ),
            mode: .hybrid,
            forceDeterministic: false
        )
        XCTAssertEqual(protectedRoute.route, .needsReview)
        XCTAssertEqual(protectedRoute.reason, .protectedContent)
        XCTAssertFalse(protectedRoute.modelCallRequired)
    }

    func testPolicyKeepsWeakEvidenceOutOfActionableSuggestions() {
        let policy = AIConnectorPhaseTwoPolicy()
        let segment = makeSegment(target: "istilah")
        let unknown = makeCandidate(
            id: "C1",
            original: "istilah",
            replacement: "Istilah",
            category: .terminology,
            evidence: .unknown
        )
        let weakSemantic = makeCandidate(
            id: "C2",
            original: "istilah",
            replacement: "Istilah hukum",
            category: .terminology,
            evidence: AIConnectorCandidateEvidence(
                tier: .semanticGlossary,
                sourceLocation: 0,
                spanLength: "istilah".utf16.count,
                rulePriority: 100,
                sourceRank: 1,
                matchedDefinitionTokenCount: 0,
                semanticScore: 0.69,
                languageScoreDelta: nil,
                isDirectTermMatch: false,
                hasSourceAnchor: true,
                isUniqueSpan: true
            )
        )

        let unknownRoute = policy.route(
            candidate: unknown,
            in: segment,
            protectionContext: .empty,
            mode: .hybrid,
            forceDeterministic: false
        )
        let weakRoute = policy.route(
            candidate: weakSemantic,
            in: segment,
            protectionContext: .empty,
            mode: .hybrid,
            forceDeterministic: false
        )

        XCTAssertEqual(unknownRoute.route, .suppressed)
        XCTAssertEqual(unknownRoute.reason, .weakEvidence)
        XCTAssertEqual(weakRoute.route, .needsReview)
        XCTAssertEqual(weakRoute.reason, .weakEvidence)
    }

    func testDeterministicModeDoesNotAutoAcceptGlossaryCandidate() {
        let policy = AIConnectorPhaseTwoPolicy()
        let candidate = makeCandidate(
            id: "C1",
            original: "data pribadi",
            replacement: "Data Pribadi",
            category: .terminology,
            evidence: makeEvidence(
                tier: .verifiedGlossary,
                location: 0,
                length: "data pribadi".utf16.count
            )
        )

        let route = policy.route(
            candidate: candidate,
            in: makeSegment(target: "data pribadi"),
            protectionContext: .empty,
            mode: .deterministic,
            forceDeterministic: true
        )

        XCTAssertEqual(route.route, .needsReview)
        XCTAssertEqual(route.reason, .modelRequired)
        XCTAssertFalse(route.modelCallRequired)
    }

    func testRankerPrefersHigherEvidenceAndDropsOverlap() {
        let ranker = AIConnectorPhaseTwoCandidateRanker()
        let exact = makeCandidate(
            id: "P1",
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            evidence: makeEvidence(tier: .exactRule, location: 0, length: 12)
        )
        let semantic = makeCandidate(
            id: "P2",
            original: "wajib",
            replacement: "harus",
            category: .terminology,
            evidence: makeEvidence(tier: .semanticGlossary, location: 0, length: 5)
        )

        let result = ranker.select([semantic, exact])

        XCTAssertEqual(result.candidates.map(\.id), ["C1"])
        XCTAssertEqual(result.candidates.first?.original, "wajib untuk")
        XCTAssertEqual(result.droppedCandidateCount, 1)
        XCTAssertEqual(result.conflictCount, 1)
    }

    func testPhaseTwoCacheNamespaceDiffersFromPhaseOne() {
        let segment = makeSegment(target: "wajib untuk")
        let profile = AIConnectorGenerationProfile(
            maxTokens: 128,
            temperature: 0,
            topP: 1,
            topK: 0,
            presencePenalty: nil,
            seed: 42
        )
        let common = { (policyVersion: String) in
            AIConnectorCacheKeyComponents(
                segment: segment,
                reviewMode: .hybrid,
                modelVariant: .qwen35Base4B,
                generationProfile: profile,
                promptVersion: "prompt",
                rulePackVersion: "rules",
                corpusVersion: "corpus",
                reviewPolicyVersion: policyVersion,
                validatorVersion: "validator",
                outputSchemaVersion: "schema",
                protectionContext: .empty
            )
        }

        let phaseOneKey = AIConnectorSegmentCache.key(
            from: common(AIConnectorPhaseTwoPolicy.disabledVersion)
        )
        let phaseTwoKey = AIConnectorSegmentCache.key(
            from: common(AIConnectorPhaseTwoPolicy.version)
        )

        XCTAssertNotEqual(phaseOneKey, phaseTwoKey)
    }

    func testProductionPhaseTwoPathRoutesExactRuleWithoutCallingModel() async throws {
        let calls = CallBox()
        let handler: AIConnectorCandidateDecisionHandler = { @MainActor [calls] request, _, _ in
            calls.count += 1
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: AIConnectorGenerationMetrics(
                    promptTokenCount: 1,
                    generationTokenCount: 1,
                    promptDuration: 0,
                    generationDuration: 0,
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
            enableCandidateChallenge: false,
            enablePhaseTwo: true
        )
        let target = "Pihak Kedua wajib untuk menyerahkan laporan."
        let result = try await processor.process(
            segment: makeSegment(target: target),
            documentProtectionContext: .empty,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(calls.count, 0)
        XCTAssertEqual(result.modelCallCount, 0)
        XCTAssertEqual(result.candidateRoutes.first?.route, .deterministic)
        XCTAssertEqual(result.candidateRoutes.first?.reason, .exactRule)
        XCTAssertEqual(result.reviews.first?.original, "wajib untuk")
        XCTAssertEqual(result.reviews.first?.replacement, "wajib")
    }

    func testComparisonRunnerRunsBothSidesInOrderAndKeepsSafeReport() async throws {
        let fixtures = [
            AIConnectorPhaseZeroFixture(
                id: "fixture-1",
                category: .hardNegative,
                text: "Tidak ada perubahan.",
                expected: .noChange,
                difficulty: "test"
            )
        ]
        var sides: [AIConnectorPhaseTwoComparisonSide] = []
        let runner = AIConnectorPhaseTwoComparisonRunner(
            fixtures: fixtures,
            pipelineVersion: "test-phase2",
            executionHandler: { side, mode, modelVariant, profile, thinkingEnabled, fixtures, collector in
                sides.append(side)
                let segment = AIReviewSegment(
                    id: 1,
                    sourceLocation: 0,
                    sourceLength: fixtures[0].text.utf16.count,
                    targetText: fixtures[0].text,
                    previousContext: nil,
                    nextContext: nil
                )
                let reviews: [AIValidatedReview] = side == .phaseTwo
                    ? [
                        AIValidatedReview(
                            segment: segment,
                            status: .needsReview,
                            category: .grammar,
                            original: "perubahan",
                            replacement: nil,
                            reason: "Perlu review manusia.",
                            glossaryMatch: nil,
                            origin: .deterministic
                        )
                    ]
                    : [
                        AIValidatedReview(
                            segment: segment,
                            status: .noSuggestion,
                            category: .none,
                            original: nil,
                            replacement: nil,
                            reason: "Tidak ada perubahan.",
                            glossaryMatch: nil,
                            origin: .deterministic
                        )
                    ]
                let result = AIConnectorSegmentResult(
                    segment: segment,
                    reviews: reviews,
                    candidates: [],
                    candidateRoutes: []
                )
                await collector.setInputMetadata(
                    utf16Length: segment.targetText.utf16.count,
                    segmentCount: 1
                )
                await collector.recordSegmentResult(result, duration: 0.25)
                let accuracy = AIConnectorPhaseZeroAccuracyEvaluator().summaries(
                    fixtures: fixtures,
                    resultsByFixtureID: [fixtures[0].id: result]
                )
                let observation = await collector.finish(
                    status: .completed,
                    accuracy: accuracy
                )
                return AIConnectorPhaseTwoRunExecution(
                    observation: observation,
                    resultsByFixtureID: [fixtures[0].id: result]
                )
            }
        )

        let report = await runner.run(
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            generationProfile: .greedy,
            thinkingEnabled: false
        )

        XCTAssertEqual(sides, [.phaseOneCompatible, .phaseTwo])
        XCTAssertEqual(report.terminalStatus, .completed)
        XCTAssertEqual(report.runs.map(\.side), [.phaseOneCompatible, .phaseTwo])
        XCTAssertEqual(report.fixtureReviewStatus, .pendingLawyerReview)
        XCTAssertEqual(report.runs.first?.accuracy.first?.noChangeCorrectCount, 1)
        XCTAssertEqual(report.delta?.modelCallCount, 0)
        XCTAssertEqual(report.delta?.needsReviewCount, 1)
    }

    func testComparisonRunnerReturnsPartialReportOnCancellation() async throws {
        let fixtures = [
            AIConnectorPhaseZeroFixture(
                id: "fixture-1",
                category: .hardNegative,
                text: "Tidak ada perubahan.",
                expected: .noChange,
                difficulty: "test"
            )
        ]
        let runner = AIConnectorPhaseTwoComparisonRunner(
            fixtures: fixtures,
            executionHandler: { side, _, _, _, _, fixtures, collector in
                if side == .phaseTwo {
                    throw CancellationError()
                }
                let segment = AIReviewSegment(
                    id: 1,
                    sourceLocation: 0,
                    sourceLength: fixtures[0].text.utf16.count,
                    targetText: fixtures[0].text,
                    previousContext: nil,
                    nextContext: nil
                )
                let observation = await collector.finish(status: .completed)
                return AIConnectorPhaseTwoRunExecution(
                    observation: observation,
                    resultsByFixtureID: [fixtures[0].id: AIConnectorSegmentResult(segment: segment)]
                )
            }
        )

        let report = await runner.run(
            mode: .deterministic,
            modelVariant: .qwen35Base4B,
            generationProfile: .greedy,
            thinkingEnabled: false
        )

        XCTAssertEqual(report.terminalStatus, .cancelled)
        XCTAssertEqual(report.runs.map(\.side), [.phaseOneCompatible, .phaseTwo])
        XCTAssertEqual(report.runs.last?.terminalStatus, .cancelled)
        XCTAssertNotNil(report.delta)
    }

    func testPhaseTwoExportIsSafeAndAtomic() async throws {
        let report = AIConnectorPhaseTwoComparisonReport(
            schemaVersion: AIConnectorPhaseTwoComparisonReport.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 0),
            terminalStatus: .completed,
            fixtureCount: 1,
            fixtureReviewStatus: .pendingLawyerReview,
            modelVariant: .qwen35Base4B,
            generationProfile: "greedy",
            thinkingEnabled: false,
            pipelineVersion: "test",
            resourcePreparation: nil,
            runs: [],
            delta: nil,
            failureCode: nil
        )
        let data = try AIConnectorPhaseTwoComparisonExporter.encode(report)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("SECRET_TARGET_TEXT"))
        XCTAssertTrue(
            AIConnectorPhaseTwoComparisonExporter.defaultFileName(
                at: Date(timeIntervalSince1970: 0)
            ).hasPrefix("amt-phase2-comparison-")
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("amt-phase2-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try AIConnectorPhaseTwoComparisonExporter.write(report, to: url), url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeCandidate(
        id: String,
        original: String,
        replacement: String,
        category: AIReviewCategory,
        evidence: AIConnectorCandidateEvidence
    ) -> AIConnectorReviewCandidate {
        AIConnectorReviewCandidate(
            id: id,
            segmentID: 1,
            original: original,
            replacement: replacement,
            category: category,
            priority: evidence.rulePriority,
            ruleID: nil,
            glossaryMatch: nil,
            explanation: "test",
            confidenceTier: evidence.tier == .exactRule
                ? .deterministicRule
                : evidence.tier == .scoredSpelling
                    ? .tataKataScored
                    : .verifiedGlossary,
            languageScoreEvidence: nil,
            evidence: evidence
        )
    }

    private func makeEvidence(
        tier: AIConnectorPhaseTwoEvidenceTier,
        location: Int,
        length: Int
    ) -> AIConnectorCandidateEvidence {
        AIConnectorCandidateEvidence(
            tier: tier,
            sourceLocation: location,
            spanLength: length,
            rulePriority: 10,
            sourceRank: 0,
            matchedDefinitionTokenCount: tier == .semanticGlossary ? 2 : 0,
            semanticScore: tier == .semanticGlossary ? 0.9 : nil,
            languageScoreDelta: tier == .scoredSpelling ? 1.0 : nil,
            isDirectTermMatch: tier == .verifiedGlossary,
            hasSourceAnchor: tier == .verifiedGlossary || tier == .semanticGlossary,
            isUniqueSpan: true
        )
    }

    private func makeSegment(target: String) -> AIReviewSegment {
        AIReviewSegment(
            id: 1,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }

    private final class CallBox: @unchecked Sendable {
        var count = 0
    }
}
#endif
