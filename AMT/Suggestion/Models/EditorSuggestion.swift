//
//  EditorSuggestion.swift
//  AMT
//

import Foundation

/// A validated, user-facing suggestion anchored to the current document text.
///
/// `sourceRange` uses UTF-16 offsets because AppKit's text system and
/// `NSRange` use the same indexing model.
struct EditorSuggestion: Identifiable, Hashable {
    let id: UUID
    var sourceRange: NSRange
    let original: String
    let replacement: String
    let category: AIReviewCategory
    let reason: String
    let origin: AIReviewOrigin
    let reference: EditorSuggestionReference?
    let prefixContext: String?
    let suffixContext: String?

    init(
        id: UUID,
        sourceRange: NSRange,
        original: String,
        replacement: String,
        category: AIReviewCategory,
        reason: String,
        origin: AIReviewOrigin,
        reference: EditorSuggestionReference? = nil,
        prefixContext: String? = nil,
        suffixContext: String? = nil
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.original = original
        self.replacement = replacement
        self.category = category
        self.reason = reason
        self.origin = origin
        self.reference = reference
        self.prefixContext = prefixContext
        self.suffixContext = suffixContext
    }
}

struct EditorSuggestionReference: Hashable {
    let term: String
    let regulation: String
    let regulationTitle: String
    let sourceURL: URL?
}

enum EditorSuggestionMapper {
    static func make(
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
                  let localRange = uniqueRange(of: original, in: review.segment.targetText)
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
            sourceURL: match.entry.sourceURL
        )
    }
}

enum EditorSuggestionReconciler {
    static func afterAccept(
        suggestions: [EditorSuggestion],
        acceptedID: UUID,
        replacementDelta: Int
    ) -> [EditorSuggestion] {
        guard let accepted = suggestions.first(where: { $0.id == acceptedID }) else {
            return suggestions
        }

        let acceptedEnd = NSMaxRange(accepted.sourceRange)
        return suggestions.compactMap { suggestion in
            guard suggestion.id != acceptedID else { return nil }

            let overlap = NSIntersectionRange(
                accepted.sourceRange,
                suggestion.sourceRange
            )
            guard overlap.length == 0 else { return nil }

            var reconciled = suggestion
            if suggestion.sourceRange.location >= acceptedEnd {
                reconciled.sourceRange.location += replacementDelta
            }
            return reconciled
        }
    }
}
