import Foundation

/// Derived, per-document mapping. Raw reviews remain owned by the ViewModel.
/// Cross-segment overlap uses the full mapper because its acceptance order is global.
@MainActor
final class AIConnectorEditorMappingState {
    private struct SegmentMapping {
        let suggestions: [EditorSuggestion]
        let annotations: [EditorReviewAnnotation]
        let matches: [EditorReviewAnnotation]
    }
    private struct OccurrenceKey: Hashable {
        let anchor: AIConnectorReviewAnchor?
        let status: AIReviewStatus
        let category: AIReviewCategory
        let original: String?
        let replacement: String?
        init(_ review: AIValidatedReview) {
            anchor = review.sourceAnchor; status = review.status; category = review.category
            original = review.original; replacement = review.replacement
        }
    }

    private var context: EditorSuggestionMappingContext?
    private var mappings: [Int: SegmentMapping] = [:]
    private var segments: [Int: AIReviewSegment] = [:]
    private var occurrences: [Int: [OccurrenceKey: UUID]] = [:]
    private var occurrenceIndexReady = false
    private var findings: [AIConnectorDocumentFinding] = []
    private var findingAnnotations: [EditorReviewAnnotation] = []
    private var permitsIncrementalMapping = true
    private(set) var suggestions: [EditorSuggestion] = []
    private(set) var annotations: [EditorReviewAnnotation] = []
    private(set) var definitionMatches: [EditorReviewAnnotation] = []
#if DEBUG
    private(set) var diagnostics = AIConnectorMappingBenchmarkMetrics()
#endif

    func invalidate() {
        context = nil; mappings = [:]; segments = [:]; occurrences = [:]
        occurrenceIndexReady = false; findings = []; findingAnnotations = []
        suggestions = []; annotations = []; definitionMatches = []
        permitsIncrementalMapping = true
    }

    func preservingOccurrenceIDs(_ reviews: [AIValidatedReview], existingReviews: [AIValidatedReview]) -> [AIValidatedReview] {
        if !occurrenceIndexReady { indexOccurrences(existingReviews) }
        return reviews.map { review in
            guard let id = occurrences[review.segment.id]?[OccurrenceKey(review)] else { return review }
            return AIValidatedReview(id: id, segment: review.segment, status: review.status, category: review.category,
                                     original: review.original, replacement: review.replacement, reason: review.reason,
                                     glossaryMatch: review.glossaryMatch, origin: review.origin, ruleID: review.ruleID,
                                     sourceAnchor: review.sourceAnchor)
        }
    }

    func rebuild(reviews: [AIValidatedReview], assessments: [AIConnectorDefinitionAssessment], findings: [AIConnectorDocumentFinding], documentText: String) {
        let context = self.context?.text == documentText ? self.context : nil
        let prepared = context ?? EditorSuggestionMappingContext(documentText)
        self.context = prepared
        let reviewsBySegment = Dictionary(grouping: reviews, by: { $0.segment.id })
        let assessmentsBySegment = Dictionary(grouping: assessments, by: { $0.segment.id })
        mappings = [:]; segments = [:]
        permitsIncrementalMapping = true
        for segment in reviews.map(\.segment) + assessments.map(\.segment) {
            if let previous = segments[segment.id], previous != segment { permitsIncrementalMapping = false }
            segments[segment.id] = segment
        }
        if !segments.values.allSatisfy({ isCanonical($0, in: prepared) }) { permitsIncrementalMapping = false }
        let orderedSegments = segments.values.sorted { $0.sourceLocation < $1.sourceLocation }
        for pair in zip(orderedSegments, orderedSegments.dropFirst()) {
            if NSIntersectionRange(range(pair.0), range(pair.1)).length > 0 { permitsIncrementalMapping = false }
        }
        for id in segments.keys {
            mappings[id] = map(reviews: reviewsBySegment[id] ?? [], assessments: assessmentsBySegment[id] ?? [], context: prepared)
        }
        indexOccurrences(reviews)
        self.findings = findings
        findingAnnotations = EditorSuggestionMapper.makeFindingAnnotations(findings: findings, documentText: prepared)
        // Full mapping preserves global acceptance order, including malformed or overlapping inputs.
        if permitsIncrementalMapping {
            publish()
        } else {
            suggestions = EditorSuggestionMapper.make(reviews: reviews, definitionAssessments: assessments, documentText: prepared)
            annotations = EditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: prepared) + findingAnnotations
            definitionMatches = EditorSuggestionMapper.makeDefinitionMatchAnnotations(assessments: assessments, documentText: prepared)
        }
#if DEBUG
        diagnostics.fullRebuildCount += 1
        diagnostics.remappedSegmentCount += segments.count
        diagnostics.findingMappingCount += 1
#endif
    }

    func updateSegment(_ segment: AIReviewSegment, reviews: [AIValidatedReview], assessments: [AIConnectorDefinitionAssessment], allReviews: [AIValidatedReview], allAssessments: [AIConnectorDefinitionAssessment], findings: [AIConnectorDocumentFinding], documentText: String) {
        guard let context, context.text == documentText, permitsIncrementalMapping, isCanonical(segment, in: context),
              reviews.allSatisfy({ $0.segment == segment }), assessments.allSatisfy({ $0.segment == segment }),
              !segments.values.contains(where: { $0.id != segment.id && NSIntersectionRange(range($0), range(segment)).length > 0 }) else {
            rebuild(reviews: allReviews, assessments: allAssessments, findings: findings, documentText: documentText)
            return
        }
        if reviews.isEmpty && assessments.isEmpty {
            mappings.removeValue(forKey: segment.id); segments.removeValue(forKey: segment.id)
        } else {
            mappings[segment.id] = map(reviews: reviews, assessments: assessments, context: context)
            segments[segment.id] = segment
        }
        occurrences[segment.id] = occurrenceIDs(reviews)
        updateFindingAnnotations(findings, context: context)
        publish()
#if DEBUG
        diagnostics.remappedSegmentCount += 1
#endif
    }

    func updateFindings(_ findings: [AIConnectorDocumentFinding], reviews: [AIValidatedReview], assessments: [AIConnectorDefinitionAssessment], documentText: String) {
        guard let context, context.text == documentText else {
            rebuild(reviews: reviews, assessments: assessments, findings: findings, documentText: documentText)
            return
        }
        updateFindingAnnotations(findings, context: context)
        // Retain the already-resolved global review order even in fallback mode.
        if permitsIncrementalMapping { publish() }
        else {
            annotations = EditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: context) + findingAnnotations
        }
    }

    private func map(reviews: [AIValidatedReview], assessments: [AIConnectorDefinitionAssessment], context: EditorSuggestionMappingContext) -> SegmentMapping {
        SegmentMapping(suggestions: EditorSuggestionMapper.make(reviews: reviews, definitionAssessments: assessments, documentText: context),
                       annotations: EditorSuggestionMapper.makeReviewAnnotations(reviews: reviews, definitionAssessments: assessments, documentText: context),
                       matches: EditorSuggestionMapper.makeDefinitionMatchAnnotations(assessments: assessments, documentText: context))
    }

    private func publish() {
        suggestions = mappings.values.flatMap(\.suggestions).sorted { sourceOrder($0.sourceRange, $1.sourceRange) }
        annotations = mappings.values.flatMap(\.annotations).sorted { sourceOrder($0.sourceRange, $1.sourceRange) } + findingAnnotations
        definitionMatches = mappings.values.flatMap(\.matches).sorted { sourceOrder($0.sourceRange, $1.sourceRange) }
    }

    private func updateFindingAnnotations(_ findings: [AIConnectorDocumentFinding], context: EditorSuggestionMappingContext) {
        guard self.findings != findings else { return }
        self.findings = findings
        findingAnnotations = EditorSuggestionMapper.makeFindingAnnotations(findings: findings, documentText: context)
#if DEBUG
        diagnostics.findingMappingCount += 1
#endif
    }

    func recordReviews(for segmentID: Int, reviews: [AIValidatedReview]) {
        occurrences[segmentID] = occurrenceIDs(reviews)
        occurrenceIndexReady = true
    }

    private func isCanonical(_ segment: AIReviewSegment, in context: EditorSuggestionMappingContext) -> Bool {
        segment.sourceLocation >= 0 && segment.sourceLocation <= context.length
            && segment.sourceLength >= 0 && segment.sourceLength <= context.length - segment.sourceLocation
            && segment.sourceLength == segment.targetText.utf16.count
    }

    private func range(_ segment: AIReviewSegment) -> NSRange { NSRange(location: segment.sourceLocation, length: segment.sourceLength) }
    private func sourceOrder(_ lhs: NSRange, _ rhs: NSRange) -> Bool { lhs.location == rhs.location ? lhs.length < rhs.length : lhs.location < rhs.location }
    private func occurrenceIDs(_ reviews: [AIValidatedReview]) -> [OccurrenceKey: UUID] {
        var ids: [OccurrenceKey: UUID] = [:]
        for review in reviews where ids[OccurrenceKey(review)] == nil { ids[OccurrenceKey(review)] = review.id }
        return ids
    }
    private func indexOccurrences(_ reviews: [AIValidatedReview]) {
        occurrences = Dictionary(grouping: reviews, by: { $0.segment.id }).mapValues(occurrenceIDs)
        occurrenceIndexReady = true
    }
}
