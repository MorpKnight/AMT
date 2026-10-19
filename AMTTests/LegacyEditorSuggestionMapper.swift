import CryptoKit
import Foundation
@testable import AMT

// Frozen test-only reference from ade8ce5; production never calls this copy.
@MainActor
enum LegacyEditorSuggestionMapper {
    static func make(
        reviews: [AIValidatedReview],
        documentText: String
    ) -> [EditorSuggestion] {
        make(
            reviews: reviews,
            definitionAssessments: [],
            documentText: documentText
        )
    }

    static func make(
        reviews: [AIValidatedReview],
        definitionAssessments: [AIConnectorDefinitionAssessment],
        documentText: String
    ) -> [EditorSuggestion] {
        // Definition assessments are deliberately not mapped into actionable
        // editor suggestions. They use the separate read-only diagnostic
        // layer below so the application never offers an automatic legal
        // rewrite based on a definition mismatch.
        _ = definitionAssessments
        return makeLanguageSuggestions(
            reviews: reviews,
            documentText: documentText
        )
    }

    /// Maps non-actionable reviews to the read-only layer shown in the normal
    /// editor. Definition matches are kept separate so the UI can opt into
    /// the low-noise green annotations without changing the default review.
    static func makeReviewAnnotations(
        reviews: [AIValidatedReview],
        definitionAssessments: [AIConnectorDefinitionAssessment],
        documentText: String
    ) -> [EditorReviewAnnotation] {
        let reviewAnnotations = reviews.compactMap {
            makeReviewAnnotation(for: $0, documentText: documentText)
        }
        let definitionAnnotations = makeDefinitionAnnotations(
            assessments: definitionAssessments,
            includeMatches: false,
            documentText: documentText
        )
        return (reviewAnnotations + definitionAnnotations).sorted(by: sourceOrder)
    }

    /// Maps Phase 5 document findings to the read-only annotation boundary.
    /// The related evidence remains attached to the annotation so the popover
    /// can navigate to the comparison clause without losing the primary item.
    static func makeFindingAnnotations(
        findings: [AIConnectorDocumentFinding],
        documentText: String
    ) -> [EditorReviewAnnotation] {
        findings.compactMap { finding in
            guard finding.isAnchored(to: documentText) else { return nil }
            let (prefixContext, suffixContext) = extractSurroundingContext(
                range: finding.sourceRange,
                in: documentText
            )
            let kind: EditorReviewAnnotationKind = finding.kind == .definedTerm
                ? .definedTerm
                : .legalRisk
            let category: AIReviewCategory = finding.kind == .definedTerm
                ? .terminology
                : .clarity
            return EditorReviewAnnotation(
                id: finding.id,
                sourceRange: finding.sourceRange,
                original: finding.original,
                category: category,
                kind: kind,
                title: finding.title,
                reason: finding.reason,
                origin: finding.origin,
                prefixContext: prefixContext,
                suffixContext: suffixContext,
                relatedEvidence: finding.relatedEvidence
            )
        }
        .sorted(by: sourceOrder)
    }

    static func makeDefinitionMatchAnnotations(
        assessments: [AIConnectorDefinitionAssessment],
        documentText: String
    ) -> [EditorReviewAnnotation] {
        makeDefinitionAnnotations(
            assessments: assessments,
            includeMatches: true,
            documentText: documentText
        )
        .filter { $0.definitionDiagnosticStatus == .matches }
        .sorted(by: sourceOrder)
    }

    private static func makeReviewAnnotation(
        for review: AIValidatedReview,
        documentText: String
    ) -> EditorReviewAnnotation? {
        guard review.status == .needsReview,
              let original = review.original,
              !original.isEmpty,
              let localRange = reviewLocalRange(for: review),
              let absoluteRange = absoluteRange(
                  localRange: localRange,
                  segment: review.segment,
                  documentText: documentText
              ) else {
            return nil
        }

        let (prefixContext, suffixContext) = extractSurroundingContext(
            range: absoluteRange,
            in: documentText
        )
        return EditorReviewAnnotation(
            id: review.id,
            sourceRange: absoluteRange,
            original: original,
            category: review.category,
            kind: .needsReview,
            reason: review.reason,
            origin: review.origin,
            reference: reference(from: review),
            prefixContext: prefixContext,
            suffixContext: suffixContext
        )
    }

    private static func makeDefinitionAnnotations(
        assessments: [AIConnectorDefinitionAssessment],
        includeMatches: Bool,
        documentText: String
    ) -> [EditorReviewAnnotation] {
        let documentLength = documentText.utf16.count

        return assessments.compactMap { assessment in
            guard let diagnosticStatus = EditorDefinitionDiagnosticStatus(
                legacyAlignment: assessment.alignment
            ),
                  assessment.classification != .notDefinition,
                  (includeMatches || diagnosticStatus != .matches),
                  let localRange = definitionDebugSourceRange(for: assessment),
                  localRange.location >= 0 else {
                return nil
            }

            let absoluteRange = NSRange(
                location: assessment.segment.sourceLocation + localRange.location,
                length: localRange.length
            )
            guard absoluteRange.location >= 0,
                  NSMaxRange(absoluteRange) <= documentLength,
                  absoluteRange.length > 0 else {
                return nil
            }

            let original = (documentText as NSString).substring(with: absoluteRange)
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let reference = assessment.candidate.map {
                definitionReference(
                    for: $0,
                    sourceDefinition: sourceDefinitionBody(
                        from: $0.sourceDefinition,
                        term: $0.term
                    )
                )
            }
            let (prefixContext, suffixContext) = extractSurroundingContext(
                range: absoluteRange,
                in: documentText
            )

            return EditorReviewAnnotation(
                id: stableDefinitionAnnotationID(for: assessment),
                sourceRange: absoluteRange,
                original: original,
                category: .terminology,
                kind: .definition,
                definitionDiagnosticStatus: diagnosticStatus,
                definitionTerm: assessment.term ?? assessment.candidate?.term,
                reason: assessment.reason,
                origin: assessment.origin,
                reference: reference,
                prefixContext: prefixContext,
                suffixContext: suffixContext
            )
        }
    }

    private static func reviewLocalRange(for review: AIValidatedReview) -> NSRange? {
        guard let original = review.original else { return nil }
        if let anchor = review.sourceAnchor {
            guard anchor.isValid(for: review.segment, original: original) else {
                return nil
            }
            return anchor.range
        }
        return uniqueRange(of: original, in: review.segment.targetText)
    }

    private static func absoluteRange(
        localRange: NSRange,
        segment: AIReviewSegment,
        documentText: String
    ) -> NSRange? {
        let absoluteRange = NSRange(
            location: segment.sourceLocation + localRange.location,
            length: localRange.length
        )
        guard absoluteRange.location >= 0,
              absoluteRange.length > 0,
              NSMaxRange(absoluteRange) <= documentText.utf16.count else {
            return nil
        }
        return absoluteRange
    }

    static func makeDefinitionSuggestions(
        assessments: [AIConnectorDefinitionAssessment],
        documentText: String
    ) -> [EditorSuggestion] {
        let documentLength = documentText.utf16.count

        return assessments.compactMap { assessment in
            guard assessment.alignment == .mismatch,
                  assessment.classification == .explicitDefinition
                    || assessment.classification == .implicitDefinition,
                  let candidate = assessment.candidate,
                  let localRange = definitionSourceRange(for: assessment),
                  localRange.location >= 0 else {
                return nil
            }

            let absoluteRange = NSRange(
                location: assessment.segment.sourceLocation + localRange.location,
                length: localRange.length
            )
            guard absoluteRange.location >= 0,
                  NSMaxRange(absoluteRange) <= documentLength,
                  absoluteRange.length > 0 else {
                return nil
            }

            let original = (documentText as NSString).substring(with: absoluteRange)
            let replacement = definitionReplacement(
                for: original,
                sourceDefinition: candidate.sourceDefinition,
                term: candidate.term
            )
            guard let replacement,
                  !replacement.isEmpty,
                  replacement != original else {
                return nil
            }

            let (prefixContext, suffixContext) = extractSurroundingContext(
                range: absoluteRange,
                in: documentText
            )

            return EditorSuggestion(
                id: stableDefinitionSuggestionID(for: assessment),
                sourceRange: absoluteRange,
                original: original,
                replacement: replacement,
                category: .terminology,
                kind: .definition,
                definitionDiagnosticStatus: .mismatch,
                definitionTerm: candidate.term,
                reason: assessment.reason,
                origin: assessment.origin,
                reference: definitionReference(
                    for: candidate,
                    sourceDefinition: replacement
                ),
                prefixContext: prefixContext,
                suffixContext: suffixContext
            )
        }
        .sorted { lhs, rhs in
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.sourceRange.length < rhs.sourceRange.length
        }
    }

    /// Creates read-only annotations for definition findings. These are
    /// intentionally separate from normal suggestions so they can be shown
    /// only in debug mode and can never be accepted as an edit.
    static func makeDefinitionDebugSuggestions(
        assessments: [AIConnectorDefinitionAssessment],
        documentText: String
    ) -> [EditorSuggestion] {
        let documentLength = documentText.utf16.count

        return assessments.compactMap { assessment in
            guard let diagnosticStatus = EditorDefinitionDiagnosticStatus(
                legacyAlignment: assessment.alignment
            ),
                  assessment.classification != .notDefinition,
                  let localRange = definitionDebugSourceRange(for: assessment),
                  localRange.location >= 0 else {
                return nil
            }

            let absoluteRange = NSRange(
                location: assessment.segment.sourceLocation + localRange.location,
                length: localRange.length
            )
            guard absoluteRange.location >= 0,
                  NSMaxRange(absoluteRange) <= documentLength,
                  absoluteRange.length > 0 else {
                return nil
            }

            let original = (documentText as NSString).substring(with: absoluteRange)
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let sourceDefinition = assessment.candidate.map {
                sourceDefinitionBody(from: $0.sourceDefinition, term: $0.term)
            }

            let (prefixContext, suffixContext) = extractSurroundingContext(
                range: absoluteRange,
                in: documentText
            )

            return EditorSuggestion(
                id: stableDefinitionSuggestionID(for: assessment),
                sourceRange: absoluteRange,
                original: original,
                replacement: original,
                category: .terminology,
                kind: .definition,
                isDebugOnly: true,
                definitionDiagnosticStatus: diagnosticStatus,
                definitionTerm: assessment.term ?? assessment.candidate?.term,
                reason: assessment.reason,
                origin: assessment.origin,
                reference: assessment.candidate.map {
                    definitionReference(
                        for: $0,
                        sourceDefinition: sourceDefinition ?? $0.sourceDefinition
                    )
                },
                prefixContext: prefixContext,
                suffixContext: suffixContext
            )
        }
        .sorted { lhs, rhs in
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.sourceRange.length < rhs.sourceRange.length
        }
    }

    private static func makeLanguageSuggestions(
        reviews: [AIValidatedReview],
        documentText: String
    ) -> [EditorSuggestion] {
        var mapped: [EditorSuggestion] = []
        var mappedCountBySegment: [Int: Int] = [:]
        let documentLength = documentText.utf16.count

        for review in reviews {
            guard review.status == .suggestion,
                  let original = review.original,
                  let replacement = review.replacement,
                  !original.isEmpty,
                  !replacement.isEmpty,
                  replacement != original,
                  let localRange = reviewLocalRange(for: review),
                  (review.segment.targetText as NSString).substring(with: localRange) == original
            else {
                continue
            }

            let absoluteRange = NSRange(
                location: review.segment.sourceLocation + localRange.location,
                length: localRange.length
            )

            guard absoluteRange.location >= 0,
                  NSMaxRange(absoluteRange) <= documentLength,
                  mappedCountBySegment[review.segment.id, default: 0] < 3,
                  !mapped.contains(where: {
                      NSIntersectionRange($0.sourceRange, absoluteRange).length > 0
                  })
            else {
                continue
            }

            mappedCountBySegment[review.segment.id, default: 0] += 1
            let (prefixContext, suffixContext) = extractSurroundingContext(
                range: absoluteRange,
                in: documentText
            )

            mapped.append(
                EditorSuggestion(
                    id: review.id,
                    sourceRange: absoluteRange,
                    original: original,
                    replacement: replacement,
                    category: review.category,
                    reason: review.reason,
                    origin: review.origin,
                    reference: reference(from: review),
                    prefixContext: prefixContext,
                    suffixContext: suffixContext
                )
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.sourceRange.length < rhs.sourceRange.length
        }
    }

    static func merge(_ suggestions: [EditorSuggestion]) -> [EditorSuggestion] {
        var merged: [EditorSuggestion] = []

        for suggestion in suggestions {
            guard !merged.contains(where: {
                NSIntersectionRange($0.sourceRange, suggestion.sourceRange).length > 0
            }) else {
                continue
            }
            merged.append(suggestion)
        }

        return merged.sorted { lhs, rhs in
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.sourceRange.length < rhs.sourceRange.length
        }
    }

    nonisolated private static func sourceOrder(
        _ lhs: EditorReviewAnnotation,
        _ rhs: EditorReviewAnnotation
    ) -> Bool {
        if lhs.sourceRange.location != rhs.sourceRange.location {
            return lhs.sourceRange.location < rhs.sourceRange.location
        }
        return lhs.sourceRange.length < rhs.sourceRange.length
    }

    private static func definitionSourceRange(
        for assessment: AIConnectorDefinitionAssessment
    ) -> NSRange? {
        let targetText = assessment.segment.targetText
        let statementText = assessment.statementText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !statementText.isEmpty else { return nil }

        if let localRange = uniqueRange(of: statementText, in: targetText),
           localRange.length < targetText.utf16.count {
            return localRange
        }

        // Retrieved candidates can represent an implicit definition whose
        // assessment statement is the whole segment. Only accept it when a
        // legal definition cue gives us an unambiguous replacement span.
        guard let term = assessment.term ?? assessment.candidate?.term else {
            return nil
        }
        return explicitDefinitionBodyRange(for: term, in: targetText)
    }

    private static func definitionDebugSourceRange(
        for assessment: AIConnectorDefinitionAssessment
    ) -> NSRange? {
        let targetText = assessment.segment.targetText
        if let term = assessment.term ?? assessment.candidate?.term,
           let expression = try? NSRegularExpression(
               pattern: explicitDefinitionPattern(for: term)
           ),
           let match = expression.firstMatch(
               in: targetText,
               range: NSRange(location: 0, length: targetText.utf16.count)
           ) {
            return match.range
        }

        let statementText = assessment.statementText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !statementText.isEmpty else { return nil }
        return uniqueRange(of: statementText, in: targetText)
    }

    private static func explicitDefinitionBodyRange(
        for term: String,
        in text: String
    ) -> NSRange? {
        let pattern = explicitDefinitionPattern(for: term, captureBody: true)
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(location: 0, length: text.utf16.count)
              ) else {
            return nil
        }
        return match.range(at: 1)
    }

    private static func explicitDefinitionPattern(
        for term: String,
        captureBody: Bool = false
    ) -> String {
        let escapedTerm = NSRegularExpression.escapedPattern(for: term)
        let body = captureBody ? "(.+)" : ".+"
        return "(?is)(?:yang\\s+dimaksud\\s+dengan\\s+)?"
            + escapedTerm
            + "\\s*[,;:]?\\s*(?:adalah|ialah|merupakan|berarti|"
            + "didefinisikan\\s+sebagai|diartikan\\s+sebagai)\\s+"
            + body + "$"
    }

    private static func definitionReplacement(
        for original: String,
        sourceDefinition: String,
        term: String
    ) -> String? {
        let sourceBody = sourceDefinitionBody(
            from: sourceDefinition,
            term: term
        )
        guard !sourceBody.isEmpty else { return nil }

        let originalTrimmed = original.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var replacement = sourceBody
        let replacementEndsWithPunctuation = replacement.last.map {
            terminalPunctuation.contains($0)
        } ?? false
        if let punctuation = originalTrimmed.last,
           terminalPunctuation.contains(punctuation),
           !replacementEndsWithPunctuation {
            replacement.append(punctuation)
        }
        return replacement
    }

    private static func sourceDefinitionBody(
        from sourceDefinition: String,
        term: String
    ) -> String {
        let trimmed = sourceDefinition.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return "" }

        let termPrefix: String
        if trimmed.count >= term.count {
            let end = trimmed.index(trimmed.startIndex, offsetBy: term.count)
            termPrefix = String(trimmed[..<end])
        } else {
            termPrefix = ""
        }
        guard termPrefix.compare(
            term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: nil
        ) == .orderedSame else {
            return trimmed
        }

        let suffixStart = trimmed.index(trimmed.startIndex, offsetBy: term.count)
        let suffix = String(trimmed[suffixStart...])
        let pattern = #"(?is)^\s*[,;:]?\s*(?:adalah|ialah|merupakan|berarti|didefinisikan\s+sebagai|diartikan\s+sebagai)\s+(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: suffix,
                  range: NSRange(location: 0, length: suffix.utf16.count)
              ) else {
            return trimmed
        }
        return (suffix as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func definitionReference(
        for candidate: AIConnectorDefinitionCandidate,
        sourceDefinition: String
    ) -> EditorSuggestionReference {
        let entry = candidate.match.entry
        return EditorSuggestionReference(
            term: entry.term,
            regulation: entry.regulation,
            regulationTitle: entry.regulationTitle,
            sourceURL: entry.sourceURL,
            definition: sourceDefinition,
            officialDocumentURL: entry.officialDocumentURL,
            referenceID: entry.referenceID,
            sourcePassageID: entry.sourcePassageID,
            articleLocator: entry.articleLocator,
            applicabilityStatus: entry.applicabilityStatus
        )
    }

    private static func stableDefinitionSuggestionID(
        for assessment: AIConnectorDefinitionAssessment
    ) -> UUID {
        let candidateID = assessment.candidate?.match.entry.id
            ?? assessment.term
            ?? "unknown"
        let key = "definition-suggestion-v1|\(assessment.segment.id)|"
            + "\(candidateID)|\(assessment.statementText)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func stableDefinitionAnnotationID(
        for assessment: AIConnectorDefinitionAssessment
    ) -> UUID {
        let candidateID = assessment.candidate?.match.entry.id
            ?? assessment.term
            ?? "unknown"
        let key = "definition-annotation-v2|\(assessment.segment.id)|"
            + "\(candidateID)|\(assessment.statementText)|\(assessment.alignment.rawValue)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Stable identity shared by the read-only definition annotation and its
    /// Phase 6 resolution choices.
    static func definitionAnnotationID(
        for assessment: AIConnectorDefinitionAssessment
    ) -> UUID {
        stableDefinitionAnnotationID(for: assessment)
    }

    private static let terminalPunctuation: Set<Character> = [
        ".", "!", "?", ";", ":"
    ]

    static func extractSurroundingContext(
        range: NSRange,
        in documentText: String
    ) -> (prefix: String?, suffix: String?) {
        let nsText = documentText as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsText.length else {
            return (nil, nil)
        }

        var prefix: String? = nil
        if range.location > 0 {
            let prefixLength = min(range.location, 40)
            let prefixRange = NSRange(location: range.location - prefixLength, length: prefixLength)
            let rawPrefix = nsText.substring(with: prefixRange)
            let words = rawPrefix.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if let lastWord = words.last {
                prefix = lastWord
            }
        }

        var suffix: String? = nil
        let afterLocation = NSMaxRange(range)
        if afterLocation < nsText.length {
            let suffixLength = min(nsText.length - afterLocation, 40)
            let suffixRange = NSRange(location: afterLocation, length: suffixLength)
            let rawSuffix = nsText.substring(with: suffixRange)
            let words = rawSuffix.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if let firstWord = words.first {
                suffix = firstWord + "..."
            }
        }

        return (prefix, suffix)
    }

    private static func uniqueRange(of substring: String, in text: String) -> NSRange? {
        let wholeRange = NSRange(location: 0, length: text.utf16.count)
        let first = (text as NSString).range(
            of: substring,
            options: .literal,
            range: wholeRange,
            locale: nil
        )
        guard first.location != NSNotFound else { return nil }

        let afterFirstLocation = NSMaxRange(first)
        guard afterFirstLocation < wholeRange.length else { return first }

        let remainingRange = NSRange(
            location: afterFirstLocation,
            length: wholeRange.length - afterFirstLocation
        )
        let second = (text as NSString).range(
            of: substring,
            options: .literal,
            range: remainingRange,
            locale: nil
        )
        return second.location == NSNotFound ? first : nil
    }

    private static func reference(from review: AIValidatedReview) -> EditorSuggestionReference? {
        guard review.category == .terminology,
              let match = review.glossaryMatch
        else {
            return nil
        }

        return EditorSuggestionReference(
            term: match.entry.term,
            regulation: match.entry.regulation,
            regulationTitle: match.entry.regulationTitle,
            sourceURL: match.entry.sourceURL,
            definition: match.entry.definition,
            officialDocumentURL: match.entry.officialDocumentURL,
            referenceID: match.entry.referenceID,
            sourcePassageID: match.entry.sourcePassageID,
            articleLocator: match.entry.articleLocator,
            applicabilityStatus: match.entry.applicabilityStatus
        )
    }
}


private extension EditorDefinitionDiagnosticStatus {
    init?(legacyAlignment alignment: AIConnectorDefinitionAlignment) {
        switch alignment {
        case .matches:
            self = .matches
        case .mismatch:
            self = .mismatch
        case .needsReview:
            self = .needsReview
        case .notApplicable:
            return nil
        }
    }
}
