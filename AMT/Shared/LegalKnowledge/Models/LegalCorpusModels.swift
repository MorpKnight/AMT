import Foundation

nonisolated enum LegalCorpusApplicabilityStatus: String, Codable, Hashable, Sendable {
    case inForce = "in_force"
    case notInForce = "not_in_force"
    case unknown

    var displayTitle: String {
        switch self {
        case .inForce:
            "Berlaku"
        case .notInForce:
            "Tidak berlaku"
        case .unknown:
            "Status belum diketahui"
        }
    }
}

nonisolated enum LegalCorpusReviewStatus: String, Codable, Hashable, Sendable {
    case machineExact = "machine_exact_unreviewed"
    case humanVerified = "human_verified"
    case needsReview = "needs_human_review"
}

nonisolated struct LegalCorpusReference: Codable, Hashable, Sendable {
    let referenceID: String
    let displayName: String
    let officialDetailURL: URL?
    let officialDocumentURL: URL?
    let officialTitle: String
    let officialStatus: String
    let officialStatusCode: LegalCorpusApplicabilityStatus?

    enum CodingKeys: String, CodingKey {
        case referenceID = "reference_id"
        case displayName = "display_name"
        case officialDetailURL = "official_detail_url"
        case officialDocumentURL = "official_document_url"
        case officialTitle = "official_title"
        case officialStatus = "official_status"
        case officialStatusCode = "official_status_code"
    }

    init(
        referenceID: String,
        displayName: String,
        officialDetailURL: URL?,
        officialDocumentURL: URL?,
        officialTitle: String,
        officialStatus: String,
        officialStatusCode: LegalCorpusApplicabilityStatus?
    ) {
        self.referenceID = referenceID
        self.displayName = displayName
        self.officialDetailURL = officialDetailURL
        self.officialDocumentURL = officialDocumentURL
        self.officialTitle = officialTitle
        self.officialStatus = officialStatus
        self.officialStatusCode = officialStatusCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        referenceID = try container.decode(String.self, forKey: .referenceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        officialDetailURL = try container.decodeIfPresent(URL.self, forKey: .officialDetailURL)
        officialDocumentURL = try container.decodeIfPresent(URL.self, forKey: .officialDocumentURL)
        officialTitle = try container.decodeIfPresent(String.self, forKey: .officialTitle) ?? ""
        officialStatus = try container.decodeIfPresent(String.self, forKey: .officialStatus) ?? ""

        let rawStatus = try container.decodeIfPresent(String.self, forKey: .officialStatusCode)
        officialStatusCode = rawStatus.flatMap { raw in
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LegalCorpusApplicabilityStatus(rawValue: raw) ?? .unknown
        }
    }
}

nonisolated struct LegalSourceEvidence: Codable, Hashable, Sendable {
    let passageID: String
    let referenceID: String
    let articleLocator: String?
    let pageStart: Int?
    let pageEnd: Int?
    let matchedDefinitionText: String
    let officialDetailURL: URL?
    let officialDocumentURL: URL?
    let regulationTitle: String
    let verificationStatus: LegalCorpusReviewStatus?

    enum CodingKeys: String, CodingKey {
        case passageID = "passage_id"
        case referenceID = "reference_id"
        case articleLocator = "article_locator"
        case pageStart = "page_start"
        case pageEnd = "page_end"
        case matchedDefinitionText = "matched_definition_text"
        case officialDetailURL = "official_detail_url"
        case officialDocumentURL = "official_document_url"
        case regulationTitle = "regulation_title"
        case verificationStatus = "verification_status"
    }

    init(
        passageID: String,
        referenceID: String,
        articleLocator: String?,
        pageStart: Int?,
        pageEnd: Int?,
        matchedDefinitionText: String,
        officialDetailURL: URL?,
        officialDocumentURL: URL?,
        regulationTitle: String,
        verificationStatus: LegalCorpusReviewStatus?
    ) {
        self.passageID = passageID
        self.referenceID = referenceID
        self.articleLocator = articleLocator
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.matchedDefinitionText = matchedDefinitionText
        self.officialDetailURL = officialDetailURL
        self.officialDocumentURL = officialDocumentURL
        self.regulationTitle = regulationTitle
        self.verificationStatus = verificationStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        passageID = try container.decode(String.self, forKey: .passageID)
        referenceID = try container.decode(String.self, forKey: .referenceID)
        articleLocator = try container.decodeIfPresent(String.self, forKey: .articleLocator)
        pageStart = try container.decodeIfPresent(Int.self, forKey: .pageStart)
        pageEnd = try container.decodeIfPresent(Int.self, forKey: .pageEnd)
        matchedDefinitionText = try container.decodeIfPresent(String.self, forKey: .matchedDefinitionText) ?? ""
        officialDetailURL = try container.decodeIfPresent(URL.self, forKey: .officialDetailURL)
        officialDocumentURL = try container.decodeIfPresent(URL.self, forKey: .officialDocumentURL)
        regulationTitle = try container.decodeIfPresent(String.self, forKey: .regulationTitle) ?? ""

        let rawStatus = try container.decodeIfPresent(String.self, forKey: .verificationStatus)
        verificationStatus = rawStatus.flatMap { LegalCorpusReviewStatus(rawValue: $0) }
    }
}

nonisolated struct LegalConcept: Identifiable, Codable, Hashable, Sendable {
    let recordID: String
    let termID: String
    let term: String
    let definition: String
    let definitionIndex: Int
    let references: [LegalCorpusReference]
    let evidence: [LegalSourceEvidence]
    let actionable: Bool
    let actionableEvidence: LegalSourceEvidence?
    let sources: [String]
    let sourceURLs: [URL]

    var id: String { recordID }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case termID = "term_id"
        case term
        case definition
        case definitionIndex = "definition_index"
        case references
        case evidence
        case actionable
        case actionableEvidence = "actionable_evidence"
        case sources
        case sourceURLs = "source_urls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decode(String.self, forKey: .recordID)
        termID = try container.decode(String.self, forKey: .termID)
        term = try container.decode(String.self, forKey: .term)
        definition = try container.decode(String.self, forKey: .definition)
        definitionIndex = try container.decode(Int.self, forKey: .definitionIndex)
        references = try container.decode([LegalCorpusReference].self, forKey: .references)
        evidence = try container.decode([LegalSourceEvidence].self, forKey: .evidence)
        actionable = try container.decode(Bool.self, forKey: .actionable)
        actionableEvidence = try container.decodeIfPresent(
            LegalSourceEvidence.self,
            forKey: .actionableEvidence
        )
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        sourceURLs = try container.decodeIfPresent([URL].self, forKey: .sourceURLs) ?? []
    }
}

nonisolated struct LegalRegulation: Identifiable, Codable, Hashable, Sendable {
    let referenceID: String
    let referenceName: String
    let citationNormalized: String
    let officialDetailURL: URL?
    let officialDocumentURL: URL?
    let officialTitle: String
    let officialStatusRaw: String
    let officialStatusCode: LegalCorpusApplicabilityStatus?
    let institution: String?
    let number: String?
    let year: Int?

    var id: String { referenceID }
    var applicabilityStatus: LegalCorpusApplicabilityStatus {
        officialStatusCode ?? .unknown
    }

    enum CodingKeys: String, CodingKey {
        case referenceID = "reference_id"
        case referenceName = "reference_name"
        case citationNormalized = "citation_normalized"
        case officialDetailURL = "official_detail_url"
        case officialDocumentURL = "official_document_url"
        case officialTitle = "official_title"
        case officialStatusRaw = "official_status_raw"
        case officialStatusCode = "official_status_code"
        case institution
        case number
        case year
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        referenceID = try container.decode(String.self, forKey: .referenceID)
        referenceName = try container.decode(String.self, forKey: .referenceName)
        citationNormalized = try container.decode(String.self, forKey: .citationNormalized)
        officialDetailURL = try container.decodeIfPresent(URL.self, forKey: .officialDetailURL)
        officialDocumentURL = try container.decodeIfPresent(URL.self, forKey: .officialDocumentURL)
        officialTitle = try container.decodeIfPresent(String.self, forKey: .officialTitle) ?? ""
        officialStatusRaw = try container.decodeIfPresent(String.self, forKey: .officialStatusRaw) ?? ""

        let rawStatus = try container.decodeIfPresent(String.self, forKey: .officialStatusCode)
        officialStatusCode = rawStatus.flatMap { raw in
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LegalCorpusApplicabilityStatus(rawValue: raw) ?? .unknown
        }

        institution = try container.decodeIfPresent(String.self, forKey: .institution)
        number = try container.decodeIfPresent(String.self, forKey: .number)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
    }
}

nonisolated struct LegalRegulationRelation: Identifiable, Codable, Hashable, Sendable {
    let relationID: String
    let sourceReferenceID: String
    let targetReferenceID: String
    let relationType: String
    let inverseRelationType: String
    let evidenceSource: String
    let evidenceText: String

    var id: String { relationID }

    enum CodingKeys: String, CodingKey {
        case relationID = "relation_id"
        case sourceReferenceID = "source_reference_id"
        case targetReferenceID = "target_reference_id"
        case relationType = "relation_type"
        case inverseRelationType = "inverse_relation_type"
        case evidenceSource = "evidence_source"
        case evidenceText = "evidence_text"
    }
}

nonisolated struct LegalSourcePassage: Identifiable, Codable, Hashable, Sendable {
    let passageID: String
    let referenceID: String
    let articleLocator: String?
    let pageStart: Int?
    let pageEnd: Int?
    let text: String
    let officialDocumentURL: URL?
    let conceptIDs: [String]

    var id: String { passageID }

    enum CodingKeys: String, CodingKey {
        case passageID = "passage_id"
        case referenceID = "reference_id"
        case articleLocator = "article_locator"
        case pageStart = "page_start"
        case pageEnd = "page_end"
        case text
        case officialDocumentURL = "official_document_url"
        case conceptIDs = "concept_ids"
    }
}

nonisolated struct LegalCorpusRetrievalConfiguration: Codable, Hashable, Sendable {
    let rrfK: Int
    let lexicalTopK: Int
    let semanticTopK: Int
    let suggestionCandidateLimit: Int
    let suggestionMinimumSpanTokens: Int
    let suggestionMaximumSpanTokens: Int
    let suggestionMinimumKeywordCoverage: Double
    let suggestionSemanticThreshold: Float
    let suggestionTopOneMargin: Float

    enum CodingKeys: String, CodingKey {
        case rrfK = "rrf_k"
        case lexicalTopK = "lexical_top_k"
        case semanticTopK = "semantic_top_k"
        case suggestionCandidateLimit = "suggestion_candidate_limit"
        case suggestionMinimumSpanTokens = "suggestion_minimum_span_tokens"
        case suggestionMaximumSpanTokens = "suggestion_maximum_span_tokens"
        case suggestionMinimumKeywordCoverage = "suggestion_minimum_keyword_coverage"
        case suggestionSemanticThreshold = "suggestion_semantic_threshold"
        case suggestionTopOneMargin = "suggestion_top_one_margin"
    }

    /// Stable material for cache invalidation. Keep this independent from
    /// Swift's synthesized `Hashable`, whose representation is not a
    /// persistence contract.
    var cacheKey: String {
        [
            String(rrfK),
            String(lexicalTopK),
            String(semanticTopK),
            String(suggestionCandidateLimit),
            String(suggestionMinimumSpanTokens),
            String(suggestionMaximumSpanTokens),
            String(suggestionMinimumKeywordCoverage),
            String(suggestionSemanticThreshold),
            String(suggestionTopOneMargin)
        ].joined(separator: ":")
    }
}

nonisolated struct LegalCorpusEmbeddingConfiguration: Codable, Hashable, Sendable {
    let model: String
    let revision: String
    let dimension: Int
    let dtype: String
    let normalized: Bool
    let passageFormat: String
    let queryPrefix: String
    let conceptOrderSHA256: String?

    enum CodingKeys: String, CodingKey {
        case model
        case revision
        case dimension
        case dtype
        case normalized
        case passageFormat = "passage_format"
        case queryPrefix = "query_prefix"
        case conceptOrderSHA256 = "concept_order_sha256"
    }

    /// Stable material for cache invalidation and diagnostics.
    var cacheKey: String {
        [
            model,
            revision,
            String(dimension),
            dtype,
            normalized ? "normalized" : "unnormalized",
            passageFormat,
            queryPrefix,
            conceptOrderSHA256 ?? ""
        ].joined(separator: ":")
    }
}

nonisolated struct LegalCorpusManifest: Codable, Hashable, Sendable {
    let schemaVersion: String
    let corpusVersion: String
    let sourceDatasetRevision: String
    let sourceDatasetView: String?
    let sourceInputSHA256: [String: String]
    let conceptCount: Int
    let regulationCount: Int
    let relationCount: Int
    let sourcePassageCount: Int
    let actionableConceptCount: Int
    let embedding: LegalCorpusEmbeddingConfiguration
    let retrieval: LegalCorpusRetrievalConfiguration
    let files: [String: String]
    let filesSHA256: [String: String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case corpusVersion = "corpus_version"
        case sourceDatasetRevision = "source_dataset_revision"
        case sourceDatasetView = "source_dataset_view"
        case sourceInputSHA256 = "source_input_sha256"
        case conceptCount = "concept_count"
        case regulationCount = "regulation_count"
        case relationCount = "relation_count"
        case sourcePassageCount = "source_passage_count"
        case actionableConceptCount = "actionable_concept_count"
        case embedding
        case retrieval
        case files
        case filesSHA256 = "files_sha256"
    }
}

nonisolated enum LegalSearchIntent: String, Codable, Hashable, Sendable {
    case exactTerm
    case reverseLookup
    case suggestion
}

nonisolated struct LegalRetrievalRequest: Hashable, Sendable {
    let query: String
    let intent: LegalSearchIntent
    let limit: Int

    init(query: String, intent: LegalSearchIntent, limit: Int = 5) {
        self.query = query
        self.intent = intent
        self.limit = max(0, limit)
    }
}

nonisolated enum LegalRetrievalOrigin: String, Codable, Hashable, Sendable {
    case exact
    case lexical
    case semantic
    case hybrid
}

nonisolated struct LegalRetrievalMatch: Identifiable, Hashable, Sendable {
    let concept: LegalConcept
    let evidence: LegalSourceEvidence?
    let lexicalScore: Double?
    let semanticScore: Float?
    let fusionScore: Double?
    let rank: Int
    let origin: LegalRetrievalOrigin
    let isActionable: Bool

    var id: String { concept.recordID }
}
