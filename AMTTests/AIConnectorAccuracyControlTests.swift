import Foundation
import XCTest
@testable import AMT

/// Corpus-backed exact/negation controls, separate from pending legal labels.
@MainActor
final class AIConnectorAccuracyControlTests: XCTestCase {
    func testSpellingValidatorDiagnostic() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_ACCURACY_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in validator attribution for the accuracy experiment.")
        }
        let path = try XCTUnwrap(env["AMT_ACCURACY_OUTPUT"])
        guard path.hasPrefix("/private/tmp/") else { throw XCTSkip("External reports required.") }
        let fixture = try XCTUnwrap(AIConnectorBackendEvaluationFixtures.fixtures.first { $0.id == "backend46-spelling-2" })
        let expected = try XCTUnwrap(fixture.expected.findings.first)
        let original = try XCTUnwrap(expected.original)
        let replacement = try XCTUnwrap(expected.replacement)
        let segment = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: fixture.text.utf16.count,
            targetText: fixture.text, previousContext: nil, nextContext: nil)
        let candidate = AIParsedReview(status: .suggestion, category: .spelling, original: original,
            replacement: replacement, glossaryID: nil,
            reason: "TataKata menilai penggantian \(original) menjadi \(replacement) lebih sesuai dengan konteks kalimat.")
        let range = (fixture.text as NSString).range(of: original)
        let anchor = AIConnectorReviewAnchor(segmentID: 1, sourceRange: range, original: original)
        do {
            _ = try AIConnectorSuggestionValidator().validate(candidate, for: segment, glossaryMatches: [], sourceAnchor: anchor)
            XCTFail("Expected the current legal-structure guard to reject the keyword restoration.")
        } catch let error as AIConnectorValidationError {
            XCTAssertEqual(error, .legalStructureChanged)
            let data: [String: String] = ["fixtureID": fixture.id, "original": original,
                "replacement": replacement, "validatorError": "legalStructureChanged", "reason": error.message]
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: URL(fileURLWithPath: path).appendingPathComponent("validator-diagnostic.json"), options: .atomic)
        }
    }

    func testVerifiedDefinitionControls() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AMT_RUN_ACCURACY_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in corpus/model accuracy controls.")
        }
        let path = try XCTUnwrap(env["AMT_ACCURACY_OUTPUT"])
        guard path.hasPrefix("/private/tmp/") else { throw XCTSkip("External reports required.") }
        let destination = URL(fileURLWithPath: path)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            try encoder.encode(value).write(to: destination.appendingPathComponent(name), options: .atomic)
        }
        let service = QwenSuggestionService()
        let store = LegalDictionaryStore(inferenceScheduler: service.inferenceScheduler)
        XCTAssertNotNil(store.corpusStore)
        let terms = ["Sarana perkeretaapian", "Sertifikat Deposito", "Usia Pensiun", "WUPK", "Objek Sita", "Tempat Uji Kompetensi"]
        var controls: [Control] = []
        for term in terms {
            let eligible = store.entries(forTerm: term).filter {
                $0.authority == .verified && $0.isActionable && $0.applicabilityStatus == .inForce
            }
            let entry = try XCTUnwrap(eligible.first, "Frozen term must have eligible production evidence: \(term)")
            XCTAssertEqual(eligible.count, 1, "Controls require an unambiguous source.")
            XCTAssertTrue(entry.definition.contains("dapat"))
            for kind in ["exact", "negated", "mention"] {
                let body = kind == "negated" ? entry.definition.replacingOccurrences(of: "dapat", with: "tidak dapat") : entry.definition
                let text = kind == "mention" ? "Para Pihak membicarakan \(term)." : "Yang dimaksud dengan \(term) adalah \(body)"
                controls.append(Control(id: "control-\(controls.count + 1)", kind: kind, term: term,
                                        text: text, sourceID: entry.id, sourceDefinition: entry.definition))
            }
        }
        // Freeze all source text and expected operator changes before inference.
        try write(controls, "definition-controls.json")
        let vm = AIConnectorViewModel(service: service, dictionaryStore: store)
        vm.flowBenchmarkReuseCaches = true
        try await vm.flowBenchmarkPrepareResources()
        var records: [Record] = []
        for mode in [AIConnectorReviewMode.deterministic, .hybrid] {
            for control in controls {
                await vm.flowBenchmarkClearCaches()
                let fixture = AIConnectorQualityFixture(id: control.id, scenarioID: control.id,
                    category: .definition, split: .regression, text: control.text,
                    expected: AIConnectorQualityExpectation(), question: "Exact/negation/mention corpus control; pending experiment.")
                let output = try await vm.runPhaseEightFixture(fixture, mode: mode)
                await vm.flowBenchmarkAwaitCompletion()
                let assessments = vm.definitionAssessments.map {
                    Assessment(term: $0.term, classification: $0.classification.rawValue,
                               alignment: $0.alignment.rawValue, sourceID: $0.candidate?.match.entry.id,
                               reason: $0.reason, modelReviewed: $0.modelReviewed)
                }
                records.append(Record(id: control.id, mode: mode, output: output, assessments: assessments,
                                      observation: vm.observationReport))
                try write(records, "definition-control-records.json")
                print("ACCURACY CONTROL \(mode.rawValue) \(control.kind) \(control.term)")
            }
        }
        XCTAssertEqual(records.count, 36)
        var repeats: [SpellingRepeat] = []
        for iteration in 1...3 {
            for fixture in AIConnectorBackendEvaluationFixtures.fixtures where fixture.category == .spelling {
                await vm.flowBenchmarkClearCaches()
                let output = try await vm.runPhaseEightFixture(fixture, mode: .hybrid)
                await vm.flowBenchmarkAwaitCompletion()
                let candidates = vm.currentCandidates.map { candidate in
                    let decision = vm.currentCandidateDecisions.first { $0.candidateID == candidate.id }
                    return SpellingCandidate(original: candidate.original, replacement: candidate.replacement,
                        delta: candidate.languageScoreEvidence?.delta, decision: decision?.decision?.rawValue,
                        route: decision?.route?.rawValue, routeReason: decision?.routeReason?.rawValue,
                        rejection: decision?.rejectionClass?.rawValue)
                }
                repeats.append(SpellingRepeat(fixtureID: fixture.id, iteration: iteration,
                                             output: output, candidates: candidates, observation: vm.observationReport))
                try write(repeats, "spelling-repeat-records.json")
                print("ACCURACY SPELLING REPEAT \(iteration) \(fixture.id)")
            }
        }
        XCTAssertEqual(repeats.count, 18)
    }
    private struct Control: Codable {
        let id: String
        let kind: String
        let term: String
        let text: String
        let sourceID: String
        let sourceDefinition: String
    }
    private struct Assessment: Codable {
        let term: String?
        let classification: String
        let alignment: String
        let sourceID: String?
        let reason: String
        let modelReviewed: Bool
    }
    private struct Record: Codable {
        let id: String
        let mode: AIConnectorReviewMode
        let output: AIConnectorQualityObservedOutput
        let assessments: [Assessment]
        let observation: AIConnectorObservationReport?
    }
    private struct SpellingCandidate: Codable {
        let original: String
        let replacement: String
        let delta: Double?
        let decision: String?
        let route: String?
        let routeReason: String?
        let rejection: String?
    }
    private struct SpellingRepeat: Codable {
        let fixtureID: String
        let iteration: Int
        let output: AIConnectorQualityObservedOutput
        let candidates: [SpellingCandidate]
        let observation: AIConnectorObservationReport?
    }
}
