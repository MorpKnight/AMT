import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorTataKataPilotTests: XCTestCase {
    func testIndonesianSpellCheckerUsesGuessesAndCapsTrustedCandidates() {
        let text = "datta penggua salah"
        let checker = StubSpellChecker(issues: [
            issue(for: "datta", in: text, guesses: ["data", "darta", "ditta"]),
            issue(for: "penggua", in: text, guesses: ["pengguna"]),
            issue(for: "salah", in: text, guesses: ["salh"])
        ])
        let provider = SystemIndonesianSpellingCandidateProvider(checker: checker)

        let candidates = provider.candidates(
            for: makeSegment(target: text),
            protectionContext: .empty,
            excludedOriginals: []
        )

        XCTAssertEqual(Set(candidates.map(\.sourceLocation)).count, 2)
        XCTAssertLessThanOrEqual(
            candidates.count,
            SystemIndonesianSpellingCandidateProvider.maximumMisspelledWordsPerSegment
                * SystemIndonesianSpellingCandidateProvider.maximumGuessesPerWord
        )
        XCTAssertEqual(
            Set(candidates.map(\.original)),
            Set(["datta", "penggua"])
        )
        XCTAssertTrue(candidates.contains { $0.original == "datta" && $0.replacement == "data" })
        XCTAssertTrue(candidates.contains { $0.original == "penggua" && $0.replacement == "pengguna" })
    }

    func testSpellCheckerProtectsTermsIdentifiersQuotesAndNumbers() {
        let text = "Pihak Kedua datta ABCD KTP-2026 1234 kutip"
        let checker = StubSpellChecker(issues: [
            issue(for: "Pihak", in: text, guesses: ["pihakx"]),
            issue(for: "datta", in: text, guesses: ["data"]),
            issue(for: "ABCD", in: text, guesses: ["abcd"]),
            issue(for: "KTP", in: text, guesses: ["ktp"]),
            issue(for: "1234", in: text, guesses: ["12345"]),
            issue(for: "kutip", in: text, guesses: ["kutipan"])
        ])
        let provider = SystemIndonesianSpellingCandidateProvider(checker: checker)
        let context = AIConnectorDocumentProtectionContext(
            definedTerms: [],
            partyNames: ["Pihak Kedua"],
            acronyms: ["ABCD"],
            quotedTerms: ["kutip"],
            identifiers: ["KTP-2026"]
        )

        let candidates = provider.candidates(
            for: makeSegment(target: text),
            protectionContext: context,
            excludedOriginals: []
        )

        XCTAssertEqual(candidates.map(\.original), ["datta"])
        XCTAssertEqual(candidates.first?.replacement, "data")
    }

    func testSpellCheckerDoesNotInventMetadattaOrAlterLegalReferences() {
        let text = "pasal 12 ayat (1) mencatat metadatta."
        let checker = StubSpellChecker(issues: [
            issue(for: "pasal", in: text, guesses: ["pasar"]),
            issue(for: "ayat", in: text, guesses: ["ayak"]),
            issue(for: "metadatta", in: text, guesses: [])
        ])
        let provider = SystemIndonesianSpellingCandidateProvider(checker: checker)

        let candidates = provider.candidates(
            for: makeSegment(target: text),
            protectionContext: .empty,
            excludedOriginals: []
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testTrustedMemasukanRuleIsDeterministic() {
        let store = AIConnectorRuleStore()
        let rule = store.activeRules.first { $0.id == "spelling-memasukan" }
        XCTAssertEqual(rule?.value, "memasukan")
        XCTAssertEqual(rule?.replacement, "memasukkan")

        let candidates = AIConnectorCandidateBuilder(ruleStore: store).build(
            for: makeSegment(target: "Pihak Kedua memasukan data."),
            glossaryMatches: []
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.ruleID, "spelling-memasukan")
        XCTAssertEqual(candidates.first?.confidenceTier, .deterministicRule)
        XCTAssertNil(candidates.first?.languageScoreEvidence)
    }

    func testLanguageScorePolicyRejectsNegativeAndBelowThresholdEvidence() {
        XCTAssertTrue(
            AIConnectorLanguageScorePolicy.isEligible(
                makeEvidence(delta: AIConnectorLanguageScorerConfiguration.minimumImprovementInNats)
            )
        )
        XCTAssertFalse(AIConnectorLanguageScorePolicy.isEligible(makeEvidence(delta: -0.01)))
        XCTAssertFalse(
            AIConnectorLanguageScorePolicy.isEligible(
                makeEvidence(
                    delta: AIConnectorLanguageScorerConfiguration.minimumImprovementInNats - 0.001
                )
            )
        )
        XCTAssertFalse(
            AIConnectorLanguageScorePolicy.isEligible(
                makeEvidence(modelID: "untrusted/model", delta: 0.8)
            )
        )
    }

    func testCandidateBuilderDoesNotForwardInvalidLanguageScores() {
        let target = "Pihak datta menyerahkan dokumen."
        let builder = AIConnectorCandidateBuilder(
            ruleStore: AIConnectorRuleStore(version: "empty", rules: [])
        )
        let invalid = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "data",
            delta: -1
        )
        let belowThreshold = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "darta",
            delta: 0.1
        )

        XCTAssertTrue(
            builder.build(
                for: makeSegment(target: target),
                glossaryMatches: [],
                spellingCandidates: [invalid, belowThreshold]
            ).isEmpty
        )
    }

    func testCandidateBuilderKeepsTheBestSingleTataKataCandidatePerSegment() {
        let target = "Pihak datta dan penggua menyerahkan dokumen."
        let builder = AIConnectorCandidateBuilder(
            ruleStore: AIConnectorRuleStore(version: "empty", rules: [])
        )
        let candidates = builder.build(
            for: makeSegment(target: target),
            glossaryMatches: [],
            spellingCandidates: [
                makeSpellingCandidate(
                    target: target,
                    original: "datta",
                    replacement: "data",
                    delta: 0.3
                ),
                makeSpellingCandidate(
                    target: target,
                    original: "penggua",
                    replacement: "pengguna",
                    delta: 0.9
                )
            ]
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.original, "penggua")
        XCTAssertEqual(candidates.first?.confidenceTier, .tataKataScored)
    }

    func testAcceptedTataKataCandidateUsesQwenAndValidator() async throws {
        let target = "Pihak datta menyerahkan dokumen."
        let rawCandidate = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "data",
            delta: 0.8
        )
        let provider = StubSpellingCandidateProvider(candidates: [rawCandidate])
        let scorer = StubLanguageScorer(scoredCandidates: [rawCandidate])
        let decisions = TataKataDecisionBox()
        let handler = acceptingHandler(decisions: decisions)
        let processor = makeProcessor(
            provider: provider,
            scorer: scorer,
            candidateDecisionHandler: handler
        )
        let stages = TataKataStageBox()

        let result = try await processor.process(
            segment: makeSegment(target: target),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in },
            progressStage: { stage in stages.values.append(stage) }
        )

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.confidenceTier, .tataKataScored)
        XCTAssertEqual(result.candidates.first?.languageScoreEvidence?.delta, 0.8)
        XCTAssertEqual(result.reviews.first?.category, .spelling)
        XCTAssertEqual(result.reviews.first?.original, "datta")
        XCTAssertEqual(result.reviews.first?.replacement, "data")
        XCTAssertEqual(result.reviews.first?.origin, .qwen)
        XCTAssertEqual(result.candidateDecisions.first?.decision, .accept)
        XCTAssertEqual(decisions.requests.count, 1)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(stages.values.contains(.languageModelDownload))
        XCTAssertTrue(stages.values.contains(.languageModelLoading))
        XCTAssertTrue(stages.values.contains(.languageScoring))

        let scoreCalls = await scorer.scoreCallCount
        XCTAssertEqual(scoreCalls, 1)
    }

    func testTataKataRejectionDoesNotReceiveDeterministicFallback() async throws {
        let target = "Pihak datta menyerahkan dokumen."
        let candidate = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "data",
            delta: 0.8
        )
        let decisions = TataKataDecisionBox()
        let processor = makeProcessor(
            provider: StubSpellingCandidateProvider(candidates: [candidate]),
            scorer: StubLanguageScorer(scoredCandidates: [candidate]),
            candidateDecisionHandler: rejectingHandler(decisions: decisions)
        )

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

        XCTAssertEqual(decisions.requests.count, 1)
        XCTAssertEqual(result.candidateDecisions.first?.decision, .reject)
        XCTAssertFalse(result.usedFallback)
        XCTAssertFalse(result.candidateDecisions.first?.usedFallback ?? true)
        XCTAssertFalse(
            result.reviews.contains {
                $0.status == .suggestion && $0.category == .spelling
            }
        )
    }

    func testTataKataCandidateStillPassesThroughValidator() async throws {
        let target = "Pihak datta wajib menyerahkan dokumen."
        let candidate = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "wajib",
            delta: 0.8
        )
        let processor = makeProcessor(
            provider: StubSpellingCandidateProvider(candidates: [candidate]),
            scorer: StubLanguageScorer(scoredCandidates: [candidate]),
            candidateDecisionHandler: acceptingHandler(decisions: TataKataDecisionBox())
        )

        let result = try await processor.process(
            segment: makeSegment(target: target),
            documentProtectionContext: .empty,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertTrue(result.reviews.isEmpty)
        XCTAssertEqual(result.rejections.first?.classification, .validator)
        XCTAssertFalse(result.usedFallback)
    }

    func testTataKataFailureLeavesDeterministicRulesAvailable() async throws {
        let rule = makeRule(
            id: "spelling-memasukan",
            value: "memasukan",
            replacement: "memasukkan"
        )
        let target = "Pihak Kedua memasukan data dan datta."
        let candidate = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "data",
            delta: 0.8
        )
        let decisions = TataKataDecisionBox()
        let processor = makeProcessor(
            ruleStore: AIConnectorRuleStore(version: "test-rule", rules: [rule]),
            provider: StubSpellingCandidateProvider(candidates: [candidate]),
            scorer: StubLanguageScorer(shouldThrow: true),
            candidateDecisionHandler: acceptingHandler(decisions: decisions)
        )

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

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.ruleID, "spelling-memasukan")
        XCTAssertEqual(result.reviews.first?.original, "memasukan")
        XCTAssertEqual(result.reviews.first?.replacement, "memasukkan")
        XCTAssertEqual(result.reviews.first?.origin, .qwen)
        XCTAssertEqual(decisions.requests.count, 1)
    }

    func testTataKataCancellationPropagatesWithoutFallback() async throws {
        let target = "Pihak datta menyerahkan dokumen."
        let candidate = makeSpellingCandidate(
            target: target,
            original: "datta",
            replacement: "data",
            delta: 0.8
        )
        let processor = makeProcessor(
            provider: StubSpellingCandidateProvider(candidates: [candidate]),
            scorer: StubLanguageScorer(throwsCancellation: true),
            candidateDecisionHandler: acceptingHandler(decisions: TataKataDecisionBox())
        )

        do {
            _ = try await processor.process(
                segment: makeSegment(target: target),
                documentProtectionContext: .empty,
                mode: .hybrid,
                modelVariant: .qwen35Base4B,
                thinkingEnabled: false,
                forceDeterministic: false,
                downloadProgress: { _ in },
                generationProgress: { _ in }
            )
            XCTFail("Cancellation should propagate from the language scorer.")
        } catch is CancellationError {
            // Expected: cancellation is not converted into a suggestion.
        }
    }

    func testDeterministicProfileDoesNotTouchTataKata() async throws {
        let candidate = makeSpellingCandidate(
            target: "Pihak datta menyerahkan dokumen.",
            original: "datta",
            replacement: "data",
            delta: 0.8
        )
        let provider = StubSpellingCandidateProvider(candidates: [candidate])
        let scorer = StubLanguageScorer(scoredCandidates: [candidate])
        let decisions = TataKataDecisionBox()
        let processor = makeProcessor(
            provider: provider,
            scorer: scorer,
            candidateDecisionHandler: acceptingHandler(decisions: decisions)
        )

        _ = try await processor.process(
            segment: makeSegment(target: "Pihak datta menyerahkan dokumen."),
            documentProtectionContext: .empty,
            mode: .deterministic,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            forceDeterministic: false,
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(decisions.requests.count, 0)
        let scoreCalls = await scorer.scoreCallCount
        let loadedReads = await scorer.isLoadedReadCount
        XCTAssertEqual(scoreCalls, 0)
        XCTAssertEqual(loadedReads, 0)
    }

    func testLanguageScoreCacheKeyUsesRevisionWindowAndReplacement() {
        let key = AIConnectorLanguageScoreCacheKey(
            revision: "rev-a",
            sourceWindow: "Pihak datta menyerahkan dokumen.",
            replacement: "data"
        )
        XCTAssertEqual(
            key,
            AIConnectorLanguageScoreCacheKey(
                revision: "rev-a",
                sourceWindow: "Pihak datta menyerahkan dokumen.",
                replacement: "data"
            )
        )
        XCTAssertNotEqual(
            key,
            AIConnectorLanguageScoreCacheKey(
                revision: "rev-a",
                sourceWindow: "Pihak datta menyerahkan dokumen.",
                replacement: "darta"
            )
        )
        XCTAssertNotEqual(
            key,
            AIConnectorLanguageScoreCacheKey(
                revision: "rev-b",
                sourceWindow: "Pihak datta menyerahkan dokumen.",
                replacement: "data"
            )
        )
        XCTAssertNotEqual(
            key,
            AIConnectorLanguageScoreCacheKey(
                revision: "rev-a",
                sourceWindow: "Pihak datta menyerahkan dokumen.",
                replacement: "data",
                replacementSourceLocation: 6,
                replacementSourceLength: 5
            )
        )
    }

    func testTataKataConfigurationIsPinnedAndPipelineVersionIsExplicit() {
        XCTAssertEqual(TataKataLanguageScorer.modelID, "citylighxts/TataKata")
        XCTAssertEqual(
            TataKataLanguageScorer.revision,
            "4b90902f013ea22096f47f99f3a7c8aac508e3c7"
        )
        XCTAssertEqual(
            TataKataLanguageScorer.expectedModelSHA256,
            "9e52c5e4334ce4428bf980aded27300617bec7a663b32600f5ab439211844883"
        )
        XCTAssertEqual(AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount, 30_521)
        XCTAssertEqual(AIConnectorLanguageScorerConfiguration.configuredVocabularyCount, 50_000)
        XCTAssertTrue(
            AIConnectorLanguageScorerConfiguration.pipelineVersion.contains("64wp")
        )
    }

    private func makeProcessor(
        ruleStore: AIConnectorRuleStore? = nil,
        provider: any AIConnectorSpellingCandidateProviding,
        scorer: any AIConnectorLanguageCandidateScoring,
        candidateDecisionHandler: @escaping AIConnectorCandidateDecisionHandler
    ) -> AIConnectorSegmentProcessor {
        AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: ruleStore
                ?? AIConnectorRuleStore(version: "empty", rules: []),
            candidateDecisionHandler: candidateDecisionHandler,
            spellingCandidateProvider: provider,
            languageScorer: scorer
        )
    }

    private func acceptingHandler(
        decisions: TataKataDecisionBox
    ) -> AIConnectorCandidateDecisionHandler {
        { @MainActor request, _, _ in
            decisions.requests.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .accept,
                metrics: tataKataTestMetrics(),
                containsReasoningMarkers: false
            )
        }
    }

    private func rejectingHandler(
        decisions: TataKataDecisionBox
    ) -> AIConnectorCandidateDecisionHandler {
        { @MainActor request, _, _ in
            decisions.requests.append(request)
            return QwenCandidateDecisionResult(
                candidateID: request.candidate.id,
                decision: .reject,
                metrics: tataKataTestMetrics(),
                containsReasoningMarkers: false
            )
        }
    }

    private func makeSegment(
        id: Int = 1,
        target: String
    ) -> AIReviewSegment {
        AIReviewSegment(
            id: id,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }

    private func makeSpellingCandidate(
        target: String,
        original: String,
        replacement: String,
        delta: Double
    ) -> AIConnectorSpellingCandidate {
        let range = (target as NSString).range(of: original)
        precondition(range.location != NSNotFound)
        return AIConnectorSpellingCandidate(
            original: original,
            replacement: replacement,
            sourceLocation: range.location,
            sourceLength: range.length,
            evidence: makeEvidence(
                sourceWindow: target,
                originalScore: 0,
                replacementScore: delta,
                delta: delta
            )
        )
    }

    private func makeEvidence(
        modelID: String = AIConnectorLanguageScorerConfiguration.modelID,
        revision: String = AIConnectorLanguageScorerConfiguration.revision,
        sourceWindow: String = "Pihak datta menyerahkan dokumen.",
        originalScore: Double = -4,
        replacementScore: Double = -3.2,
        delta: Double
    ) -> AIConnectorLanguageScoreEvidence {
        AIConnectorLanguageScoreEvidence(
            modelID: modelID,
            revision: revision,
            sourceWindow: sourceWindow,
            originalScore: originalScore,
            replacementScore: replacementScore,
            delta: delta,
            tokenizerVocabularyCount: AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount,
            configuredVocabularyCount: AIConnectorLanguageScorerConfiguration.configuredVocabularyCount
        )
    }

    private func issue(
        for word: String,
        in text: String,
        guesses: [String]
    ) -> StubSpellChecker.Issue {
        let range = (text as NSString).range(of: word)
        precondition(range.location != NSNotFound)
        return StubSpellChecker.Issue(range: range, guesses: guesses)
    }

    private func makeRule(
        id: String,
        value: String,
        replacement: String
    ) -> AIConnectorRuleDefinition {
        AIConnectorRuleDefinition(
            id: id,
            revision: 1,
            category: .spelling,
            matcher: .tokenSequence,
            value: value,
            replacement: replacement,
            reason: "Koreksi ejaan tepercaya.",
            priority: 22,
            exceptions: [],
            status: .active,
            sourceNote: "Test rule.",
            owner: "test",
            reviewer: "test",
            changelog: "TataKata pilot test",
            positiveFixtures: [value],
            negativeFixtures: [replacement]
        )
    }
}

@MainActor
private final class StubSpellChecker: AIConnectorSystemSpellChecker {
    struct Issue {
        let range: NSRange
        let guesses: [String]
    }

    let issues: [Issue]

    init(issues: [Issue]) {
        self.issues = issues
    }

    func checkSpelling(
        in text: String,
        startingAt location: Int,
        language: String
    ) -> NSRange {
        issues.first { $0.range.location >= location }?.range
            ?? NSRange(location: NSNotFound, length: 0)
    }

    func guesses(
        forWordRange range: NSRange,
        in text: String,
        language: String
    ) -> [String] {
        issues.first { $0.range == range }?.guesses ?? []
    }
}

@MainActor
private final class StubSpellingCandidateProvider: AIConnectorSpellingCandidateProviding {
    let candidatesToReturn: [AIConnectorSpellingCandidate]
    private(set) var callCount = 0

    init(candidates: [AIConnectorSpellingCandidate]) {
        self.candidatesToReturn = candidates
    }

    func candidates(
        for segment: AIReviewSegment,
        protectionContext: AIConnectorDocumentProtectionContext,
        excludedOriginals: Set<String>
    ) -> [AIConnectorSpellingCandidate] {
        callCount += 1
        return candidatesToReturn
    }
}

private actor StubLanguageScorer: AIConnectorLanguageCandidateScoring {
    let scoredCandidates: [AIConnectorSpellingCandidate]
    let shouldThrow: Bool
    let throwsCancellation: Bool
    private(set) var scoreCallCount = 0
    private(set) var isLoadedReadCount = 0

    init(
        scoredCandidates: [AIConnectorSpellingCandidate] = [],
        shouldThrow: Bool = false,
        throwsCancellation: Bool = false
    ) {
        self.scoredCandidates = scoredCandidates
        self.shouldThrow = shouldThrow
        self.throwsCancellation = throwsCancellation
    }

    var isLoaded: Bool {
        isLoadedReadCount += 1
        return false
    }

    func score(
        segment: AIReviewSegment,
        candidates: [AIConnectorSpellingCandidate],
        progress: @MainActor @Sendable @escaping (AIConnectorLanguageScoringProgress) -> Void
    ) async throws -> [AIConnectorSpellingCandidate] {
        scoreCallCount += 1
        if shouldThrow {
            throw TataKataLanguageScorerError.inferenceFailed
        }
        if throwsCancellation {
            throw CancellationError()
        }
        await progress(.downloading(1))
        await progress(.loading)
        await progress(.scoring(1))
        return scoredCandidates
    }
}

@MainActor
private final class TataKataDecisionBox {
    var requests: [AIConnectorCandidateReviewRequest] = []
}

@MainActor
private final class TataKataStageBox {
    var values: [AIConnectorProgressStage] = []
}

private func tataKataTestMetrics() -> AIConnectorGenerationMetrics {
    AIConnectorGenerationMetrics(
        promptTokenCount: 10,
        generationTokenCount: 4,
        promptDuration: 0.01,
        generationDuration: 0.02,
        stopReason: .stop
    )
}

/// Opt-in only. This test downloads the pinned 499 MB TataKata artifact and
/// records the calibrated golden fixtures. It is intentionally skipped by the
/// regular unit-test command.
@MainActor
final class AIConnectorTataKataBenchmarkTests: XCTestCase {
    func testOptInTataKataGoldenFixtures() async throws {
        guard tataKataEnvironmentValue("AMT_RUN_TATAKATA_BENCHMARK") == "1" else {
            throw XCTSkip(
                "Set TEST_RUNNER_AMT_RUN_TATAKATA_BENCHMARK=1 to run the TataKata benchmark."
            )
        }

        XCTAssertEqual(TataKataLanguageScorer.modelID, "citylighxts/TataKata")
        XCTAssertEqual(
            TataKataLanguageScorer.revision,
            "4b90902f013ea22096f47f99f3a7c8aac508e3c7"
        )
        XCTAssertEqual(
            TataKataLanguageScorer.expectedModelSHA256,
            "9e52c5e4334ce4428bf980aded27300617bec7a663b32600f5ab439211844883"
        )

        let scorer = TataKataLanguageScorer()
        let fixtures = [
            ("datta", "data", "Pihak datta menyerahkan dokumen."),
            ("penggua", "pengguna", "Data penggua diproses oleh Pihak Kedua."),
            ("memasukan", "memasukkan", "Pihak Kedua memasukan data."),
            ("metadatta", "metadata", "Metadata metadatta dicatat dalam lampiran.")
        ]
        var rows: [TataKataGoldenRow] = []

        for (original, replacement, text) in fixtures {
            let candidate = makeTataKataBenchmarkCandidate(
                target: text,
                original: original,
                replacement: replacement
            )
            do {
                let scored = try await scorer.scoreForDiagnostics(
                    segment: AIReviewSegment(
                        id: 1,
                        sourceLocation: 0,
                        sourceLength: text.utf16.count,
                        targetText: text,
                        previousContext: nil,
                        nextContext: nil
                    ),
                    candidates: [candidate],
                    progress: { _ in }
                )
                rows.append(
                    TataKataGoldenRow(
                        fixture: original + " -> " + replacement,
                        original: original,
                        expectedReplacement: replacement,
                        selectedReplacement: scored.first?.replacement,
                        delta: scored.first?.evidence?.delta,
                        accepted: scored.first?.evidence.map(
                            AIConnectorLanguageScorePolicy.isEligible
                        ) ?? false,
                        error: nil
                    )
                )
            } catch {
                rows.append(
                    TataKataGoldenRow(
                        fixture: original + " -> " + replacement,
                        original: original,
                        expectedReplacement: replacement,
                        selectedReplacement: nil,
                        delta: nil,
                        accepted: false,
                        error: error.localizedDescription
                    )
                )
            }
        }

        let reportURL = try tataKataReportURL(
            environmentKey: "AMT_TATAKATA_GOLDEN_REPORT_PATH",
            defaultPath: "/private/tmp/amt-tatakata-golden.json"
        )
        try tataKataJSONEncoder().encode(
            TataKataGoldenReport(
                modelID: TataKataLanguageScorer.modelID,
                revision: TataKataLanguageScorer.revision,
                modelSHA256: TataKataLanguageScorer.expectedModelSHA256,
                rows: rows
            )
        ).write(to: reportURL, options: .atomic)

        let scorerLoaded = await scorer.isLoaded
        XCTAssertTrue(scorerLoaded)
        XCTAssertEqual(rows.count, fixtures.count)
        XCTAssertTrue(rows.allSatisfy { $0.error == nil })

        let rowsByOriginal = Dictionary(uniqueKeysWithValues: rows.map { ($0.original, $0) })
        XCTAssertEqual(rowsByOriginal["datta"]?.selectedReplacement, "data")
        XCTAssertFalse(rowsByOriginal["datta"]?.accepted ?? true)
        XCTAssertLessThan(
            rowsByOriginal["datta"]?.delta ?? .greatestFiniteMagnitude,
            AIConnectorLanguageScorerConfiguration.minimumImprovementInNats
        )
        XCTAssertEqual(rowsByOriginal["penggua"]?.selectedReplacement, "pengguna")
        XCTAssertTrue(rowsByOriginal["penggua"]?.accepted ?? false)
        XCTAssertEqual(rowsByOriginal["memasukan"]?.selectedReplacement, "memasukkan")
        XCTAssertTrue(rowsByOriginal["memasukan"]?.accepted ?? false)
    }

    /// Opt-in end-to-end code smoke test. It converts the supplied DOCX in
    /// memory, runs the document through the existing queue and writes only a
    /// diagnostic report under /private/tmp. The source document is untouched.
    func testOptInTataKataDocumentSmoke() async throws {
        guard tataKataEnvironmentValue("AMT_RUN_TATAKATA_DOCUMENT_SMOKE") == "1" else {
            throw XCTSkip(
                "Set TEST_RUNNER_AMT_RUN_TATAKATA_DOCUMENT_SMOKE=1 to run the DOCX smoke test."
            )
        }

        let sourcePath = tataKataEnvironmentValue("AMT_TATAKATA_DOCUMENT_PATH")
            ?? "/Users/giovan/Downloads/Dokumen_Legal_Fiktif_Pengujian.docx"
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("DOCX smoke source tidak ditemukan: \(sourceURL.path)")
        }

        let documentText = try DocxToMarkdownConverter.convert(fileURL: sourceURL)
        let allSegments = LegalTextSegmenter().segment(documentText: documentText).segments
        guard !allSegments.isEmpty else {
            throw XCTSkip("DOCX tidak menghasilkan segmen yang dapat dianalisis.")
        }

        let segmentsForSmoke: [AIReviewSegment]
        if let needle = tataKataEnvironmentValue("AMT_TATAKATA_DOCUMENT_NEEDLE"),
           !needle.isEmpty {
            segmentsForSmoke = allSegments.filter {
                $0.targetText.localizedCaseInsensitiveContains(needle)
            }
        } else {
            segmentsForSmoke = allSegments
        }
        guard !segmentsForSmoke.isEmpty else {
            throw XCTSkip("DOCX tidak memiliki segmen yang memuat needle smoke test.")
        }

        let selectedSegments: [AIReviewSegment]
        if let rawLimit = tataKataEnvironmentValue("AMT_TATAKATA_DOCUMENT_MAX_SEGMENTS"),
           let limit = Int(rawLimit), limit > 0 {
            selectedSegments = Array(segmentsForSmoke.prefix(limit))
        } else {
            selectedSegments = segmentsForSmoke
        }

        let recordingProvider = RecordingSpellingCandidateProvider()
        let processor = AIConnectorSegmentProcessor(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: []),
            ruleStore: AIConnectorRuleStore(),
            spellingCandidateProvider: recordingProvider,
            languageScorer: TataKataLanguageScorer()
        )
        let queue = AIConnectorWorkQueue(processor: processor)
        let stream = await queue.start(
            runID: UUID(),
            segments: selectedSegments,
            mode: .modelOnly,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            documentProtectionContext: processor.protectionContext(for: documentText),
            downloadProgress: { _ in },
            generationProgress: { _ in }
        )

        var tataKataScoredCandidateCount = 0
        var tataKataQwenRejectedCount = 0
        var validatorRejectedCount = 0
        var displayedSuggestionCount = 0
        var summary: AIConnectorRunSummary?
        var queueFailure: String?

        for await event in stream {
            switch event {
            case let .result(result):
                let tataCandidates = result.candidates.filter {
                    $0.confidenceTier == .tataKataScored
                }
                tataKataScoredCandidateCount += tataCandidates.count
                tataKataQwenRejectedCount += result.candidateDecisions.filter {
                    $0.confidenceTier == .tataKataScored
                        && $0.decision == .reject
                }.count
                validatorRejectedCount += result.candidateDecisions.filter {
                    $0.confidenceTier == .tataKataScored
                        && $0.rejectionClass == .validator
                }.count

                let tataPairs = Set(
                    tataCandidates.map { $0.original + "\u{1F}" + $0.replacement }
                )
                displayedSuggestionCount += result.reviews.filter { review in
                    guard review.status == .suggestion,
                          review.category == .spelling,
                          review.origin == .qwen || review.origin == .qwenRepaired,
                          let original = review.original,
                          let replacement = review.replacement else {
                        return false
                    }
                    return tataPairs.contains(original + "\u{1F}" + replacement)
                }.count
                await queue.acknowledgeResult()

            case let .finished(value):
                summary = value
            case let .failed(message):
                queueFailure = message
            default:
                break
            }
        }

        let report = TataKataDocumentSmokeReport(
            sourcePath: sourceURL.path,
            segmentCount: selectedSegments.count,
            candidateFound: recordingProvider.rawSpanCount,
            tataKataScored: tataKataScoredCandidateCount,
            tataKataRejected: max(
                0,
                recordingProvider.rawSpanCount - tataKataScoredCandidateCount
            ),
            qwenRejected: tataKataQwenRejectedCount,
            validatorRejected: validatorRejectedCount,
            displayed: displayedSuggestionCount,
            processedSegmentCount: summary?.processedSegmentCount ?? 0,
            queueFailure: queueFailure
        )
        let reportURL = try tataKataReportURL(
            environmentKey: "AMT_TATAKATA_DOCUMENT_REPORT_PATH",
            defaultPath: "/private/tmp/amt-tatakata-document-smoke.json"
        )
        try tataKataJSONEncoder().encode(report).write(to: reportURL, options: .atomic)

        XCTAssertNil(queueFailure)
        XCTAssertEqual(summary?.processedSegmentCount, selectedSegments.count)
    }

    private func tataKataEnvironmentValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }

    private func tataKataReportURL(
        environmentKey: String,
        defaultPath: String
    ) throws -> URL {
        let path = tataKataEnvironmentValue(environmentKey) ?? defaultPath
        guard path.hasPrefix("/private/tmp/") else {
            throw XCTSkip("\(environmentKey) harus berada di bawah /private/tmp/.")
        }
        return URL(fileURLWithPath: path)
    }
}

private struct TataKataGoldenReport: Codable {
    let modelID: String
    let revision: String
    let modelSHA256: String
    let rows: [TataKataGoldenRow]
}

private struct TataKataGoldenRow: Codable {
    let fixture: String
    let original: String
    let expectedReplacement: String
    let selectedReplacement: String?
    let delta: Double?
    let accepted: Bool
    let error: String?
}

private struct TataKataDocumentSmokeReport: Codable {
    let sourcePath: String
    let segmentCount: Int
    let candidateFound: Int
    let tataKataScored: Int
    let tataKataRejected: Int
    let qwenRejected: Int
    let validatorRejected: Int
    let displayed: Int
    let processedSegmentCount: Int
    let queueFailure: String?
}

@MainActor
private final class RecordingSpellingCandidateProvider: AIConnectorSpellingCandidateProviding {
    private let baseProvider = SystemIndonesianSpellingCandidateProvider()
    private(set) var rawSpanCount = 0

    func candidates(
        for segment: AIReviewSegment,
        protectionContext: AIConnectorDocumentProtectionContext,
        excludedOriginals: Set<String>
    ) -> [AIConnectorSpellingCandidate] {
        let candidates = baseProvider.candidates(
            for: segment,
            protectionContext: protectionContext,
            excludedOriginals: excludedOriginals
        )
        rawSpanCount += Set(
            candidates.map {
                "\($0.sourceLocation):\($0.sourceLength):\($0.original)"
            }
        ).count
        return candidates
    }
}

private func makeTataKataBenchmarkCandidate(
    target: String,
    original: String,
    replacement: String
) -> AIConnectorSpellingCandidate {
    let range = (target as NSString).range(of: original)
    precondition(range.location != NSNotFound)
    return AIConnectorSpellingCandidate(
        original: original,
        replacement: replacement,
        sourceLocation: range.location,
        sourceLength: range.length
    )
}

private func tataKataJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
