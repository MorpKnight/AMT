import Foundation

nonisolated enum LegalDictionaryEntryAuthority: String, Codable, Hashable, Sendable {
    case legacy
    case verified
}

nonisolated enum LegalDictionaryCorpusVersion {
    static let legacyKamusV1 = "legacy-kamus-v1"
    static let legacyRAGExportV1 = "legacy-rag-export-v1"
    static let previewV1 = "preview-v1"
    static let unspecifiedLegacy = "unspecified-legacy"
}

nonisolated struct LegalDictionaryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let term: String
    let definition: String
    let regulation: String
    let regulationTitle: String
    let sourceURL: URL?
    let officialDocumentURL: URL?
    let referenceID: String?
    let authority: LegalDictionaryEntryAuthority
    let corpusVersion: String
    let applicabilityStatus: LegalCorpusApplicabilityStatus
    let sourcePassageID: String?
    let articleLocator: String?
    let pageStart: Int?
    let pageEnd: Int?
    let isActionable: Bool

    init(
        id: String,
        term: String,
        definition: String,
        regulation: String,
        regulationTitle: String,
        sourceURL: URL?,
        officialDocumentURL: URL? = nil,
        referenceID: String? = nil,
        authority: LegalDictionaryEntryAuthority = .legacy,
        corpusVersion: String = LegalDictionaryCorpusVersion.unspecifiedLegacy,
        applicabilityStatus: LegalCorpusApplicabilityStatus = .unknown,
        sourcePassageID: String? = nil,
        articleLocator: String? = nil,
        pageStart: Int? = nil,
        pageEnd: Int? = nil,
        isActionable: Bool? = nil
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.regulation = regulation
        self.regulationTitle = regulationTitle
        self.sourceURL = sourceURL
        self.officialDocumentURL = officialDocumentURL
        self.referenceID = referenceID
        self.authority = authority
        self.corpusVersion = corpusVersion
        self.applicabilityStatus = applicabilityStatus
        self.sourcePassageID = sourcePassageID
        self.articleLocator = articleLocator
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.isActionable = isActionable ?? (authority == .verified)
    }

    nonisolated static let previewEntries = [
        LegalDictionaryEntry(
            id: "preview-data-pribadi",
            term: "Data Pribadi",
            definition: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi.",
            regulation: "Undang-Undang Nomor 27 Tahun 2022",
            regulationTitle: "Pelindungan Data Pribadi",
            sourceURL: nil,
            authority: .legacy,
            corpusVersion: LegalDictionaryCorpusVersion.previewV1
        ),
        LegalDictionaryEntry(
            id: "preview-hukum-adat",
            term: "Hukum Adat",
            definition: "Aturan atau norma tidak tertulis yang hidup dalam masyarakat hukum adat.",
            regulation: "Undang-Undang Nomor 21 Tahun 2001",
            regulationTitle: "Otonomi Khusus bagi Provinsi Papua",
            sourceURL: nil,
            authority: .legacy,
            corpusVersion: LegalDictionaryCorpusVersion.previewV1
        )
    ]
}

/// A source-backed glossary candidate returned by the local retrieval index.
nonisolated struct LegalDictionaryMatch: Identifiable, Hashable, Sendable {
    let entry: LegalDictionaryEntry
    let score: Double
    let rank: Int
    let matchedDefinitionTokenCount: Int
    let isDirectTermMatch: Bool
    let semanticScore: Float?
    let fusionScore: Double?
    let retrievalOrigin: LegalRetrievalOrigin?

    var id: String { entry.id }

    init(
        entry: LegalDictionaryEntry,
        score: Double,
        rank: Int,
        matchedDefinitionTokenCount: Int,
        isDirectTermMatch: Bool,
        semanticScore: Float? = nil,
        fusionScore: Double? = nil,
        retrievalOrigin: LegalRetrievalOrigin? = nil
    ) {
        self.entry = entry
        self.score = score
        self.rank = rank
        self.matchedDefinitionTokenCount = matchedDefinitionTokenCount
        self.isDirectTermMatch = isDirectTermMatch
        self.semanticScore = semanticScore
        self.fusionScore = fusionScore
        self.retrievalOrigin = retrievalOrigin
    }
}

nonisolated struct LegalDictionaryStore: Sendable {
    private static let suggestionMinimumScore = 20.0
    private static let suggestionMinimumMargin = 3.0
    private static let suggestionMinimumMatchedDefinitionTokens = 4

    private struct RetrievalIndexEntry: Sendable {
        let termTokens: [String]
        let definitionTokenSet: Set<String>
        let termFrequencies: [String: Int]
        let tokenCount: Int
    }

    let entries: [LegalDictionaryEntry]
    private let localRAG: LocalRAG
    let corpusStore: LegalCorpusStore?
    let semanticRetriever: LegalSemanticRetriever?
    private let retrievalIndex: [RetrievalIndexEntry]
    private let inverseDocumentFrequencies: [String: Double]
    private let averageDocumentLength: Double

    var activeCorpusVersion: String {
        corpusStore?.manifest.corpusVersion ?? LegalDictionaryCorpusVersion.legacyKamusV1
    }

    var semanticModelRevision: String {
        corpusStore?.manifest.embedding.revision ?? "none"
    }

    var semanticRetrievalConfiguration: LegalCorpusRetrievalConfiguration? {
        corpusStore?.manifest.retrieval
    }

    var semanticEmbeddingSchema: String {
        corpusStore?.manifest.embedding.cacheKey ?? "none"
    }

    var semanticRetrievalProfile: String {
        corpusStore?.manifest.retrieval.cacheKey ?? "none"
    }

    nonisolated init(
        bundle: Bundle = .main,
        localRAG: LocalRAG = .shared,
        corpusStore: LegalCorpusStore? = nil,
        semanticRetriever: LegalSemanticRetriever? = nil
    ) {
        let loadedCorpus = corpusStore ?? (try? LegalCorpusStore(bundle: bundle))
        if let loadedCorpus {
            let corpusEntries = loadedCorpus.dictionaryEntries()
            let corpusTerms = Set(corpusEntries.map { Self.normalize($0.term) })
            let supplementalLegacyEntries: [LegalDictionaryEntry]
            if let resourceURL = bundle.url(forResource: "kamus_hukum", withExtension: "csv"),
               let data = try? Data(contentsOf: resourceURL),
               let loadedEntries = Self.loadEntries(from: data) {
                // Keep the verified corpus authoritative for terms it owns.
                // The older CSV still supplies Dictionary-only coverage for
                // concepts not present in the versioned pack, such as a term
                // that is useful for local lookup but lacks current evidence.
                supplementalLegacyEntries = loadedEntries.filter {
                    !corpusTerms.contains(Self.normalize($0.term))
                }
            } else {
                supplementalLegacyEntries = []
            }
            self.init(
                entries: corpusEntries + supplementalLegacyEntries,
                localRAG: localRAG,
                corpusStore: loadedCorpus,
                semanticRetriever: semanticRetriever ?? LegalSemanticRetriever(corpus: loadedCorpus)
            )
        } else if let resourceURL = bundle.url(forResource: "kamus_hukum", withExtension: "csv"),
           let data = try? Data(contentsOf: resourceURL),
           let loadedEntries = Self.loadEntries(from: data),
           !loadedEntries.isEmpty {
            self.init(entries: loadedEntries, localRAG: localRAG)
        } else {
            self.init(entries: LegalDictionaryEntry.previewEntries, localRAG: localRAG)
        }
    }

    nonisolated init(
        entries: [LegalDictionaryEntry],
        localRAG: LocalRAG = .shared,
        corpusStore: LegalCorpusStore? = nil,
        semanticRetriever: LegalSemanticRetriever? = nil
    ) {
        self.entries = entries
        self.localRAG = localRAG
        self.corpusStore = corpusStore
        self.semanticRetriever = semanticRetriever

        let index = entries.map { entry in
            let retrievalDefinition = Self.retrievalDefinition(for: entry)
            let searchableText = [
                entry.term,
                retrievalDefinition,
                entry.regulation,
                entry.regulationTitle
            ].joined(separator: " ")
            let tokens = Self.tokenize(searchableText)

            return RetrievalIndexEntry(
                termTokens: Self.tokenize(entry.term),
                definitionTokenSet: Set(Self.tokenize(retrievalDefinition)),
                termFrequencies: Self.termFrequencies(for: tokens),
                tokenCount: tokens.count
            )
        }
        retrievalIndex = index

        var documentFrequency: [String: Int] = [:]
        for document in index {
            for token in document.termFrequencies.keys {
                documentFrequency[token, default: 0] += 1
            }
        }

        let documentCount = Double(index.count)
        inverseDocumentFrequencies = Dictionary(uniqueKeysWithValues: documentFrequency.map { token, frequency in
            let frequency = Double(frequency)
            return (
                token,
                log(1.0 + (documentCount - frequency + 0.5) / (frequency + 0.5))
            )
        })
        averageDocumentLength = index.isEmpty
            ? 0
            : Double(index.reduce(0) { $0 + $1.tokenCount }) / documentCount
    }

    nonisolated func search(_ query: String, limit: Int = 30) -> [LegalDictionaryEntry] {
        rankedSearch(query, limit: limit).map(\.entry)
    }

    /// Returns every definition attached to the same canonical term. The
    /// corpus intentionally keeps these records separate so Dictionary can
    /// show competing definitions and their individual provenance.
    nonisolated func entries(forTerm term: String) -> [LegalDictionaryEntry] {
        let normalizedTerm = Self.normalize(term)
        guard !normalizedTerm.isEmpty else { return [] }

        return entries.filter { Self.normalize($0.term) == normalizedTerm }
    }

    nonisolated func regulationRelations(
        for entry: LegalDictionaryEntry
    ) -> [LegalRegulationRelation] {
        guard let corpusStore, let referenceID = entry.referenceID else { return [] }
        return corpusStore.relations(for: referenceID)
    }

    nonisolated func isSemanticModelLoaded() async -> Bool {
        guard let semanticRetriever else { return false }
        return await semanticRetriever.isLoaded
    }

    nonisolated private func rankedSearch(
        _ query: String,
        limit: Int
    ) -> [(entry: LegalDictionaryEntry, score: Double)] {
        let normalizedQuery = Self.normalize(query)
        let queryTokens = Array(Set(Self.tokenize(query)))
        guard limit > 0, !normalizedQuery.isEmpty, !queryTokens.isEmpty else {
            return []
        }

        return entries.indices
            .compactMap { index -> (entry: LegalDictionaryEntry, score: Double)? in
                let entry = entries[index]
                let normalizedTerm = Self.normalize(entry.term)
                let normalizedDefinition = Self.normalize(entry.definition)
                var score = bm25Score(queryTokens: queryTokens, documentIndex: index)

                if normalizedTerm == normalizedQuery {
                    score += 1_000
                } else if normalizedTerm.hasPrefix(normalizedQuery) {
                    score += 300
                } else if normalizedTerm.contains(normalizedQuery) {
                    score += 150
                }

                if normalizedDefinition.contains(normalizedQuery) {
                    score += 100
                }

                return score > 0 ? (entry, score) : nil
            }
            .sorted { lhs, rhs in
                let lhsIsExactTerm = Self.normalize(lhs.entry.term) == normalizedQuery
                let rhsIsExactTerm = Self.normalize(rhs.entry.term) == normalizedQuery
                if lhsIsExactTerm != rhsIsExactTerm {
                    return lhsIsExactTerm
                }
                if lhsIsExactTerm && rhsIsExactTerm,
                   lhs.entry.authority != rhs.entry.authority {
                    return lhs.entry.authority == .verified
                }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.entry.authority != rhs.entry.authority {
                    return lhs.entry.authority == .verified
                }
                let lhsCorpusPriority = Self.corpusPriority(lhs.entry.corpusVersion)
                let rhsCorpusPriority = Self.corpusPriority(rhs.entry.corpusVersion)
                if lhsCorpusPriority != rhsCorpusPriority {
                    return lhsCorpusPriority > rhsCorpusPriority
                }
                return lhs.entry.term.localizedCaseInsensitiveCompare(rhs.entry.term) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Searches the versioned corpus. Exact and prefix term queries stay
    /// lexical and therefore work offline; reverse lookup uses equal-weight
    /// BM25 + E5 reciprocal-rank fusion when the semantic model is available.
    /// A failed E5 load is intentionally contained and falls back to BM25.
    nonisolated func searchRAG(
        _ query: String,
        limit: Int = 30,
        semanticProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [LegalDictionaryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !trimmedQuery.isEmpty else { return [] }

        if corpusStore != nil, semanticRetriever != nil {
            let normalizedQuery = Self.normalize(trimmedQuery)
            let hasLexicalShortcut = entries.contains { entry in
                let term = Self.normalize(entry.term)
                let regulation = Self.normalize(
                    "\(entry.regulation) \(entry.regulationTitle)"
                )
                return term == normalizedQuery
                    || term.hasPrefix(normalizedQuery)
                    || regulation.contains(normalizedQuery)
            }
            if hasLexicalShortcut {
                return search(trimmedQuery, limit: limit)
            }

            let request = LegalRetrievalRequest(
                query: trimmedQuery,
                intent: .reverseLookup,
                limit: limit
            )
            if let matches = try? await hybridMatches(
                request,
                semanticProgress: semanticProgress
            ), !matches.isEmpty {
                return matches.compactMap { match in
                    entries.first { $0.id == match.concept.recordID }
                }
            }
            return search(trimmedQuery, limit: limit)
        }

        let retrievalLimit = max(limit * 6, 30)
        async let primaryEntries = Task.detached(priority: .userInitiated) {
            self.search(trimmedQuery, limit: retrievalLimit)
        }.value

        let legacyMatches = (try? await localRAG.searchByKeyword(
            query: trimmedQuery,
            topK: retrievalLimit
        )) ?? []
        let primary = await primaryEntries
        let legacyEntries = legacyMatches.map { match in
            LegalDictionaryEntry(
                id: "rag-lexical-\(match.rank)-\(match.document.istilah)",
                term: match.document.istilah,
                definition: match.document.pengertian,
                regulation: match.document.undangUndang,
                regulationTitle: "",
                sourceURL: URL(string: match.document.url),
                authority: .legacy,
                corpusVersion: LegalDictionaryCorpusVersion.legacyRAGExportV1
            )
        }
        let mergedEntries = Self.deduplicatedEntries(primary + legacyEntries)

        return await Task.detached(priority: .userInitiated) {
            LegalDictionaryStore(entries: mergedEntries, localRAG: self.localRAG)
                .search(trimmedQuery, limit: limit)
        }.value
    }

    /// Returns source-backed retrieval matches for Dictionary and future
    /// suggestion span retrieval. The method is also useful to diagnostics
    /// because it preserves lexical, semantic, and fused scores separately.
    nonisolated func retrieve(
        _ request: LegalRetrievalRequest,
        semanticProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> [LegalRetrievalMatch] {
        guard request.limit > 0,
              !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        if request.intent == .exactTerm {
            return lexicalMatches(
                for: request.query,
                limit: request.limit,
                origin: .exact
            )
        }

        if corpusStore != nil, semanticRetriever != nil {
            return try await hybridMatches(request, semanticProgress: semanticProgress)
        }

        return lexicalMatches(
            for: request.query,
            limit: request.limit,
            origin: .lexical
        )
    }

    /// Suggestion retrieval remains conservative: legacy records are exposed
    /// to Dictionary/diagnostics but cannot become terminology candidates.
    /// Semantic failure returns lexical candidates so spelling and grammar do
    /// not stop when E5 is unavailable.
    nonisolated func suggestionCandidatesAsync(
        for text: String,
        limit: Int = 3,
        semanticProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> [LegalDictionaryMatch] {
        guard limit > 0 else { return [] }

        if corpusStore != nil, semanticRetriever != nil {
            let effectiveLimit = min(
                limit,
                corpusStore?.manifest.retrieval.suggestionCandidateLimit ?? limit
            )
            guard effectiveLimit > 0 else { return [] }
            let queries = Self.retrievalQueries(for: text)
            let queryCount = max(1, queries.count)
            var matchesByEntryID: [String: LegalDictionaryMatch] = [:]

            for (queryIndex, query) in queries.enumerated() {
                if Task.isCancelled {
                    return []
                }
                let request = LegalRetrievalRequest(
                    query: query,
                    intent: .suggestion,
                    limit: max(
                        3,
                        min(100, corpusStore?.manifest.retrieval.semanticTopK ?? 100)
                    )
                )
                guard let hybrid = try? await hybridMatches(
                    request,
                    semanticProgress: { progress in
                        let overall = (Double(queryIndex) + progress) / Double(queryCount)
                        semanticProgress(overall)
                    }
                ) else {
                    continue
                }
                if Task.isCancelled {
                    return []
                }

                for match in makeSuggestionMatches(
                    from: hybrid,
                    text: query,
                    limit: effectiveLimit
                ) {
                    if let previous = matchesByEntryID[match.entry.id] {
                        if Self.isBetterSuggestionMatch(match, than: previous) {
                            matchesByEntryID[match.entry.id] = match
                        }
                    } else {
                        matchesByEntryID[match.entry.id] = match
                    }
                }
            }

            semanticProgress(1)
            return matchesByEntryID.values
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.entry.id < rhs.entry.id
                }
                .prefix(effectiveLimit)
                .map { $0 }
        }

        return suggestionCandidates(for: text, limit: limit)
            .filter { $0.entry.isActionable }
    }

    private nonisolated func lexicalMatches(
        for query: String,
        limit: Int,
        origin: LegalRetrievalOrigin
    ) -> [LegalRetrievalMatch] {
        guard let corpusStore, limit > 0 else { return [] }

        return rankedSearch(query, limit: limit).enumerated().compactMap { rank, item in
            guard let concept = corpusStore.concept(id: item.entry.id) else { return nil }
            let evidence = concept.actionableEvidence ?? concept.evidence.first
            return LegalRetrievalMatch(
                concept: concept,
                evidence: evidence,
                lexicalScore: item.score,
                semanticScore: nil,
                fusionScore: nil,
                rank: rank + 1,
                origin: origin,
                isActionable: item.entry.isActionable
            )
        }
    }

    private nonisolated func hybridMatches(
        _ request: LegalRetrievalRequest,
        semanticProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> [LegalRetrievalMatch] {
        guard let corpusStore, let semanticRetriever else { return [] }

        let retrievalConfiguration = corpusStore.manifest.retrieval
        let lexicalLimit = max(
            request.limit,
            retrievalConfiguration.lexicalTopK
        )
        let semanticLimit = max(
            request.limit,
            retrievalConfiguration.semanticTopK
        )
        let lexical = rankedSearch(request.query, limit: lexicalLimit)
        let semantic = try await semanticRetriever.search(
            request.query,
            limit: semanticLimit,
            progress: semanticProgress
        )

        struct Accumulator {
            let concept: LegalConcept
            let evidence: LegalSourceEvidence?
            var lexicalScore: Double?
            var semanticScore: Float?
            var lexicalRank: Int?
            var semanticRank: Int?
        }

        var accumulator: [String: Accumulator] = [:]
        for (zeroBasedRank, item) in lexical.enumerated() {
            guard let concept = corpusStore.concept(id: item.entry.id) else { continue }
            var value = accumulator[item.entry.id] ?? Accumulator(
                concept: concept,
                evidence: concept.actionableEvidence ?? concept.evidence.first,
                lexicalScore: nil,
                semanticScore: nil,
                lexicalRank: nil,
                semanticRank: nil
            )
            value.lexicalScore = item.score
            value.lexicalRank = zeroBasedRank + 1
            accumulator[item.entry.id] = value
        }

        for (zeroBasedRank, item) in semantic.enumerated() {
            var value = accumulator[item.concept.recordID] ?? Accumulator(
                concept: item.concept,
                evidence: item.evidence,
                lexicalScore: nil,
                semanticScore: nil,
                lexicalRank: nil,
                semanticRank: nil
            )
            value.semanticScore = item.semanticScore
            value.semanticRank = zeroBasedRank + 1
            accumulator[item.concept.recordID] = value
        }

        let rrfK = Double(max(1, retrievalConfiguration.rrfK))
        return accumulator.values
            .map { value in
                let lexicalContribution = value.lexicalRank.map {
                    1.0 / (rrfK + Double($0))
                } ?? 0
                let semanticContribution = value.semanticRank.map {
                    1.0 / (rrfK + Double($0))
                } ?? 0
                let fusionScore = lexicalContribution + semanticContribution
                let origin: LegalRetrievalOrigin
                if value.lexicalRank != nil, value.semanticRank != nil {
                    origin = .hybrid
                } else if value.semanticRank != nil {
                    origin = .semantic
                } else {
                    origin = .lexical
                }

                return LegalRetrievalMatch(
                    concept: value.concept,
                    evidence: value.evidence,
                    lexicalScore: value.lexicalScore,
                    semanticScore: value.semanticScore,
                    fusionScore: fusionScore,
                    rank: 0,
                    origin: origin,
                    isActionable: value.concept.actionable
                )
            }
            .sorted { lhs, rhs in
                if lhs.fusionScore != rhs.fusionScore {
                    return (lhs.fusionScore ?? 0) > (rhs.fusionScore ?? 0)
                }
                if lhs.semanticScore != rhs.semanticScore {
                    return (lhs.semanticScore ?? -.greatestFiniteMagnitude)
                        > (rhs.semanticScore ?? -.greatestFiniteMagnitude)
                }
                return lhs.concept.recordID < rhs.concept.recordID
            }
            .prefix(request.limit)
            .enumerated()
            .map { rank, match in
                LegalRetrievalMatch(
                    concept: match.concept,
                    evidence: match.evidence,
                    lexicalScore: match.lexicalScore,
                    semanticScore: match.semanticScore,
                    fusionScore: match.fusionScore,
                    rank: rank + 1,
                    origin: match.origin,
                    isActionable: match.isActionable
                )
            }
    }

    private nonisolated func makeSuggestionMatches(
        from matches: [LegalRetrievalMatch],
        text: String,
        limit: Int
    ) -> [LegalDictionaryMatch] {
        guard let corpusStore, limit > 0 else { return [] }
        let configuration = corpusStore.manifest.retrieval
        let semanticCandidates = matches
            // Historical/unresolved concepts may rank highly for a semantic
            // query, but they must not participate in the suggestion margin
            // or become terminology candidates.
            .filter { $0.semanticScore != nil && $0.isActionable }
            .sorted { lhs, rhs in
                if lhs.semanticScore != rhs.semanticScore {
                    return (lhs.semanticScore ?? -.greatestFiniteMagnitude)
                        > (rhs.semanticScore ?? -.greatestFiniteMagnitude)
                }
                return lhs.concept.recordID < rhs.concept.recordID
            }
        guard let first = semanticCandidates.first,
              let firstScore = first.semanticScore,
              firstScore >= configuration.suggestionSemanticThreshold else {
            return []
        }

        let secondScore = semanticCandidates.dropFirst().first?.semanticScore ?? 0
        guard semanticCandidates.count == 1
            || firstScore - secondScore >= configuration.suggestionTopOneMargin else {
            return []
        }

        return semanticCandidates
            .filter {
                $0.isActionable
                    && ($0.semanticScore ?? -.greatestFiniteMagnitude)
                        >= configuration.suggestionSemanticThreshold
            }
            .compactMap { match in
                guard let entry = entries.first(where: { $0.id == match.concept.recordID }) else {
                    return nil
                }
                let definitionTokens = Set(Self.tokenize(entry.definition))
                let textTokens = Self.tokenize(text)
                let termTokens = Self.tokenize(entry.term)
                let matchedDefinitionTokenCount = Set(textTokens)
                    .intersection(definitionTokens)
                    .count
                let isDirectTermMatch = !termTokens.isEmpty
                    && Self.containsTokenSequence(textTokens, termTokens)

                return LegalDictionaryMatch(
                    entry: entry,
                    score: match.fusionScore ?? Double(match.semanticScore ?? 0),
                    rank: match.rank,
                    matchedDefinitionTokenCount: matchedDefinitionTokenCount,
                    isDirectTermMatch: isDirectTermMatch,
                    semanticScore: match.semanticScore,
                    fusionScore: match.fusionScore,
                    retrievalOrigin: match.origin
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    private nonisolated static func retrievalQueries(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let clauses = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tokenize($0).count >= 2 }

        var queries: [String] = [trimmed]
        var seen = Set([normalize(trimmed)])
        for clause in clauses where seen.insert(normalize(clause)).inserted {
            queries.append(clause)
        }
        return queries
    }

    private nonisolated static func isBetterSuggestionMatch(
        _ candidate: LegalDictionaryMatch,
        than existing: LegalDictionaryMatch
    ) -> Bool {
        if candidate.score != existing.score { return candidate.score > existing.score }
        if candidate.semanticScore != existing.semanticScore {
            return (candidate.semanticScore ?? -.greatestFiniteMagnitude)
                > (existing.semanticScore ?? -.greatestFiniteMagnitude)
        }
        if candidate.matchedDefinitionTokenCount != existing.matchedDefinitionTokenCount {
            return candidate.matchedDefinitionTokenCount
                > existing.matchedDefinitionTokenCount
        }
        return candidate.entry.id < existing.entry.id
    }

    nonisolated func relatedTerms(
        excluding currentTerm: String,
        limit: Int = 4
    ) -> [String] {
        guard limit > 0 else { return [] }
        let excluded = Self.normalize(currentTerm)
        var seen: Set<String> = []

        return entries.compactMap { entry -> String? in
            let normalizedTerm = Self.normalize(entry.term)
            guard !normalizedTerm.isEmpty,
                  normalizedTerm != excluded,
                  seen.insert(normalizedTerm).inserted else {
                return nil
            }
            return entry.term
        }
        .prefix(limit)
        .map { $0 }
    }


    /// Returns only a conservative, source-backed candidate for model context.
    ///
    /// The score threshold and margin are calibrated against the current full
    /// glossary as a provisional guard. They are intentionally stricter than
    /// ordinary dictionary search because an unrelated candidate can mislead a
    /// suggestion model. This method returns no candidate when the evidence is
    /// weak or ambiguous.
    nonisolated func suggestionCandidates(for text: String, limit: Int = 3) -> [LegalDictionaryMatch] {
        guard limit > 0 else { return [] }

        let queryTokens = Self.tokenize(text)
        guard !queryTokens.isEmpty, !entries.isEmpty else { return [] }

        let uniqueTermIndices = Dictionary(grouping: entries.indices, by: { index in
            Self.normalize(entries[index].term)
        })
            .compactMapValues { indices in
                indices.max { lhs, rhs in
                    bm25Score(queryTokens: queryTokens, documentIndex: lhs)
                        < bm25Score(queryTokens: queryTokens, documentIndex: rhs)
                }
            }

        let directTermIndices = uniqueTermIndices.values.filter { index in
            let termTokens = retrievalIndex[index].termTokens
            return termTokens.count >= 2
                && Self.containsTokenSequence(queryTokens, termTokens)
        }
        .sorted { lhs, rhs in
            let lhsTokens = retrievalIndex[lhs].termTokens.count
            let rhsTokens = retrievalIndex[rhs].termTokens.count
            if lhsTokens != rhsTokens { return lhsTokens > rhsTokens }
            return entries[lhs].term.localizedCaseInsensitiveCompare(entries[rhs].term) == .orderedAscending
        }

        let scored = uniqueTermIndices.values.compactMap { index -> LegalDictionaryMatch? in
            let score = bm25Score(queryTokens: queryTokens, documentIndex: index)
            guard score > 0 else { return nil }

            let document = retrievalIndex[index]
            let matchedDefinitionTokenCount = Set(queryTokens)
                .intersection(document.definitionTokenSet)
                .count
            let isDirectTermMatch = document.termTokens.count >= 2
                && Self.containsTokenSequence(queryTokens, document.termTokens)

            return LegalDictionaryMatch(
                entry: entries[index],
                score: score,
                rank: 0,
                matchedDefinitionTokenCount: matchedDefinitionTokenCount,
                isDirectTermMatch: isDirectTermMatch
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.term.localizedCaseInsensitiveCompare(rhs.entry.term) == .orderedAscending
        }

        guard let first = scored.first else { return [] }

        let secondScore = scored.dropFirst().first?.score ?? 0
        let margin = first.score - secondScore
        if first.score >= Self.suggestionMinimumScore,
           first.matchedDefinitionTokenCount >= Self.suggestionMinimumMatchedDefinitionTokens,
           (scored.count == 1 || margin >= Self.suggestionMinimumMargin) {
            return scored
                .filter {
                    $0.score >= Self.suggestionMinimumScore
                        && $0.matchedDefinitionTokenCount
                            >= Self.suggestionMinimumMatchedDefinitionTokens
                }
                .prefix(limit)
                .enumerated()
                .map { index, match in
                    LegalDictionaryMatch(
                        entry: match.entry,
                        score: match.score,
                        rank: index + 1,
                        matchedDefinitionTokenCount: match.matchedDefinitionTokenCount,
                        isDirectTermMatch: match.isDirectTermMatch
                    )
                }
        }

        return directTermIndices.prefix(limit).enumerated().map { rank, index in
            LegalDictionaryMatch(
                entry: entries[index],
                score: bm25Score(queryTokens: queryTokens, documentIndex: index),
                rank: rank + 1,
                matchedDefinitionTokenCount: Set(queryTokens)
                    .intersection(retrievalIndex[index].definitionTokenSet)
                    .count,
                isDirectTermMatch: true
            )
        }
    }

    nonisolated private func bm25Score(queryTokens: [String], documentIndex: Int) -> Double {
        guard !queryTokens.isEmpty,
              let document = retrievalIndex[safe: documentIndex],
              averageDocumentLength > 0 else {
            return 0
        }

        let k1 = 1.5
        let b = 0.75
        let documentLength = Double(document.tokenCount)
        let normalization = 1.0 - b + b * (documentLength / averageDocumentLength)
        var score = 0.0

        for token in queryTokens {
            let frequency = Double(document.termFrequencies[token] ?? 0)
            guard frequency > 0 else { continue }

            let numerator = frequency * (k1 + 1.0)
            let denominator = frequency + k1 * normalization
            score += (inverseDocumentFrequencies[token] ?? 0) * numerator / denominator
        }

        return score
    }

    nonisolated private static func deduplicatedEntries(
        _ candidates: [LegalDictionaryEntry]
    ) -> [LegalDictionaryEntry] {
        var selected: [LegalDictionaryEntry] = []
        var indexByTerm: [String: Int] = [:]

        for candidate in candidates {
            let key = normalize(candidate.term)
            guard !key.isEmpty else { continue }

            if let existingIndex = indexByTerm[key] {
                if shouldPrefer(candidate, over: selected[existingIndex]) {
                    selected[existingIndex] = candidate
                }
            } else {
                indexByTerm[key] = selected.count
                selected.append(candidate)
            }
        }

        return selected
    }

    nonisolated private static func shouldPrefer(
        _ candidate: LegalDictionaryEntry,
        over existing: LegalDictionaryEntry
    ) -> Bool {
        if candidate.authority != existing.authority {
            return candidate.authority == .verified
        }

        let candidatePriority = corpusPriority(candidate.corpusVersion)
        let existingPriority = corpusPriority(existing.corpusVersion)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }

        return existing.sourceURL == nil && candidate.sourceURL != nil
    }

    nonisolated private static func corpusPriority(_ corpusVersion: String) -> Int {
        switch corpusVersion {
        case LegalDictionaryCorpusVersion.legacyKamusV1:
            3
        case LegalDictionaryCorpusVersion.legacyRAGExportV1:
            2
        case LegalDictionaryCorpusVersion.previewV1:
            1
        default:
            0
        }
    }

    nonisolated private static func loadEntries(from data: Data) -> [LegalDictionaryEntry]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let rows = CSVParser.parse(text)
        guard let headerRow = rows.first else { return nil }

        let headers = headerRow.map {
            $0.replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        return rows.dropFirst().enumerated().compactMap { index, row -> LegalDictionaryEntry? in
            let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
            guard let term = values["istilah"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let definition = values["pengertian"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty,
                  !definition.isEmpty else {
                return nil
            }

            let authority: LegalDictionaryEntryAuthority
            if let status = values["status"], !status.isEmpty {
                if status.caseInsensitiveCompare("VERIFIED") == .orderedSame {
                    authority = .verified
                } else if status.caseInsensitiveCompare("OK") == .orderedSame {
                    authority = .legacy
                } else {
                    return nil
                }
            } else {
                authority = .legacy
            }

            return LegalDictionaryEntry(
                id: "csv-\(index)-\(term)",
                term: term,
                definition: definition,
                regulation: values["undang_undang"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                regulationTitle: values["uu"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceURL: URL(string: values["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
                authority: authority,
                corpusVersion: LegalDictionaryCorpusVersion.legacyKamusV1,
                isActionable: false
            )
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func tokenize(_ value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    nonisolated private static func termFrequencies(for tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
    }

    nonisolated private static func retrievalDefinition(for entry: LegalDictionaryEntry) -> String {
        let normalizedTerm = normalize(entry.term)
        let normalizedDefinition = normalize(entry.definition)

        for connector in ["adalah", "ialah", "merupakan"] {
            let prefix = "\(normalizedTerm) \(connector) "
            if normalizedDefinition.hasPrefix(prefix) {
                return String(normalizedDefinition.dropFirst(prefix.count))
            }
        }

        return normalizedDefinition
    }

    nonisolated private static func containsTokenSequence(_ tokens: [String], _ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= tokens.count else { return false }

        for start in 0...(tokens.count - sequence.count) {
            if Array(tokens[start..<(start + sequence.count)]) == sequence {
                return true
            }
        }

        return false
    }
}

private extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private enum CSVParser {
    nonisolated static func parse(_ input: String) -> [[String]] {
        let characters = Array(input)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isQuoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        isQuoted = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            switch character {
            case "\"":
                isQuoted = true
                index += 1
            case ",":
                row.append(field)
                field = ""
                index += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
            case "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
                if index < characters.count, characters[index] == "\n" {
                    index += 1
                }
            default:
                field.append(character)
                index += 1
            }
        }

        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
