import Foundation
import XCTest
@testable import AMT

/// Opt-in only: this test downloads/loads the selected pinned model and can
/// take several minutes. It exercises candidate-first tool decisions and all
/// three generation profiles. Normal unit-test runs skip it before touching MLX.
@MainActor
final class AIConnectorModelBenchmarkTests: XCTestCase {
    func testP011CandidateFirstSelectedModelBenchmark() async throws {
        guard environmentValue("AMT_RUN_P011_MODEL_BENCHMARK") == "1"
            || environmentValue("AMT_RUN_P09_MODEL_BENCHMARK") == "1" else {
            throw XCTSkip("Set TEST_RUNNER_AMT_RUN_P011_MODEL_BENCHMARK=1 to run the model benchmark.")
        }

        let reportPath = environmentValue("AMT_P011_REPORT_PATH")
            ?? environmentValue("AMT_P09_REPORT_PATH")
            ?? "/private/tmp/amt-p011-base-4b.json"
        guard reportPath.hasPrefix("/private/tmp/") else {
            throw XCTSkip("AMT_P011_REPORT_PATH must be under /private/tmp/.")
        }

        let service = QwenSuggestionService()
        let dictionaryStore = benchmarkDictionaryStore()
        let runner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: dictionaryStore
        )
        let model: AIConnectorModelVariant
        if let rawModelVariant = environmentValue("AMT_P011_MODEL_VARIANT")
            ?? environmentValue("AMT_P09_MODEL_VARIANT") {
            guard let selectedModel = AIConnectorModelVariant(rawValue: rawModelVariant) else {
                XCTFail("Unknown AMT_P011_MODEL_VARIANT: \(rawModelVariant)")
                return
            }
            model = selectedModel
        } else {
            model = .qwen35Base4B
        }

        let baseline = try await runner.run(
            mode: .deterministic,
            modelVariant: model,
            thinkingEnabled: false,
            progress: { _, _ in }
        )
        var profileReports: [AIConnectorBenchmarkReport] = []
        for profile in AIConnectorGenerationProfilePreset.allCases {
            let report = try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: false,
                resetCache: true,
                generationProfilePreset: profile,
                progress: { _, _ in }
            )
            profileReports.append(report)
        }

        let qwenOnly = profileReports[0]
        let bestProfileReport = profileReports.max { lhs, rhs in
            benchmarkScore(for: lhs) < benchmarkScore(for: rhs)
        } ?? qwenOnly
        let bestProfile = AIConnectorGenerationProfilePreset(
            rawValue: bestProfileReport.generationProfile
        ) ?? .greedy
        // Each profile has an independent cache key, but the profile matrix is
        // intentionally reset between runs. Populate the greedy cache again
        // before asserting that the following rerun is a cache hit.
        _ = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            resetCache: true,
            generationProfilePreset: .greedy,
            progress: { _, _ in }
        )
        let cachedQwenOnly = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            resetCache: false,
            generationProfilePreset: .greedy,
            progress: { _, _ in }
        )
        let hybrid = try await runner.run(
            mode: .hybrid,
            modelVariant: model,
            thinkingEnabled: false,
            generationProfilePreset: bestProfile,
            progress: { _, _ in }
        )

        var thinkingReport: AIConnectorBenchmarkReport?
        var thinkingError: String?
        do {
            thinkingReport = try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: true,
                samples: [AIConnectorSample.samples[0]],
                generationProfilePreset: bestProfile,
                progress: { _, _ in }
            )
        } catch {
            thinkingError = error.localizedDescription
        }

        var cancellationProgressCount = 0
        var cancellationPassed = false
        let cancellationTask = Task { @MainActor in
            try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: false,
                samples: AIConnectorSample.samples,
                generationProfilePreset: bestProfile,
                progress: { _, _ in
                    cancellationProgressCount += 1
                }
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            XCTFail("Cancelled benchmark unexpectedly completed.")
        } catch is CancellationError {
            // Expected: the runner must not start the next fixture.
            cancellationPassed = true
        } catch let error as QwenSuggestionError {
            XCTFail("Cancellation surfaced as a model error: \(error.localizedDescription)")
        }
        XCTAssertTrue(cancellationPassed)
        XCTAssertLessThanOrEqual(
            cancellationProgressCount,
            1,
            "Cancellation must not start a second fixture."
        )

        let envelope = AIConnectorP011BenchmarkEnvelope(
            generatedAt: Date(),
            modelID: model.modelID,
            revision: model.revision,
            baseline: baseline,
            qwenOnly: qwenOnly,
            cachedQwenOnly: cachedQwenOnly,
            hybrid: hybrid,
            thinking: thinkingReport,
            thinkingError: thinkingError,
            cancellationPassed: cancellationPassed,
            profileMatrix: profileReports,
            selectedProfile: bestProfile.rawValue
        )
        let data = try JSONEncoder.prettySorted.encode(envelope)
        try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)

        XCTAssertEqual(baseline.passedCount, baseline.totalCount)
        XCTAssertEqual(qwenOnly.records.count, AIConnectorSample.samples.count)
        XCTAssertTrue(cachedQwenOnly.records.allSatisfy(\.cacheHit))
        XCTAssertEqual(hybrid.records.count, AIConnectorSample.samples.count)
        XCTAssertEqual(profileReports.count, AIConnectorGenerationProfilePreset.allCases.count)
        XCTAssertTrue(profileReports.allSatisfy { report in
            !report.records.contains { $0.diagnosticOutput.orEmpty.contains("<think>") }
        })
    }

    /// Opt-in holdout matrix. These fixtures are intentionally separate from
    /// the eight quality-gate samples so profile behavior is observed rather
    /// than tuned against the gate itself.
    func testP011ExpandedCandidateMatrix() async throws {
        guard environmentValue("AMT_RUN_P011_EXPANDED_BENCHMARK") == "1" else {
            throw XCTSkip("Set TEST_RUNNER_AMT_RUN_P011_EXPANDED_BENCHMARK=1 to run the expanded model benchmark.")
        }

        let reportPath = environmentValue("AMT_P011_EXPANDED_REPORT_PATH")
            ?? "/private/tmp/amt-p011-expanded-base-4b.json"
        guard reportPath.hasPrefix("/private/tmp/") else {
            throw XCTSkip("AMT_P011_EXPANDED_REPORT_PATH must be under /private/tmp/.")
        }

        let model: AIConnectorModelVariant
        if let rawModelVariant = environmentValue("AMT_P011_MODEL_VARIANT") {
            guard let selectedModel = AIConnectorModelVariant(rawValue: rawModelVariant) else {
                XCTFail("Unknown AMT_P011_MODEL_VARIANT: \(rawModelVariant)")
                return
            }
            model = selectedModel
        } else {
            model = .qwen35Base4B
        }

        let fixtures = expandedFixtures()
        let samples = fixtures.map(\.sample)
        let service = QwenSuggestionService()
        let runner = AIConnectorBenchmarkRunner(
            service: service,
            dictionaryStore: benchmarkDictionaryStore()
        )

        let baseline = try await runner.run(
            mode: .deterministic,
            modelVariant: model,
            thinkingEnabled: false,
            samples: samples,
            progress: { _, _ in }
        )

        var profileReports: [AIConnectorBenchmarkReport] = []
        for profile in AIConnectorGenerationProfilePreset.allCases {
            profileReports.append(
                try await runner.run(
                    mode: .modelOnly,
                    modelVariant: model,
                    thinkingEnabled: false,
                    samples: samples,
                    resetCache: true,
                    generationProfilePreset: profile,
                    progress: { _, _ in }
                )
            )
        }

        let selectedProfile: AIConnectorGenerationProfilePreset = .greedy
        _ = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            samples: samples,
            resetCache: true,
            generationProfilePreset: selectedProfile,
            progress: { _, _ in }
        )
        let cached = try await runner.run(
            mode: .modelOnly,
            modelVariant: model,
            thinkingEnabled: false,
            samples: samples,
            resetCache: false,
            generationProfilePreset: selectedProfile,
            progress: { _, _ in }
        )
        let hybrid = try await runner.run(
            mode: .hybrid,
            modelVariant: model,
            thinkingEnabled: false,
            samples: samples,
            generationProfilePreset: selectedProfile,
            progress: { _, _ in }
        )

        let thinkingFixture = try XCTUnwrap(
            fixtures.first(where: { $0.sample.id == "expanded-terminology-data-exact" })
        )
        var thinkingReport: AIConnectorBenchmarkReport?
        var thinkingError: String?
        do {
            thinkingReport = try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: true,
                samples: [thinkingFixture.sample],
                generationProfilePreset: selectedProfile,
                progress: { _, _ in }
            )
        } catch {
            thinkingError = error.localizedDescription
        }

        var cancellationProgressCount = 0
        var cancellationPassed = false
        let cancellationTask = Task { @MainActor in
            try await runner.run(
                mode: .modelOnly,
                modelVariant: model,
                thinkingEnabled: false,
                samples: samples,
                generationProfilePreset: selectedProfile,
                progress: { _, _ in
                    cancellationProgressCount += 1
                }
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            XCTFail("Cancelled expanded benchmark unexpectedly completed.")
        } catch is CancellationError {
            cancellationPassed = true
        } catch let error as QwenSuggestionError {
            XCTFail("Expanded cancellation surfaced as a model error: \(error.localizedDescription)")
        }

        let envelope = AIConnectorP011ExpandedBenchmarkEnvelope(
            generatedAt: Date(),
            modelID: model.modelID,
            revision: model.revision,
            fixtureCount: fixtures.count,
            baseline: makeExpandedRunReport(
                baseline,
                fixtures: fixtures,
                requiresModelDecision: false
            ),
            profileMatrix: profileReports.map {
                makeExpandedRunReport(
                    $0,
                    fixtures: fixtures,
                    requiresModelDecision: true
                )
            },
            cached: makeExpandedRunReport(
                cached,
                fixtures: fixtures,
                requiresModelDecision: true
            ),
            hybrid: makeExpandedRunReport(
                hybrid,
                fixtures: fixtures,
                requiresModelDecision: true
            ),
            thinking: thinkingReport.map {
                makeExpandedRunReport(
                    $0,
                    fixtures: [thinkingFixture],
                    requiresModelDecision: true
                )
            },
            thinkingError: thinkingError,
            cancellationPassed: cancellationPassed,
            cancellationProgressCount: cancellationProgressCount,
            selectedProfile: selectedProfile.rawValue
        )
        let data = try JSONEncoder.prettySorted.encode(envelope)
        try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)

        XCTAssertEqual(baseline.records.count, fixtures.count)
        XCTAssertGreaterThanOrEqual(baseline.candidateRecords.count, 10)
        XCTAssertEqual(profileReports.count, AIConnectorGenerationProfilePreset.allCases.count)
        XCTAssertTrue(cached.records.filter { !$0.skipped }.allSatisfy(\.cacheHit))
        XCTAssertTrue(cancellationPassed)
        XCTAssertLessThanOrEqual(cancellationProgressCount, 1)
    }

    private func benchmarkDictionaryStore() -> LegalDictionaryStore {
        let verifiedEntries = [
            LegalDictionaryEntry(
                id: "p011-data-pribadi",
                term: "Data Pribadi",
                definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
                regulation: "Undang-Undang Nomor 27 Tahun 2022",
                regulationTitle: "Pelindungan Data Pribadi",
                sourceURL: nil,
                authority: .verified
            ),
            LegalDictionaryEntry(
                id: "p011-korporasi",
                term: "Korporasi",
                definition: "Korporasi adalah kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum.",
                regulation: "Undang-Undang Nomor 1 Tahun 2023",
                regulationTitle: "Kitab Undang-Undang Hukum Pidana",
                sourceURL: nil,
                authority: .verified
            ),
            LegalDictionaryEntry(
                id: "p011-keadaan-kahar",
                term: "Keadaan Kahar",
                definition: "Keadaan Kahar adalah suatu keadaan yang terjadi di luar kehendak para pihak dalam Kontrak dan tidak dapat diperkirakan sebelumnya, sehingga kewajiban yang ditentukan dalam Kontrak menjadi tidak dapat dipenuhi.",
                regulation: "P011 Test Corpus",
                regulationTitle: "Verified synthetic fixture",
                sourceURL: nil,
                authority: .verified
            )
        ]

        // The production BM25 threshold is calibrated against a real-sized
        // corpus. Keep this benchmark fixture representative without making
        // the production corpus or its authority metadata less conservative.
        let fillers = (0..<100).map { index in
            LegalDictionaryEntry(
                id: "p011-filler-\(index)",
                term: "P011 Filler \(index)",
                definition: "token unik p011 filler \(index)",
                regulation: "",
                regulationTitle: "",
                sourceURL: nil,
                authority: .legacy
            )
        }
        return LegalDictionaryStore(entries: verifiedEntries + fillers)
    }

    private func benchmarkScore(for report: AIConnectorBenchmarkReport) -> Int {
        let gate = report.qualityGate
        let modelOriginCount = report.candidateRecords.filter {
            $0.finalOrigin == .qwen || $0.finalOrigin == .qwenRepaired
        }.count
        return gate.exactExpectationPassCount * 100
            + modelOriginCount * 10
            - gate.truncatedCount * 1_000
            - gate.repetitionCount * 1_000
            - gate.reasoningLeakCount * 1_000
    }

    private func expandedFixtures() -> [AIConnectorP011ExpandedFixture] {
        let dataDefinition = "data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik"
        let korporasiDefinition = "kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum"
        let keadaanKaharDefinition = "suatu keadaan yang terjadi di luar kehendak para pihak dalam Kontrak dan tidak dapat diperkirakan sebelumnya, sehingga kewajiban yang ditentukan dalam Kontrak menjadi tidak dapat dipenuhi"
        let dataDefinitionCapitalized = String(dataDefinition.prefix(1)).uppercased() + String(dataDefinition.dropFirst())
        let longClause = "Pihak Kedua wajib untuk melaksanakan kewajiban administratif berikut: "
            + Array(repeating: "dokumen pendukung harus tersedia untuk pemeriksaan dan pencatatan internal", count: 90)
                .joined(separator: ", ")
            + "."

        return [
            expandedFixture(
                id: "expanded-grammar-basic",
                title: "Grammar: wajib untuk dalam kewajiban",
                text: "Pihak Kedua wajib untuk menyerahkan laporan bulanan kepada Pihak Pertama.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Menerima penghapusan kata yang berlebih."
            ),
            expandedFixture(
                id: "expanded-grammar-negation",
                title: "Grammar: negasi dipertahankan",
                text: "Pihak Pertama tidak wajib untuk membayar biaya tambahan.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Menerima koreksi lokal tanpa mengubah tidak."
            ),
            expandedFixture(
                id: "expanded-grammar-condition",
                title: "Grammar: kondisi dan pengecualian",
                text: "Apabila diperlukan, Para Pihak wajib untuk melakukan klarifikasi tertulis sebelum pembayaran.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Menerima koreksi lokal dalam kalimat bersyarat."
            ),
            expandedFixture(
                id: "expanded-grammar-deadline",
                title: "Grammar: modalitas dan tenggat",
                text: "Pihak Kedua wajib untuk menyampaikan pemberitahuan paling lambat 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Menerima koreksi dengan angka dan tenggat tetap."
            ),
            expandedFixture(
                id: "expanded-spelling-ditanda-basic",
                title: "Ejaan: ditanda tangani",
                text: "Perjanjian ini telah ditanda tangani oleh Para Pihak.",
                expected: [expectedCandidate("ditanda tangani", "ditandatangani", .spelling)],
                signal: "Menerima ejaan baku."
            ),
            expandedFixture(
                id: "expanded-spelling-ditanda-defined-term",
                title: "Ejaan: defined term tidak berubah",
                text: "Perubahan ini ditanda tangani oleh Para Pihak setelah persetujuan tertulis.",
                expected: [expectedCandidate("ditanda tangani", "ditandatangani", .spelling)],
                signal: "Menerima ejaan tanpa mengubah Para Pihak."
            ),
            expandedFixture(
                id: "expanded-spelling-ditanda-unicode",
                title: "Ejaan: punctuation dan Unicode",
                text: "Perjanjian ini telah ditanda tangani oleh “Para Pihak”—pada tanggal 10 Agustus 2026.",
                expected: [expectedCandidate("ditanda tangani", "ditandatangani", .spelling)],
                signal: "Menerima ejaan dengan tanda kutip dan dash."
            ),
            expandedFixture(
                id: "expanded-spelling-di-simpan-basic",
                title: "Ejaan: di simpan",
                text: "Dokumen pendukung harus di simpan oleh Pihak Kedua selama 5 (lima) tahun.",
                expected: [expectedCandidate("di simpan", "disimpan", .spelling)],
                signal: "Menerima koreksi imbuhan."
            ),
            expandedFixture(
                id: "expanded-spelling-di-simpan-identifier",
                title: "Ejaan: identifier dan modalitas",
                text: "Catatan elektronik di simpan secara aman oleh Pihak Pertama dan hanya dapat diakses oleh Pihak Kedua.",
                expected: [expectedCandidate("di simpan", "disimpan", .spelling)],
                signal: "Menerima koreksi tanpa mengubah hak akses."
            ),
            expandedFixture(
                id: "expanded-multi-two",
                title: "Multi-candidate: dua koreksi lokal",
                text: "Dokumen di simpan dan ditanda tangani oleh Pihak Kedua.",
                expected: [
                    expectedCandidate("ditanda tangani", "ditandatangani", .spelling),
                    expectedCandidate("di simpan", "disimpan", .spelling)
                ],
                signal: "Menghasilkan dua kandidat non-overlap."
            ),
            expandedFixture(
                id: "expanded-multi-three",
                title: "Multi-candidate: tiga koreksi lokal",
                text: "Pihak Kedua wajib untuk memastikan dokumen di simpan dan ditanda tangani sebelum diserahkan.",
                expected: [
                    expectedCandidate("wajib untuk", "wajib", .grammar),
                    expectedCandidate("ditanda tangani", "ditandatangani", .spelling),
                    expectedCandidate("di simpan", "disimpan", .spelling)
                ],
                signal: "Menghasilkan maksimal tiga kandidat non-overlap."
            ),
            expandedFixture(
                id: "expanded-terminology-data-exact",
                title: "Terminologi: Data Pribadi exact definition",
                text: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
                expected: [expectedCandidate(dataDefinitionCapitalized, "Data Pribadi", .terminology)],
                signal: "Menilai istilah canonical dari glossary verified."
            ),
            expandedFixture(
                id: "expanded-terminology-data-embedded",
                title: "Terminologi: Data Pribadi embedded",
                text: "Pihak Kedua memproses data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik untuk pelaksanaan Layanan.",
                expected: [expectedCandidate(dataDefinition, "Data Pribadi", .terminology)],
                signal: "Menilai istilah dalam konteks klausa layanan."
            ),
            expandedFixture(
                id: "expanded-terminology-korporasi",
                title: "Terminologi: Korporasi",
                text: "Dalam pemeriksaan ini, kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum menjadi subjek pemeriksaan.",
                expected: [expectedCandidate(korporasiDefinition, "Korporasi", .terminology)],
                signal: "Menilai istilah Korporasi dari glossary verified."
            ),
            expandedFixture(
                id: "expanded-terminology-keadaan-kahar",
                title: "Terminologi: Keadaan Kahar",
                text: "Keterlambatan yang disebabkan oleh suatu keadaan yang terjadi di luar kehendak para pihak dalam Kontrak dan tidak dapat diperkirakan sebelumnya, sehingga kewajiban yang ditentukan dalam Kontrak menjadi tidak dapat dipenuhi harus segera dilaporkan.",
                expected: [expectedCandidate(keadaanKaharDefinition, "Keadaan Kahar", .terminology)],
                signal: "Menilai istilah keadaan kahar tanpa sumber dari model."
            ),
            expandedFixture(
                id: "expanded-negative-correct-forms",
                title: "Negative control: bentuk sudah baku",
                text: "Pihak Kedua wajib menyerahkan laporan dan dokumen disimpan oleh Pihak Pertama.",
                expected: [],
                signal: "Tidak membuat saran pada bentuk yang sudah benar."
            ),
            expandedFixture(
                id: "expanded-negative-duplicate-rule",
                title: "Negative control: frasa berulang ambigu",
                text: "Pihak Kedua wajib untuk memenuhi kewajiban dan wajib untuk memberikan laporan.",
                expected: [],
                signal: "Tidak memilih replacement ketika rule muncul lebih dari sekali."
            ),
            expandedFixture(
                id: "expanded-negative-defined-terms",
                title: "Negative control: defined terms",
                text: "Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja.",
                expected: [],
                signal: "Tidak menerjemahkan Borrower, notice, atau Lender."
            ),
            expandedFixture(
                id: "expanded-safety-number-deadline",
                title: "Safety: angka dan tenggat",
                text: "Pihak Kedua wajib untuk menyampaikan pemberitahuan sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Koreksi lokal dengan angka-terbilang dan deadline utuh."
            ),
            expandedFixture(
                id: "expanded-safety-currency",
                title: "Safety: mata uang dan kondisi",
                text: "Pihak Pertama wajib untuk membayar denda sebesar Rp100.000.000 (seratus juta rupiah) apabila terjadi pelanggaran material.",
                expected: [expectedCandidate("wajib untuk", "wajib", .grammar)],
                signal: "Koreksi lokal dengan nominal dan kondisi utuh."
            ),
            expandedFixture(
                id: "expanded-safety-conditional-spelling",
                title: "Safety: kondisi dan ejaan",
                text: "Apabila Dokumen di simpan oleh Pihak Kedua, akses harus dibatasi sesuai dengan Perjanjian.",
                expected: [expectedCandidate("di simpan", "disimpan", .spelling)],
                signal: "Koreksi ejaan tanpa mengubah kondisi akses."
            ),
            expandedFixture(
                id: "expanded-negative-source-claim",
                title: "Negative control: tanpa sumber",
                text: "Perusahaan wajib mematuhi seluruh peraturan yang berlaku dalam melaksanakan kewajibannya.",
                expected: [],
                signal: "Tidak membuat kutipan atau sumber hukum."
            ),
            expandedFixture(
                id: "expanded-too-long",
                title: "Boundary: segmen lebih dari 512 token",
                text: longClause,
                expected: [],
                signal: "Segmen terlalu panjang dilewati tanpa memanggil model."
            )
        ]
    }

    private func expandedFixture(
        id: String,
        title: String,
        text: String,
        expected: [AIConnectorP011ExpectedCandidate],
        signal: String
    ) -> AIConnectorP011ExpandedFixture {
        AIConnectorP011ExpandedFixture(
            sample: AIConnectorSample(
                id: id,
                title: title,
                text: text,
                expectedSignal: signal
            ),
            expectedCandidates: expected
        )
    }

    private func expectedCandidate(
        _ original: String,
        _ replacement: String,
        _ category: AIReviewCategory
    ) -> AIConnectorP011ExpectedCandidate {
        AIConnectorP011ExpectedCandidate(
            original: original,
            replacement: replacement,
            category: category
        )
    }

    private func makeExpandedRunReport(
        _ report: AIConnectorBenchmarkReport,
        fixtures: [AIConnectorP011ExpandedFixture],
        requiresModelDecision: Bool
    ) -> AIConnectorP011ExpandedRunReport {
        let fixtureReports = fixtures.map { fixture in
            let candidates = report.candidateRecords.filter {
                $0.sampleID == fixture.sample.id
            }
            let sampleRecord = report.records.first {
                $0.sampleID == fixture.sample.id
            }
            let expectedPass = expandedExpectationPassed(
                fixture: fixture,
                candidates: candidates,
                sampleRecord: sampleRecord,
                reviewMode: report.reviewMode,
                requiresModelDecision: requiresModelDecision
            )

            return AIConnectorP011ExpandedFixtureReport(
                sampleID: fixture.sample.id,
                title: fixture.sample.title,
                expectedCandidates: fixture.expectedCandidates.map {
                    AIConnectorP011ExpectedCandidateReport(
                        original: $0.original,
                        replacement: $0.replacement,
                        category: $0.category.rawValue
                    )
                },
                actualStatus: sampleRecord?.validatedStatus,
                skipped: sampleRecord?.skipped ?? false,
                expectedPass: expectedPass,
                candidates: candidates.map {
                    AIConnectorP011ActualCandidateReport(
                        candidateID: $0.candidateID,
                        category: $0.category.rawValue,
                        original: $0.original,
                        replacement: $0.replacement,
                        source: $0.source.rawValue,
                        decision: $0.decision?.rawValue,
                        finalOrigin: $0.finalOrigin?.rawValue,
                        attemptCount: $0.attemptCount,
                        repairAttempted: $0.repairAttempted,
                        challengeAttempted: $0.challengeAttempted,
                        usedFallback: $0.usedFallback,
                        rejectionClass: $0.rejectionClass,
                        stopReason: $0.stopReason?.rawValue,
                        promptTokenCount: $0.promptTokenCount,
                        generationTokenCount: $0.generationTokenCount,
                        repeatedSixGramRatio: $0.repeatedSixGramRatio
                    )
                }
            )
        }

        return AIConnectorP011ExpandedRunReport(
            mode: report.reviewMode.rawValue,
            profile: report.generationProfile,
            thinkingEnabled: report.thinkingEnabled,
            duration: report.duration,
            fixtureCount: fixtures.count,
            candidateCount: report.candidateRecords.count,
            modelCallCount: report.candidateRecords.reduce(0) {
                $0 + $1.attemptCount
            },
            qwenOriginCount: report.candidateRecords.filter {
                $0.finalOrigin == .qwen || $0.finalOrigin == .qwenRepaired
            }.count,
            fallbackCount: report.candidateRecords.filter(\.usedFallback).count,
            repairCount: report.candidateRecords.filter(\.repairAttempted).count,
            challengeCount: report.candidateRecords.filter(\.challengeAttempted).count,
            cacheHitCount: report.records.filter(\.cacheHit).count,
            expectedPassCount: fixtureReports.filter(\.expectedPass).count,
            expectedTotalCount: fixtureReports.count,
            internalGate: report.qualityGate,
            fixtures: fixtureReports
        )
    }

    private func expandedExpectationPassed(
        fixture: AIConnectorP011ExpandedFixture,
        candidates: [AIConnectorBenchmarkCandidateRecord],
        sampleRecord: AIConnectorBenchmarkRecord?,
        reviewMode: AIConnectorReviewMode,
        requiresModelDecision: Bool
    ) -> Bool {
        guard !fixture.expectedCandidates.isEmpty else {
            return candidates.isEmpty
                && (sampleRecord?.validatedStatus == AIReviewStatus.noSuggestion.rawValue
                    || sampleRecord?.validatedStatus == AIReviewStatus.needsReview.rawValue
                    || sampleRecord?.skipped == true)
        }

        guard candidates.count == fixture.expectedCandidates.count else {
            return false
        }

        return fixture.expectedCandidates.allSatisfy { expected in
            guard let actual = candidates.first(where: {
                $0.original == expected.original
                    && $0.replacement == expected.replacement
                    && $0.category == expected.category
            }) else {
                return false
            }

            guard requiresModelDecision else { return true }
            if actual.decision == AIConnectorCandidateDecision.accept {
                return true
            }

            // Hybrid may retain a proven spelling/grammar correction after an
            // explicit model failure, but terminology still requires ACCEPT.
            return reviewMode == .hybrid
                && actual.usedFallback
                && expected.category != .terminology
        }
    }

    private func environmentValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }
}

private struct AIConnectorP011BenchmarkEnvelope: Codable {
    let generatedAt: Date
    let modelID: String
    let revision: String
    let baseline: AIConnectorBenchmarkReport
    let qwenOnly: AIConnectorBenchmarkReport
    let cachedQwenOnly: AIConnectorBenchmarkReport
    let hybrid: AIConnectorBenchmarkReport
    let thinking: AIConnectorBenchmarkReport?
    let thinkingError: String?
    let cancellationPassed: Bool
    let profileMatrix: [AIConnectorBenchmarkReport]
    let selectedProfile: String
}

private struct AIConnectorP011ExpandedFixture {
    let sample: AIConnectorSample
    let expectedCandidates: [AIConnectorP011ExpectedCandidate]
}

private struct AIConnectorP011ExpectedCandidate {
    let original: String
    let replacement: String
    let category: AIReviewCategory
}

private struct AIConnectorP011ExpandedBenchmarkEnvelope: Codable {
    let generatedAt: Date
    let modelID: String
    let revision: String
    let fixtureCount: Int
    let baseline: AIConnectorP011ExpandedRunReport
    let profileMatrix: [AIConnectorP011ExpandedRunReport]
    let cached: AIConnectorP011ExpandedRunReport
    let hybrid: AIConnectorP011ExpandedRunReport
    let thinking: AIConnectorP011ExpandedRunReport?
    let thinkingError: String?
    let cancellationPassed: Bool
    let cancellationProgressCount: Int
    let selectedProfile: String
}

private struct AIConnectorP011ExpandedRunReport: Codable {
    let mode: String
    let profile: String
    let thinkingEnabled: Bool
    let duration: TimeInterval
    let fixtureCount: Int
    let candidateCount: Int
    let modelCallCount: Int
    let qwenOriginCount: Int
    let fallbackCount: Int
    let repairCount: Int
    let challengeCount: Int
    let cacheHitCount: Int
    let expectedPassCount: Int
    let expectedTotalCount: Int
    let internalGate: AIConnectorQualityGate
    let fixtures: [AIConnectorP011ExpandedFixtureReport]
}

private struct AIConnectorP011ExpandedFixtureReport: Codable {
    let sampleID: String
    let title: String
    let expectedCandidates: [AIConnectorP011ExpectedCandidateReport]
    let actualStatus: String?
    let skipped: Bool
    let expectedPass: Bool
    let candidates: [AIConnectorP011ActualCandidateReport]
}

private struct AIConnectorP011ExpectedCandidateReport: Codable {
    let original: String
    let replacement: String
    let category: String
}

private struct AIConnectorP011ActualCandidateReport: Codable {
    let candidateID: String
    let category: String
    let original: String
    let replacement: String
    let source: String
    let decision: String?
    let finalOrigin: String?
    let attemptCount: Int
    let repairAttempted: Bool
    let challengeAttempted: Bool
    let usedFallback: Bool
    let rejectionClass: AIConnectorRejectionClass?
    let stopReason: String?
    let promptTokenCount: Int?
    let generationTokenCount: Int?
    let repeatedSixGramRatio: Double?
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
