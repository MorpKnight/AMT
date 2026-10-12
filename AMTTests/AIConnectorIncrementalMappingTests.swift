import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorIncrementalMappingTests: XCTestCase {
    func testLocalFinalReplacementEmptyAndSkippedMatchFrozenMapper() async throws {
        let text = "😀 memasukan arsip.\nmemasukan laporan.\nData adalah informasi."
        let segments = makeSegments(text)
        let vm = makeVM(text)
        for segment in segments.prefix(2) {
            vm.mappingBenchmarkApplyLocal(.init(segment: segment, reviews: [review(segment)]))
            assertReference(vm, text)
        }
        let ids = vm.editorSuggestions.map(\.id)
        for segment in segments.prefix(2).reversed() {
            await vm.mappingBenchmarkApplyFinal(.init(segment: segment, reviews: [review(segment, reason: "Updated")]))
            assertReference(vm, text)
        }
        XCTAssertEqual(vm.editorSuggestions.map(\.id), ids)
        XCTAssertEqual(vm.processedSegmentCount, 2)
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[2], definitionAssessment: assessment(segments[2], .needsReview)))
        assertReference(vm, text)
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[2], definitionAssessment: assessment(segments[2], .matches)))
        assertReference(vm, text)
        XCTAssertTrue(vm.reviewAnnotations.isEmpty)
        XCTAssertEqual(vm.definitionMatchAnnotations.count, 1)
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[2], definitionAssessment: assessment(segments[2], .notApplicable)))
        assertReference(vm, text)
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[0], skipped: true))
        assertReference(vm, text)
        XCTAssertEqual(vm.editorSuggestions.count, 2)
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[1]))
        assertReference(vm, text)
        XCTAssertEqual(vm.editorSuggestions.count, 1)
    }

    func testRepeatedOriginalsExplicitAnchorsInvalidAnchorAndLimitRemainEquivalent() async {
        let text = "😀 memasukan memasukan memasukan memasukan."
        let segment = makeSegments(text)[0]
        let ns = text as NSString
        var offset = 0
        var reviews: [AIValidatedReview] = []
        for index in 0..<4 {
            let range = ns.range(of: "memasukan", range: NSRange(location: offset, length: ns.length-offset))
            offset = NSMaxRange(range)
            reviews.append(review(segment, reason: "\(index)", anchor: AIConnectorReviewAnchor(segmentID: segment.id, sourceRange: range, original: "memasukan")))
        }
        let vm = makeVM(text)
        vm.mappingBenchmarkApplyLocal(.init(segment: segment, reviews: reviews))
        assertReference(vm, text)
        XCTAssertEqual(vm.editorSuggestions.count, 3, "Preserve the existing mapper limit in this refactor.")
        let invalid = review(segment, anchor: AIConnectorReviewAnchor(segmentID: segment.id, sourceRange: NSRange(location: 1000, length: 9), original: "memasukan"))
        await vm.mappingBenchmarkApplyFinal(.init(segment: segment, reviews: [invalid]))
        assertReference(vm, text)
        XCTAssertTrue(vm.editorSuggestions.isEmpty)
    }

    func testOverlappingSegmentsAndTiesUseReferenceFallback() async {
        let text = "memasukan arsip."
        let first = makeSegments(text)[0]
        let second = AIReviewSegment(id: 2, sourceLocation: 0, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
        let vm = makeVM(text)
        vm.mappingBenchmarkApplyLocal(.init(segment: first, reviews: [review(first)]))
        vm.mappingBenchmarkApplyLocal(.init(segment: second, reviews: [review(second)]))
        assertReference(vm, text)
        XCTAssertEqual(vm.editorSuggestions.count, 1)
        await vm.mappingBenchmarkApplyFinal(.init(segment: first, reviews: [review(first, status: .needsReview)], definitionAssessment: assessment(first, .needsReview)))
        assertReference(vm, text)
        XCTAssertGreaterThan(vm.mappingBenchmarkMetrics.fullRebuildCount, 1)
    }

    func testInstancesAndResetDoNotRetainMappings() async {
        let text = "memasukan arsip."
        let segment = makeSegments(text)[0]
        let first = makeVM(text); let second = makeVM(text)
        first.mappingBenchmarkApplyLocal(.init(segment: segment, reviews: [review(segment)]))
        XCTAssertTrue(second.editorSuggestions.isEmpty)
        let oldID = first.editorSuggestions.first?.id
        first.mappingBenchmarkReset(documentText: "Pembukaan 😀.\n" + text)
        XCTAssertTrue(first.editorSuggestions.isEmpty)
        let moved = AIReviewSegment(id: 1, sourceLocation: "Pembukaan 😀.\n".utf16.count, sourceLength: text.utf16.count, targetText: text, previousContext: nil, nextContext: nil)
        await first.mappingBenchmarkApplyFinal(.init(segment: moved, reviews: [review(moved)]))
        assertReference(first, "Pembukaan 😀.\n" + text)
        XCTAssertNotEqual(first.editorSuggestions.first?.id, oldID)
    }

    func testNormalReplayRemapsOnlyChangedSegments() async {
        let text = (1...20).map { "Bagian \($0) memasukan arsip." }.joined(separator: "\n")
        let vm = makeVM(text)
        for segment in makeSegments(text) {
            vm.mappingBenchmarkApplyLocal(.init(segment: segment, reviews: [review(segment)]))
            await vm.mappingBenchmarkApplyFinal(.init(segment: segment, reviews: [review(segment)]))
            assertReference(vm, text)
        }
        XCTAssertLessThanOrEqual(vm.mappingBenchmarkMetrics.fullRebuildCount, 1)
        XCTAssertEqual(vm.mappingBenchmarkMetrics.remappedSegmentCount, 40)
        XCTAssertLessThanOrEqual(vm.mappingBenchmarkMetrics.findingMappingCount, 1)
    }

    func testFindingUpdatesKeepSeparateOrderAndDoNotRemapReviews() {
        let text = "Data adalah informasi.\nmemasukan arsip."
        let segments = makeSegments(text)
        let reviews = [review(segments[1])]
        let assessments = [assessment(segments[0], .needsReview)]
        let state = AIConnectorEditorMappingState()
        state.rebuild(reviews: reviews, assessments: assessments, findings: [], documentText: text)
        let before = state.diagnostics
        let finding = AIConnectorDocumentFinding(ruleID: "test", kind: .internalReference,
            sourceRange: NSRange(location: 0, length: 4), original: "Data", title: "Reference", reason: "Inspect", origin: .deterministic)
        state.updateFindings([finding], reviews: reviews, assessments: assessments, documentText: text)
        XCTAssertEqual(state.suggestions, LegacyEditorSuggestionMapper.make(reviews: reviews, documentText: text))
        XCTAssertEqual(state.annotations, LegacyEditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: text) + LegacyEditorSuggestionMapper.makeFindingAnnotations(findings: [finding], documentText: text))
        XCTAssertEqual(state.annotations.last?.id, finding.id, "Findings remain the separate trailing group even at an earlier location.")
        XCTAssertEqual(state.diagnostics.remappedSegmentCount, before.remappedSegmentCount)
        XCTAssertEqual(state.diagnostics.findingMappingCount, before.findingMappingCount + 1)
        state.updateFindings([], reviews: reviews, assessments: assessments, documentText: text)
        XCTAssertEqual(state.annotations, LegacyEditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: text))
    }

    func testContextOverloadsPreserveAllPublicMapperResults() {
        let text = "😀 Data adalah informasi.\nmemasukan arsip."
        let segments = makeSegments(text)
        let reviews = [review(segments[1], status: .needsReview)]
        let assessments = [assessment(segments[0], .needsReview)]
        let context = EditorSuggestionMappingContext(text)
        XCTAssertEqual(EditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: context), LegacyEditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: text))
        XCTAssertEqual(EditorSuggestionMapper.makeDefinitionSuggestions(assessments: assessments, documentText: context), LegacyEditorSuggestionMapper.makeDefinitionSuggestions(assessments: assessments, documentText: text))
        XCTAssertEqual(EditorSuggestionMapper.makeDefinitionDebugSuggestions(assessments: assessments, documentText: context), LegacyEditorSuggestionMapper.makeDefinitionDebugSuggestions(assessments: assessments, documentText: text))
        let range = NSRange(location: 3, length: 4)
        let actual = EditorSuggestionMapper.extractSurroundingContext(range: range, in: context)
        let expected = LegacyEditorSuggestionMapper.extractSurroundingContext(range: range, in: text)
        XCTAssertEqual(actual.prefix, expected.prefix); XCTAssertEqual(actual.suffix, expected.suffix)
    }

    func testOccurrenceIndexDoesNotRequireEditorMappingPublication() {
        let state = AIConnectorEditorMappingState()
        let segment = makeSegments("memasukan arsip.")[0]
        let old = review(segment)
        state.recordReviews(for: segment.id, reviews: [old])
        let changed = review(segment, reason: "Updated")
        let preserved = state.preservingOccurrenceIDs([changed], existingReviews: [old])
        XCTAssertEqual(preserved.first?.id, old.id)
        XCTAssertEqual(preserved.first?.reason, "Updated")
        state.invalidate()
        XCTAssertEqual(state.preservingOccurrenceIDs([changed], existingReviews: []).first?.id, changed.id)
    }

    func testMalformedSegmentBoundsTakeFullMappingFallback() async {
        let text = "memasukan arsip."
        let short = AIReviewSegment(id: 1, sourceLocation: 0, sourceLength: 1, targetText: text, previousContext: nil, nextContext: nil)
        let vm = makeVM(text)
        vm.mappingBenchmarkApplyLocal(.init(segment: short, reviews: [review(short)]))
        await vm.mappingBenchmarkApplyFinal(.init(segment: short, reviews: [review(short)]))
        assertReference(vm, text)
        XCTAssertEqual(vm.mappingBenchmarkMetrics.fullRebuildCount, 2)
    }

    func testInconsistentResultSegmentUsesFullReferenceFallback() async {
        let text = "memasukan arsip.\nmemasukan laporan."
        let segments = makeSegments(text)
        let vm = makeVM(text)
        vm.mappingBenchmarkApplyLocal(.init(segment: segments[0], reviews: [review(segments[0])]))
        await vm.mappingBenchmarkApplyFinal(.init(segment: segments[0], reviews: [review(segments[1])]))
        assertReference(vm, text)
        XCTAssertEqual(vm.editorSuggestions.count, 1)
        XCTAssertEqual(vm.editorSuggestions.first?.sourceRange.location, segments[1].sourceLocation)
        XCTAssertEqual(vm.mappingBenchmarkMetrics.fullRebuildCount, 2)
    }

    private func makeVM(_ text: String) -> AIConnectorViewModel {
        let vm = AIConnectorViewModel(service: QwenSuggestionService(), dictionaryStore: LegalDictionaryStore(entries: []))
        vm.mappingBenchmarkReset(documentText: text)
        return vm
    }

    private func makeSegments(_ text: String) -> [AIReviewSegment] {
        var offset = 0
        return text.components(separatedBy: "\n").enumerated().map { index, line in
            defer { offset += line.utf16.count + 1 }
            return AIReviewSegment(id: index+1, sourceLocation: offset, sourceLength: line.utf16.count, targetText: line, previousContext: nil, nextContext: nil)
        }
    }

    private func review(_ segment: AIReviewSegment, status: AIReviewStatus = .suggestion, reason: String = "Initial", anchor: AIConnectorReviewAnchor? = nil) -> AIValidatedReview {
        AIValidatedReview(segment: segment, status: status, category: .spelling, original: "memasukan", replacement: status == .suggestion ? "memasukkan" : nil, reason: reason, glossaryMatch: nil, origin: .deterministic, sourceAnchor: anchor)
    }

    private func assessment(_ segment: AIReviewSegment, _ alignment: AIConnectorDefinitionAlignment) -> AIConnectorDefinitionAssessment {
        AIConnectorDefinitionAssessment(segment: segment, term: "Data", statementText: segment.targetText, candidate: nil, candidateCount: 0, detection: .explicitPattern, classification: alignment == .notApplicable ? .notDefinition : .explicitDefinition, alignment: alignment, reason: "Definition", origin: .deterministic, modelReviewed: false, retrievalOrigin: nil, semanticScore: nil, requiresHumanReview: true)
    }

    private func assertReference(_ vm: AIConnectorViewModel, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vm.editorSuggestions, LegacyEditorSuggestionMapper.make(reviews: vm.validatedReviews, definitionAssessments: vm.definitionAssessments, documentText: text), file: file, line: line)
        XCTAssertEqual(vm.reviewAnnotations, LegacyEditorSuggestionMapper.makeReviewAnnotations(reviews: vm.validatedReviews, definitionAssessments: vm.definitionAssessments, documentText: text) + LegacyEditorSuggestionMapper.makeFindingAnnotations(findings: vm.documentFindings, documentText: text), file: file, line: line)
        XCTAssertEqual(vm.definitionMatchAnnotations, LegacyEditorSuggestionMapper.makeDefinitionMatchAnnotations(assessments: vm.definitionAssessments, documentText: text), file: file, line: line)
    }
}
