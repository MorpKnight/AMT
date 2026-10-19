import Foundation

/// Local, non-persisted evidence binding a one-operation spelling restoration
/// to its exact occurrence and the document context used to propose it.
nonisolated struct AIConnectorSpellingRestorationEvidence: Hashable, Sendable {
    let original: String
    let replacement: String
    let sourceLocation: Int
    let sourceLength: Int
    let segmentText: String
    let documentText: String?
    let uniqueSpellCheckerGuess: Bool
    let explicitDocumentPhrase: String?

    var permitsContextualReview: Bool {
        uniqueSpellCheckerGuess || explicitDocumentPhrase != nil
    }

    var fingerprint: String {
        [original, replacement, String(sourceLocation), String(sourceLength),
         segmentText, documentText ?? "", String(uniqueSpellCheckerGuess),
         explicitDocumentPhrase ?? ""].joined(separator: "\u{1F}")
    }

    func isValid(in segment: AIReviewSegment,
                 context: AIConnectorDocumentProtectionContext) -> Bool {
        guard segment.targetText == segmentText,
              documentText == context.revisionText,
              sourceLocation >= 0, sourceLength == original.utf16.count,
              sourceLocation + sourceLength <= segmentText.utf16.count,
              (segmentText as NSString).substring(with: NSRange(location: sourceLocation, length: sourceLength)) == original,
              Self.isSingleEdit(original, replacement) else { return false }
        if let term = explicitDocumentPhrase {
            guard context.explicitDocumentTerms.contains(term),
                  context.explicitTermScopes[term]?.contains(where: {
                      NSLocationInRange(segment.sourceLocation + sourceLocation, $0)
                  }) == true else { return false }
        }
        let absoluteRange = NSRange(location: segment.sourceLocation + sourceLocation, length: sourceLength)
        return !context.protectedSourceRanges.contains {
            NSIntersectionRange(absoluteRange, $0).length > 0
        }
    }

    static func isSingleEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.precomposedStringWithCanonicalMapping.lowercased())
        let b = Array(rhs.precomposedStringWithCanonicalMapping.lowercased())
        guard a != b, abs(a.count - b.count) <= 1 else { return false }
        if a.count == b.count {
            let different = a.indices.filter { a[$0] != b[$0] }
            if different.count == 1 { return true }
            return different.count == 2 && different[1] == different[0] + 1
                && a[different[0]] == b[different[1]] && a[different[1]] == b[different[0]]
        }
        let shorter = a.count < b.count ? a : b
        let longer = a.count < b.count ? b : a
        var i = 0, j = 0, skipped = false
        while i < shorter.count {
            if shorter[i] == longer[j] { i += 1; j += 1 }
            else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }
}
