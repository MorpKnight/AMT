import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorAccuracyFixTests: XCTestCase {
    func testCapitalizationTranspositionAndUnicodeAnchors() throws {
        let text = "😀 Datta disimpan; Laproan diserahkan."
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller(["datta": ["data"], "laproan": ["laporan"]]))
        let values = provider.candidates(for: segment(text), protectionContext: .empty, excludedOriginals: [])
        XCTAssertEqual(values.map { $0.original + "|" + $0.replacement }, ["Datta|Data", "Laproan|Laporan"])
        for value in values {
            XCTAssertEqual((text as NSString).substring(with: NSRange(location: value.sourceLocation, length: value.sourceLength)), value.original)
            XCTAssertNotNil(value.restorationEvidence)
        }
    }
    func testNamesQuotesIdentifiersAndAcronymsStayProtected() {
        let text = "PT Datta Nusantara memakai “Laproan”, Datta_ID dan DATTA."
        let protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller(["datta": ["data"], "laproan": ["laporan"]]))
        XCTAssertTrue(provider.candidates(for: segment(text), protectionContext: protection, excludedOriginals: []).isEmpty)
    }
    func testExplicitDocumentPhraseDoesNotBecomeUnscopedVocabulary() throws {
        let text = "Yang dimaksud dengan Data Pribadi adalah data tentang individu. Datta Pribadi disimpan. Datta Arsip diserahkan."
        let protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller([:]))
        let values = provider.candidates(for: segment(text), protectionContext: protection, excludedOriginals: [])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.original, "Datta")
        XCTAssertEqual(values.first?.replacement, "Data")
        XCTAssertEqual(values.first?.sourceLocation, (text as NSString).range(of: "Datta Pribadi").location)
    }
    func testReverseDeclarationProvidesScopedPhraseRestoration() throws {
        let text = "PASAL 1\nDEFINISI\nData tentang individu selanjutnya disebut “Data Pribadi”.\n\nPASAL 2\nPELAKSANAAN\nDatta Pribadi disimpan. Datta Arsip diserahkan."
        let protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller([:]))
        let values = provider.candidates(for: segment(text), protectionContext: protection, excludedOriginals: [])
        XCTAssertEqual(values.map { $0.original + "|" + $0.replacement }, ["Datta|Data"])
        XCTAssertEqual(values.first?.sourceLocation, (text as NSString).range(of: "Datta Pribadi").location)
        XCTAssertTrue(protection.explicitDocumentTerms.contains("Data Pribadi"))
    }
    func testWholeDummyReverseDeclarationRestoresDattaOutsideProtectedContent() throws {
        let original = "Pihak Kedua hanya boleh memproses Data Pribadi"
        let text = AIConnectorDummyDocument.initialContent.replacingOccurrences(of: original,
            with: "Pihak Kedua hanya boleh memproses Datta Pribadi")
        XCTAssertTrue(text.contains("Datta Pribadi"))
        let protection = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller([:]))
        let values = provider.candidates(for: segment(text), protectionContext: protection, excludedOriginals: [])
        let datta = try XCTUnwrap(values.first { $0.original == "Datta" },
            "terms=\(protection.explicitDocumentTerms); scopes=\(protection.explicitTermScopes["Data Pribadi"] ?? []); names=\(protection.partyNames)")
        XCTAssertEqual(datta.replacement, "Data")
        XCTAssertEqual(datta.sourceLocation, (text as NSString).range(of: "Datta Pribadi").location)
    }
    func testLowNegativeScoreRequiresModelReviewWithoutRelaxingStrictThreshold() throws {
        let text = "Pihak menyerahkan perjanjain."
        let native = SystemIndonesianSpellingCandidateProvider(checker: Speller(["perjanjain": ["perjanjian"]]))
        let raw = try XCTUnwrap(native.candidates(for: segment(text), protectionContext: .empty, excludedOriginals: []).first)
        let scored = score(raw, text: text, delta: -1)
        XCTAssertFalse(AIConnectorLanguageScorePolicy.isEligible(try XCTUnwrap(scored.evidence)))
        let candidate = try XCTUnwrap(builder.buildResult(for: segment(text), glossaryMatches: [], spellingCandidates: [scored], phaseTwoEnabled: true).candidates.first)
        let hybrid = AIConnectorPhaseTwoPolicy().route(candidate: candidate, in: segment(text), protectionContext: .empty, mode: .hybrid, forceDeterministic: false)
        XCTAssertEqual(hybrid.route, .modelReview)
        XCTAssertTrue(hybrid.modelCallRequired)
        let deterministic = AIConnectorPhaseTwoPolicy().route(candidate: candidate, in: segment(text), protectionContext: .empty, mode: .deterministic, forceDeterministic: false)
        XCTAssertEqual(deterministic.route, .needsReview)
        XCTAssertFalse(deterministic.modelCallRequired)
    }
    func testAmbiguousGuessDoesNotOverrideLowScoreAndInvalidEvidenceIsRejected() throws {
        let text = "Pihak menerima karyawann."
        let provider = SystemIndonesianSpellingCandidateProvider(checker: Speller(["karyawann": ["karyawan", "karyawana"]]))
        let values = provider.candidates(for: segment(text), protectionContext: .empty, excludedOriginals: [])
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(builder.buildResult(for: segment(text), glossaryMatches: [], spellingCandidates: values.map { score($0, text: text, delta: -0.1) }, phaseTwoEnabled: true).candidates.isEmpty)
        let single = try XCTUnwrap(values.first)
        XCTAssertTrue(builder.buildResult(for: segment(text), glossaryMatches: [], spellingCandidates: [score(single, text: text, delta: .nan)], phaseTwoEnabled: true).candidates.isEmpty)
    }
    func testCapitalizedRestorationRequiresEvidenceAndApprovedReview() throws {
        let text = "Datta disimpan."
        let raw = try XCTUnwrap(SystemIndonesianSpellingCandidateProvider(checker: Speller(["datta": ["data"]])).candidates(for: segment(text), protectionContext: .empty, excludedOriginals: []).first)
        let parsed = AIParsedReview(status: .suggestion, category: .spelling, original: raw.original, replacement: raw.replacement, glossaryID: nil, reason: "Pemulihan ejaan Datta menjadi Data.")
        let anchor = AIConnectorReviewAnchor(segmentID: 1, sourceRange: NSRange(location: raw.sourceLocation, length: raw.sourceLength), original: raw.original)
        XCTAssertThrowsError(try AIConnectorSuggestionValidator().validate(parsed, for: segment(text), glossaryMatches: [], sourceAnchor: anchor))
        let valid = try AIConnectorSuggestionValidator().validate(parsed, for: segment(text), glossaryMatches: [], origin: .qwen, sourceAnchor: anchor, restorationEvidence: raw.restorationEvidence)
        XCTAssertEqual(valid.status, .suggestion)
        XCTAssertThrowsError(try AIConnectorSuggestionValidator().validate(parsed, for: segment(text), glossaryMatches: [], origin: .deterministic, sourceAnchor: anchor, restorationEvidence: raw.restorationEvidence))
    }
    func testLegalMarkerRestorationAlwaysRoutesToReadOnlyReview() throws {
        let text = "Pihak memenuhi kewajban."
        let raw = try XCTUnwrap(SystemIndonesianSpellingCandidateProvider(checker: Speller(["kewajban": ["kewajiban"]])).candidates(for: segment(text), protectionContext: .empty, excludedOriginals: []).first)
        let candidate = try XCTUnwrap(builder.buildResult(for: segment(text), glossaryMatches: [], spellingCandidates: [score(raw, text: text, delta: 0.8)], phaseTwoEnabled: true).candidates.first)
        for mode in AIConnectorReviewMode.allCases {
            let route = AIConnectorPhaseTwoPolicy().route(candidate: candidate, in: segment(text), protectionContext: .empty, mode: mode, forceDeterministic: false)
            XCTAssertEqual(route.route, .needsReview)
            XCTAssertFalse(route.modelCallRequired)
        }
    }
    func testExplicitTermCannotBindAnUnrelatedSource() {
        let text = "Yang dimaksud dengan Data Pribadi adalah data tentang individu."
        let unrelated = entry("wrong", "Ketransmigrasian", "data tentang penyelenggaraan transmigrasi")
        let detection = AIConnectorDefinitionDetector(dictionaryStore: LegalDictionaryStore(entries: [unrelated])).detect(segment: segment(text), glossaryMatches: [LegalDictionaryMatch(entry: unrelated, score: 100, rank: 1, matchedDefinitionTokenCount: 3, isDirectTermMatch: false)])
        XCTAssertEqual(detection.term, "Data Pribadi")
        XCTAssertEqual(detection.detection, .explicitPattern)
        XCTAssertTrue(detection.candidates.isEmpty)
    }
    func testMissingEligibleSourcePreservesStrongDocumentDefinition() async throws {
        let result = try await analyze("Yang dimaksud dengan Data Pribadi adalah data tentang individu.", entries: []) { _,_,_ in XCTFail("No unrelated inference"); throw TestFailure.unavailable }
        XCTAssertEqual(result.assessment?.term, "Data Pribadi")
        XCTAssertEqual(result.assessment?.classification, .explicitDefinition)
        XCTAssertEqual(result.assessment?.alignment, .needsReview)
        XCTAssertEqual(result.modelCallCount, 0)
    }
    func testCompleteNarrowNegationMismatchHasNoEditProposal() async throws {
        let source = entry("rail", "Sarana perkeretaapian", "kendaraan yang dapat bergerak di jalan rel.")
        let text = "Yang dimaksud dengan Sarana perkeretaapian adalah kendaraan yang tidak dapat bergerak di jalan rel."
        let result = try await analyze(text, entries: [source]) { _,_,_ in XCTFail("Narrow complete mismatch is local"); throw TestFailure.unavailable }
        let assessment = try XCTUnwrap(result.assessment)
        XCTAssertEqual(assessment.classification, .explicitDefinition)
        XCTAssertEqual(assessment.alignment, .mismatch)
        XCTAssertEqual(result.modelCallCount, 0)
        let resolutions = try await AIConnectorDefinitionResolutionService(dictionaryStore: LegalDictionaryStore(entries: [source])).resolve(assessment: assessment, documentText: text, mode: .hybrid, modelVariant: .qwen35Base4B, includeReverseTermCandidates: true)
        XCTAssertTrue(resolutions.resolution.options.isEmpty)
    }
    func testOtherPredicateNegationStillNeedsContextualReview() async throws {
        let box = Requests()
        let source = entry("data", "Data", "informasi yang dapat disimpan dan diumumkan.")
        let result = try await analyze("Yang dimaksud dengan Data adalah informasi yang dapat disimpan dan tidak diumumkan.", entries: [source]) { request,_,_ in
            box.values.append(request)
            return QwenDefinitionReviewResult(candidateID: request.candidate.id, classification: .explicitDefinition, alignment: .needsReview, metrics: Self.metrics, containsReasoningMarkers: false)
        }
        XCTAssertEqual(box.values.count, 1)
        XCTAssertEqual(box.values.first?.documentTerm, "Data")
        XCTAssertEqual(result.assessment?.alignment, .needsReview)
    }
    func testDefinitionFormatRepairIsBoundedToOne() async throws {
        let source = entry("data", "Data", "informasi yang dapat disimpan.")
        let box = Requests()
        let result = try await analyze("Yang dimaksud dengan Data adalah informasi elektronik.", entries: [source]) { request,_,_ in
            box.values.append(request)
            if box.values.count == 1 { throw AIConnectorDefinitionReviewParserError.invalidDecision }
            XCTAssertNotNil(request.retryInstruction)
            return QwenDefinitionReviewResult(candidateID: request.candidate.id, classification: .explicitDefinition, alignment: .needsReview, metrics: Self.metrics, containsReasoningMarkers: false)
        }
        XCTAssertEqual(box.values.count, 2)
        XCTAssertEqual(result.modelCallCount, 2)
        XCTAssertTrue(result.isComplete)
        let failedBox = Requests()
        let failed = try await analyze("Yang dimaksud dengan Data adalah informasi elektronik.", entries: [source]) { request,_,_ in failedBox.values.append(request); throw AIConnectorDefinitionReviewParserError.invalidDecision }
        XCTAssertEqual(failedBox.values.count, 2)
        XCTAssertFalse(failed.isComplete)
    }
    func testCurrencyDecimalsPercentagesAndDeicticAppendicesAreNotMissingReferences() async {
        for text in ["Pihak membayar Rp10.000.000.", "Volume 2.500,5 kg dan bunga 2,5%.", "Lampiran ini disimpan bersama Lampiran tersebut."] {
            let review = await documentReview(text)
            XCTAssertTrue(review.findings.filter { $0.kind == .internalReference }.isEmpty, text)
        }
    }
    func testExplicitMissingAppendixAndValidOutlineRemainRecognized() async {
        let missing = await documentReview("Silakan lihat Lampiran C.")
        XCTAssertTrue(missing.findings.contains { $0.kind == .internalReference && $0.original == "Lampiran C" })
        let valid = await documentReview("1.2 Ketentuan\n\nPihak merujuk angka 1.2.")
        XCTAssertFalse(valid.findings.contains { $0.kind == .internalReference })
    }
    func testExplicitAliasIsTheOnlyAdditionalExplicitSourceBinding() {
        let text = "“Data Pribadi”, selanjutnya disebut “Informasi Pengguna”.\n\nYang dimaksud dengan Informasi Pengguna adalah data tentang individu."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let builder = AIConnectorDocumentContextProfileBuilder()
        let profile = builder.build(documentText: text, structure: structure)
        let block = structure.blocks.last
        var target = segment("Yang dimaksud dengan Informasi Pengguna adalah data tentang individu.")
        if let block { target = AIReviewSegment(id: 1, sourceLocation: block.sourceRange.location,
            sourceLength: block.sourceRange.length, targetText: block.text, previousContext: nil,
            nextContext: nil, context: builder.context(for: block, structure: structure, profile: profile)) }
        let source = entry("data", "Data Pribadi", "data tentang individu.")
        let result = AIConnectorDefinitionDetector(dictionaryStore: LegalDictionaryStore(entries: [source]))
            .detect(segment: target, glossaryMatches: [])
        XCTAssertEqual(profile.explicitTermAliases["Informasi Pengguna"], "Data Pribadi")
        XCTAssertEqual(result.term, "Informasi Pengguna")
        XCTAssertEqual(result.candidates.first?.term, "Data Pribadi")
    }
    func testRestorationRejectsChangedContextRevisionAndFabricatedWindow() throws {
        let text = "Datta disimpan."
        let context = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let raw = try XCTUnwrap(SystemIndonesianSpellingCandidateProvider(checker: Speller(["datta": ["data"]]))
            .candidates(for: segment(text), protectionContext: context, excludedOriginals: []).first)
        let stale = AIConnectorDocumentProtectionContextBuilder().build(documentText: text + " Konteks berubah.")
        XCTAssertFalse(try XCTUnwrap(raw.restorationEvidence).isValid(in: segment(text), context: stale))
        let scored = score(raw, text: "Konteks lain berisi Datta.", delta: -0.2)
        XCTAssertTrue(builder.buildResult(for: segment(text), glossaryMatches: [], spellingCandidates: [scored],
            phaseTwoEnabled: true, protectionContext: context).candidates.isEmpty)
    }
    func testDefinitionSemanticDisagreementIsNotRetried() async throws {
        let box = Requests()
        let source = entry("data", "Data", "informasi elektronik.")
        let result = try await analyze("Yang dimaksud dengan Data adalah informasi elektronik.", entries: [source]) { request,_,_ in
            box.values.append(request)
            return QwenDefinitionReviewResult(candidateID: request.candidate.id, classification: .notDefinition,
                alignment: .notApplicable, metrics: Self.metrics, containsReasoningMarkers: false)
        }
        XCTAssertEqual(box.values.count, 1)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.repairCount, 0)
        XCTAssertEqual(result.assessment?.classification, .needsReview)
    }
    func testReferenceNumberNeedsStructureOrReferralEvidence() async {
        let measurement = await documentReview("Nilai rata-rata 1.25 telah diperiksa.")
        XCTAssertFalse(measurement.findings.contains { $0.kind == .internalReference })
        let missing = await documentReview("Pihak merujuk angka 9.8.")
        XCTAssertTrue(missing.findings.contains { $0.kind == .internalReference && $0.original == "9.8" })
    }
    func testDocumentPhraseEvidenceSurvivesAnAmbiguousNativeGuess() throws {
        let text = "Yang dimaksud dengan Data Pribadi adalah data tentang individu. Datta Pribadi disimpan."
        let context = AIConnectorDocumentProtectionContextBuilder().build(documentText: text)
        let raw = SystemIndonesianSpellingCandidateProvider(checker: Speller(["datta": ["data", "datar"]]))
            .candidates(for: segment(text), protectionContext: context, excludedOriginals: [])
        let restoration = try XCTUnwrap(raw.first { $0.original == "Datta" && $0.replacement == "Data" })
        XCTAssertEqual(restoration.restorationEvidence?.explicitDocumentPhrase, "Data Pribadi")
        XCTAssertEqual(raw.filter { $0.replacement == "Data" }.count, 1)
        let candidates = builder.buildResult(for: segment(text), glossaryMatches: [],
            spellingCandidates: [score(restoration, text: text, delta: -1)],
            phaseTwoEnabled: true, protectionContext: context).candidates
        XCTAssertEqual(candidates.count, 1)
    }
    func testDeclaredProductNameDoesNotBindToAnEmbeddedCorpusTerm() {
        let text = "“Produk Data” adalah aplikasi pengarsipan perusahaan."
        let source = entry("data", "Data", "informasi elektronik.")
        let result = AIConnectorDefinitionDetector(dictionaryStore: LegalDictionaryStore(entries: [source]))
            .detect(segment: segment(text), glossaryMatches: [])
        XCTAssertEqual(result.term, "Produk Data")
        XCTAssertEqual(result.explicitSignalStrength, .strong)
        XCTAssertTrue(result.candidates.isEmpty)
    }
    private var builder: AIConnectorCandidateBuilder { AIConnectorCandidateBuilder(ruleStore: AIConnectorRuleStore()) }
    private func segment(_ text: String) -> AIReviewSegment { AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil) }
    private func score(_ raw: AIConnectorSpellingCandidate, text: String, delta: Double) -> AIConnectorSpellingCandidate {
        AIConnectorSpellingCandidate(original: raw.original, replacement: raw.replacement, sourceLocation: raw.sourceLocation, sourceLength: raw.sourceLength, sourceRank: raw.sourceRank, evidence: AIConnectorLanguageScoreEvidence(modelID: AIConnectorLanguageScorerConfiguration.modelID, revision: AIConnectorLanguageScorerConfiguration.revision, sourceWindow: text, originalScore: -2, replacementScore: -2 + delta, delta: delta, tokenizerVocabularyCount: AIConnectorLanguageScorerConfiguration.tokenizerVocabularyCount, configuredVocabularyCount: AIConnectorLanguageScorerConfiguration.configuredVocabularyCount), restorationEvidence: raw.restorationEvidence)
    }
    private func entry(_ id: String, _ term: String, _ definition: String) -> LegalDictionaryEntry { LegalDictionaryEntry(id: id, term: term, definition: definition, regulation: "Sumber sintetis", regulationTitle: "Uji", sourceURL: nil, authority: .verified, corpusVersion: "accuracy-offline-v2", applicabilityStatus: .inForce, isActionable: true) }
    private func analyze(_ text: String, entries: [LegalDictionaryEntry], reviewer: @escaping AIConnectorDefinitionReviewHandler) async throws -> AIConnectorDefinitionAnalysisResult {
        try await AIConnectorDefinitionAnalyzer(dictionaryStore: LegalDictionaryStore(entries: entries), reviewHandler: reviewer).analyze(segment: segment(text), glossaryMatches: [], mode: .hybrid, modelVariant: .qwen35Base4B, thinkingEnabled: false, forceDeterministic: false, generationProfile: AIConnectorGenerationProfilePreset.greedy.profile(for: .qwen35Base4B, thinkingEnabled: false), downloadProgress: { _ in }, generationProgress: { _ in }, semanticProgress: { _ in }, progressStage: { _ in })
    }
    private func documentReview(_ text: String) async -> AIConnectorDocumentReviewResult {
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(documentText: text, structure: structure)
        return await AIConnectorDocumentReviewDetector().analyze(documentText: text, structure: structure, profile: profile, mode: .deterministic, modelVariant: .qwen35Base4B)
    }
    private static var metrics: AIConnectorGenerationMetrics { AIConnectorGenerationMetrics(promptTokenCount: 12, generationTokenCount: 3, promptDuration: 0.01, generationDuration: 0.01, stopReason: .stop) }
    private enum TestFailure: Error { case unavailable }
    @MainActor private final class Requests { var values: [AIConnectorDefinitionReviewRequest] = [] }
    @MainActor private final class Speller: AIConnectorSystemSpellChecker {
        let words: [String: [String]]
        init(_ words: [String: [String]]) { self.words = words }
        func checkSpelling(in text: String, startingAt location: Int, language: String) -> NSRange {
            let ns = text as NSString
            guard location < ns.length else { return NSRange(location: NSNotFound, length: 0) }
            return words.keys.map { ns.range(of: $0, options: .caseInsensitive, range: NSRange(location: location, length: ns.length-location)) }.filter { $0.location != NSNotFound }.min(by: { $0.location < $1.location }) ?? NSRange(location: NSNotFound, length: 0)
        }
        func guesses(forWordRange range: NSRange, in text: String, language: String) -> [String] { words[(text as NSString).substring(with: range).lowercased()] ?? [] }
    }
}
