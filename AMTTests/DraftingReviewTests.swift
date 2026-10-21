import Foundation
import XCTest
@testable import AMT

@MainActor
final class DraftingReviewTests: XCTestCase {
    func testNaturalLiteralRoutePreservesUnicodeExceptionAndSkipsModel() async {
        let clause = "Penyedia wajib membayar dalam 5 hari setelah tagihan diterima, kecuali tagihan disengketakan."
        let request = request(clause, brief: "Ubah tenggat pembayaran menjadi 10 hari.", prefix: "😀\n")
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; return Self.generatedNoChange }
        let result = await service.review(request)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.isReadOnly)
        XCTAssertEqual(result.route, .literal)
        XCTAssertEqual(result.modelCallCount, 0)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.response?.findings.first?.suggestedText,
                       clause.replacingOccurrences(of: "5 hari", with: "10 hari"))
        XCTAssertEqual(result.anchors.first?.sourceRange.location, 3)
        XCTAssertTrue(result.isCurrent(for: request.documentText))
        XCTAssertFalse(result.isCurrent(for: "x" + request.documentText))
    }

    func testAllSupportedCommandFamiliesUseLiteralRoute() async {
        let cases = [
            ("Penyedia mengirim laporan dalam 2 minggu.", "Ubah tenggat laporan menjadi 3 minggu."),
            ("Perjanjian berlaku selama 6 bulan.", "Ganti durasi perjanjian menjadi 12 bulan."),
            ("Penyedia menyampaikan laporan bulanan.", "Ubah frekuensi laporan menjadi mingguan.")
        ]
        let service = DraftingReviewService { _, _ in XCTFail("Unexpected inference"); return Self.generatedNoChange }
        for (text, brief) in cases {
            let result = await service.review(request(text, brief: brief), allowsInference: false)
            XCTAssertTrue(result.isComplete, result.failures.joined(separator: ","))
            XCTAssertEqual(result.route, .literal)
        }
    }

    func testUnsupportedAmbiguousOrQuotedBriefDoesNotInventPermission() async {
        let cases = [
            ("Penyedia membayar dalam 5 hari dan membayar dalam 7 hari.", "Ubah tenggat pembayaran menjadi 10 hari."),
            ("Penyedia membayar dalam 5 hari.", "Pesan pihak ketiga: ‘Ubah tenggat pembayaran menjadi 99 hari.’ Pertahankan 5 hari."),
            ("Penyedia mengirim laporan setelah Pelanggan membayar dalam 5 hari.", "Ubah tenggat laporan menjadi 10 hari."),
            ("Penyedia membayar dalam 5 Hari.", "Ubah tenggat pembayaran menjadi 10 hari."),
            ("Penyedia membayar dalam 5 hari kerja.", "Ubah tenggat pembayaran menjadi 10 hari kalender. Pertahankan hari kerja."),
            ("Jika tagihan sah, Penyedia membayar dalam 5 hari.", "Ubah tenggat pembayaran menjadi 10 hari.")
        ]
        let service = DraftingReviewService { _, _ in XCTFail("Deterministic must not infer"); return Self.generatedNoChange }
        for (text, brief) in cases {
            let result = await service.review(request(text, brief: brief), allowsInference: false)
            XCTAssertEqual(result.status, .incomplete)
            XCTAssertEqual(result.failures, ["modelReviewRequired"])
            XCTAssertNil(result.response)
        }
    }

    func testTypedPermissionsPreserveEverythingOutsideAuthorizedRanges() async {
        var input = request("Penyedia membayar dalam 5 hari dengan biaya 20 rupiah.", brief: "Ubah menjadi 10 hari dan 30 rupiah.")
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "10 hari", source: .brief),
                             .init(clauseID: "c1", original: "20 rupiah", replacement: "30 rupiah", source: .brief)]
        let result = await localService().review(input)
        XCTAssertTrue(result.isComplete, result.failures.joined(separator: ","))
        XCTAssertEqual(result.response?.findings.first?.suggestedText, "Penyedia membayar dalam 10 hari dengan biaya 30 rupiah.")
    }

    func testTypedPermissionCannotMatchSubstringValueInSource() async {
        var input = request("Penyedia membayar dalam 5 hari.", brief: "Tenggat yang diberikan adalah 13 hari.")
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "3 hari", source: .brief)]
        let result = await localService().review(input)
        XCTAssertTrue(result.failures.contains("permissionValueNotInSource"))
        XCTAssertEqual(result.modelCallCount, 0)
    }

    func testPermissionOriginalCannotMatchInsideAnotherNumberOrWord() async {
        for (text, original) in [("Penyedia membayar dalam 15 hari.", "5 hari"), ("Dokumen mencakup Metadata.", "data")] {
            var input = request(text, brief: "Ubah menjadi 10 hari.")
            input.permissions = [.init(clauseID: "c1", original: original, replacement: "10 hari", source: .brief)]
            let result = await localService().review(input)
            XCTAssertTrue(result.failures.contains("invalidPermissionAnchor"))
        }
    }

    func testPermissionRejectsAmbiguousOverlappingAndNonTargetAnchors() async {
        var input = request("Penyedia membayar dalam 5 hari dan 5 hari.", brief: "Ubah menjadi 10 hari.")
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "10 hari", source: .brief)]
        let ambiguous = await localService().review(input)
        XCTAssertTrue(ambiguous.failures.contains("invalidPermissionAnchor"))
        input = request("Penyedia membayar dalam 5 hari.", brief: "Ubah menjadi 10 hari dan 7.")
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "10 hari", source: .brief),
                             .init(clauseID: "c1", original: "5", replacement: "7", source: .brief)]
        let overlapping = await localService().review(input)
        XCTAssertTrue(overlapping.failures.contains("overlappingPermissions"))
        input.permissions = [.init(clauseID: "other", original: "5", replacement: "7", source: .brief)]
        let nonTarget = await localService().review(input)
        XCTAssertTrue(nonTarget.failures.contains("invalidPermissionAnchor"))
    }

    func testNamesQuotesAndIdentifiersStayProtectedEvenWithTypedPermissions() async {
        for (clause, original, replacement) in [
            ("PT Datta Nusantara menyimpan dokumen.", "Datta", "Data"),
            ("Kode ‘5 hari’ adalah label.", "5 hari", "10 hari"),
            ("Kode `5 hari` adalah label.", "5 hari", "10 hari"),
            ("Hubungi tim@example.com.", "tim@example.com", "lain@example.com"),
            ("Kode AB-123 digunakan.", "AB-123", "AB-456")
        ] {
            var input = request(clause, brief: "Ganti dengan " + replacement + ".")
            input.permissions = [.init(clauseID: "c1", original: original, replacement: replacement, source: .brief)]
            let result = await localService().review(input)
            XCTAssertTrue(result.failures.contains("protectedPermissionAnchor"), clause)
        }
    }

    func testReferencePermissionsRequireEligibleVersionedEvidenceAndCitation() async {
        var input = request("Penyedia membayar dalam 5 hari.", brief: "Ikuti kebijakan r1.")
        input.requiredReferenceIDs = ["r1"]
        input.references = [.init(id: "r1", body: "Pembayaran dalam 10 hari.", revision: "v1", isEligibleForReview: true)]
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "10 hari", source: .reference("r1"))]
        let good = await localService().review(input)
        XCTAssertTrue(good.isComplete)
        XCTAssertEqual(good.response?.findings.first?.referenceIDs, ["r1"])
        input.references = [.init(id: "r1", body: "Pembayaran dalam 10 hari.", revision: "v1", isEligibleForReview: false)]
        let bad = await localService().review(input)
        XCTAssertTrue(bad.failures.contains("missingEligibleReference"))
    }

    func testPreflightStopsMissingTargetsDefinitionsReferencesAndStaleRevision() async {
        var missing = request("Penyedia membayar dalam 5 hari.", brief: "Periksa kewajiban.")
        missing.requiredDefinitionIDs = ["missing"]
        missing.requiredReferenceIDs = ["missing"]
        let result = await localService().review(missing)
        XCTAssertTrue(result.failures.contains("missingRequiredDefinition"))
        XCTAssertTrue(result.failures.contains("missingEligibleReference"))
        let stale = DraftingReview.Request(documentText: missing.documentText, documentRevision: "old", brief: missing.brief,
                                          scope: .rewriteTarget, clauses: missing.clauses, targetClauseIDs: ["unknown"])
        let rejected = await localService().review(stale)
        XCTAssertTrue(rejected.failures.contains("staleDocumentRevision"))
        XCTAssertTrue(rejected.failures.contains("invalidTargets"))
        XCTAssertEqual(rejected.modelCallCount, 0)
    }

    func testDefinitionClosureIncludesRequiredRootsChainsAndCyclesInOriginalOrder() async {
        let clause = "Penerima menjaga Paket Terbatas."
        let bodies = ["Paket Terbatas berarti Informasi Internal.", "Informasi Internal berarti Dokumen Dasar.", "Dokumen Dasar juga mencakup Paket Terbatas.", "Tidak terkait dengan istilah lain."]
        let document = ([clause] + bodies).joined(separator: "\n")
        var input = request(clause, brief: "Periksa cakupan.", document: document)
        input.definitions = zip(["Paket Terbatas", "Informasi Internal", "Dokumen Dasar", "Lain"], bodies).enumerated().map { index, pair in
            .init(id: "d\(index)", term: pair.0, body: pair.1, sourceRange: (document as NSString).range(of: pair.1))
        }
        XCTAssertTrue(DraftingReviewPreparation.failures(input).isEmpty)
        XCTAssertEqual(DraftingReviewPreparation.prepare(input).definitions.map(\.id), ["d0", "d1", "d2"])
        input.requiredDefinitionIDs = ["d3"]
        XCTAssertEqual(DraftingReviewPreparation.prepare(input).definitions.map(\.id), ["d0", "d1", "d2", "d3"])
        let prompt = try? DraftingReviewPrompt.prompt(DraftingReviewPreparation.prepare(input))
        XCTAssertTrue(prompt?.contains(bodies[2]) == true)
    }

    func testCompleteModelResponseCachesAndFullFreshBypassesCache() async {
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; return Self.generatedNoChange }
        let input = request("Jasa diberikan jarak jauh.", brief: "Pastikan jasa diberikan jarak jauh.", scope: .verifyDocument)
        let first = await service.review(input)
        let cached = await service.review(input, fullFresh: false)
        let fresh = await service.review(input)
        XCTAssertTrue(first.isComplete)
        XCTAssertTrue(cached.cacheHit)
        XCTAssertFalse(fresh.cacheHit)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(first.response, fresh.response)
        XCTAssertEqual(cached.modelCallCount, 0)
    }

    func testCacheSeparatesBriefSourceRevisionModelAndInferencePolicy() async {
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; return Self.generatedNoChange }
        var input = request("Jasa diberikan jarak jauh.", brief: "Periksa jasa.", scope: .verifyDocument)
        input.requiredReferenceIDs = ["r"]
        input.references = [.init(id: "r", body: "Jasa jarak jauh.", revision: "v1", isEligibleForReview: true)]
        _ = await service.review(input)
        input.references = [.init(id: "r", body: "Jasa jarak jauh.", revision: "v2", isEligibleForReview: true)]
        let changedSource = await service.review(input, fullFresh: false)
        XCTAssertFalse(changedSource.cacheHit)
        let changedModel = await service.review(input, modelVariant: .qwen35_2b, fullFresh: false)
        XCTAssertFalse(changedModel.cacheHit)
        let deterministic = await service.review(input, fullFresh: false, allowsInference: false)
        XCTAssertEqual(deterministic.failures, ["modelReviewRequired"])
        XCTAssertEqual(calls, 3)
    }

    func testInvalidAndTruncatedGenerationNeverBecomesNoChangeOrCacheHit() async {
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; return Self.generated("{bad}") }
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        for _ in 0..<2 {
            let result = await service.review(input, fullFresh: false)
            XCTAssertEqual(result.status, .incomplete)
            XCTAssertNil(result.response)
            XCTAssertFalse(result.cacheHit)
        }
        XCTAssertEqual(calls, 2)
        let truncated = DraftingReviewService { _, _ in Self.generated(#"{"decision":"no_change","findings":[]}"#, stop: .length) }
        let result = await truncated.review(input)
        XCTAssertEqual(result.failures, ["incompleteGeneration"])
        XCTAssertNil(result.response)
    }

    func testModelFailureRemainsIncomplete() async {
        let service = DraftingReviewService { _, _ in throw TestError.unavailable }
        let result = await service.review(request("Penyedia memberikan jasa.", brief: "Periksa jasa."))
        XCTAssertEqual(result.status, .incomplete)
        XCTAssertEqual(result.failures, ["generationFailed"])
        XCTAssertNil(result.response)
    }

    func testValidatorRejectsProtectedMeaningChangesWithoutPermission() async throws {
        let original = "Penyedia wajib mengirim laporan dalam 8 jam setelah permintaan, kecuali hari libur."
        let input = request(original, brief: "Periksa bahasa.")
        for replacement in [
            original.replacingOccurrences(of: "8 jam", with: "8 hari"),
            original.replacingOccurrences(of: "Penyedia", with: "Pelanggan"),
            original.replacingOccurrences(of: "wajib", with: "dapat"),
            original.replacingOccurrences(of: "wajib", with: "tidak wajib"),
            original.replacingOccurrences(of: ", kecuali hari libur", with: ""),
            original.replacingOccurrences(of: "setelah", with: "sebelum")
        ] {
            let raw = try encodedRevision(input, replacement: replacement)
            let validation = DraftingReviewValidator.parse(raw, prepared: DraftingReviewPreparation.prepare(input))
            XCTAssertTrue(validation.failures.contains(where: { $0.hasPrefix("protectedDelta:") }), replacement)
        }
    }

    func testValidatorRejectsUnpermittedConceptChangeAlongsideAuthorizedEdit() async throws {
        var input = request("Penyedia membayar dalam 5 hari untuk enkripsi.", brief: "Ubah menjadi 10 hari.")
        input.permissions = [.init(clauseID: "c1", original: "5 hari", replacement: "10 hari", source: .brief)]
        let validation = DraftingReviewValidator.parse(try encodedRevision(input, replacement: "Penyedia membayar dalam 10 hari untuk kompresi.", flag: "authorized"),
                                                       prepared: DraftingReviewPreparation.prepare(input))
        XCTAssertTrue(validation.failures.contains("outsideAuthorizedRanges"))
    }

    func testValidatorRejectsSubstantiveAuthorizationInventedByModel() async throws {
        let input = request("Penyedia membayar dalam 5 hari.", brief: "Periksa ketentuan pembayaran.")
        let raw = try encodedRevision(input, replacement: "Penyedia membayar dalam 10 hari.", flag: "authorized")
        let service = DraftingReviewService { _, _ in Self.generated(raw) }
        let result = await service.review(input)
        XCTAssertEqual(result.status, .incomplete)
        XCTAssertNil(result.response)
        XCTAssertTrue(result.failures.contains("missingMutationPermission"))
    }

    func testStrictParserRejectsMissingNullsUnknownReferencesAndDuplicateFindings() throws {
        let input = request("Penyedia memberikan jasa.", brief: "Periksa bahasa.")
        let prepared = DraftingReviewPreparation.prepare(input)
        let missingNull = #"{"decision":"clarify","findings":[{"clause_id":"c1","quote":"Penyedia memberikan jasa.","category":"completeness","reason":"Perlu lokasi.","clarification_question":"Di mana?","substance_change":"undetermined","reference_ids":[]}]}"#
        XCTAssertEqual(DraftingReviewValidator.parse(missingNull, prepared: prepared).failures, ["invalidSchema"])
        let finding = DraftingReview.Finding(clauseID: "c1", quote: input.clauses[0].text, category: "completeness", reason: "Perlu lokasi.",
                                            suggestedText: nil, clarificationQuestion: "Di mana lokasi jasa?", substanceChange: "undetermined", referenceIDs: ["definition-id"])
        let result = DraftingReviewValidator.validate(.init(decision: .clarify, findings: [finding, finding]), prepared: prepared)
        XCTAssertTrue(result.failures.contains("unknownReference"))
        XCTAssertTrue(result.failures.contains("duplicateFinding"))
    }

    func testUTF16AnchorAmbiguityAndNonTargetFindingsAreRejected() throws {
        let input = request("😀 laporan laporan.", brief: "Periksa bahasa.")
        let finding = DraftingReview.Finding(clauseID: "c1", quote: "laporan", category: "completeness", reason: "Perlu detail.",
                                            suggestedText: nil, clarificationQuestion: "Laporan yang mana?", substanceChange: "undetermined", referenceIDs: [])
        XCTAssertTrue(DraftingReviewValidator.validate(.init(decision: .clarify, findings: [finding]),
            prepared: DraftingReviewPreparation.prepare(input)).failures.contains("invalidOrAmbiguousQuote"))
        XCTAssertNil(DraftingReviewPreparation.uniqueRange(of: "aa", in: "aaa"))
    }

    func testViewModelUsesBackendRouteAndDoesNotCreateEditorEdits() async {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        vm.reviewMode = .deterministic
        let input = request("Penyedia membayar dalam 5 hari.", brief: "Ubah tenggat pembayaran menjadi 10 hari.")
        let result = await vm.reviewDrafting(input, documentText: input.documentText)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(vm.draftingReviewResult?.response, result.response)
        XCTAssertTrue(vm.editorSuggestions.isEmpty)
        XCTAssertTrue(vm.reviewAnnotations.isEmpty)
        vm.markDocumentEdited(documentText: "x" + input.documentText)
        XCTAssertNil(vm.draftingReviewResult)
    }

    func testViewModelRejectsStaleInvocationAndClearsResultOnReset() async {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        let input = request("Penyedia membayar dalam 5 hari.", brief: "Ubah tenggat pembayaran menjadi 10 hari.")
        let stale = await vm.reviewDrafting(input, documentText: "changed")
        XCTAssertEqual(stale.failures, ["staleDocumentRevision"])
        _ = await vm.reviewDrafting(input, documentText: input.documentText)
        vm.resetInputMetadata()
        XCTAssertNil(vm.draftingReviewResult)
    }

    func testCancellationAndDocumentIsolationWhileModelIsActive() async throws {
        let generator: DraftingReviewService.Generator = { _, _ in
            try await Task.sleep(for: .milliseconds(80))
            return Self.generatedNoChange
        }
        let qwen = QwenSuggestionService()
        let first = AIConnectorViewModel(service: qwen, dictionaryStore: LegalDictionaryStore(entries: []), draftingGenerator: generator)
        let second = AIConnectorViewModel(service: qwen, dictionaryStore: LegalDictionaryStore(entries: []), draftingGenerator: generator)
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.", scope: .verifyDocument)
        let one = Task { await first.reviewDrafting(input, documentText: input.documentText) }
        let two = Task { await second.reviewDrafting(input, documentText: input.documentText) }
        try await Task.sleep(for: .milliseconds(20))
        first.cancelDraftingReview()
        let cancelled = await one.value
        let completed = await two.value
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertTrue(completed.isComplete)
        XCTAssertNil(first.draftingReviewResult)
        XCTAssertNotNil(second.draftingReviewResult)
    }

    func testDocumentEditDuringGenerationCannotPublishOldProposal() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            draftingGenerator: { _, _ in try await Task.sleep(for: .milliseconds(80)); return Self.generatedNoChange })
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        let running = Task { await vm.reviewDrafting(input, documentText: input.documentText) }
        try await Task.sleep(for: .milliseconds(20))
        vm.markDocumentEdited(documentText: "changed")
        let result = await running.value
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertNil(vm.draftingReviewResult)
    }

    func testDeletingDocumentBeforeLanguageAnalysisInvalidatesDrafting() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            draftingGenerator: { _, _ in try await Task.sleep(for: .milliseconds(60)); return Self.generatedNoChange })
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        let running = Task { await vm.reviewDrafting(input, documentText: input.documentText) }
        try await Task.sleep(for: .milliseconds(10))
        vm.markDocumentEdited(documentText: "")
        let result = await running.value
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertNil(vm.draftingReviewResult)
    }

    func testCacheClearDuringInferenceDoesNotRepopulateOldEpoch() async throws {
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; try await Task.sleep(for: .milliseconds(40)); return Self.generatedNoChange }
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        let running = Task { await service.review(input) }
        try await Task.sleep(for: .milliseconds(10))
        service.clearCache()
        _ = await running.value
        let rerun = await service.review(input, fullFresh: false)
        XCTAssertFalse(rerun.cacheHit)
        XCTAssertEqual(calls, 2)
    }

    func testViewModelUsesInteractiveSchedulerPriorityAndRejectsChangedConfiguration() async throws {
        var priority: AIConnectorInferencePriority?
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            draftingGenerator: { _, _ in
                priority = AIConnectorInferenceContext.priority
                try await Task.sleep(for: .milliseconds(50))
                return Self.generatedNoChange
            })
        let input = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        let running = Task { await vm.reviewDrafting(input, documentText: input.documentText) }
        try await Task.sleep(for: .milliseconds(10))
        vm.modelVariant = .qwen35_2b
        let result = await running.value
        if case .interactive = priority { } else { XCTFail("Expected interactive priority") }
        XCTAssertEqual(result.failures, ["configurationChanged"])
        XCTAssertNil(vm.draftingReviewResult)
    }

    func testNewRequestSupersedesOnlyItsOwnOldPublication() async throws {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []),
            draftingGenerator: { _, _ in try await Task.sleep(for: .milliseconds(60)); return Self.generatedNoChange })
        let old = request("Penyedia memberikan jasa.", brief: "Periksa jasa.")
        let running = Task { await vm.reviewDrafting(old, documentText: old.documentText) }
        try await Task.sleep(for: .milliseconds(10))
        let newer = request("Penyedia membayar dalam 5 hari.", brief: "Ubah tenggat pembayaran menjadi 10 hari.")
        let completed = await vm.reviewDrafting(newer, documentText: newer.documentText)
        let previous = await running.value
        XCTAssertTrue(completed.isComplete)
        XCTAssertEqual(previous.status, .cancelled)
        XCTAssertEqual(vm.draftingReviewResult?.response, completed.response)
    }

    func testExplicitNumericCommandsBindSelectedTargetWithUnrelatedContext() async {
        let cases = [
            ("Pembayaran dilakukan paling lambat 14 hari setelah faktur diterima.", "Ubah tenggat pembayaran menjadi 30 hari setelah faktur diterima.", "30 hari"),
            ("Kewajiban kerahasiaan berlaku selama 1 tahun setelah perjanjian berakhir.", "Ubah durasi kerahasiaan menjadi 3 tahun setelah perjanjian berakhir.", "3 tahun"),
            ("Pelanggan memberi pemberitahuan pengakhiran 7 hari sebelumnya.", "Ubah masa pemberitahuan pengakhiran menjadi 21 hari.", "21 hari"),
            ("Penyedia menjamin hasil pekerjaan selama 10 hari sejak serah terima.", "Ubah masa jaminan menjadi 45 hari sejak serah terima.", "45 hari")
        ]
        for (clause, brief, expected) in cases {
            let other = "Laporan contoh disampaikan dalam 90 hari."
            let body = "Inventaris Uji adalah daftar perangkat sintetis."
            let document = "😀\n" + clause + "\n" + other + "\n" + body
            var input = request(clause, brief: "Tinjau hanya klausul c1. " + brief, document: document)
            input = .init(documentText: input.documentText, documentRevision: input.documentRevision, brief: input.brief,
                          scope: input.scope, clauses: input.clauses + [.init(id: "context", text: other, sourceRange: (document as NSString).range(of: other))],
                          targetClauseIDs: input.targetClauseIDs,
                          definitions: [.init(id: "irrelevant", term: "Inventaris Uji", body: body, sourceRange: (document as NSString).range(of: body))])
            let result = await localService().review(input, allowsInference: false)
            XCTAssertTrue(result.isComplete, result.failures.joined(separator: ","))
            XCTAssertEqual(result.route, .literal)
            XCTAssertTrue(result.response?.findings[0].suggestedText?.contains(expected) == true)
            XCTAssertEqual(result.anchors.first?.sourceRange.location, 3)
            XCTAssertEqual(result.response?.findings.map(\.clauseID), ["c1"])
        }
    }

    func testExpandedBriefCompilerStillDeclinesContradictoryOrUnboundInstructions() async {
        let cases = [
            ("Pembayaran dilakukan paling lambat 14 hari setelah faktur diterima.", "Ubah tenggat pembayaran menjadi 30 hari sebelum faktur diterima."),
            ("Pembayaran dilakukan paling lambat 14 hari setelah faktur diterima.", "Ubah tenggat pembayaran menjadi 30 hari. Ubah biaya menjadi 99 rupiah."),
            ("Masa jaminan adalah 10 hari dan masa tambahan 20 hari.", "Ubah masa jaminan menjadi 45 hari."),
            ("Jika dokumen sah, Pembayaran dilakukan paling lambat 14 hari.", "Ubah tenggat pembayaran menjadi 30 hari."),
            ("Penyedia mengirim laporan dalam 14 hari.", "Ubah tenggat pembayaran menjadi 30 hari."),
            ("Perjanjian berlaku selama 6 bulan.", "Ubah durasi perjanjian menjadi 12 bulan. Pertahankan 6 bulan."),
            ("Pembayaran dilakukan paling lambat 14 hari setelah faktur lengkap diterima.", "Ubah tenggat pembayaran menjadi 30 hari setelah faktur diterima.")
        ]
        for (clause, brief) in cases {
            let result = await localService().review(request(clause, brief: brief), allowsInference: false)
            XCTAssertEqual(result.failures, ["modelReviewRequired"], brief)
            XCTAssertNil(result.response)
        }
    }

    func testApplicableDefinitionStillRequiresContextualReview() async {
        let clause = "Penyedia mengirim laporan dalam 5 hari untuk Paket Uji."
        let body = "Paket Uji adalah layanan dengan tenggat khusus."
        let document = clause + "\n" + body
        var input = request(clause, brief: "Ubah tenggat laporan menjadi 10 hari.", document: document)
        input.definitions = [.init(id: "d", term: "Paket Uji", body: body, sourceRange: (document as NSString).range(of: body))]
        let result = await localService().review(input, allowsInference: false)
        XCTAssertEqual(result.failures, ["modelReviewRequired"])
    }

    func testInactiveNullRepairUsesOneGenerationAndCachesOnlyValidatedResult() async {
        let raw = #"{"decision":"clarify","findings":[{"clause_id":"c1","quote":"Jasa diberikan daring.","category":"completeness","reason":"Lokasi belum dipilih.","clarification_question":"Di lokasi mana jasa diberikan?","substance_change":"undetermined","reference_ids":[]}]}"#
        let input = request("Jasa diberikan daring.", brief: "Tanyakan lokasi layanan.")
        var calls = 0
        let service = DraftingReviewService { _, _ in calls += 1; return Self.generated(raw) }
        let first = await service.review(input)
        XCTAssertTrue(first.isComplete)
        XCTAssertEqual(first.formatRepairCount, 1)
        XCTAssertEqual(first.modelCallCount, 1)
        XCTAssertEqual(first.response?.decision, .clarify)
        let cached = await service.review(input, fullFresh: false)
        XCTAssertTrue(cached.cacheHit)
        XCTAssertEqual(cached.modelCallCount, 0)
        XCTAssertEqual(cached.formatRepairCount, 0)
        _ = await service.review(input, fullFresh: true)
        XCTAssertEqual(calls, 2)
    }

    func testMissingInactiveQuestionCanBeRepairedWithoutChangingLanguageProposal() async {
        let raw = #"{"decision":"revise","findings":[{"clause_id":"c1","quote":"Jasa diberikan daring.","category":"language","reason":"Perjelas redaksi.","suggested_text":"Jasa diberikan secara daring.","substance_change":"none","reference_ids":[]}]}"#
        let service = DraftingReviewService { _, _ in Self.generated(raw) }
        let result = await service.review(request("Jasa diberikan daring.", brief: "Periksa bahasa."))
        XCTAssertTrue(result.isComplete, result.failures.joined(separator: ","))
        XCTAssertEqual(result.response?.findings.first?.suggestedText, "Jasa diberikan secara daring.")
        XCTAssertEqual(result.formatRepairCount, 1)
    }

    func testDuplicateKeysRequireEqualValuesAndStrictParserRemainsStrict() async {
        let input = request("Jasa diberikan daring.", brief: "Verifikasi layanan.")
        let equal = #"{"decision":"no_change","decision":"no_change","findings":[]}"#
        XCTAssertEqual(DraftingReviewValidator.parse(equal, prepared: DraftingReviewPreparation.prepare(input)).failures, ["invalidSchema"])
        let service = DraftingReviewService { _, _ in Self.generated(equal) }
        let good = await service.review(input)
        XCTAssertTrue(good.isComplete)
        XCTAssertEqual(good.formatRepairCount, 1)
        for raw in [
            #"{"decision":"revise","decision":"no_change","findings":[]}"#,
            #"{"decision":"no_change","findings":[],"findings":[{}]}"#,
            #"{"decision":"no_change","findings":[],"decisi\u006fn":"clarify"}"#
        ] {
            let bad = await DraftingReviewService { _, _ in Self.generated(raw) }.review(input)
            XCTAssertFalse(bad.isComplete)
            XCTAssertEqual(bad.failures, ["invalidSchema"])
            XCTAssertEqual(bad.formatRepairCount, 0)
        }
    }

    func testNestedDuplicateKeyRepairPreservesEscapesAndEmoji() async {
        let clause = "😀 Jasa diberikan daring."
        let raw = #"{"decision":"clarify","findings":[{"clause_id":"c1","quote":"😀 Jasa diberikan daring.","category":"completeness","reason":"Lokasi belum dipilih.","reas\u006fn":"Lokasi belum dipilih.","suggested_text":null,"clarification_question":"Apakah label \"reason\" berada di lokasi layanan?","substance_change":"undetermined","reference_ids":[]}]}"#
        let result = await DraftingReviewService { _, _ in Self.generated(raw) }.review(request(clause, brief: "Tanyakan lokasi."))
        XCTAssertTrue(result.isComplete, result.failures.joined(separator: ","))
        XCTAssertEqual(result.formatRepairCount, 1)
        XCTAssertEqual(result.anchors.first?.sourceRange.length, clause.utf16.count)
        XCTAssertEqual(result.response?.findings.first?.clarificationQuestion, "Apakah label \"reason\" berada di lokasi layanan?")
        let conflict = raw.replacingOccurrences(of: #""reas\u006fn":"Lokasi belum dipilih.""#, with: #""reas\u006fn":"Makna berbeda.""#)
        XCTAssertNil(DraftingReviewJSON.object(conflict))
    }

    func testRepairNeverInventsActiveFieldAcceptsExtraKeysOrTruncation() async {
        let base = #"{"decision":"clarify","findings":[{"clause_id":"c1","quote":"Jasa diberikan daring.","category":"completeness","reason":"Lokasi belum dipilih.","suggested_text":null,"substance_change":"undetermined","reference_ids":[]}]}"#
        let rawCases = [base, base + " trailing", String(base.dropLast()),
                        base.replacingOccurrences(of: #""suggested_text":null"#, with: #""suggested_text":null,"extra":true"#),
                        base.replacingOccurrences(of: #""suggested_text":null"#, with: #""suggested_text":null,"clarification_question":3"#)]
        for raw in rawCases {
            var calls = 0
            let service = DraftingReviewService { _, _ in calls += 1; return Self.generated(raw) }
            let input = request("Jasa diberikan daring.", brief: "Tanyakan lokasi.")
            for _ in 0..<2 {
                let result = await service.review(input, fullFresh: false)
                XCTAssertEqual(result.status, .incomplete)
                XCTAssertNil(result.response)
                XCTAssertFalse(result.cacheHit)
            }
            XCTAssertEqual(calls, 2)
        }
    }

    func testStructuralRepairStillEnforcesPermissionsMeaningAndSources() async {
        let clause = "Penyedia membayar dalam 5 hari."
        let input = request(clause, brief: "Periksa ketentuan.")
        let raw = #"{"decision":"revise","findings":[{"clause_id":"c1","quote":"Penyedia membayar dalam 5 hari.","category":"business","reason":"Usulan perubahan.","suggested_text":"Pelanggan membayar dalam 10 hari.","substance_change":"authorized","reference_ids":["unknown"]}]}"#
        let service = DraftingReviewService { _, _ in Self.generated(raw) }
        let result = await service.review(input)
        XCTAssertEqual(result.status, .incomplete)
        XCTAssertEqual(result.formatRepairCount, 1)
        XCTAssertTrue(result.failures.contains("missingMutationPermission"))
        XCTAssertTrue(result.failures.contains("protectedDelta:actors"))
        XCTAssertTrue(result.failures.contains("protectedDelta:numbers"))
        XCTAssertTrue(result.failures.contains("unknownReference"))
        XCTAssertNil(result.response)
    }

    func testMalformedOversizedAndDeepJSONNeverCrashesOrRepairs() {
        for raw in ["{", "[]", "null", "{\"decision\":true,\"findings\":[]}",
                    String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40),
                    String(repeating: " ", count: 128 * 1_024 + 1)] {
            XCTAssertNil(DraftingReviewJSON.repaired(raw))
        }
    }

    private enum TestError: Error { case unavailable }

    private func request(_ clause: String, brief: String, scope: DraftingReview.Scope = .rewriteTarget,
                         prefix: String = "", document: String? = nil) -> DraftingReview.Request {
        let text = document ?? (prefix + clause)
        return .init(documentText: text, documentRevision: DocumentFingerprinting.contentSHA256(text), brief: brief,
                     scope: scope, clauses: [.init(id: "c1", text: clause, sourceRange: (text as NSString).range(of: clause))], targetClauseIDs: ["c1"])
    }

    private func localService() -> DraftingReviewService {
        DraftingReviewService { _, _ in XCTFail("Preflight/literal must not infer"); return Self.generatedNoChange }
    }

    private static var generatedNoChange: QwenReviewResult { generated(#"{"decision":"no_change","findings":[]}"#) }

    private static func generated(_ raw: String, stop: AIConnectorGenerationStopReason = .stop) -> QwenReviewResult {
        .init(output: raw, metrics: .init(promptTokenCount: 1, generationTokenCount: 1, promptDuration: 0, generationDuration: 0, stopReason: stop), containsReasoningMarkers: false)
    }

    private func encodedRevision(_ input: DraftingReview.Request, replacement: String, flag: String = "none") throws -> String {
        let response = DraftingReview.Response(decision: .revise, findings: [
            .init(clauseID: "c1", quote: input.clauses[0].text, category: "language", reason: "Usulan revisi.",
                  suggestedText: replacement, clarificationQuestion: nil, substanceChange: flag, referenceIDs: [])
        ])
        return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    }
}
