import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseThreeTests: XCTestCase {
    func testReviewAnchorUsesSegmentRelativeUTF16RangesAndRejectsStaleText() {
        let target = "😀 wajib untuk dan wajib untuk."
        let segment = makeSegment(id: 7, target: target)
        let firstRange = (target as NSString).range(of: "wajib untuk")
        let secondRange = (target as NSString).range(
            of: "wajib untuk",
            options: .literal,
            range: NSRange(
                location: firstRange.location + firstRange.length,
                length: target.utf16.count - firstRange.location - firstRange.length
            )
        )

        let first = AIConnectorReviewAnchor(
            segmentID: segment.id,
            sourceRange: firstRange,
            original: "wajib untuk"
        )
        let second = AIConnectorReviewAnchor(
            segmentID: segment.id,
            sourceRange: secondRange,
            original: "wajib untuk"
        )

        XCTAssertTrue(first.isValid(for: segment, original: "wajib untuk"))
        XCTAssertTrue(second.isValid(for: segment, original: "wajib untuk"))
        XCTAssertNotEqual(first.range, second.range)
        XCTAssertEqual(first.range.location, 3, "Emoji occupies two UTF-16 code units.")

        let wrongSegment = AIReviewSegment(
            id: 8,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
        XCTAssertFalse(first.isValid(for: wrongSegment, original: "wajib untuk"))
        XCTAssertFalse(first.isValid(for: segment, original: "wajib"))

        let outOfBounds = AIConnectorReviewAnchor(
            segmentID: segment.id,
            sourceLocation: target.utf16.count,
            sourceLength: 1,
            originalSHA256: "invalid"
        )
        XCTAssertFalse(outOfBounds.isValid(for: segment, original: "x"))

        let wrongHash = AIConnectorReviewAnchor(
            segmentID: segment.id,
            sourceLocation: firstRange.location,
            sourceLength: firstRange.length,
            originalSHA256: "not-the-hash"
        )
        XCTAssertFalse(wrongHash.isValid(for: segment, original: "wajib untuk"))
    }

    func testDeterministicRuleCreatesOneCandidatePerOccurrence() {
        let target = "Pihak pertama wajib untuk menyerahkan laporan dan Pihak kedua wajib untuk membayar."
        let segment = makeSegment(target: target)
        let builder = AIConnectorCandidateBuilder(
            ruleStore: AIConnectorRuleStore(
                version: "phase3-test-rules",
                rules: [
                    AIConnectorRuleDefinition(
                        id: "test-wajib-untuk",
                        revision: 1,
                        category: .grammar,
                        matcher: .tokenSequence,
                        value: "wajib untuk",
                        replacement: "wajib",
                        reason: "Perbaikan frasa lokal.",
                        priority: 10,
                        exceptions: [],
                        status: .active,
                        sourceNote: "Test",
                        owner: "Test",
                        reviewer: "Test",
                        changelog: "Phase 3"
                    )
                ]
            )
        )

        let candidates = builder.build(for: segment, glossaryMatches: [])

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(
            candidates.map { $0.evidence.sourceLocation },
            [
                (target as NSString).range(of: "wajib untuk").location,
                (target as NSString).range(
                    of: "wajib untuk",
                    options: .literal,
                    range: NSRange(
                        location: (target as NSString).range(of: "wajib untuk").location
                            + "wajib untuk".utf16.count,
                        length: target.utf16.count
                            - (target as NSString).range(of: "wajib untuk").location
                            - "wajib untuk".utf16.count
                    )
                ).location
            ]
        )
        XCTAssertEqual(candidates.map(\.original), ["wajib untuk", "wajib untuk"])
    }

    func testRankerAndConflictResolverKeepSeparateOccurrences() throws {
        let target = "wajib untuk lalu wajib untuk"
        let firstRange = (target as NSString).range(of: "wajib untuk")
        let secondRange = (target as NSString).range(
            of: "wajib untuk",
            options: .literal,
            range: NSRange(
                location: firstRange.location + firstRange.length,
                length: target.utf16.count - firstRange.location - firstRange.length
            )
        )
        let firstCandidate = makeCandidate(
            id: "P1",
            location: firstRange.location,
            length: firstRange.length
        )
        let secondCandidate = makeCandidate(
            id: "P2",
            location: secondRange.location,
            length: secondRange.length
        )

        let ranked = AIConnectorPhaseTwoCandidateRanker().select(
            [firstCandidate, secondCandidate]
        )
        XCTAssertEqual(ranked.candidates.count, 2)
        XCTAssertEqual(
            ranked.candidates.map { $0.evidence.sourceLocation },
            [firstRange.location, secondRange.location]
        )

        let segment = makeSegment(target: target)
        let firstReview = try AIConnectorSuggestionValidator().validate(
            parsedReview(original: "wajib untuk"),
            for: segment,
            glossaryMatches: [],
            sourceAnchor: AIConnectorReviewAnchor(
                segmentID: segment.id,
                sourceRange: firstRange,
                original: "wajib untuk"
            )
        )
        let secondReview = try AIConnectorSuggestionValidator().validate(
            parsedReview(original: "wajib untuk"),
            for: segment,
            glossaryMatches: [],
            sourceAnchor: AIConnectorReviewAnchor(
                segmentID: segment.id,
                sourceRange: secondRange,
                original: "wajib untuk"
            )
        )

        XCTAssertEqual(
            AIConnectorSuggestionConflictResolver().resolve([firstReview, secondReview]).count,
            2
        )
    }

    func testValidatorRequiresExactAnchorForDuplicateOriginals() throws {
        let target = "wajib untuk kemudian wajib untuk"
        let segment = makeSegment(target: target)
        let firstRange = (target as NSString).range(of: "wajib untuk")
        let anchor = AIConnectorReviewAnchor(
            segmentID: segment.id,
            sourceRange: firstRange,
            original: "wajib untuk"
        )

        let validated = try AIConnectorSuggestionValidator().validate(
            parsedReview(original: "wajib untuk"),
            for: segment,
            glossaryMatches: [],
            sourceAnchor: anchor
        )
        XCTAssertEqual(validated.sourceAnchor?.range, firstRange)

        XCTAssertThrowsError(
            try AIConnectorSuggestionValidator().validate(
                parsedReview(original: "wajib untuk"),
                for: segment,
                glossaryMatches: []
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectorValidationError, .originalNotUnique)
        }
    }

    func testCacheMaterializesTheAnchoredReviewOnTheSameSegment() async throws {
        let segment = makeSegment(id: 12, target: "😀 wajib untuk")
        let original = "wajib untuk"
        let range = (segment.targetText as NSString).range(of: original)
        let review = AIValidatedReview(
            segment: segment,
            status: .suggestion,
            category: .grammar,
            original: original,
            replacement: "wajib",
            reason: "Perbaikan lokal.",
            glossaryMatch: nil,
            origin: .deterministic,
            sourceAnchor: AIConnectorReviewAnchor(
                segmentID: segment.id,
                sourceRange: range,
                original: original
            )
        )
        let cache = AIConnectorSegmentCache()
        await cache.insert(
            AIConnectorCachedSegmentResult(
                reviews: [AIConnectorCachedReview(review: review)],
                rejectionReasons: [],
                modelAttempts: 0,
                repairAttempted: false,
                usedFallback: false,
                firstPassSucceeded: true
            ),
            for: "phase3-test"
        )

        let cachedValue = await cache.value(for: "phase3-test")
        let restored = try XCTUnwrap(cachedValue)
        let materialized = try XCTUnwrap(restored.reviews.first?.materialize(for: segment))
        XCTAssertEqual(materialized.sourceAnchor?.range, range)
        XCTAssertTrue(
            materialized.sourceAnchor?.isValid(for: segment, original: original) == true
        )
    }

    func testNeedsReviewAndDefinitionFindingsUseReadOnlyAnnotations() throws {
        let target = "Data Pribadi adalah informasi mengenai perusahaan."
        let segment = makeSegment(target: target)
        let needsReview = try AIConnectorSuggestionValidator().validate(
            AIParsedReview(
                status: .needsReview,
                category: .clarity,
                original: "informasi mengenai perusahaan.",
                replacement: nil,
                glossaryID: nil,
                reason: "Evidence perlu diperiksa."
            ),
            for: segment,
            glossaryMatches: [],
            sourceAnchor: AIConnectorReviewAnchor(
                segmentID: segment.id,
                sourceRange: (target as NSString).range(of: "informasi mengenai perusahaan."),
                original: "informasi mengenai perusahaan."
            )
        )
        let definitionAssessment = makeDefinitionAssessment(
            segment: segment,
            entry: makeDefinitionEntry(),
            statementText: "informasi mengenai perusahaan.",
            alignment: .mismatch
        )

        let annotations = EditorSuggestionMapper.makeReviewAnnotations(
            reviews: [needsReview],
            definitionAssessments: [definitionAssessment],
            documentText: target
        )
        XCTAssertEqual(annotations.count, 2)
        XCTAssertTrue(annotations.allSatisfy(\.isReadOnlyDiagnostic))
        XCTAssertTrue(annotations.contains { $0.kind == .needsReview })
        let definition = try XCTUnwrap(annotations.first { $0.kind == .definition })
        XCTAssertEqual(definition.definitionDiagnosticStatus, .mismatch)
        XCTAssertEqual(definition.reference?.regulation, "Undang-Undang Nomor 27 Tahun 2022")
        XCTAssertEqual(definition.reference?.articleLocator, "Pasal 1 angka 1")
        XCTAssertEqual(definition.reference?.sourcePassageID, "passage-data-pribadi")
        XCTAssertEqual(definition.reference?.applicabilityStatus, .inForce)
    }

    func testDefinitionMatchesAreSeparateAndHiddenFromDefaultItems() throws {
        let target = "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi."
        let segment = makeSegment(target: target)
        let assessment = makeDefinitionAssessment(
            segment: segment,
            entry: makeDefinitionEntry(),
            statementText: "data tentang orang perseorangan yang teridentifikasi.",
            alignment: .matches
        )

        let matches = EditorSuggestionMapper.makeDefinitionMatchAnnotations(
            assessments: [assessment],
            documentText: target
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.definitionDiagnosticStatus, .matches)

        XCTAssertTrue(
            EditorSuggestionMapper.makeReviewAnnotations(
                reviews: [],
                definitionAssessments: [assessment],
                documentText: target
            ).isEmpty,
            "Definition matches remain hidden from the default annotation list."
        )
    }

    func testNavigatorOrderingBoundariesDismissAndAcceptReconciliation() throws {
        let document = "wajib untuk. Pihak Kedua wajib untuk."
        let firstLocation = (document as NSString).range(of: "wajib untuk").location
        let secondLocation = (document as NSString).range(
            of: "wajib untuk",
            options: .literal,
            range: NSRange(
                location: firstLocation + "wajib untuk".utf16.count,
                length: document.utf16.count - firstLocation - "wajib untuk".utf16.count
            )
        ).location
        let first = makeSuggestion(
            location: firstLocation,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let second = makeSuggestion(
            location: secondLocation,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(document),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(timeIntervalSince1970: 1),
            editorSuggestions: [first, second]
        )

        XCTAssertTrue(viewModel.restoreAnalysisSnapshot(snapshot, documentText: document))
        XCTAssertEqual(viewModel.reviewItems.map(\.id), [first.id, second.id])

        viewModel.selectPreviousReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, second.id)
        viewModel.selectPreviousReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, first.id)
        viewModel.selectPreviousReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, first.id)
        viewModel.selectReviewItem(nil)
        viewModel.selectNextReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, first.id)
        viewModel.selectNextReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, second.id)
        viewModel.selectNextReviewItem()
        XCTAssertEqual(viewModel.selectedReviewItemID, second.id)

        viewModel.dismissReviewItem(first.id)
        XCTAssertEqual(viewModel.reviewItems.map(\.id), [second.id])
        let dismissedSnapshot = try XCTUnwrap(
            viewModel.makeAnalysisSnapshot(documentText: document)
        )
        XCTAssertTrue(dismissedSnapshot.ignoredReviewItemIDs.contains(first.id))

        let accepted = makeSuggestion(
            id: second.id,
            location: secondLocation,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let updated = document.replacingCharacters(
            in: Range(
                NSRange(location: secondLocation, length: "wajib untuk".utf16.count),
                in: document
            )!,
            with: "wajib"
        )
        XCTAssertTrue(
            viewModel.reconcileAfterAccept(
                accepted,
                previousText: document,
                updatedText: updated
            )
        )
        XCTAssertTrue(viewModel.reviewItems.isEmpty)
        let acceptedSnapshot = try XCTUnwrap(viewModel.makeAnalysisSnapshot(documentText: updated))
        XCTAssertTrue(acceptedSnapshot.editorSuggestions.isEmpty)
        XCTAssertEqual(acceptedSnapshot.analyzedContentSHA256, DocumentFingerprinting.contentSHA256(updated))
    }

    func testAcceptingOneSuggestionRetainsOtherSuggestionsAndAllowsSnapshotPersistence() throws {
        let originalText = "Kata pertama wajib untuk diuji dan kata kedua adalah adalah salah."
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        let firstLoc = (originalText as NSString).range(of: "wajib untuk").location
        let secondLoc = (originalText as NSString).range(of: "adalah adalah").location

        let sugID1 = UUID()
        let sugID2 = UUID()

        let suggestion1 = makeSuggestion(
            id: sugID1,
            location: firstLoc,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let suggestion2 = makeSuggestion(
            id: sugID2,
            location: secondLoc,
            original: "adalah adalah",
            replacement: "adalah"
        )

        let initialSnapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(originalText),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(),
            editorSuggestions: [suggestion1, suggestion2]
        )
        XCTAssertTrue(viewModel.restoreAnalysisSnapshot(initialSnapshot, documentText: originalText))
        XCTAssertEqual(viewModel.editorSuggestions.count, 2)

        // Accept first suggestion
        let updatedText = (originalText as NSString).replacingCharacters(
            in: NSRange(location: firstLoc, length: "wajib untuk".utf16.count),
            with: "wajib"
        )
        XCTAssertTrue(
            viewModel.reconcileAfterAccept(
                suggestion1,
                previousText: originalText,
                updatedText: updatedText
            )
        )

        // Only suggestion 1 accepted and removed; suggestion 2 retained with shifted range
        XCTAssertEqual(viewModel.editorSuggestions.count, 1)
        let remaining = viewModel.editorSuggestions[0]
        XCTAssertEqual(remaining.id, sugID2)
        let lengthDelta = "wajib".utf16.count - "wajib untuk".utf16.count // -6
        XCTAssertEqual(remaining.sourceRange.location, secondLoc + lengthDelta)
        XCTAssertEqual(
            (updatedText as NSString).substring(with: remaining.sourceRange),
            "adalah adalah"
        )

        // Snapshot is eligible and persisted correctly with remaining suggestion and new SHA
        let persistedSnapshot = try XCTUnwrap(viewModel.makeAnalysisSnapshot(documentText: updatedText))
        XCTAssertEqual(persistedSnapshot.editorSuggestions.count, 1)
        XCTAssertEqual(persistedSnapshot.editorSuggestions[0].id, sugID2)
        XCTAssertEqual(persistedSnapshot.analyzedContentSHA256, DocumentFingerprinting.contentSHA256(updatedText))

        // Restoring the persisted snapshot on the updated text succeeds
        let restoredVM = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        XCTAssertTrue(restoredVM.restoreAnalysisSnapshot(persistedSnapshot, documentText: updatedText))
        XCTAssertEqual(restoredVM.editorSuggestions.count, 1)
        XCTAssertEqual(restoredVM.editorSuggestions[0].id, sugID2)
    }

    func testSnapshotVersionFourDecodesButCannotBeRestoredAsActiveResults() throws {
        let document = "wajib untuk."
        let viewModel = AIConnectorViewModel(
            service: QwenSuggestionService(),
            dictionaryStore: LegalDictionaryStore(entries: [])
        )
        let oldSuggestion = makeSuggestion(
            location: 0,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let oldSnapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(document),
            analysisProfile: viewModel.currentAnalysisProfile,
            completedAt: Date(timeIntervalSince1970: 1),
            editorSuggestions: [oldSuggestion],
            version: 4
        )
        let encoded = try JSONEncoder().encode(oldSnapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "reviewAnnotations")
        object.removeValue(forKey: "definitionMatchAnnotations")
        object.removeValue(forKey: "ignoredReviewItemIDs")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DocumentAnalysisSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.version, 4)
        XCTAssertFalse(
            decoded.isCompatible(
                with: document,
                profile: viewModel.currentAnalysisProfile
            )
        )
        XCTAssertFalse(viewModel.restoreAnalysisSnapshot(decoded, documentText: document))
        XCTAssertTrue(viewModel.reviewItems.isEmpty)
    }

    func testPlaceholderAnnotationsRemainReadOnly() {
        let annotation = EditorReviewAnnotation(
            id: UUID(),
            sourceRange: NSRange(location: 0, length: 5),
            original: "Pihak",
            category: .clarity,
            kind: .legalRisk,
            reason: "Placeholder Phase 5.",
            origin: .deterministic
        )

        let item = EditorReviewItem.annotation(annotation)
        XCTAssertTrue(item.isReadOnly)
        XCTAssertTrue(annotation.isReadOnlyDiagnostic)
    }

    private func parsedReview(original: String) -> AIParsedReview {
        AIParsedReview(
            status: .suggestion,
            category: .grammar,
            original: original,
            replacement: "wajib",
            glossaryID: nil,
            reason: "Perbaikan lokal."
        )
    }

    private func makeCandidate(
        id: String,
        location: Int,
        length: Int
    ) -> AIConnectorReviewCandidate {
        AIConnectorReviewCandidate(
            id: id,
            segmentID: 1,
            original: "wajib untuk",
            replacement: "wajib",
            category: .grammar,
            priority: 10,
            ruleID: "test-rule",
            glossaryMatch: nil,
            explanation: "Perbaikan lokal.",
            confidenceTier: .deterministicRule,
            languageScoreEvidence: nil,
            evidence: AIConnectorCandidateEvidence(
                tier: .exactRule,
                sourceLocation: location,
                spanLength: length,
                rulePriority: 10,
                sourceRank: 0,
                matchedDefinitionTokenCount: 0,
                semanticScore: nil,
                languageScoreDelta: nil,
                isDirectTermMatch: false,
                hasSourceAnchor: false,
                isUniqueSpan: true
            )
        )
    }

    private func makeSuggestion(
        id: UUID = UUID(),
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
            reason: "Perbaikan lokal.",
            origin: .deterministic
        )
    }

    private func makeSegment(id: Int = 1, target: String) -> AIReviewSegment {
        AIReviewSegment(
            id: id,
            sourceLocation: 0,
            sourceLength: target.utf16.count,
            targetText: target,
            previousContext: nil,
            nextContext: nil
        )
    }

    private func makeDefinitionEntry() -> LegalDictionaryEntry {
        LegalDictionaryEntry(
            id: "data-pribadi",
            term: "Data Pribadi",
            definition: "Data Pribadi adalah data tentang orang perseorangan yang teridentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: URL(string: "https://example.invalid/detail"),
            officialDocumentURL: URL(string: "https://example.invalid/official"),
            referenceID: "ref-data-pribadi",
            authority: .verified,
            corpusVersion: "phase3-test",
            applicabilityStatus: .inForce,
            sourcePassageID: "passage-data-pribadi",
            articleLocator: "Pasal 1 angka 1",
            isActionable: true
        )
    }

    private func makeDefinitionAssessment(
        segment: AIReviewSegment,
        entry: LegalDictionaryEntry,
        statementText: String,
        alignment: AIConnectorDefinitionAlignment
    ) -> AIConnectorDefinitionAssessment {
        let match = LegalDictionaryMatch(
            entry: entry,
            score: 1,
            rank: 1,
            matchedDefinitionTokenCount: 5,
            isDirectTermMatch: true,
            retrievalOrigin: .exact
        )
        let candidate = AIConnectorDefinitionCandidate(
            id: "D1",
            match: match,
            statementText: statementText,
            detection: .explicitPattern
        )
        return AIConnectorDefinitionAssessment(
            segment: segment,
            term: entry.term,
            statementText: statementText,
            candidate: candidate,
            candidateCount: 1,
            detection: .explicitPattern,
            classification: .explicitDefinition,
            alignment: alignment,
            reason: "Definisi dibandingkan dengan evidence corpus.",
            origin: .qwen,
            modelReviewed: true,
            retrievalOrigin: .exact,
            semanticScore: 1,
            requiresHumanReview: true
        )
    }
}
