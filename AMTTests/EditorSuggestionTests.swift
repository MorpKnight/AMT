import Foundation
import XCTest
@testable import AMT

final class EditorSuggestionTests: XCTestCase {
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
}
