import AppKit
import Foundation
import XCTest
@testable import AMT

/// Synthetic accuracy experiment. Pending labels never become human approvals.
@MainActor
final class AIConnectorAccuracyBenchmarkTests: XCTestCase {
    func testProductionAccuracyExperiment() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_ACCURACY_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in model accuracy experiment; regular tests remain offline.")
        }
        let directory = try XCTUnwrap(env["AMT_ACCURACY_OUTPUT"])
        guard directory.hasPrefix("/private/tmp/") else { throw XCTSkip("External reports required.") }
        let destination = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            try encoder.encode(value).write(to: destination.appendingPathComponent(name), options: .atomic)
        }

        let fixtures = AIConnectorQualityFixtureCatalog.fixtures
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
        try write(fixtures, "fixtures.json")
        let service = QwenSuggestionService()
        let store = LegalDictionaryStore(inferenceScheduler: service.inferenceScheduler)
        XCTAssertNotNil(store.corpusStore, "Use the production corpus, never preview entries.")
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        vm.flowBenchmarkReuseCaches = true
        let preparedAt = ContinuousClock.now
        try await vm.flowBenchmarkPrepareResources()
        let preparation = AIConnectorObservationTiming.seconds(preparedAt.duration(to: .now))
        var records: [Record] = []
        var outputs: [AIConnectorReviewMode: [String: AIConnectorQualityObservedOutput]] = [:]
        for mode in [AIConnectorReviewMode.deterministic, .hybrid, .modelOnly] {
            for (index, fixture) in fixtures.enumerated() {
                await vm.flowBenchmarkClearCaches()
                let observed = try await vm.runPhaseEightFixture(fixture, mode: mode)
                await vm.flowBenchmarkAwaitCompletion()
                let assessments = vm.definitionAssessments.map { assessment in
                    Definition(term: assessment.term, classification: assessment.classification.rawValue,
                               alignment: assessment.alignment.rawValue, reason: assessment.reason,
                               sourceID: assessment.candidate?.match.entry.id,
                               sourceVerified: assessment.candidate?.match.entry.authority == .verified,
                               sourceActionable: assessment.candidate?.match.entry.isActionable == true,
                               modelReviewed: assessment.modelReviewed)
                }
                let mappedAnchorErrors = vm.editorSuggestions.filter { !$0.isAnchored(to: fixture.text) }.count
                    + vm.reviewAnnotations.filter { !$0.isAnchored(to: fixture.text) }.count
                records.append(Record(fixtureID: fixture.id, mode: mode, output: observed,
                                      observation: vm.observationReport, benchmark: vm.benchmarkReport,
                                      definitions: assessments, invalidMappedAnchors: mappedAnchorErrors,
                                      invalidActionableSources: vm.flowBenchmarkInvalidSourceCount(),
                                      skippedSegments: vm.skippedSegmentCount,
                                      partialRun: vm.runSummary?.wasPartial ?? true))
                outputs[mode, default: [:]][fixture.id] = observed
                try write(records, "records.json")
                print("ACCURACY \(mode.rawValue) \(index + 1)/\(fixtures.count) \(fixture.id)")
            }
        }

        // Isolate proposal recall and scoring from Qwen without injecting these
        // diagnostic candidates into the production pipeline.
        let provider = SystemIndonesianSpellingCandidateProvider()
        var diagnostics: [SpellingDiagnostic] = []
        for fixture in fixtures where fixture.category == .spelling {
            guard let finding = fixture.expected.findings.first,
                  let original = finding.original, let replacement = finding.replacement else { continue }
            let text = fixture.text
            let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: text.utf16.count,
                                          targetText: text, previousContext: nil, nextContext: nil)
            let range = (text as NSString).range(of: original)
            guard range.location != NSNotFound else { continue }
            let raw = provider.candidates(for: segment, protectionContext: .empty, excludedOriginals: [])
            let scoredRaw = try await service.languageScorer.scoreForDiagnostics(segment: segment, candidates: raw)
            let fixed = try await service.languageScorer.scoreForDiagnostics(segment: segment, candidates: [
                .init(original: original, replacement: replacement, sourceLocation: range.location, sourceLength: range.length)
            ])
            let rawGuesses = NSSpellChecker.shared.guesses(forWordRange: range, in: text, language: "id", inSpellDocumentWithTag: 0) ?? []
            diagnostics.append(SpellingDiagnostic(fixtureID: fixture.id,
                expectedOriginal: original, expectedReplacement: replacement, systemGuesses: rawGuesses,
                providerCandidates: raw.map(Candidate.init), scoredProvider: scoredRaw.map(Candidate.init),
                scoredFixed: fixed.map(Candidate.init)))
        }
        try write(diagnostics, "spelling-diagnostics.json")
        let policy = AIConnectorQualityPolicy.diagnosticDefault(modelVariant: .qwen35Base4B)
        let manifest = AIConnectorQualityCandidateManifestFactory.make(fixtures: fixtures, policy: policy,
                                                                       corpusVersion: store.corpusStore?.manifest.corpusVersion ?? "missing-corpus")
        let gate = AIConnectorQualityEvaluator().evaluate(fixtures: fixtures, reviews: [], policy: policy,
                                                          candidateManifest: manifest, outputsByMode: outputs)
        try write(gate, "reviewed-quality-gate.json")
        try write(Metadata(buildIdentity: env["AMT_ACCURACY_BUILD"] ?? "unknown", fixtureCount: fixtures.count,
                           preparationSeconds: preparation, availableSpellLanguages: NSSpellChecker.shared.availableLanguages,
                           scoringThreshold: AIConnectorLanguageScorerConfiguration.minimumImprovementInNats), "runtime.json")
        XCTAssertEqual(records.count, fixtures.count * 3)
        XCTAssertEqual(gate.overallStatus, .insufficientEvidence)
    }

    private struct Record: Codable {
        let fixtureID: String
        let mode: AIConnectorReviewMode
        let output: AIConnectorQualityObservedOutput
        let observation: AIConnectorObservationReport?
        let benchmark: AIConnectorBenchmarkReport?
        let definitions: [Definition]
        let invalidMappedAnchors: Int
        let invalidActionableSources: Int
        let skippedSegments: Int
        let partialRun: Bool
    }
    private struct Definition: Codable {
        let term: String?
        let classification: String
        let alignment: String
        let reason: String
        let sourceID: String?
        let sourceVerified: Bool
        let sourceActionable: Bool
        let modelReviewed: Bool
    }
    private struct Candidate: Codable {
        let original: String
        let replacement: String
        let location: Int
        let length: Int
        let rank: Int
        let delta: Double?
        let eligible: Bool
        init(_ value: AIConnectorSpellingCandidate) {
            original = value.original; replacement = value.replacement
            location = value.sourceLocation; length = value.sourceLength; rank = value.sourceRank
            delta = value.evidence?.delta
            eligible = value.evidence.map(AIConnectorLanguageScorePolicy.isEligible) ?? false
        }
    }
    private struct SpellingDiagnostic: Codable {
        let fixtureID: String
        let expectedOriginal: String
        let expectedReplacement: String
        let systemGuesses: [String]
        let providerCandidates: [Candidate]
        let scoredProvider: [Candidate]
        let scoredFixed: [Candidate]
    }
    private struct Metadata: Codable {
        let buildIdentity: String
        let fixtureCount: Int
        let preparationSeconds: Double
        let availableSpellLanguages: [String]
        let scoringThreshold: Double
    }
}
