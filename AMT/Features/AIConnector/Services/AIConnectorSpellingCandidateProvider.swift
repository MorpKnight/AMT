import AppKit
import Foundation

@MainActor
protocol AIConnectorSystemSpellChecker: AnyObject {
    func checkSpelling(
        in text: String,
        startingAt location: Int,
        language: String
    ) -> NSRange

    func guesses(
        forWordRange range: NSRange,
        in text: String,
        language: String
    ) -> [String]
}

@MainActor
final class NSSpellCheckerAdapter: AIConnectorSystemSpellChecker {
    private let checker: NSSpellChecker

    init(checker: NSSpellChecker = .shared) {
        self.checker = checker
    }

    func checkSpelling(
        in text: String,
        startingAt location: Int,
        language: String
    ) -> NSRange {
        checker.checkSpelling(
            of: text,
            startingAt: location,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
    }

    func guesses(
        forWordRange range: NSRange,
        in text: String,
        language: String
    ) -> [String] {
        checker.guesses(
            forWordRange: range,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
    }
}

/// Provides a deliberately small, trusted candidate set from the system's
/// Indonesian spell checker. It never performs automatic correction and never
/// invents a replacement when the spell checker has no guess.
@MainActor
final class SystemIndonesianSpellingCandidateProvider: AIConnectorSpellingCandidateProviding {
    static let language = "id"
    static let maximumMisspelledWordsPerSegment = 2
    static let maximumGuessesPerWord = 6

    private let checker: any AIConnectorSystemSpellChecker

    init(checker: (any AIConnectorSystemSpellChecker)? = nil) {
        self.checker = checker ?? NSSpellCheckerAdapter()
    }

    func candidates(
        for segment: AIReviewSegment,
        protectionContext: AIConnectorDocumentProtectionContext,
        excludedOriginals: Set<String>
    ) -> [AIConnectorSpellingCandidate] {
        let text = segment.targetText
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        let protectedRanges = rangesToProtect(
            in: text,
            context: protectionContext,
            excludedOriginals: excludedOriginals
        )
        var candidates: [AIConnectorSpellingCandidate] = []
        var misspelledWordCount = 0
        var searchLocation = 0
        let normalizedExcluded = Set(excludedOriginals.map(normalizeWord))

        while searchLocation < nsText.length,
              misspelledWordCount < Self.maximumMisspelledWordsPerSegment {
            let range = checker.checkSpelling(
                in: text,
                startingAt: searchLocation,
                language: Self.language
            )
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= nsText.length else {
                break
            }

            let nextLocation = max(NSMaxRange(range), searchLocation + 1)
            searchLocation = nextLocation

            guard !overlapsProtectedRange(range, protectedRanges),
                  let original = textAt(range, in: text),
                  isEligibleWord(original) else {
                continue
            }

            let guesses = checker.guesses(
                forWordRange: range,
                in: text,
                language: Self.language
            )
            var seenGuesses = Set<String>()
            let eligibleGuesses = guesses.enumerated().compactMap { index, guess
                -> (String, Int)? in
                let normalizedGuess = normalizeWord(guess)
                guard isEligibleWord(guess),
                      normalizedGuess != normalizeWord(original),
                      !normalizedExcluded.contains(normalizeWord(original)),
                      seenGuesses.insert(normalizedGuess).inserted,
                      editDistance(atMostOneBetween: original, and: guess) == 1 else {
                    return nil
                }
                return (guess, index)
            }
            guard !eligibleGuesses.isEmpty else { continue }

            misspelledWordCount += 1
            candidates.append(contentsOf: eligibleGuesses.prefix(Self.maximumGuessesPerWord).map {
                guess, rank in
                AIConnectorSpellingCandidate(
                    original: original,
                    replacement: guess,
                    sourceLocation: range.location,
                    sourceLength: range.length,
                    sourceRank: rank
                )
            })
        }

        return candidates
    }

    private func rangesToProtect(
        in text: String,
        context: AIConnectorDocumentProtectionContext,
        excludedOriginals: Set<String>
    ) -> [NSRange] {
        var values = context.definedTerms
        values.formUnion(context.partyNames)
        values.formUnion(context.acronyms)
        values.formUnion(context.quotedTerms)
        values.formUnion(context.identifiers)
        values.formUnion(excludedOriginals)

        var ranges = values.flatMap { allRanges(of: $0, in: text) }
        ranges.append(contentsOf: regularExpressionRanges(
            pattern: #"(?i)\b(?:https?://|www\.)[^\s<>()]+|\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b|\b(?:nomor|no\.)\s*[0-9][A-Za-z0-9./-]*\b|\b(?:pasal|ayat|huruf)\s*\(?[0-9A-Za-z]+\)?(?:\s+(?:ayat|huruf)\s*\(?[0-9A-Za-z]+\)?)?\b|\b\d+(?:[.,/-]\d+)+\b|\b\d+\b|\b[A-Za-z0-9]+(?:[-/][A-Za-z0-9]+)+\b"#,
            in: text
        ))
        return ranges
    }

    private func allRanges(of value: String, in text: String) -> [NSRange] {
        guard !value.isEmpty else { return [] }
        let nsText = text as NSString
        var result: [NSRange] = []
        var location = 0
        while location < nsText.length {
            let searchRange = NSRange(
                location: location,
                length: nsText.length - location
            )
            let match = nsText.range(
                of: value,
                options: [.literal, .caseInsensitive],
                range: searchRange,
                locale: nil
            )
            guard match.location != NSNotFound else { break }
            result.append(match)
            location = max(NSMaxRange(match), location + 1)
        }
        return result
    }

    private func regularExpressionRanges(pattern: String, in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).map(\.range)
    }

    private func overlapsProtectedRange(_ range: NSRange, _ protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private func textAt(_ range: NSRange, in text: String) -> String? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func isEligibleWord(_ word: String) -> Bool {
        guard word.count >= 4,
              word == word.lowercased(),
              !word.contains(where: { $0.isWhitespace }) else {
            return false
        }
        return word.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    private func normalizeWord(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func editDistance(atMostOneBetween lhs: String, and rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left == right { return 0 }
        if abs(left.count - right.count) > 1 { return 2 }

        if left.count == right.count {
            return zip(left, right).filter { $0 != $1 }.count <= 1 ? 1 : 2
        }

        let shorter = left.count < right.count ? left : right
        let longer = left.count < right.count ? right : left
        var shortIndex = 0
        var longIndex = 0
        var edits = 0
        while shortIndex < shorter.count, longIndex < longer.count {
            if shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
                longIndex += 1
            } else {
                edits += 1
                longIndex += 1
                if edits > 1 { return 2 }
            }
        }
        return 1
    }
}
