import Foundation

enum AIConnectorValidationError: Error, Equatable, Sendable {
    case inconsistentFields
    case missingOriginal
    case missingReplacement
    case originalNotUnique
    case replacementUnchanged
    case replacementTooLong
    case nonMinimalEditSpan
    case protectedContentChanged
    case legalStructureChanged
    case overlappingSuggestion
    case invalidGlossaryReference
    case unsupportedSourceClaim
    case ungroundedReason

    var message: String {
        switch self {
        case .inconsistentFields:
            "Kombinasi status, kategori, dan kolom output tidak konsisten."
        case .missingOriginal:
            "Model tidak menunjuk bagian teks asli secara tepat."
        case .missingReplacement:
            "Model tidak memberikan pengganti yang dapat diperiksa."
        case .originalNotUnique:
            "Bagian teks asli tidak ditemukan secara unik pada target."
        case .replacementUnchanged:
            "Usulan sama dengan teks asli."
        case .replacementTooLong:
            "Usulan terlalu panjang untuk eksperimen ini."
        case .nonMinimalEditSpan:
            "Model menyalin bagian teks yang terlalu luas; gunakan span perubahan terkecil."
        case .protectedContentChanged:
            "Usulan mengubah angka, istilah terproteksi, atau modalitas hukum."
        case .legalStructureChanged:
            "Usulan mengubah kondisi, pengecualian, referensi, atau akibat hukum."
        case .overlappingSuggestion:
            "Usulan bertabrakan dengan usulan lain pada segmen yang sama."
        case .invalidGlossaryReference:
            "Rujukan glossary tidak tersedia atau tidak sesuai."
        case .unsupportedSourceClaim:
            "Alasan mengandung klaim sumber hukum yang tidak diizinkan."
        case .ungroundedReason:
            "Alasan merujuk frasa yang tidak ditemukan pada target atau usulan."
        }
    }
}

struct AIConnectorSuggestionValidator: Sendable {
    nonisolated static let version = "validator-v3-locality-grounding"
    private static let legalModalities: Set<String> = [
        "wajib",
        "harus",
        "dapat",
        "berhak",
        "dilarang",
        "tidak",
        "tanpa",
        "sekurang-kurangnya",
        "paling lambat"
    ]

    private static let numberWords: Set<String> = [
        "nol", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh",
        "delapan", "sembilan", "sepuluh", "sebelas", "belas", "puluh",
        "ratus", "ribu", "juta", "miliar", "triliun"
    ]

    private static let definedTerms = [
        "Pihak Pertama",
        "Pihak Kedua",
        "Para Pihak",
        "Borrower",
        "Lender"
    ]

    func validate(
        _ parsedReview: AIParsedReview,
        for segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        origin: AIReviewOrigin = .qwen,
        protectionContext: AIConnectorDocumentProtectionContext = .empty
    ) throws -> AIValidatedReview {
        guard !containsUnsupportedSourceClaim(in: parsedReview.reason) else {
            throw AIConnectorValidationError.unsupportedSourceClaim
        }
        guard reasonIsGrounded(parsedReview, in: segment.targetText) else {
            throw AIConnectorValidationError.ungroundedReason
        }

        let glossaryMatch = try resolveGlossary(
            id: parsedReview.glossaryID,
            matches: glossaryMatches
        )

        switch parsedReview.status {
        case .noSuggestion:
            guard parsedReview.category == .none,
                  parsedReview.original == nil,
                  parsedReview.replacement == nil,
                  parsedReview.glossaryID == nil else {
                throw AIConnectorValidationError.inconsistentFields
            }

        case .suggestion:
            guard parsedReview.category != .none else {
                throw AIConnectorValidationError.inconsistentFields
            }
            try validateSuggestionFields(
                parsedReview,
                segment: segment,
                glossaryMatch: glossaryMatch,
                protectionContext: protectionContext
            )

        case .needsReview:
            guard parsedReview.replacement == nil else {
                throw AIConnectorValidationError.inconsistentFields
            }
            if let original = parsedReview.original {
                guard occurrenceCount(of: original, in: segment.targetText) == 1 else {
                    throw AIConnectorValidationError.originalNotUnique
                }
            }
        }

        return AIValidatedReview(
            segment: segment,
            status: parsedReview.status,
            category: parsedReview.category,
            original: parsedReview.original,
            replacement: parsedReview.replacement,
            reason: parsedReview.reason,
            glossaryMatch: glossaryMatch,
            origin: origin,
            ruleID: parsedReview.ruleID
        )
    }

    private func validateSuggestionFields(
        _ parsedReview: AIParsedReview,
        segment: AIReviewSegment,
        glossaryMatch: LegalDictionaryMatch?,
        protectionContext: AIConnectorDocumentProtectionContext
    ) throws {
        guard let original = parsedReview.original else {
            throw AIConnectorValidationError.missingOriginal
        }
        guard let replacement = parsedReview.replacement else {
            throw AIConnectorValidationError.missingReplacement
        }
        guard occurrenceCount(of: original, in: segment.targetText) == 1 else {
            throw AIConnectorValidationError.originalNotUnique
        }
        guard original != replacement else {
            throw AIConnectorValidationError.replacementUnchanged
        }
        guard replacement.count <= min(500, max(1, original.count * 2)) else {
            throw AIConnectorValidationError.replacementTooLong
        }
        if parsedReview.category == .terminology {
            guard let glossaryMatch,
                  replacement == glossaryMatch.entry.term else {
                throw AIConnectorValidationError.invalidGlossaryReference
            }
        } else if glossaryMatch != nil {
            throw AIConnectorValidationError.invalidGlossaryReference
        }

        let isTrustedGlossaryDefinitionReplacement = parsedReview.category == .terminology
            && glossaryMatch.map {
                replacement == $0.entry.term
                    && matchesGlossaryDefinition(original, entry: $0.entry)
            } == true

        guard preservesProtectedContent(
            from: original,
            to: replacement,
            allowGlossaryProtectedTermChange: isTrustedGlossaryDefinitionReplacement,
            protectionContext: protectionContext
        ) else {
            if changesLegalStructure(
                from: original,
                to: replacement,
                protectionContext: protectionContext
            ) {
                throw AIConnectorValidationError.legalStructureChanged
            }
            throw AIConnectorValidationError.protectedContentChanged
        }

        if parsedReview.category != .terminology,
           hasNonMinimalEditSpan(original: original, replacement: replacement) {
            throw AIConnectorValidationError.nonMinimalEditSpan
        }
    }

    private func resolveGlossary(
        id: String?,
        matches: [LegalDictionaryMatch]
    ) throws -> LegalDictionaryMatch? {
        guard let id else { return nil }
        guard id == "G1", let match = matches.first else {
            throw AIConnectorValidationError.invalidGlossaryReference
        }
        return match
    }

    private func matchesGlossaryDefinition(
        _ original: String,
        entry: LegalDictionaryEntry
    ) -> Bool {
        let definition = entry.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let definitionWithoutTrailingPunctuation = removeTrailingSentencePunctuation(from: definition)
        let prefixes = [
            "\(entry.term) adalah ",
            "\(entry.term) ialah ",
            "\(entry.term) merupakan "
        ]
        let candidates = [definitionWithoutTrailingPunctuation]
            + prefixes.compactMap { prefix in
                guard definitionWithoutTrailingPunctuation.lowercased().hasPrefix(prefix.lowercased()) else {
                    return nil
                }
                return String(definitionWithoutTrailingPunctuation.dropFirst(prefix.count))
            }

        let normalizedOriginal = normalizeGlossaryPhrase(original)
        if candidates.contains(where: { normalizeGlossaryPhrase($0) == normalizedOriginal }) {
            return true
        }

        // Semantic retrieval may deliberately select a shorter contiguous
        // span from a paraphrased definition. Keep this exception narrow: it
        // still requires a canonical glossary replacement and at least 70%
        // coverage of the definition's informative keywords. The caller has
        // already established that the glossary evidence is verified.
        let stopWords: Set<String> = [
            "adalah", "ialah", "merupakan", "yang", "dan", "atau", "serta",
            "dalam", "dengan", "untuk", "dari", "pada", "oleh", "terhadap",
            "sebagai", "suatu", "sebuah", "dapat", "telah", "akan", "tidak",
            "secara", "baik", "lebih", "lain", "lainnya", "ini", "itu"
        ]
        let definitionKeywords = Set(
            normalizedTokens(definitionBody(from: definition, term: entry.term))
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
        let originalKeywords = Set(
            normalizedTokens(original)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
        guard definitionKeywords.count >= 4 else { return false }
        let coverage = Double(definitionKeywords.intersection(originalKeywords).count)
            / Double(definitionKeywords.count)
        return coverage >= 0.70
    }

    private func definitionBody(from definition: String, term: String) -> String {
        let normalizedDefinition = normalizeGlossaryPhrase(definition)
        let normalizedTerm = normalizeGlossaryPhrase(term)
        for connector in ["adalah", "ialah", "merupakan"] {
            let prefix = "\(normalizedTerm) \(connector) "
            if normalizedDefinition.hasPrefix(prefix) {
                return String(normalizedDefinition.dropFirst(prefix.count))
            }
        }
        return normalizedDefinition
    }

    private func normalizeGlossaryPhrase(_ text: String) -> String {
        removeTrailingSentencePunctuation(from: text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeTrailingSentencePunctuation(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentencePunctuation = CharacterSet(charactersIn: ".!?;:")

        while let last = result.unicodeScalars.last,
              sentencePunctuation.contains(last) {
            result.removeLast()
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preservesProtectedContent(
        from original: String,
        to replacement: String,
        allowGlossaryProtectedTermChange: Bool,
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> Bool {
        // A canonical glossary term may replace its own complete, retrieved
        // definition. The definition is the trusted source for this narrow
        // exception; arbitrary model rewrites never reach this path.
        if allowGlossaryProtectedTermChange {
            return true
        }

        let originalTokens = normalizedTokens(original)
        let replacementTokens = normalizedTokens(replacement)

        let originalNumbers = digitTokens(in: original)
            + originalTokens.filter(Self.numberWords.contains)
        let replacementNumbers = digitTokens(in: replacement)
            + replacementTokens.filter(Self.numberWords.contains)
        guard originalNumbers == replacementNumbers else { return false }

        let originalModalities = protectedModalityTokens(in: originalTokens)
        let replacementModalities = protectedModalityTokens(in: replacementTokens)
        guard originalModalities == replacementModalities else { return false }

        guard dateMonthTokens(in: original) == dateMonthTokens(in: replacement),
              numericDateMarkers(in: original) == numericDateMarkers(in: replacement),
              percentageMarkers(in: original) == percentageMarkers(in: replacement),
              currencyMarkers(in: original) == currencyMarkers(in: replacement),
              protectedStructuralMarkers(in: original) == protectedStructuralMarkers(in: replacement) else {
            return false
        }

        if !allowGlossaryProtectedTermChange {
            let definedTerms = Set(Self.definedTerms).union(protectionContext.definedTerms)
            for term in definedTerms where original.contains(term) {
                guard replacement.contains(term) else { return false }
            }

            for term in protectionContext.partyNames
                .union(protectionContext.quotedTerms)
                .union(protectionContext.identifiers)
            where original.contains(term) {
                guard replacement.contains(term) else { return false }
            }

            let originalCaseSensitiveTokens = caseSensitiveTokens(in: original)
            let replacementCaseSensitiveTokens = caseSensitiveTokens(in: replacement)
            let protectedAcronyms = Set(
                originalCaseSensitiveTokens.filter(isAcronym)
            ).union(protectionContext.acronyms)
            for token in protectedAcronyms where original.contains(token) {
                guard replacementCaseSensitiveTokens.contains(token) else { return false }
            }

            guard capitalizedTokens(in: original) == capitalizedTokens(in: replacement) else {
                return false
            }

            for quotedText in quotedSubstrings(in: original) {
                guard replacement.contains(quotedText) else { return false }
            }
        }

        return true
    }

    private func changesLegalStructure(
        from original: String,
        to replacement: String,
        protectionContext: AIConnectorDocumentProtectionContext
    ) -> Bool {
        let originalMarkers = protectedStructuralMarkers(in: original)
        let replacementMarkers = protectedStructuralMarkers(in: replacement)
        guard originalMarkers != replacementMarkers else { return false }

        // A changed proposition is safer to reject than to treat as a normal
        // grammar correction. The caller may present this as NEEDS_REVIEW in a
        // future model contract, but no replacement is accepted today.
        _ = protectionContext
        return true
    }

    private func protectedStructuralMarkers(in text: String) -> [String] {
        let tokens = normalizedTokens(text)
        let structuralTokens: Set<String> = [
            "jika", "apabila", "kecuali", "sepanjang", "dalam", "hal",
            "dengan", "syarat", "sebelum", "sesudah", "setelah", "sampai",
            "sejak", "hingga", "batal", "berakhir", "mengakhiri", "sanksi",
            "dikenai", "dikenakan", "ganti", "rugi", "pengecualian", "larangan",
            "izin", "hak", "kewajiban", "pasal", "ayat", "huruf", "angka"
        ]
        var markers = tokens.filter(structuralTokens.contains)
        markers.append(contentsOf: articleReferenceMarkers(in: text))
        return markers
    }

    private func articleReferenceMarkers(in text: String) -> [String] {
        let patterns = [
            #"(?i)\bpasal\s+[0-9]+(?:\s*ayat\s*\([0-9]+\))?"#,
            #"(?i)\bayat\s*\([0-9]+\)"#,
            #"(?i)\bhuruf\s+[a-z]\b"#,
            #"(?i)\bangka\s+[0-9]+\b"#
        ]
        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: text) else { return nil }
                return normalizeMarker(String(text[matchRange]))
            }
        }.sorted()
    }

    private func normalizeMarker(_ marker: String) -> String {
        marker.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func protectedModalityTokens(in tokens: [String]) -> [String] {
        var result: [String] = []
        for (index, token) in tokens.enumerated() {
            if Self.legalModalities.contains(token) {
                result.append(token)
            }

            if token == "paling", index + 1 < tokens.count,
               tokens[index + 1] == "lambat" {
                result.append("paling lambat")
            }
            if token == "sekurang", index + 1 < tokens.count,
               tokens[index + 1] == "kurangnya" {
                result.append("sekurang-kurangnya")
            }
        }
        return result
    }

    private func normalizedTokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func caseSensitiveTokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func digitTokens(in text: String) -> [String] {
        let pattern = #"\d+(?:[.,]\d+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func dateMonthTokens(in text: String) -> [String] {
        let months: Set<String> = [
            "januari", "februari", "maret", "april", "mei", "juni",
            "juli", "agustus", "september", "oktober", "november", "desember",
            "jan", "feb", "mar", "apr", "jun", "jul", "agu", "sep", "okt", "nov", "des"
        ]
        return normalizedTokens(text).filter(months.contains)
    }

    private func numericDateMarkers(in text: String) -> [String] {
        let pattern = #"\b\d{1,4}[./-]\d{1,2}[./-]\d{2,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func percentageMarkers(in text: String) -> [String] {
        var markers = Array(repeating: "%", count: text.filter { $0 == "%" }.count)
        markers.append(contentsOf: normalizedTokens(text).filter { token in
            token == "persen" || token == "persentase"
        })
        return markers.sorted()
    }

    private func currencyMarkers(in text: String) -> [String] {
        let currencyCodes = ["rp", "idr", "usd", "eur", "gbp", "jpy", "sgd", "aud", "cad", "cny", "rmb"]
        var markers: [String] = []

        for token in text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map({ $0.lowercased() }) {
            for code in currencyCodes where token == code || token.hasPrefix(code) {
                let suffix = token.dropFirst(code.count)
                if suffix.isEmpty || suffix.allSatisfy(\.isNumber) {
                    markers.append(code)
                    break
                }
            }
        }

        for symbol in ["$", "€", "£", "¥", "₹", "₩"] {
            markers.append(contentsOf: Array(repeating: symbol, count: text.components(separatedBy: symbol).count - 1))
        }

        return markers.sorted()
    }

    private func capitalizedTokens(in text: String) -> [String] {
        caseSensitiveTokens(in: text).filter { token in
            guard let first = token.first else { return false }
            return token.count > 1 && first.isUppercase
        }
    }

    private func isAcronym(_ token: String) -> Bool {
        let letters = token.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy { $0.isUppercase }
    }

    private func quotedSubstrings(in text: String) -> [String] {
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”")]
        var result: [String] = []

        for (opening, closing) in quotePairs {
            var start: String.Index?
            for index in text.indices {
                if opening == closing, text[index] == opening {
                    if let rangeStart = start {
                        result.append(String(text[rangeStart..<index]))
                        start = nil
                    } else {
                        start = text.index(after: index)
                    }
                } else if text[index] == opening {
                    start = text.index(after: index)
                } else if text[index] == closing, let rangeStart = start {
                    result.append(String(text[rangeStart..<index]))
                    start = nil
                }
            }
        }

        return result
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = haystack.index(after: range.lowerBound)
        }
        return count
    }

    private func hasNonMinimalEditSpan(original: String, replacement: String) -> Bool {
        guard original.count >= 32, replacement.count >= 20 else { return false }

        let originalCharacters = Array(original)
        let replacementCharacters = Array(replacement)
        let sharedLimit = min(originalCharacters.count, replacementCharacters.count)

        var prefixCount = 0
        while prefixCount < sharedLimit,
              originalCharacters[prefixCount] == replacementCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < sharedLimit - prefixCount,
              originalCharacters[originalCharacters.count - 1 - suffixCount]
                == replacementCharacters[replacementCharacters.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let sharedRatio = Double(prefixCount + suffixCount)
            / Double(max(originalCharacters.count, replacementCharacters.count))
        return sharedRatio >= 0.6
    }

    private func reasonIsGrounded(_ review: AIParsedReview, in target: String) -> Bool {
        let evidence = [target, review.original, review.replacement]
            .compactMap { $0 }
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return quotedSubstrings(in: review.reason).allSatisfy { quotedText in
            let normalized = quotedText
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty || evidence.localizedCaseInsensitiveContains(normalized)
        }
    }

    private func containsUnsupportedSourceClaim(in reason: String) -> Bool {
        let tokens = normalizedTokens(reason)
        let sourceTokens: Set<String> = [
            "uu", "undang-undang", "peraturan", "pasal", "nomor", "http", "https", "www"
        ]
        return tokens.contains(where: sourceTokens.contains)
            || reason.localizedCaseInsensitiveContains("undang-undang")
            || reason.contains("http://")
            || reason.contains("https://")
    }
}
