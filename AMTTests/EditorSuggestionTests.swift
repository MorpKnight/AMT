import Foundation
import XCTest
@testable import AMT

final class EditorSuggestionTests: XCTestCase {
    @MainActor
    func testDefinitionMapperOnlyEmitsMismatchWithSourceGroundedReplacement() throws {
        let entry = makeDefinitionEntry(
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi.",
            sourcePassageID: "passage-data-pribadi"
        )
        let target = "Data Pribadi adalah informasi mengenai perusahaan."
        let segment = makeSegment(target: target)
        let candidate = AIConnectorDefinitionCandidate(
            id: "D1",
            match: LegalDictionaryMatch(
                entry: entry,
                score: 1_000,
                rank: 1,
                matchedDefinitionTokenCount: 3,
                isDirectTermMatch: true,
                retrievalOrigin: .exact
            ),
            statementText: "informasi mengenai perusahaan.",
            detection: .explicitPattern
        )
        let assessment = makeDefinitionAssessment(
            segment: segment,
            statementText: candidate.statementText,
            candidate: candidate,
            classification: .explicitDefinition,
            alignment: .mismatch
        )

        let first = try XCTUnwrap(
            EditorSuggestionMapper.makeDefinitionSuggestions(
                assessments: [assessment],
                documentText: target
            ).first
        )
        let second = try XCTUnwrap(
            EditorSuggestionMapper.makeDefinitionSuggestions(
                assessments: [assessment],
                documentText: target
            ).first
        )

        XCTAssertEqual(first.kind, .definition)
        XCTAssertEqual(first.category, .terminology)
        XCTAssertEqual(first.original, "informasi mengenai perusahaan.")
        XCTAssertEqual(
            first.replacement,
            "data tentang orang perseorangan yang teridentifikasi."
        )
        XCTAssertEqual(
            (target as NSString).substring(with: first.sourceRange),
            first.original
        )
        XCTAssertEqual(first.reference?.term, "Data Pribadi")
        XCTAssertEqual(first.reference?.definition, first.replacement)
        XCTAssertEqual(first.reference?.sourcePassageID, "passage-data-pribadi")
        XCTAssertEqual(first.id, second.id)
    }

    @MainActor
    func testDefinitionDebugMapperShowsMatchingDefinitionAsReadOnlyAnnotation() throws {
        let entry = makeDefinitionEntry(
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi.",
            sourcePassageID: "passage-data-pribadi"
        )
        let target = "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi."
        let segment = makeSegment(target: target)
        let candidate = AIConnectorDefinitionCandidate(
            id: "D1",
            match: LegalDictionaryMatch(
                entry: entry,
                score: 1_000,
                rank: 1,
                matchedDefinitionTokenCount: 8,
                isDirectTermMatch: true,
                retrievalOrigin: .exact
            ),
            statementText: "data tentang orang perseorangan yang teridentifikasi.",
            detection: .explicitPattern
        )
        let assessment = makeDefinitionAssessment(
            segment: segment,
            statementText: candidate.statementText,
            candidate: candidate,
            classification: .explicitDefinition,
            alignment: .matches
        )

        XCTAssertTrue(
            EditorSuggestionMapper.make(
                reviews: [],
                definitionAssessments: [assessment],
                documentText: target
            ).isEmpty
        )

        let suggestion = try XCTUnwrap(
            EditorSuggestionMapper.makeDefinitionDebugSuggestions(
                assessments: [assessment],
                documentText: target
            ).first
        )

        XCTAssertTrue(suggestion.isDebugOnly)
        XCTAssertEqual(suggestion.kind, .definition)
        XCTAssertEqual(
            suggestion.sourceRange,
            NSRange(location: 0, length: target.utf16.count)
        )
        XCTAssertEqual(suggestion.original, target)
        XCTAssertEqual(suggestion.replacement, suggestion.original)
        XCTAssertEqual(suggestion.reference?.term, "Data Pribadi")
        XCTAssertEqual(
            suggestion.reference?.definition,
            "data tentang orang perseorangan yang teridentifikasi."
        )
        XCTAssertEqual(suggestion.reference?.sourcePassageID, "passage-data-pribadi")
    }

    @MainActor
    func testDefinitionDebugMapperCanShowWholeImplicitDefinitionStatement() throws {
        let entry = makeDefinitionEntry(
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi."
        )
        let target = "Data Pribadi digunakan dalam perjanjian ini."
        let segment = makeSegment(target: target)
        let candidate = AIConnectorDefinitionCandidate(
            id: "D1",
            match: LegalDictionaryMatch(
                entry: entry,
                score: 0.8,
                rank: 1,
                matchedDefinitionTokenCount: 2,
                isDirectTermMatch: true,
                retrievalOrigin: .semantic
            ),
            statementText: target,
            detection: .retrievedCandidate
        )
        let assessment = makeDefinitionAssessment(
            segment: segment,
            statementText: target,
            candidate: candidate,
            classification: .implicitDefinition,
            alignment: .matches
        )

        let suggestion = try XCTUnwrap(
            EditorSuggestionMapper.makeDefinitionDebugSuggestions(
                assessments: [assessment],
                documentText: target
            ).first
        )

        XCTAssertEqual(suggestion.sourceRange, NSRange(location: 0, length: target.utf16.count))
        XCTAssertEqual(suggestion.original, target)
        XCTAssertTrue(suggestion.isDebugOnly)
    }

    @MainActor
    func testDefinitionMapperHidesMatchesUncertaintyAndUnanchoredFindings() {
        let entry = makeDefinitionEntry(
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi."
        )
        let target = "Data Pribadi digunakan dalam perjanjian ini."
        let segment = makeSegment(target: target)
        let candidate = AIConnectorDefinitionCandidate(
            id: "D1",
            match: LegalDictionaryMatch(
                entry: entry,
                score: 1_000,
                rank: 1,
                matchedDefinitionTokenCount: 3,
                isDirectTermMatch: true,
                retrievalOrigin: .exact
            ),
            statementText: target,
            detection: .retrievedCandidate
        )

        let matching = makeDefinitionAssessment(
            segment: segment,
            statementText: target,
            candidate: candidate,
            classification: .explicitDefinition,
            alignment: .matches
        )
        let uncertain = makeDefinitionAssessment(
            segment: segment,
            statementText: target,
            candidate: candidate,
            classification: .needsReview,
            alignment: .needsReview
        )
        let unanchoredMismatch = makeDefinitionAssessment(
            segment: segment,
            statementText: target,
            candidate: candidate,
            classification: .implicitDefinition,
            alignment: .mismatch
        )

        XCTAssertTrue(
            EditorSuggestionMapper.makeDefinitionSuggestions(
                assessments: [matching, uncertain, unanchoredMismatch],
                documentText: target
            ).isEmpty
        )
    }

    func testMapperUsesAbsoluteUTF16OffsetForUnicodeText() throws {
        let prefix = "Pembukaan 😀.\n"
        let target = "Pihak Kedua wajib untuk menyerahkan laporan."
        let document = prefix + target
        let segment = AIReviewSegment(
            id: 1,
            sourceLocation: prefix.utf16.count,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
        let review = makeReview(
            segment: segment,
            category: .grammar,
            original: "wajib untuk",
            replacement: "wajib"
        )

        let suggestions = EditorSuggestionMapper.make(
            reviews: [review],
            documentText: document
        )

        let suggestion = try XCTUnwrap(suggestions.first)
        let expectedLocation = prefix.utf16.count + (target as NSString).range(of: "wajib untuk").location
        XCTAssertEqual(suggestion.sourceRange, NSRange(location: expectedLocation, length: "wajib untuk".utf16.count))
        XCTAssertEqual((document as NSString).substring(with: suggestion.sourceRange), "wajib untuk")
    }

    func testMapperSkipsUnsupportedReviewsAndDuplicateOriginals() {
        let target = "Istilah yang sama muncul; Istilah yang sama muncul."
        let segment = AIReviewSegment(
            id: 2,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
        let noSuggestion = makeReview(
            segment: segment,
            status: .noSuggestion,
            category: .none,
            original: nil,
            replacement: nil
        )
        let needsReview = makeReview(
            segment: segment,
            status: .needsReview,
            category: .clarity,
            original: "Istilah yang sama",
            replacement: nil
        )
        let duplicate = makeReview(
            segment: segment,
            category: .grammar,
            original: "Istilah yang sama",
            replacement: "istilah"
        )

        XCTAssertTrue(
            EditorSuggestionMapper.make(
                reviews: [noSuggestion, needsReview, duplicate],
                documentText: target
            ).isEmpty
        )
    }

    func testTerminologyReferenceIsOptionalForNonTerminologySuggestion() throws {
        let entry = LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: URL(string: "https://peraturan.bpk.go.id")
        )
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 42,
            rank: 1,
            matchedDefinitionTokenCount: 5,
            isDirectTermMatch: false
        )
        let target = "Data tentang orang perseorangan."
        let segment = AIReviewSegment(
            id: 3,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )

        let terminology = makeReview(
            segment: segment,
            category: .terminology,
            original: target.dropLast().description,
            replacement: "Data Pribadi",
            glossaryMatch: match
        )
        let spelling = makeReview(
            segment: segment,
            category: .spelling,
            original: "Data",
            replacement: "data",
            glossaryMatch: match
        )

        XCTAssertNotNil(
            try XCTUnwrap(
                EditorSuggestionMapper.make(
                    reviews: [terminology],
                    documentText: target
                ).first
            ).reference
        )
        XCTAssertNil(
            EditorSuggestionMapper.make(
                reviews: [spelling],
                documentText: target
            ).first?.reference
        )
    }

    func testMapperSkipsSuggestionOutsideDocumentBounds() {
        let segment = AIReviewSegment(
            id: 4,
            sourceLocation: 100,
            sourceLength: 10,
            targetText: "Teks valid.",
            previousContext: nil,
            nextContext: nil
        )
        let review = makeReview(
            segment: segment,
            category: .spelling,
            original: "Teks",
            replacement: "Teks"
        )

        XCTAssertTrue(
            EditorSuggestionMapper.make(
                reviews: [review],
                documentText: "Teks valid."
            ).isEmpty
        )
    }

    func testReconcilerShiftsLaterRangesAndDropsOverlap() throws {
        let accepted = suggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            location: 5,
            original: "abc",
            replacement: "abcdef"
        )
        let later = suggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            location: 12,
            original: "next",
            replacement: "after"
        )
        let overlap = suggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            location: 7,
            original: "overlap",
            replacement: "safe"
        )

        let result = EditorSuggestionReconciler.afterAccept(
            suggestions: [accepted, later, overlap],
            acceptedID: accepted.id,
            replacementDelta: 3
        )

        let remaining = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(remaining.id, later.id)
        XCTAssertEqual(remaining.sourceRange.location, 15)
    }

    private func makeReview(
        segment: AIReviewSegment,
        status: AIReviewStatus = .suggestion,
        category: AIReviewCategory,
        original: String?,
        replacement: String?,
        glossaryMatch: LegalDictionaryMatch? = nil
    ) -> AIValidatedReview {
        AIValidatedReview(
            segment: segment,
            status: status,
            category: category,
            original: original,
            replacement: replacement,
            reason: "Perbaikan bahasa.",
            glossaryMatch: glossaryMatch,
            origin: .deterministic
        )
    }

    private func suggestion(
        id: UUID,
        location: Int,
        original: String,
        replacement: String
    ) -> EditorSuggestion {
        EditorSuggestion(
            id: id,
            sourceRange: NSRange(location: location, length: original.utf16.count),
            original: original,
            replacement: replacement,
            category: .grammar,
            reason: "Perbaikan bahasa.",
            origin: .deterministic,
            reference: nil
        )
    }

    @MainActor
    private func makeDefinitionAssessment(
        segment: AIReviewSegment,
        statementText: String,
        candidate: AIConnectorDefinitionCandidate,
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment
    ) -> AIConnectorDefinitionAssessment {
        AIConnectorDefinitionAssessment(
            segment: segment,
            term: candidate.term,
            statementText: statementText,
            candidate: candidate,
            candidateCount: 1,
            detection: candidate.detection,
            classification: classification,
            alignment: alignment,
            reason: "Definisi tidak selaras dengan evidence corpus.",
            origin: .qwen,
            modelReviewed: true,
            retrievalOrigin: candidate.match.retrievalOrigin,
            semanticScore: candidate.match.semanticScore,
            requiresHumanReview: true
        )
    }

    @MainActor
    private func makeDefinitionEntry(
        definition: String,
        sourcePassageID: String? = nil
    ) -> LegalDictionaryEntry {
        LegalDictionaryEntry(
            id: "data-pribadi-definition",
            term: "Data Pribadi",
            definition: definition,
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: URL(string: "https://example.invalid/detail"),
            officialDocumentURL: URL(string: "https://example.invalid/document"),
            referenceID: "reference-data-pribadi",
            authority: .verified,
            corpusVersion: "definition-test-v1",
            applicabilityStatus: .inForce,
            sourcePassageID: sourcePassageID,
            articleLocator: "Pasal 1 angka 1",
            isActionable: true
        )
    }

    @MainActor
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
}
