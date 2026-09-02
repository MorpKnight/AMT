import XCTest
@testable import AMT

final class AIConnectorTests: XCTestCase {
    func testSegmenterPreservesSentenceTextAndOffsets() {
        let text = "JUDUL UJI\n\nKalimat pertama. Kalimat kedua!\n\nKalimat ketiga?"
        let result = LegalTextSegmenter().segment(documentText: text)

        XCTAssertEqual(result.headingCount, 1)
        XCTAssertEqual(result.segments.map(\.targetText), [
            "Kalimat pertama.",
            "Kalimat kedua!",
            "Kalimat ketiga?"
        ])
        XCTAssertEqual(result.segments.map { segment in
            String(
                decoding: text.utf16.dropFirst(segment.sourceLocation).prefix(segment.sourceLength),
                as: UTF16.self
            )
        }, result.segments.map(\.targetText))
        XCTAssertEqual(result.segments[1].previousContext, "Kalimat pertama.")
        XCTAssertEqual(result.segments[1].nextContext, "Kalimat ketiga?")
    }

    func testSegmenterProcessesAllSegmentsAndExposesBatchSize() {
        let text = (1...15).map { "Kalimat nomor \($0)." }.joined(separator: "\n\n")
        let result = LegalTextSegmenter().segment(documentText: text)

        XCTAssertEqual(result.segments.count, 15)
        XCTAssertEqual(result.queuedSegmentCount, 15)
        XCTAssertEqual(result.omittedSegmentCount, 0)
        XCTAssertEqual(result.segments[11].nextContext, "Kalimat nomor 13.")
        XCTAssertNil(result.segments.last?.nextContext)
    }

    func testSegmenterSplitsLongSentenceAtSemicolon() {
        let text = String(repeating: "Klausul panjang ", count: 180) + "; bagian lanjutan."
        let result = LegalTextSegmenter().segment(documentText: text)

        XCTAssertGreaterThanOrEqual(result.segments.count, 2)
        XCTAssertTrue(result.segments[0].targetText.hasSuffix(";"))
        XCTAssertEqual(result.segments[1].targetText, "bagian lanjutan.")
    }

    func testSegmenterMarksSegmentOver512TokensWithoutTruncatingIt() {
        let text = String(repeating: "kata ", count: 520) + "selesai."
        let result = LegalTextSegmenter().segment(documentText: text)

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.tooLongSegmentCount, 1)
        XCTAssertTrue(result.segments[0].isTooLong)
        XCTAssertEqual(result.segments[0].targetText, text)
    }

    func testParserAcceptsTaggedSuggestion() throws {
        let output = """
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: wajib untuk
        REPLACEMENT: wajib
        GLOSSARY_ID: -
        REASON: Bentuk ini lebih ringkas tanpa mengubah makna.
        """

        let parsed = try AIConnectorOutputParser().parse(output)

        XCTAssertEqual(parsed.status, .suggestion)
        XCTAssertEqual(parsed.category, .grammar)
        XCTAssertEqual(parsed.original, "wajib untuk")
        XCTAssertEqual(parsed.replacement, "wajib")
        XCTAssertNil(parsed.glossaryID)
    }

    func testParserRejectsExtraProseAndReasoning() {
        let parser = AIConnectorOutputParser()
        let valid = """
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: -
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah yang jelas.
        """

        XCTAssertThrowsError(try parser.parse("Catatan:\n\(valid)"))
        XCTAssertThrowsError(try parser.parse(valid + "\nTambahan"))
        XCTAssertThrowsError(try parser.parse(valid.replacingOccurrences(of: "REASON:", with: "<think>\nREASON:")))
    }

    func testParserRejectsDuplicateMissingInvalidCodeFenceAndMultilineContract() {
        let parser = AIConnectorOutputParser()
        let valid = """
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: -
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah yang jelas.
        """

        XCTAssertThrowsError(try parser.parse(valid.replacingOccurrences(of: "CATEGORY: NONE", with: "STATUS: NO_SUGGESTION")))
        XCTAssertThrowsError(try parser.parse(valid.replacingOccurrences(of: "CATEGORY: NONE", with: "CATEGORY: UNSUPPORTED")))
        XCTAssertThrowsError(try parser.parse("```text\n\(valid)\n```"))
        XCTAssertThrowsError(try parser.parse(valid.replacingOccurrences(of: "REASON: Tidak ada masalah yang jelas.", with: "REASON: Baris pertama.\nBaris kedua.")))
    }

    func testNoSuggestionRequiresEmptySuggestionFields() throws {
        let segment = makeSegment(target: "Perjanjian ini berlaku.")
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: -
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah yang jelas.
        """)

        let review = try AIConnectorSuggestionValidator().validate(
            parsed,
            for: segment,
            glossaryMatches: []
        )
        XCTAssertEqual(review.status, .noSuggestion)
    }

    func testCanonicalizerClearsHarmlessNoSuggestionOriginal() throws {
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: Perjanjian ini berlaku.
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada masalah bahasa yang jelas.
        """)

        let canonical = AIConnectorOutputCanonicalizer().canonicalize(parsed)

        XCTAssertEqual(canonical.status, .noSuggestion)
        XCTAssertNil(canonical.original)
        XCTAssertNil(canonical.replacement)
        XCTAssertNil(canonical.glossaryID)
        XCTAssertNoThrow(
            try AIConnectorSuggestionValidator().validate(
                canonical,
                for: makeSegment(target: "Perjanjian ini berlaku."),
                glossaryMatches: []
            )
        )
    }

    func testCanonicalizerDoesNotRewriteConflictingSuggestionSemantics() throws {
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: NONE
        ORIGINAL: berlaku
        REPLACEMENT: efektif
        GLOSSARY_ID: -
        REASON: Perbaikan bahasa.
        """)

        XCTAssertEqual(AIConnectorOutputCanonicalizer().canonicalize(parsed), parsed)
    }

    func testValidatorRejectsChangedNumbers() throws {
        let segment = makeSegment(target: "Pihak Kedua wajib membayar 30 (tiga puluh) hari.")
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: wajib membayar 30 (tiga puluh) hari
        REPLACEMENT: wajib membayar 31 (tiga puluh satu) hari
        GLOSSARY_ID: -
        REASON: Perbaikan tata bahasa.
        """)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: segment,
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .protectedContentChanged)
        }
    }

    func testValidatorRejectsDefinedTermChanges() throws {
        let segment = makeSegment(target: "Borrower wajib memberikan notice.")
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: CLARITY
        ORIGINAL: Borrower wajib memberikan notice
        REPLACEMENT: Peminjam wajib memberikan pemberitahuan
        GLOSSARY_ID: -
        REASON: Bentuk kalimat dibuat lebih jelas.
        """)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: segment,
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .protectedContentChanged)
        }
    }

    func testValidatorRejectsChangedDatesPercentagesCurrenciesAndModalities() throws {
        let cases = [
            (
                original: "Pihak Kedua hadir pada 10 Agustus 2026.",
                replacement: "Pihak Kedua hadir pada 10 September 2026."
            ),
            (
                original: "Biaya sebesar 10%.",
                replacement: "Biaya sebesar 10 persen."
            ),
            (
                original: "Pembayaran sebesar Rp10.000.",
                replacement: "Pembayaran sebesar USD10.000."
            ),
            (
                original: "Pihak Kedua wajib membayar.",
                replacement: "Pihak Kedua dapat membayar."
            )
        ]

        for item in cases {
            let parsed = try AIConnectorOutputParser().parse("""
            STATUS: SUGGESTION
            CATEGORY: GRAMMAR
            ORIGINAL: \(item.original)
            REPLACEMENT: \(item.replacement)
            GLOSSARY_ID: -
            REASON: Perbaikan bahasa.
            """)

            XCTAssertThrowsError(
                try AIConnectorSuggestionValidator().validate(
                    parsed,
                    for: makeSegment(target: item.original),
                    glossaryMatches: []
                )
            ) { error in
                XCTAssertEqual(error as? AIConnectorValidationError, .protectedContentChanged)
            }
        }
    }

    func testValidatorRejectsUnsupportedSourceClaim() throws {
        let segment = makeSegment(target: "Perusahaan wajib mematuhi aturan.")
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: -
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Menurut UU Nomor 1, kalimat ini sudah benar.
        """)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: segment,
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .unsupportedSourceClaim)
        }
    }

    func testValidatorRejectsNonMinimalWholeSentenceEdit() throws {
        let target = "Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan."
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: GRAMMAR
        ORIGINAL: \(target)
        REPLACEMENT: Pihak Kedua wajib menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.
        GLOSSARY_ID: -
        REASON: Menghapus kata yang tidak diperlukan.
        """)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: makeSegment(target: target),
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .nonMinimalEditSpan)
        }
    }

    func testValidatorRejectsReasonQuotingTextOutsideEvidence() throws {
        let target = "Pihak Pertama dapat mengakhiri Perjanjian ini."
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: CLARITY
        ORIGINAL: mengakhiri
        REPLACEMENT: mengakhiri
        GLOSSARY_ID: -
        REASON: Frasa "untuk menyerahkan" perlu diringkas.
        """)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: makeSegment(target: target),
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .ungroundedReason)
        }
    }

    func testDeterministicFallbackProducesValidatedLowRiskLanguageSuggestions() throws {
        let engine = AIConnectorDeterministicSuggestionEngine()
        let validator = AIConnectorSuggestionValidator()
        let fixtures: [(target: String, original: String, replacement: String, category: AIReviewCategory)] = [
            (
                "Pihak Kedua wajib untuk menyerahkan laporan bulanan.",
                "wajib untuk",
                "wajib",
                .grammar
            ),
            (
                "Perjanjian ini telah ditanda tangani oleh Para Pihak.",
                "ditanda tangani",
                "ditandatangani",
                .spelling
            )
        ]

        for (index, fixture) in fixtures.enumerated() {
            let segment = makeSegment(target: fixture.target, id: index + 1)
            let parsed = try XCTUnwrap(engine.suggestion(for: segment))
            let review = try validator.validate(
                parsed,
                for: segment,
                glossaryMatches: [],
                origin: .deterministicFallback
            )

            XCTAssertEqual(review.status, .suggestion)
            XCTAssertEqual(review.category, fixture.category)
            XCTAssertEqual(review.original, fixture.original)
            XCTAssertEqual(review.replacement, fixture.replacement)
            XCTAssertEqual(review.origin, .deterministicFallback)
        }
    }

    func testDeterministicFallbackDoesNotRewriteSubstantiveClause() {
        let segment = makeSegment(
            target: "Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua."
        )

        XCTAssertNil(AIConnectorDeterministicSuggestionEngine().suggestion(for: segment))
    }

    func testDeterministicSuggestionUsesExactChangedPhrase() throws {
        let segment = makeSegment(
            target: "Dokumen pendukung harus di simpan oleh Pihak Kedua."
        )
        let parsed = try XCTUnwrap(
            AIConnectorDeterministicSuggestionEngine().suggestion(for: segment)
        )

        XCTAssertEqual(parsed.category, .spelling)
        XCTAssertEqual(parsed.original, "di simpan")
        XCTAssertEqual(parsed.replacement, "disimpan")

        let review = try AIConnectorSuggestionValidator().validate(
            parsed,
            for: segment,
            glossaryMatches: [],
            origin: .deterministic
        )
        XCTAssertEqual(review.original, "di simpan")
        XCTAssertEqual(review.replacement, "disimpan")
    }

    func testDeterministicSuggestionUsesCanonicalGlossaryTerm() throws {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 100,
            rank: 1,
            matchedDefinitionTokenCount: 20,
            isDirectTermMatch: false
        )
        let target = "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik."
        let segment = makeSegment(target: target)

        let parsed = try XCTUnwrap(
            AIConnectorDeterministicSuggestionEngine().suggestion(
                for: segment,
                glossaryMatches: [match]
            )
        )

        XCTAssertEqual(parsed.category, .terminology)
        XCTAssertEqual(parsed.original, String(target.dropLast()))
        XCTAssertEqual(parsed.replacement, "Data Pribadi")
        XCTAssertEqual(parsed.glossaryID, "G1")

        let review = try AIConnectorSuggestionValidator().validate(
            parsed,
            for: segment,
            glossaryMatches: [match],
            origin: .deterministic
        )
        XCTAssertEqual(review.glossaryMatch?.entry.term, "Data Pribadi")
    }

    func testDeterministicBaselinePassesAllBoundedFixtures() {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil,
            authority: .verified,
            isActionable: true
        )
        let fillerEntries = (0..<100).map { index in
            LegalDictionaryEntry(
                id: "baseline-filler-\(index)",
                term: "Baseline Filler \(index)",
                definition: "kata unik baseline filler \(index)",
                regulation: "",
                regulationTitle: "",
                sourceURL: nil
            )
        }
        let summary = AIConnectorFixtureEvaluator().runDeterministicBaseline(
            dictionaryStore: LegalDictionaryStore(entries: [entry] + fillerEntries)
        )

        XCTAssertEqual(summary.totalCount, AIConnectorSample.samples.count)
        let evaluationDetails = summary.evaluations.map { evaluation in
            "\(evaluation.sample.id)=\(evaluation.passed):\(evaluation.actualStatus?.rawValue ?? "nil")"
        }.joined(separator: " | ")
        XCTAssertEqual(summary.passedCount, summary.totalCount, evaluationDetails)
        XCTAssertEqual(summary.reviewMode, .deterministic)
    }

    func testDeterministicFallbackCanNormalizeUnchangedOutputToNoSuggestion() throws {
        let segment = makeSegment(
            target: "Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia."
        )
        let parsed = AIConnectorDeterministicSuggestionEngine().noSuggestion(for: segment)
        let review = try AIConnectorSuggestionValidator().validate(
            parsed,
            for: segment,
            glossaryMatches: [],
            origin: .deterministicFallback
        )

        XCTAssertEqual(review.status, .noSuggestion)
        XCTAssertEqual(review.category, .none)
        XCTAssertEqual(review.origin, .deterministicFallback)
    }

    func testMalformedNoSuggestionCanBeCanonicalizedSafely() throws {
        let segment = makeSegment(
            target: "Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia."
        )
        let malformedModelOutput = """
        STATUS: NO_SUGGESTION
        CATEGORY: NONE
        ORIGINAL: Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.
        REPLACEMENT: -
        GLOSSARY_ID: -
        REASON: Tidak ada perubahan yang diperlukan karena teks sudah jelas.
        """

        let parsedModelReview = try AIConnectorOutputParser().parse(malformedModelOutput)
        XCTAssertEqual(parsedModelReview.status, .noSuggestion)

        let canonicalReview = try AIConnectorSuggestionValidator().validate(
            AIConnectorDeterministicSuggestionEngine().noSuggestion(for: segment),
            for: segment,
            glossaryMatches: [],
            origin: .deterministicFallback
        )

        XCTAssertEqual(canonicalReview.status, .noSuggestion)
        XCTAssertNil(canonicalReview.original)
        XCTAssertNil(canonicalReview.replacement)
    }

    func testTerminologySuggestionMustUseCanonicalGlossaryTerm() throws {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 10,
            rank: 1,
            matchedDefinitionTokenCount: 4,
            isDirectTermMatch: false
        )
        let segment = makeSegment(target: entry.definition)
        let parsed = try AIConnectorOutputParser().parse("""
        STATUS: SUGGESTION
        CATEGORY: TERMINOLOGY
        ORIGINAL: \(entry.definition)
        REPLACEMENT: Data Pribadi
        GLOSSARY_ID: G1
        REASON: Istilah glossary lebih ringkas.
        """)

        let review = try AIConnectorSuggestionValidator().validate(
            parsed,
            for: segment,
            glossaryMatches: [match]
        )
        XCTAssertEqual(review.glossaryMatch?.entry.term, "Data Pribadi")
    }

    func testTerminologyReplacementCannotBypassProtectedContentForUnrelatedText() {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 10,
            rank: 1,
            matchedDefinitionTokenCount: 4,
            isDirectTermMatch: false
        )
        let segment = makeSegment(target: "Pihak Kedua wajib menyerahkan data.")
        let parsed = AIParsedReview(
            status: .suggestion,
            category: .terminology,
            original: "Pihak Kedua wajib",
            replacement: "Data Pribadi",
            glossaryID: "G1",
            reason: "Istilah glossary lebih ringkas."
        )

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsed,
                for: segment,
                glossaryMatches: [match]
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .protectedContentChanged)
        }
    }

    func testSuggestionCandidatesUseTargetText() {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil,
            authority: .verified,
            isActionable: true
        )
        let fillerEntries = (0..<100).map { index in
            LegalDictionaryEntry(
                id: "filler-\(index)",
                term: "Filler \(index)",
                definition: "kata unik filler \(index)",
                regulation: "",
                regulationTitle: "",
                sourceURL: nil
            )
        }
        let store = LegalDictionaryStore(entries: [entry] + fillerEntries)

        let matches = store.suggestionCandidates(
            for: "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi"
        )

        XCTAssertEqual(matches.first?.entry.term, "Data Pribadi")
    }

    func testSuggestionCandidatesRejectIrrelevantText() {
        let store = LegalDictionaryStore(entries: [
            LegalDictionaryEntry(
                id: "data-pribadi",
                term: "Data Pribadi",
                definition: "data tentang orang perseorangan yang teridentifikasi",
                regulation: "Undang-Undang Nomor 27 Tahun 2022",
                regulationTitle: "Pelindungan Data Pribadi",
                sourceURL: nil,
                authority: .verified,
                isActionable: true
            )
        ])

        XCTAssertTrue(store.suggestionCandidates(for: "Kopi dan teh disediakan di ruang rapat.").isEmpty)
    }

    func testBuiltInDummyDocumentCoversAdditionalCasesAndIsDocumentWide() {
        let content = AIConnectorDummyDocument.initialContent
        let segmentation = LegalTextSegmenter().segment(documentText: content)

        XCTAssertTrue(content.contains("PERJANJIAN KERJA SAMA"))
        XCTAssertTrue(content.contains("Pihak Pertama dan Pihak Kedua secara bersama-sama disebut"))
        XCTAssertTrue(content.contains("telah dibuat dan ditanda tangani"))
        XCTAssertTrue(content.contains("Pihak Kedua wajib untuk menyediakan Layanan"))
        XCTAssertTrue(content.contains("data tentang orang perseorangan yang teridentifikasi"))
        XCTAssertTrue(content.contains("kumpulan orang dan/atau kekayaan yang terorganisasi"))
        XCTAssertTrue(content.contains("Suatu keadaan yang terjadi di luar kehendak para pihak"))
        XCTAssertTrue(content.contains("kerjasama"))
        XCTAssertTrue(content.contains("bertanggungjawab"))
        XCTAssertTrue(content.contains("di simpan"))
        XCTAssertTrue(content.contains("Rp100.000.000 (seratus juta rupiah)"))
        XCTAssertTrue(content.contains("pajak pertambahan nilai sebesar 11%"))
        XCTAssertTrue(content.contains("Keadaan Kahar, kecuali"))
        XCTAssertTrue(content.contains("Borrower wajib mengirimkan quarterly report kepada Lender"))
        XCTAssertTrue(content.contains("Pihak Kedua tidak dapat mengalihkan hak dan kewajibannya"))
        XCTAssertGreaterThan(segmentation.segments.count, LegalTextSegmenter.batchSize)
        XCTAssertEqual(segmentation.queuedSegmentCount, segmentation.segments.count)
        XCTAssertEqual(segmentation.omittedSegmentCount, 0)
    }

    func testBuiltInDummyDocumentRetrievesActiveCorpusTermsOnly() {
        let store = LegalDictionaryStore()
        let segmentation = LegalTextSegmenter().segment(
            documentText: AIConnectorDummyDocument.initialContent
        )

        let retrievedTerms = Set(
            segmentation.segments.flatMap { segment in
                store.suggestionCandidates(for: segment.targetText).map { $0.entry.term }
            }
        )

        XCTAssertTrue(retrievedTerms.contains("Data Pribadi"))
        XCTAssertTrue(retrievedTerms.contains("Korporasi"))
        XCTAssertFalse(retrievedTerms.contains("Keadaan Kahar"))
    }

    func testGlossarySnapshotRetainsSegmentAndCandidateForRunHistory() {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 24.5,
            rank: 1,
            matchedDefinitionTokenCount: 5,
            isDirectTermMatch: false
        )
        let segment = makeSegment(
            target: "Data tentang orang perseorangan yang teridentifikasi.",
            id: 4
        )

        let snapshot = AIReviewGlossarySnapshot(segment: segment, matches: [match])

        XCTAssertEqual(snapshot.id, 4)
        XCTAssertEqual(snapshot.segment.targetText, segment.targetText)
        XCTAssertEqual(snapshot.matches.map(\.entry.term), ["Data Pribadi"])
    }

    func testUserFacingReviewLabelsDoNotExposeProtocolTokens() {
        XCTAssertEqual(AIReviewStatus.noSuggestion.displayTitle, "Tidak ada saran")
        XCTAssertEqual(AIReviewStatus.suggestion.displayTitle, "Saran bahasa")
        XCTAssertEqual(AIReviewCategory.grammar.displayTitle, "Tata bahasa")
        XCTAssertEqual(AIReviewOrigin.deterministicFallback.displayTitle, "Pemulihan deterministik")
        XCTAssertFalse(AIReviewStatus.noSuggestion.displayTitle.contains("NO_SUGGESTION"))
    }

    func testCannedOutputsForSevenFixturesPassSafetyContract() throws {
        let fixtures: [(String, String, AIReviewStatus)] = [
            (
                "Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.",
                """
                STATUS: SUGGESTION
                CATEGORY: GRAMMAR
                ORIGINAL: wajib untuk
                REPLACEMENT: wajib
                GLOSSARY_ID: -
                REASON: Bentuk kalimat lebih ringkas.
                """,
                .suggestion
            ),
            (
                "Perjanjian ini telah ditanda tangani oleh Para Pihak pada tanggal 10 Agustus 2026.",
                """
                STATUS: SUGGESTION
                CATEGORY: SPELLING
                ORIGINAL: ditanda tangani
                REPLACEMENT: ditandatangani
                GLOSSARY_ID: -
                REASON: Ejaan kata diperbaiki.
                """,
                .suggestion
            ),
            (
                "Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.",
                """
                STATUS: NO_SUGGESTION
                CATEGORY: NONE
                ORIGINAL: -
                REPLACEMENT: -
                GLOSSARY_ID: -
                REASON: Tidak ada masalah yang jelas.
                """,
                .noSuggestion
            ),
            (
                "Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua.",
                """
                STATUS: NEEDS_REVIEW
                CATEGORY: CLARITY
                ORIGINAL: dapat mengakhiri
                REPLACEMENT: -
                GLOSSARY_ID: -
                REASON: Perubahan dapat memengaruhi hak pengakhiran.
                """,
                .needsReview
            ),
            (
                "Pihak Kedua wajib menyampaikan pemberitahuan tertulis sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.",
                """
                STATUS: NO_SUGGESTION
                CATEGORY: NONE
                ORIGINAL: -
                REPLACEMENT: -
                GLOSSARY_ID: -
                REASON: Angka dan tenggat dipertahankan tanpa saran.
                """,
                .noSuggestion
            ),
            (
                "Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja.",
                """
                STATUS: NEEDS_REVIEW
                CATEGORY: TERMINOLOGY
                ORIGINAL: Borrower wajib memberikan notice tertulis kepada Lender
                REPLACEMENT: -
                GLOSSARY_ID: -
                REASON: Konsistensi istilah perlu review manusia.
                """,
                .needsReview
            ),
            (
                "Perusahaan wajib mematuhi seluruh peraturan yang berlaku.",
                """
                STATUS: NO_SUGGESTION
                CATEGORY: NONE
                ORIGINAL: -
                REPLACEMENT: -
                GLOSSARY_ID: -
                REASON: Tidak ada masalah ejaan yang jelas.
                """,
                .noSuggestion
            )
        ]

        for (index, fixture) in fixtures.enumerated() {
            let parsed = try AIConnectorOutputParser().parse(fixture.1)
            let review = try AIConnectorSuggestionValidator().validate(
                parsed,
                for: makeSegment(target: fixture.0, id: index + 1),
                glossaryMatches: []
            )
            XCTAssertEqual(review.status, fixture.2)
        }
    }

    private func makeSegment(target: String, id: Int = 1) -> AIReviewSegment {
        AIReviewSegment(
            id: id,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }
}
