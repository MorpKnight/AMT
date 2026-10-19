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
    static let maximumGuessesPerWord = 6

    private(set) var filterReasons: [String: Int] = [:]

    private let checker: any AIConnectorSystemSpellChecker

    init(checker: (any AIConnectorSystemSpellChecker)? = nil) {
        self.checker = checker ?? NSSpellCheckerAdapter()
    }

    func candidates(
        for segment: AIReviewSegment,
        protectionContext: AIConnectorDocumentProtectionContext,
        excludedOriginals: Set<String>
    ) -> [AIConnectorSpellingCandidate] {
        filterReasons = [:]
        let text = segment.targetText
        let nsText = text as NSString
        let normalizedText = text.lowercased()
        let scanText = normalizedText.utf16.count == text.utf16.count ? normalizedText : text
        guard nsText.length > 0 else { return [] }

        let protectedRanges = rangesToProtect(
            in: text,
            context: protectionContext,
            excludedOriginals: excludedOriginals
        )
        var candidates: [AIConnectorSpellingCandidate] = []
        var searchLocation = 0
        let normalizedExcluded = Set(excludedOriginals.map(normalizeWord))

        while searchLocation < nsText.length, !Task.isCancelled {
            let range = checker.checkSpelling(
                in: scanText,
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

            guard !overlapsProtectedRange(range, protectedRanges) else {
                filterReasons["provider.protectedSpan", default: 0] += 1
                continue
            }
            guard let original = textAt(range, in: text), isEligibleWord(original) else {
                filterReasons["provider.lengthOrCase", default: 0] += 1
                continue
            }

            let guesses = checker.guesses(
                forWordRange: range,
                in: scanText,
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
                      AIConnectorSpellingRestorationEvidence.isSingleEdit(original, guess) else {
                    return nil
                }
                return (preservingCase(of: original, replacement: normalizedGuess), index)
            }
            guard !eligibleGuesses.isEmpty else {
                filterReasons["provider.noEligibleOneEditGuess", default: 0] += 1
                continue
            }

            candidates.append(contentsOf: eligibleGuesses.prefix(Self.maximumGuessesPerWord).map {
                guess, rank in
                AIConnectorSpellingCandidate(
                    original: original,
                    replacement: guess,
                    sourceLocation: range.location,
                    sourceLength: range.length,
                    sourceRank: rank,
                    restorationEvidence: AIConnectorSpellingRestorationEvidence(original: original, replacement: guess,
                        sourceLocation: range.location, sourceLength: range.length, segmentText: text,
                        documentText: protectionContext.revisionText, uniqueSpellCheckerGuess: eligibleGuesses.count == 1,
                        explicitDocumentPhrase: nil)
                )
            })
        }

        let documentCandidates = documentPhraseCandidates(for: segment, context: protectionContext,
            protectedRanges: protectedRanges)
        var merged: [AIConnectorSpellingCandidate] = []
        var seen = Set<String>()
        var counts: [Int: Int] = [:]
        // Preserve the stronger phrase evidence even if NSSpellChecker proposed
        // the same replacement among several alternatives.
        for candidate in documentCandidates + candidates {
            let key = String(candidate.sourceLocation) + "|" + candidate.replacement
            guard seen.insert(key).inserted, counts[candidate.sourceLocation, default: 0] < Self.maximumGuessesPerWord else { continue }
            counts[candidate.sourceLocation, default: 0] += 1
            merged.append(candidate)
        }
        return merged.sorted { $0.sourceLocation != $1.sourceLocation
            ? $0.sourceLocation < $1.sourceLocation : $0.sourceRank < $1.sourceRank }
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
        ranges.append(contentsOf: regularExpressionRanges(pattern: #"(?i)\bpihak\s+(?:pert[\p{L}]{1,8}|ked[\p{L}]{1,8}|ketig[\p{L}]{0,4}|kesat[\p{L}]{0,4}|[a-z])\b"#, in: text))
        ranges.append(contentsOf: regularExpressionRanges(
            pattern: #"(?i)\b(?:https?://|www\.)[^\s<>()]+|\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b|\b(?:nomor|no\.)\s*[0-9][A-Za-z0-9./-]*\b|\b(?:pasal|ayat|huruf)\s*\(?[0-9A-Za-z]+\)?(?:\s+(?:ayat|huruf)\s*\(?[0-9A-Za-z]+\)?)?\b|\b\d+(?:[.,/-]\d+)+\b|\b\d+\b|\b[A-Za-z0-9]+(?:[-/_][A-Za-z0-9]+)+\b"#,
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
              (word == word.lowercased() || word == word.prefix(1).uppercased() + word.dropFirst().lowercased()),
              !word.contains(where: { $0.isWhitespace }) else {
            return false
        }
        return word.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    private func normalizeWord(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func preservingCase(of original: String, replacement: String) -> String {
        original.first?.isUppercase == true
            ? replacement.prefix(1).uppercased() + replacement.dropFirst() : replacement
    }

    private func documentPhraseCandidates(for segment: AIReviewSegment,
        context: AIConnectorDocumentProtectionContext, protectedRanges: [NSRange]) -> [AIConnectorSpellingCandidate] {
        guard context.revisionText != nil,
              let regex = try? NSRegularExpression(pattern: #"\b[\p{L}]+\b"#) else { return [] }
        let text = segment.targetText as NSString
        let tokens = regex.matches(in: segment.targetText, range: NSRange(location: 0, length: text.length))
        var proposals: [AIConnectorSpellingCandidate] = []
        // A full multi-word phrase with exactly one misspelled token is required.
        for term in context.explicitDocumentTerms {
            let scope = context.explicitTermScopes[term] ?? []
            guard scope.contains(where: { NSIntersectionRange($0, NSRange(location: segment.sourceLocation,
                length: segment.sourceLength)).length > 0 }) else { continue }
            let words = term.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard words.count >= 2, tokens.count >= words.count else { continue }
            for start in 0...(tokens.count - words.count) {
                let ranges = Array(tokens[start..<(start + words.count)]).map(\.range)
                // Do not match across punctuation, a list boundary or a newline.
                let span = NSRange(location: ranges[0].location,
                    length: NSMaxRange(ranges.last ?? ranges[0]) - ranges[0].location)
                let phrase = text.substring(with: span)
                let whitespaceSeparated = ranges.dropLast().enumerated().allSatisfy { index, range in
                    let gap = text.substring(with: NSRange(location: NSMaxRange(range),
                        length: ranges[index + 1].location - NSMaxRange(range)))
                    return !gap.isEmpty && gap.allSatisfy { $0.isWhitespace && !$0.isNewline }
                }
                guard whitespaceSeparated, phrase.split(whereSeparator: { $0.isWhitespace }).count == words.count,
                      !phrase.contains("\n") else { continue }
                let observed = ranges.map { text.substring(with: $0) }
                let differences = words.indices.filter { normalizeWord(words[$0]) != normalizeWord(observed[$0]) }
                guard differences.count == 1, let index = differences.first,
                      isEligibleWord(observed[index]),
                      AIConnectorSpellingRestorationEvidence.isSingleEdit(observed[index], words[index]),
                      !overlapsProtectedRange(ranges[index], protectedRanges) else { continue }
                let range = ranges[index]
                let original = observed[index]
                let replacement = preservingCase(of: original, replacement: words[index].lowercased())
                proposals.append(AIConnectorSpellingCandidate(original: original, replacement: replacement,
                    sourceLocation: range.location, sourceLength: range.length,
                    restorationEvidence: AIConnectorSpellingRestorationEvidence(original: original, replacement: replacement,
                        sourceLocation: range.location, sourceLength: range.length, segmentText: segment.targetText,
                        documentText: context.revisionText, uniqueSpellCheckerGuess: false, explicitDocumentPhrase: term)))
            }
        }
        // Conflicting document declarations are evidence of ambiguity, not a unique restoration.
        return proposals.filter { value in
            Set(proposals.filter { $0.sourceLocation == value.sourceLocation }.map(\.replacement)).count == 1
        }
    }
}
