import Foundation
import XCTest
@testable import AMT

final class LegalCorpusP012Tests: XCTestCase {
    func testBundledCorpusPackIsVersionedAndInternallyConsistent() throws {
        let corpus = try LegalCorpusStore(bundle: .main)

        XCTAssertEqual(
            corpus.manifest.corpusVersion,
            "hukumonline-kamus-dictionary-serving@17a6fe91aad1b9451ecfa49d086ad086c44e6120"
        )
        XCTAssertEqual(corpus.manifest.sourceDatasetView, "dictionary-serving")
        XCTAssertEqual(corpus.concepts.count, 5_416)
        XCTAssertEqual(corpus.regulations.count, 1_591)
        XCTAssertEqual(corpus.relations.count, 315)
        XCTAssertEqual(corpus.sourcePassages.count, 636)
        XCTAssertEqual(corpus.manifest.actionableConceptCount, 2_323)
        XCTAssertEqual(corpus.termGroups.count, 6_537)
        XCTAssertEqual(corpus.primaryRecords.count, 6_537)
        XCTAssertEqual(corpus.alternatives.count, 2_975)
        XCTAssertEqual(corpus.manifest.termGroupCount, 6_537)
        XCTAssertEqual(corpus.manifest.alternativeCount, 2_975)
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
            "e1faa656a6c81c4aabd36b208742be1f6793cb0d5690f369f18d4ecc69106ade"
        )
    }

    func testBundledCorpusUsesOnePrimaryConceptForOneTerm() throws {
        let corpus = try LegalCorpusStore(bundle: .main)
        let dataPribadi = corpus.concepts.filter {
            $0.term.caseInsensitiveCompare("Data Pribadi") == .orderedSame
        }

        XCTAssertEqual(dataPribadi.count, 1)
        XCTAssertEqual(dataPribadi.first?.references.map(\.referenceID), [
            "peraturan.go.id:uu-no-27-tahun-2022"
        ])
        XCTAssertEqual(dataPribadi.first?.sources, ["Paralegal.id"])
        XCTAssertTrue(
            dataPribadi.first?.definition.contains("orang perseorangan") == true
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

    func testDictionaryPrimaryDoesNotFanOutCrossSourceDefinitions() {
        let store = LegalDictionaryStore()
        let entries = store.entries(forTerm: "Data Pribadi")

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries.map(\.term)).count, 1)
        XCTAssertEqual(entries.first?.referenceID, "peraturan.go.id:uu-no-27-tahun-2022")
        XCTAssertEqual(entries.first?.sources, ["Paralegal.id"])

        let alternatives = store.alternatives(forTerm: "Data Pribadi")
        XCTAssertEqual(alternatives.count, 3)
        XCTAssertEqual(
            alternatives.first?.definitionID,
            "definition:083ac1e28c6e6fde0d70c2cb"
        )
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

    func testDictionaryPrimaryKeepsOneSourceDefinitionPerSelectedTerm() {
        let store = LegalDictionaryStore()
        let entries = store.entries(forTerm: "Adat")

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.sources, ["Paralegal.id"])
        XCTAssertEqual(entries.first?.referenceID, "peraturan.go.id:uu-no-21-tahun-2001")
    }

    func testDictionaryCorpusSummaryExposesEnrichmentScope() {
        let store = LegalDictionaryStore()
        let summary = store.corpusSummary

        XCTAssertEqual(summary.sourceDatasetView, "dictionary-serving")
        XCTAssertEqual(summary.conceptCount, 5_416)
        XCTAssertEqual(summary.regulationCount, 1_591)
        XCTAssertEqual(summary.relationCount, 315)
        XCTAssertEqual(summary.sourcePassageCount, 636)
        XCTAssertTrue(summary.isEnriched)
        XCTAssertTrue(summary.sourceNames.contains("Hukumonline Kamus"))
    }

    func testDictionaryReferencesRetainOfficialMetadataAndSourcePassage() throws {
        let store = LegalDictionaryStore()
        let entry = try XCTUnwrap(
            store.entries.first {
                $0.isActionable
                    && $0.referenceID != nil
                    && $0.sourcePassageID != nil
            }
        )
        let references = store.references(for: entry)
        let reference = try XCTUnwrap(
            references.first { $0.referenceID == entry.referenceID }
        )

        XCTAssertNotNil(reference.sourcePassageText)
        XCTAssertNotNil(reference.officialStatus)
        XCTAssertNotNil(reference.number)
        XCTAssertNotNil(reference.year)
        XCTAssertNotNil(reference.officialDocumentURL)
        XCTAssertNotNil(reference.verificationStatus)
    }

    func testDictionaryPreservesMultipleOfficialReferencesForOnePrimaryDefinition() throws {
        let store = LegalDictionaryStore()
        let entry = try XCTUnwrap(
            store.entries(forTerm: "RKL")
                .first { $0.isActionable }
        )
        let references = store.references(for: entry)
        let referenceIDs = Set(references.compactMap(\.referenceID))

        XCTAssertGreaterThanOrEqual(references.count, 2)
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-12-tahun-2020"))
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-27-tahun-2012"))
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
        XCTAssertEqual(corpus.manifest.conceptCount, 5_416)
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
