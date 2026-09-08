import Foundation

/// Builds source-backed choices for one definition mismatch. Retrieval is
/// intentionally lazy: the reverse term lookup is performed only after the
/// lawyer asks for it from the popover.
@MainActor
struct AIConnectorDefinitionResolutionService: Sendable {
    typealias Reviewer = @MainActor @Sendable (
        AIConnectorDefinitionResolutionReviewRequest
    ) async throws -> AIConnectorDefinitionResolutionReviewResult

    static let version = AIConnectorDefinitionResolution.version
    static let maximumCandidates = 3

    private let dictionaryStore: LegalDictionaryStore

    init(dictionaryStore: LegalDictionaryStore) {
        self.dictionaryStore = dictionaryStore
    }

    func resolve(
        assessment: AIConnectorDefinitionAssessment,
        documentText: String,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        includeReverseTermCandidates: Bool = false,
        reviewer: Reviewer? = nil,
        semanticProgress: @escaping @Sendable (Double) -> Void = { _ in },
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void = { _ in }
    ) async throws -> AIConnectorDefinitionResolutionResult {
        let clock = ContinuousClock()
        let startedAt = clock.now
        try Task.checkCancellation()

        let anchors = anchors(for: assessment, documentText: documentText)
        let sourceCandidates = Array(
            (assessment.candidates.isEmpty
                ? assessment.candidate.map { [$0] } ?? []
                : assessment.candidates)
                .prefix(Self.maximumCandidates)
        )

        var options: [AIConnectorDefinitionResolutionOption] = []
        var references: [EditorSuggestionReference] = []
        var candidateCount = 0

        for candidate in sourceCandidates {
            let reference = makeReference(
                for: candidate,
                sourceDefinition: sourceDefinitionBody(
                    from: candidate.sourceDefinition,
                    term: candidate.term
                )
            )
            if !references.contains(reference) {
                references.append(reference)
            }
            candidateCount += 1

            let sourceBody = sourceDefinitionBody(
                from: candidate.sourceDefinition,
                term: candidate.term
            )
            let sourceEligible = isEligibleSource(candidate.match.entry)
            let contractMessage = "Dokumen tampak memberi arti khusus pada istilah ini; perubahan otomatis tidak tersedia."
            let sourceMessage = sourceEligibilityMessage(candidate.match.entry)

            let useStatus: AIConnectorDefinitionResolutionOptionStatus
            let useMessage: String?
            if assessment.alignment != .mismatch {
                useStatus = .informational
                useMessage = "Perubahan definisi hanya tersedia untuk definisi yang dinilai tidak selaras."
            } else if contractDefined(in: assessment.segment.targetText) {
                useStatus = .informational
                useMessage = contractMessage
            } else if anchors.bodyRange == nil || sourceBody.isEmpty {
                useStatus = .informational
                useMessage = "Batas isi definisi tidak dapat ditentukan dengan aman."
            } else if !sourceEligible {
                useStatus = .informational
                useMessage = sourceMessage
            } else {
                useStatus = .actionable
                useMessage = nil
            }

            if let bodyRange = anchors.bodyRange,
               let bodyOriginal = anchors.bodyOriginal {
                options.append(
                    AIConnectorDefinitionResolutionOption(
                        id: "\(assessment.id)-definition-\(candidate.id)",
                        action: .useDefinition,
                        title: "Gunakan definisi dari sumber",
                        targetRange: absoluteRange(bodyRange, segment: assessment.segment),
                        original: bodyOriginal,
                        replacement: sourceBody.isEmpty ? nil : preserveTerminalPunctuation(
                            sourceBody,
                            from: bodyOriginal
                        ),
                        term: candidate.term,
                        reference: reference,
                        sourceCandidateID: candidate.id,
                        status: useStatus,
                        statusMessage: useMessage
                    )
                )
            } else {
                options.append(
                    AIConnectorDefinitionResolutionOption(
                        id: "\(assessment.id)-definition-\(candidate.id)-informational",
                        action: .useDefinition,
                        title: "Gunakan definisi dari sumber",
                        targetRange: NSRange(location: 0, length: 0),
                        original: "",
                        replacement: nil,
                        term: candidate.term,
                        reference: reference,
                        sourceCandidateID: candidate.id,
                        status: .informational,
                        statusMessage: "Batas isi definisi tidak dapat ditentukan dengan aman."
                    )
                )
            }

            if let termRange = anchors.termRange,
               let termOriginal = anchors.termOriginal,
               normalize(termOriginal) != normalize(candidate.term) {
                let termStatus: AIConnectorDefinitionResolutionOptionStatus
                let termMessage: String?
                if contractDefined(in: assessment.segment.targetText) {
                    termStatus = .informational
                    termMessage = contractMessage
                } else if !sourceEligible {
                    termStatus = .informational
                    termMessage = sourceMessage
                } else {
                    termStatus = .actionable
                    termMessage = nil
                }
                options.append(
                    AIConnectorDefinitionResolutionOption(
                        id: "\(assessment.id)-term-\(candidate.id)",
                        action: .replaceTerm,
                        title: "Ganti istilah",
                        targetRange: absoluteRange(termRange, segment: assessment.segment),
                        original: termOriginal,
                        replacement: candidate.term,
                        term: candidate.term,
                        reference: reference,
                        sourceCandidateID: candidate.id,
                        status: termStatus,
                        statusMessage: termMessage
                    )
                )
            }
        }

        var queryCount = 0
        var semanticMatches: [LegalDictionaryMatch] = []
        if includeReverseTermCandidates,
           anchors.bodyOriginal != nil,
           !contractDefined(in: assessment.segment.targetText),
           assessment.alignment == .mismatch {
            queryCount = 1
            semanticMatches = try await reverseMatches(
                body: anchors.bodyOriginal ?? "",
                mode: mode,
                semanticProgress: semanticProgress
            )
        }

        var modelCallCount = 0
        var fallbackCount = 0
        for (index, match) in semanticMatches.prefix(Self.maximumCandidates).enumerated() {
            let sourceDefinition = sourceDefinitionBody(from: match.entry.definition, term: match.entry.term)
            guard let termRange = anchors.termRange,
                  let termOriginal = anchors.termOriginal,
                  !sourceDefinition.isEmpty,
                  normalize(termOriginal) != normalize(match.entry.term) else {
                continue
            }
            let reference = makeReference(
                entry: match.entry,
                sourceDefinition: sourceDefinition
            )
            if !references.contains(reference) {
                references.append(reference)
            }

            let candidateID = "R\(index + 1)"
            var status: AIConnectorDefinitionResolutionOptionStatus = .needsReview
            var message: String? = "Kandidat istilah berasal dari reverse retrieval dan memerlukan review."
            if mode == .deterministic {
                if normalizedDefinition(sourceDefinition) == normalizedDefinition(anchors.bodyOriginal ?? "") {
                    status = .actionable
                    message = nil
                } else {
                    status = .informational
                    message = "Mode deterministic hanya mengaktifkan kecocokan definisi yang identik setelah normalisasi."
                }
            } else if let reviewer {
                let request = AIConnectorDefinitionResolutionReviewRequest(
                    candidateID: candidateID,
                    targetTerm: assessment.term ?? termOriginal,
                    documentDefinition: anchors.bodyOriginal ?? "",
                    candidateTerm: match.entry.term,
                    candidateDefinition: sourceDefinition,
                    context: assessment.segment.context,
                    modelVariant: modelVariant
                )
                modelCallCount += 1
                do {
                    let result = try await reviewer(request)
                    guard result.candidateID == candidateID else {
                        throw QwenSuggestionError.contextClassificationInvalid
                    }
                    switch result.decision {
                    case .termFits:
                        status = .actionable
                        message = nil
                    case .termMayFit, .ambiguous:
                        status = .needsReview
                    case .contractTermOverride:
                        status = .informational
                        message = "Model menemukan kemungkinan defined term khusus kontrak; verifikasi manual diperlukan."
                    case .wrongTerm, .notApplicable:
                        status = .informational
                        message = "Kandidat ini tidak cukup sesuai dengan isi definisi."
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    fallbackCount += 1
                    status = .needsReview
                    message = "Penilaian model gagal; kandidat tetap harus diverifikasi manusia."
                }
            } else {
                fallbackCount += 1
            }

            options.append(
                AIConnectorDefinitionResolutionOption(
                    id: "\(assessment.id)-reverse-\(candidateID)",
                    action: .replaceTerm,
                    title: "Ganti istilah dengan \(match.entry.term)",
                    targetRange: absoluteRange(termRange, segment: assessment.segment),
                    original: termOriginal,
                    replacement: match.entry.term,
                    term: match.entry.term,
                    reference: reference,
                    sourceCandidateID: candidateID,
                    status: status,
                    statusMessage: message,
                    requiresModelReview: mode.usesModel
                )
            )
        }

        if assessment.alignment == .mismatch {
            options.append(
                AIConnectorDefinitionResolutionOption(
                    id: "\(assessment.id)-reject",
                    action: .rejectRecommendation,
                    title: "Tolak rekomendasi",
                    targetRange: anchors.primaryRange.map { absoluteRange($0, segment: assessment.segment) }
                        ?? NSRange(location: 0, length: 0),
                    original: anchors.primaryOriginal ?? "",
                    status: .actionable
                )
            )
        }

        let primaryRange = anchors.primaryRange.map {
            absoluteRange($0, segment: assessment.segment)
        } ?? NSRange(
            location: assessment.segment.sourceLocation,
            length: assessment.segment.sourceLength
        )
        let primaryOriginal = substring(primaryRange, in: documentText)
        let resolution = AIConnectorDefinitionResolution(
            id: "definition-resolution-\(assessment.id)-\(DocumentFingerprinting.contentSHA256(documentText).prefix(12))",
            assessmentID: assessment.id,
            annotationID: EditorSuggestionMapper.definitionAnnotationID(for: assessment),
            primaryRange: primaryRange,
            primaryOriginal: primaryOriginal,
            termRange: anchors.termRange.map { absoluteRange($0, segment: assessment.segment) },
            termOriginal: anchors.termOriginal,
            bodyRange: anchors.bodyRange.map { absoluteRange($0, segment: assessment.segment) },
            bodyOriginal: anchors.bodyOriginal,
            options: options,
            sourceReferences: references,
            contractDefined: contractDefined(in: assessment.segment.targetText),
            sourceFingerprint: DocumentFingerprinting.contentSHA256(documentText),
            corpusVersion: dictionaryStore.activeCorpusVersion
        )
        let status = resolution.contractDefined
            ? "contract-defined-read-only"
            : resolution.hasActionableOption ? "completed" : "informational"
        return AIConnectorDefinitionResolutionResult(
            resolution: resolution,
            metrics: AIConnectorDefinitionResolutionMetrics(
                retrievalQueryCount: queryCount,
                candidateCount: candidateCount + semanticMatches.count,
                modelCallCount: modelCallCount,
                fallbackCount: fallbackCount,
                duration: AIConnectorObservationTiming.seconds(startedAt.duration(to: clock.now)),
                status: status
            )
        )
    }

    private func reverseMatches(
        body: String,
        mode: AIConnectorReviewMode,
        semanticProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [LegalDictionaryMatch] {
        let request = LegalRetrievalRequest(
            query: body,
            intent: .reverseLookup,
            limit: Self.maximumCandidates * 2
        )
        let retrieved: [LegalDictionaryMatch]
        if dictionaryStore.corpusStore == nil {
            // Unit tests, previews, and installations without the optional
            // versioned corpus still have a local lexical dictionary. Keep
            // deterministic reverse resolution useful there without
            // pretending a semantic score exists.
            retrieved = dictionaryStore.search(
                body,
                limit: Self.maximumCandidates * 2
            ).enumerated().map { index, entry in
                LegalDictionaryMatch(
                    entry: entry,
                    score: Double(Self.maximumCandidates * 2 - index),
                    rank: index + 1,
                    matchedDefinitionTokenCount: 0,
                    isDirectTermMatch: false,
                    retrievalOrigin: .lexical
                )
            }
        } else {
            let retrievalMatches = try await dictionaryStore.retrieve(
                request,
                semanticProgress: semanticProgress
            )
            retrieved = retrievalMatches.compactMap { match in
                guard let entry = dictionaryStore.entries.first(where: {
                    $0.id == match.concept.recordID
                }) else {
                    return nil
                }
                return LegalDictionaryMatch(
                    entry: entry,
                    score: match.fusionScore
                        ?? Double(match.semanticScore ?? Float(match.lexicalScore ?? 0)),
                    rank: match.rank,
                    matchedDefinitionTokenCount: 0,
                    isDirectTermMatch: false,
                    semanticScore: match.semanticScore,
                    fusionScore: match.fusionScore,
                    retrievalOrigin: match.origin
                )
            }
        }
        let threshold = dictionaryStore.semanticRetrievalConfiguration?
            .suggestionSemanticThreshold
            ?? LegalDictionaryStore.dictionarySemanticThreshold
        var matches: [LegalDictionaryMatch] = []
        for match in retrieved {
            guard isEligibleSource(match.entry) else {
                continue
            }
            if let semanticScore = match.semanticScore,
               (!semanticScore.isFinite || semanticScore < threshold) {
                continue
            }
            let sourceDefinition = sourceDefinitionBody(
                from: match.entry.definition,
                term: match.entry.term
            )
            if mode == .deterministic,
               normalizedDefinition(sourceDefinition) != normalizedDefinition(body) {
                continue
            }
            matches.append(match)
        }
        return matches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.entry.id < rhs.entry.id
            }
            .prefix(Self.maximumCandidates)
            .map { $0 }
    }

    private struct Anchors {
        let primaryRange: NSRange?
        let primaryOriginal: String?
        let termRange: NSRange?
        let termOriginal: String?
        let bodyRange: NSRange?
        let bodyOriginal: String?
    }

    private func anchors(
        for assessment: AIConnectorDefinitionAssessment,
        documentText: String
    ) -> Anchors {
        let target = assessment.segment.targetText
        let term = assessment.term ?? assessment.candidate?.term
        let termRange = term.flatMap {
            uniqueRange(
                of: $0,
                in: target,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        let termOriginal = termRange.map { substring($0, in: target) }
        // A body is only safe to edit when the term occurrence itself is
        // unique in this target. Otherwise a broad regex could silently bind
        // the source definition to the wrong occurrence.
        let body = termRange == nil
            ? nil
            : term.flatMap { definitionBodyRange(term: $0, in: target) }
        let bodyOriginal = body.map { substring($0, in: target) }
        let statementRange = definitionStatementRange(
            term: term,
            target: target,
            fallback: assessment.statementText
        )
        return Anchors(
            primaryRange: statementRange,
            primaryOriginal: statementRange.map { substring($0, in: target) },
            termRange: termRange,
            termOriginal: termOriginal,
            bodyRange: body,
            bodyOriginal: bodyOriginal
        )
    }

    private func definitionStatementRange(
        term: String?,
        target: String,
        fallback: String
    ) -> NSRange? {
        if let term,
           let expression = try? NSRegularExpression(pattern: explicitPattern(for: term)) {
            let matches = expression.matches(
                in: target,
                range: NSRange(location: 0, length: target.utf16.count)
            )
            if matches.count > 1 {
                return nil
            }
            if let match = matches.first {
                return trimmedRange(match.range, in: target)
            }
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFallback.isEmpty else { return nil }
        return uniqueRange(of: trimmedFallback, in: target)
    }

    private func definitionBodyRange(term: String, in target: String) -> NSRange? {
        guard let expression = try? NSRegularExpression(pattern: explicitPattern(for: term, captureBody: true)) else {
            return nil
        }
        let matches = expression.matches(
            in: target,
            range: NSRange(location: 0, length: target.utf16.count)
        )
        guard matches.count == 1, let match = matches.first else { return nil }
        return trimmedBodyRange(match.range(at: 1), in: target)
    }

    private func explicitPattern(for term: String, captureBody: Bool = false) -> String {
        let body = captureBody ? "(.+?)" : ".+?"
        return "(?is)(?:[\\\"“”‘’']\\s*)?(?:yang\\s+dimaksud\\s+dengan\\s+)?"
            + NSRegularExpression.escapedPattern(for: term)
            + "(?:\\s*[\\\"“”‘’'])?"
            + "\\s*[,;:]?\\s*(?:adalah|ialah|merupakan|berarti|didefinisikan\\s+sebagai|diartikan\\s+sebagai)\\s+"
            + body + "[.!?;]?$"
    }

    private func contractDefined(in text: String) -> Bool {
        text.range(
            of: #"(?i)\b(?:dalam\s+(?:dokumen|perjanjian)\s+ini|khusus\s+untuk|selanjutnya\s+disebut|didefinisikan\s+(?:dalam|oleh))\b"#,
            options: .regularExpression
        ) != nil
    }

    private func isEligibleSource(_ entry: LegalDictionaryEntry) -> Bool {
        entry.authority == .verified
            && entry.isActionable
            && entry.applicabilityStatus == .inForce
            && entry.corpusVersion != LegalCorpusDictionaryVersion.legacyKamusV1
            && entry.corpusVersion != LegalCorpusDictionaryVersion.legacyRAGExportV1
    }

    private func sourceEligibilityMessage(_ entry: LegalDictionaryEntry) -> String {
        guard entry.authority == .verified, entry.isActionable else {
            return "Sumber ini belum ditandai sebagai sumber terverifikasi yang dapat diterapkan."
        }
        guard entry.applicabilityStatus == .inForce else {
            return entry.applicabilityStatus == .notInForce
                ? "Sumber ini tercatat tidak berlaku."
                : "Status keberlakuan sumber belum diketahui."
        }
        return "Sumber ini belum memenuhi syarat penerapan."
    }

    private func makeReference(
        for candidate: AIConnectorDefinitionCandidate,
        sourceDefinition: String
    ) -> EditorSuggestionReference {
        makeReference(entry: candidate.match.entry, sourceDefinition: sourceDefinition)
    }

    private func makeReference(
        entry: LegalDictionaryEntry,
        sourceDefinition: String
    ) -> EditorSuggestionReference {
        EditorSuggestionReference(
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

    private func sourceDefinitionBody(from source: String, term: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count >= term.count else { return trimmed }
        let termEnd = trimmed.index(trimmed.startIndex, offsetBy: term.count)
        let prefix = String(trimmed[..<termEnd])
        guard prefix.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
            return trimmed
        }
        let suffix = String(trimmed[termEnd...])
        let pattern = #"(?is)^\s*[,;:]?\s*(?:adalah|ialah|merupakan|berarti|didefinisikan\s+sebagai|diartikan\s+sebagai)\s+(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: suffix, range: NSRange(location: 0, length: suffix.utf16.count)) else {
            return trimmed
        }
        return (suffix as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preserveTerminalPunctuation(_ replacement: String, from original: String) -> String {
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let punctuation = original.trimmingCharacters(in: .whitespacesAndNewlines).last,
              ".,;:!?".contains(punctuation),
              trimmedReplacement.last.map({ !".,;:!?".contains($0) }) ?? true
        else {
            return replacement
        }
        return replacement + String(punctuation)
    }

    private func absoluteRange(_ local: NSRange, segment: AIReviewSegment) -> NSRange {
        NSRange(location: segment.sourceLocation + local.location, length: local.length)
    }

    private func substring(_ range: NSRange, in text: String) -> String {
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= text.utf16.count else { return "" }
        return (text as NSString).substring(with: range)
    }

    private func uniqueRange(
        of value: String,
        in text: String,
        options: NSString.CompareOptions = []
    ) -> NSRange? {
        guard !value.isEmpty else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var searchLocation = 0
        var match: NSRange?

        while searchLocation < nsText.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: nsText.length - searchLocation
            )
            let candidate = nsText.range(of: value, options: options, range: searchRange)
            guard candidate.location != NSNotFound else { break }
            if match != nil { return nil }
            match = candidate
            searchLocation = max(
                NSMaxRange(candidate),
                searchLocation + 1
            )
        }

        guard let match, NSMaxRange(match) <= fullRange.length else { return nil }
        return match
    }

    private func trimmedRange(_ range: NSRange, in text: String) -> NSRange {
        trimmedBodyRange(range, in: text)
    }

    private func trimmedBodyRange(_ range: NSRange, in text: String) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let nsText = text as NSString
        while start < end, nsText.character(at: start).isWhitespaceASCII { start += 1 }
        while end > start, nsText.character(at: end - 1).isWhitespaceASCII { end -= 1 }
        if end > start, nsText.character(at: end - 1).isTerminalPunctuation {
            end -= 1
            while end > start, nsText.character(at: end - 1).isWhitespaceASCII { end -= 1 }
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
    }

    private func normalizedDefinition(_ value: String) -> String {
        normalize(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension unichar {
    var isWhitespaceASCII: Bool {
        self == 9 || self == 10 || self == 13 || self == 32
    }

    var isTerminalPunctuation: Bool {
        self == 46 || self == 59 || self == 63 || self == 33
    }
}

private enum LegalCorpusDictionaryVersion {
    static let legacyKamusV1 = "legacy-kamus-v1"
    static let legacyRAGExportV1 = "legacy-rag-export-v1"
}
