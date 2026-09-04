import Foundation
import XCTest
@testable import AMT

final class LegalCorpusP012Tests: XCTestCase {
    func testBundledCorpusPackIsVersionedAndInternallyConsistent() throws {
        let corpus = try LegalCorpusStore(bundle: .main)

        XCTAssertEqual(
            corpus.manifest.corpusVersion,
            "hukumonline-kamus-combined-deduplicated@78a2ab626c092662b0441c95904c353b2487b216"
        )
        XCTAssertEqual(corpus.manifest.sourceDatasetView, "combined-deduplicated")
        XCTAssertEqual(corpus.concepts.count, 8_272)
        XCTAssertEqual(corpus.regulations.count, 1_591)
        XCTAssertEqual(corpus.relations.count, 315)
        XCTAssertEqual(corpus.sourcePassages.count, 628)
        XCTAssertEqual(corpus.manifest.actionableConceptCount, 2_238)
        XCTAssertEqual(corpus.concepts.count, corpus.manifest.conceptCount)
        XCTAssertEqual(corpus.regulations.count, corpus.manifest.regulationCount)
        XCTAssertEqual(corpus.relations.count, corpus.manifest.relationCount)
        XCTAssertEqual(corpus.sourcePassages.count, corpus.manifest.sourcePassageCount)
        XCTAssertEqual(
            corpus.embeddings.count,
            corpus.concepts.count * corpus.manifest.embedding.dimension
        )
        XCTAssertEqual(
            corpus.concepts.filter(\.actionable).count,
            corpus.manifest.actionableConceptCount
        )
        XCTAssertEqual(corpus.manifest.embedding.dimension, 384)
        XCTAssertTrue(corpus.manifest.embedding.normalized)
        XCTAssertEqual(
            corpus.manifest.embedding.conceptOrderSHA256,
            "3b9e8320a31dfee5dffbed433ea594e5cb137285f1fbdb2a862e3d1d3ac85f84"
        )
    }

    func testBundledCorpusKeepsMultipleDefinitionsForOneTerm() throws {
        let corpus = try LegalCorpusStore(bundle: .main)
        let dataPribadi = corpus.concepts.filter {
            $0.term.caseInsensitiveCompare("Data Pribadi") == .orderedSame
        }

        XCTAssertGreaterThanOrEqual(dataPribadi.count, 2)
        XCTAssertGreaterThanOrEqual(
            Set(dataPribadi.map(\.recordID)).count,
            2
        )
    }

    func testSemanticRowMappingUsesStableConceptOrder() throws {
        let corpus = try LegalCorpusStore(bundle: .main)
        let dimension = corpus.manifest.embedding.dimension
        let queryVector = Array(corpus.embeddings.prefix(dimension))

        let matches = corpus.semanticMatches(for: queryVector, limit: 1)

        XCTAssertEqual(matches.first?.concept.recordID, corpus.concepts.first?.recordID)
        XCTAssertGreaterThan(matches.first?.semanticScore ?? 0, 0.99)
    }

    func testDictionaryGroupsCorpusEntriesOnlyAtPresentationBoundary() {
        let store = LegalDictionaryStore()
        let entries = store.entries(forTerm: "Data Pribadi")

        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.term)).count, 1)
        XCTAssertTrue(entries.contains(where: { $0.isActionable }))
        XCTAssertTrue(entries.contains(where: { !$0.isActionable }))
    }

    func testCombinedCorpusExposesParalegalProvenanceWithoutSuggestionAuthority() throws {
        let store = LegalDictionaryStore()
        let entry = try XCTUnwrap(store.entries(forTerm: "Kosmetika Impor").first)

        XCTAssertEqual(entry.sources, ["Paralegal.id"])
        XCTAssertEqual(
            entry.sourceURLs.map(\.absoluteString),
            ["https://paralegal.id/pengertian/kosmetika-impor/"]
        )
        XCTAssertEqual(entry.corpusVersion, store.activeCorpusVersion)
        XCTAssertEqual(entry.authority, .legacy)
        XCTAssertFalse(entry.isActionable)
        XCTAssertNil(entry.sourcePassageID)
        XCTAssertEqual(entry.applicabilityStatus, .inForce)
        XCTAssertNotNil(entry.officialDocumentURL)
    }

    func testCombinedCorpusRetainsDistinctDefinitionsAndSourceProvenance() {
        let store = LegalDictionaryStore()
        let entries = store.entries(forTerm: "Adat")
        let sources = Set(entries.flatMap(\.sources))

        XCTAssertGreaterThanOrEqual(entries.count, 3)
        XCTAssertTrue(sources.contains("Hukumonline Kamus"))
        XCTAssertTrue(sources.contains("Paralegal.id"))
        XCTAssertTrue(entries.contains(where: { $0.isActionable }))
        XCTAssertTrue(entries.contains(where: { !$0.isActionable }))
    }

    func testExactTermLookupDoesNotLoadSemanticModel() async {
        let store = LegalDictionaryStore()

        let results = await store.searchRAG("Data Pribadi", limit: 5)

        XCTAssertEqual(results.first?.term, "Data Pribadi")
        let isSemanticModelLoaded = await store.isSemanticModelLoaded()
        XCTAssertFalse(isSemanticModelLoaded)
    }

    /// Opt-in runtime smoke test. Regular XCTest must remain offline and
    /// therefore skips this test before creating a semantic query.
    func testOptInE5SemanticLookup() async throws {
        guard ProcessInfo.processInfo.environment["AMT_RUN_P012_E5_SMOKE"] == "1"
            || ProcessInfo.processInfo.environment["TEST_RUNNER_AMT_RUN_P012_E5_SMOKE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_AMT_RUN_P012_E5_SMOKE=1 to load the pinned E5 model.")
        }

        let store = LegalDictionaryStore()
        let matches = try await store.retrieve(
            LegalRetrievalRequest(
                query: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi",
                intent: .reverseLookup,
                limit: 5
            )
        )

        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.allSatisfy { $0.rank > 0 })
        let semanticScores = matches.compactMap(\.semanticScore)
        XCTAssertFalse(semanticScores.isEmpty)
        XCTAssertTrue(semanticScores.allSatisfy(\.isFinite))
        let isSemanticModelLoaded = await store.isSemanticModelLoaded()
        XCTAssertTrue(isSemanticModelLoaded)
    }

    func testSemanticConfigurationIsAvailableForCacheInvalidation() {
        let store = LegalDictionaryStore()

        XCTAssertNotEqual(store.semanticEmbeddingSchema, "none")
        XCTAssertNotEqual(store.semanticRetrievalProfile, "none")
        XCTAssertTrue(store.semanticRetrievalProfile.contains("60"))
    }

    func testLegacyCSVRuntimeIsDisabledWithoutDeletingItsParser() {
        XCTAssertFalse(LegalDictionaryStore.legacyCSVRuntimeEnabled)

        let activeEntries = LegalDictionaryStore().entries
        XCTAssertTrue(activeEntries.allSatisfy {
            $0.corpusVersion != LegalDictionaryCorpusVersion.legacyKamusV1
        })

        let retainedLegacyEntry = LegalDictionaryEntry(
            id: "legacy-fixture",
            term: "Legacy Fixture",
            definition: "Fixture legacy untuk menguji batas actionable.",
            regulation: "",
            regulationTitle: "",
            sourceURL: nil,
            authority: .verified,
            corpusVersion: LegalDictionaryCorpusVersion.legacyKamusV1,
            isActionable: false
        )
        XCTAssertFalse(retainedLegacyEntry.isActionable)
    }

    func testCorpusLoaderRejectsTamperedPayload() throws {
        let corpus = try LegalCorpusStore(bundle: .main)
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "manifest", withExtension: "json")
        )
        let sourceDirectory = manifestURL.deletingLastPathComponent()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AMT-P012-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: sourceDirectory, to: temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let conceptsURL = temporaryDirectory.appendingPathComponent("concepts.json")
        var data = try Data(contentsOf: conceptsURL)
        data[0] = data[0] == 0x5B ? 0x5D : 0x5B
        try data.write(to: conceptsURL, options: .atomic)

        XCTAssertThrowsError(try LegalCorpusStore(directory: temporaryDirectory)) { error in
            XCTAssertEqual(error as? LegalCorpusStoreError, .hashMismatch("concepts.json"))
        }
        XCTAssertEqual(corpus.manifest.conceptCount, 8_272)
    }

    func testLocalToolsExposeCorpusEvidenceWithoutWriteCapability() async throws {
        let store = LegalDictionaryStore()
        guard let entry = store.entries.first(where: {
            $0.isActionable && $0.sourcePassageID != nil && $0.referenceID != nil
        }) else {
            return XCTFail("Bundled corpus has no actionable evidence fixture")
        }
        let dispatcher = AIConnectorLocalToolDispatcher(dictionaryStore: store)

        let passageResponse = try await dispatcher.call(
            AIConnectorLocalToolRequest(
                name: .getSourcePassage,
                passageID: entry.sourcePassageID
            )
        )
        XCTAssertEqual(
            passageResponse.corpusVersion,
            store.activeCorpusVersion
        )
        XCTAssertTrue(passageResponse.payload.contains(entry.sourcePassageID ?? ""))

        let statusResponse = try await dispatcher.call(
            AIConnectorLocalToolRequest(
                name: .getRegulationStatus,
                referenceID: entry.referenceID
            )
        )
        XCTAssertTrue(statusResponse.payload.contains("in_force"))
        XCTAssertTrue(statusResponse.isAuthoritative)
    }

    func testLegacyEntriesRemainNonActionableForTerminology() {
        let entry = LegalDictionaryEntry(
            id: "legacy-term",
            term: "Istilah Lama",
            definition: "Definisi lama.",
            regulation: "Regulasi lama",
            regulationTitle: "",
            sourceURL: nil,
            authority: .legacy,
            corpusVersion: LegalDictionaryCorpusVersion.legacyKamusV1
        )

        XCTAssertFalse(entry.isActionable)
        XCTAssertTrue(
            AIConnectorCandidateBuilder(ruleStore: AIConnectorRuleStore(version: "test", rules: []))
                .build(
                    for: AIReviewSegment(
                        id: 1,
                        sourceLocation: 0,
                        sourceLength: 20,
                        targetText: "Definisi lama yang panjang.",
                        previousContext: nil,
                        nextContext: nil
                    ),
                    glossaryMatches: [
                        LegalDictionaryMatch(
                            entry: entry,
                            score: 10,
                            rank: 1,
                            matchedDefinitionTokenCount: 3,
                            isDirectTermMatch: false
                        )
                    ]
                )
                .isEmpty
        )
    }
}
