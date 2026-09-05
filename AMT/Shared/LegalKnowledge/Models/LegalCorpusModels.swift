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
    case machineOCRTolerantUnreviewed = "machine_ocr_tolerant_unreviewed"
    case humanVerified = "human_verified"
    case needsReview = "needs_human_review"

    var displayTitle: String {
        switch self {
        case .machineExact:
            "Terverifikasi otomatis"
        case .machineOCRTolerantUnreviewed:
            "Cocok OCR (belum ditinjau)"
        case .humanVerified:
            "Diverifikasi manusia"
        case .needsReview:
            "Perlu ditinjau"
        }
    }

    var isAcceptedEvidence: Bool {
        switch self {
        case .machineExact, .machineOCRTolerantUnreviewed, .humanVerified:
            true
        case .needsReview:
            false
        }
    }
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
    let evidenceID: String?
    let edgeID: String?
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
    let matchMethod: String?

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case edgeID = "edge_id"
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
        case matchMethod = "match_method"
    }

    init(
        evidenceID: String? = nil,
        edgeID: String? = nil,
        passageID: String,
        referenceID: String,
        articleLocator: String?,
        pageStart: Int?,
        pageEnd: Int?,
        matchedDefinitionText: String,
        officialDetailURL: URL?,
        officialDocumentURL: URL?,
        regulationTitle: String,
        verificationStatus: LegalCorpusReviewStatus?,
        matchMethod: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.edgeID = edgeID
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
        self.matchMethod = matchMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceID = try container.decodeIfPresent(String.self, forKey: .evidenceID)
        edgeID = try container.decodeIfPresent(String.self, forKey: .edgeID)
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
        matchMethod = try container.decodeIfPresent(String.self, forKey: .matchMethod)
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

    init(
        recordID: String,
        termID: String,
        term: String,
        definition: String,
        definitionIndex: Int,
        references: [LegalCorpusReference],
        evidence: [LegalSourceEvidence],
        actionable: Bool,
        actionableEvidence: LegalSourceEvidence?,
        sources: [String],
        sourceURLs: [URL]
    ) {
        self.recordID = recordID
        self.termID = termID
        self.term = term
        self.definition = definition
        self.definitionIndex = definitionIndex
        self.references = references
        self.evidence = evidence
        self.actionable = actionable
        self.actionableEvidence = actionableEvidence
        self.sources = sources
        self.sourceURLs = sourceURLs
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

/// Evidence link from the dictionary serving projection to an official passage.
nonisolated struct LegalDictionaryEvidenceLink: Codable, Hashable, Sendable {
    let evidenceID: String
    let edgeID: String
    let regulationID: String
    let passageID: String
    let articleLocator: String?
    let pageStart: Int?
    let pageEnd: Int?
    let matchedDefinitionText: String
    let verificationStatus: LegalCorpusReviewStatus?
    let matchMethod: String?

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case edgeID = "edge_id"
        case regulationID = "regulation_id"
        case passageID = "passage_id"
        case articleLocator = "article_locator"
        case pageStart = "page_start"
        case pageEnd = "page_end"
        case matchedDefinitionText = "matched_definition_text"
        case verificationStatus = "verification_status"
        case matchMethod = "match_method"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceID = try container.decodeIfPresent(String.self, forKey: .evidenceID) ?? ""
        edgeID = try container.decodeIfPresent(String.self, forKey: .edgeID) ?? ""
        regulationID = try container.decode(String.self, forKey: .regulationID)
        passageID = try container.decode(String.self, forKey: .passageID)
        articleLocator = try container.decodeIfPresent(String.self, forKey: .articleLocator)
        pageStart = try container.decodeIfPresent(Int.self, forKey: .pageStart)
        pageEnd = try container.decodeIfPresent(Int.self, forKey: .pageEnd)
        matchedDefinitionText = try container.decodeIfPresent(
            String.self,
            forKey: .matchedDefinitionText
        ) ?? ""
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .verificationStatus)
        verificationStatus = rawStatus.flatMap { LegalCorpusReviewStatus(rawValue: $0) }
        matchMethod = try container.decodeIfPresent(String.self, forKey: .matchMethod)
    }
}

/// One row from the selected-primary dictionary serving view.
nonisolated struct LegalDictionaryPrimaryRecord: Codable, Hashable, Sendable {
    let termGroupID: String
    let term: String
    let termNormalized: String
    let selectionStatus: String
    let selectionReason: String
    let selectionConfidence: String
    let primaryAvailable: Bool
    let primaryDefinitionID: String?
    let primaryDefinition: String?
    let primarySource: String?
    let primarySourceRecordID: String?
    let primarySourceURL: URL?
    let primaryAttributionStatus: String?
    let primaryAuthority: String?
    let primaryApplicabilityStatus: LegalCorpusApplicabilityStatus
    let primaryIsActionable: Bool
    let primaryReferenceIDs: [String]
    let primaryEvidence: [LegalDictionaryEvidenceLink]
    let alternativeDefinitionCount: Int
    let candidateDefinitionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case termGroupID = "term_group_id"
        case term
        case termNormalized = "term_normalized"
        case selectionStatus = "selection_status"
        case selectionReason = "selection_reason"
        case selectionConfidence = "selection_confidence"
        case primaryAvailable = "primary_available"
        case primaryDefinitionID = "primary_definition_id"
        case primaryDefinition = "primary_definition"
        case primarySource = "primary_source"
        case primarySourceRecordID = "primary_source_record_id"
        case primarySourceURL = "primary_source_url"
        case primaryAttributionStatus = "primary_attribution_status"
        case primaryAuthority = "primary_authority"
        case primaryApplicabilityStatus = "primary_applicability_status"
        case primaryIsActionable = "primary_is_actionable"
        case primaryReferenceIDs = "primary_reference_ids"
        case primaryEvidence = "primary_evidence"
        case alternativeDefinitionCount = "alternative_definition_count"
        case candidateDefinitionIDs = "candidate_definition_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termGroupID = try container.decode(String.self, forKey: .termGroupID)
        term = try container.decode(String.self, forKey: .term)
        termNormalized = try container.decodeIfPresent(String.self, forKey: .termNormalized) ?? ""
        selectionStatus = try container.decodeIfPresent(String.self, forKey: .selectionStatus) ?? ""
        selectionReason = try container.decodeIfPresent(String.self, forKey: .selectionReason) ?? ""
        selectionConfidence = try container.decodeIfPresent(String.self, forKey: .selectionConfidence) ?? ""
        primaryAvailable = try container.decodeIfPresent(Bool.self, forKey: .primaryAvailable) ?? false
        primaryDefinitionID = try container.decodeIfPresent(String.self, forKey: .primaryDefinitionID)
        primaryDefinition = try container.decodeIfPresent(String.self, forKey: .primaryDefinition)
        primarySource = try container.decodeIfPresent(String.self, forKey: .primarySource)
        primarySourceRecordID = try container.decodeIfPresent(String.self, forKey: .primarySourceRecordID)
        primarySourceURL = try container.decodeIfPresent(URL.self, forKey: .primarySourceURL)
        primaryAttributionStatus = try container.decodeIfPresent(
            String.self,
            forKey: .primaryAttributionStatus
        )
        primaryAuthority = try container.decodeIfPresent(String.self, forKey: .primaryAuthority)
        let rawApplicabilityStatus = try container.decodeIfPresent(
            String.self,
            forKey: .primaryApplicabilityStatus
        )
        primaryApplicabilityStatus = rawApplicabilityStatus.flatMap {
            LegalCorpusApplicabilityStatus(rawValue: $0)
        } ?? .unknown
        primaryIsActionable = try container.decodeIfPresent(
            Bool.self,
            forKey: .primaryIsActionable
        ) ?? false
        primaryReferenceIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .primaryReferenceIDs
        ) ?? []
        primaryEvidence = try container.decodeIfPresent(
            [LegalDictionaryEvidenceLink].self,
            forKey: .primaryEvidence
        ) ?? []
        alternativeDefinitionCount = try container.decodeIfPresent(
            Int.self,
            forKey: .alternativeDefinitionCount
        ) ?? 0
        candidateDefinitionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .candidateDefinitionIDs
        ) ?? []
    }
}

/// Group-level selection metadata for one normalized dictionary term.
nonisolated struct LegalDictionaryTermGroup: Codable, Hashable, Sendable {
    let termGroupID: String
    let term: String
    let termNormalized: String
    let definitionCount: Int
    let sourceNames: [String]
    let regulationIDs: [String]
    let candidateDefinitionIDs: [String]
    let candidateScopeLabels: [String]
    let primaryDefinitionID: String?
    let selectionStatus: String
    let selectionReason: String
    let displayPolicy: String
    let alternativeDefinitionCount: Int
    let hasMultipleSources: Bool
    let hasMultipleDefinitions: Bool

    enum CodingKeys: String, CodingKey {
        case termGroupID = "term_group_id"
        case term
        case termNormalized = "term_normalized"
        case definitionCount = "definition_count"
        case sourceNames = "source_names"
        case regulationIDs = "regulation_ids"
        case candidateDefinitionIDs = "candidate_definition_ids"
        case candidateScopeLabels = "candidate_scope_labels"
        case primaryDefinitionID = "primary_definition_id"
        case selectionStatus = "selection_status"
        case selectionReason = "selection_reason"
        case displayPolicy = "display_policy"
        case alternativeDefinitionCount = "alternative_definition_count"
        case hasMultipleSources = "has_multiple_sources"
        case hasMultipleDefinitions = "has_multiple_definitions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termGroupID = try container.decode(String.self, forKey: .termGroupID)
        term = try container.decode(String.self, forKey: .term)
        termNormalized = try container.decodeIfPresent(String.self, forKey: .termNormalized) ?? ""
        definitionCount = try container.decodeIfPresent(Int.self, forKey: .definitionCount) ?? 0
        sourceNames = try container.decodeIfPresent([String].self, forKey: .sourceNames) ?? []
        regulationIDs = try container.decodeIfPresent([String].self, forKey: .regulationIDs) ?? []
        candidateDefinitionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .candidateDefinitionIDs
        ) ?? []
        candidateScopeLabels = try container.decodeIfPresent(
            [String].self,
            forKey: .candidateScopeLabels
        ) ?? []
        primaryDefinitionID = try container.decodeIfPresent(String.self, forKey: .primaryDefinitionID)
        selectionStatus = try container.decodeIfPresent(String.self, forKey: .selectionStatus) ?? ""
        selectionReason = try container.decodeIfPresent(String.self, forKey: .selectionReason) ?? ""
        displayPolicy = try container.decodeIfPresent(String.self, forKey: .displayPolicy) ?? ""
        alternativeDefinitionCount = try container.decodeIfPresent(
            Int.self,
            forKey: .alternativeDefinitionCount
        ) ?? 0
        hasMultipleSources = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasMultipleSources
        ) ?? false
        hasMultipleDefinitions = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasMultipleDefinitions
        ) ?? false
    }
}

/// A non-primary definition retained for contextual provenance in Dictionary.
nonisolated struct LegalDictionaryAlternative: Codable, Hashable, Sendable {
    let definitionID: String
    let termGroupID: String
    let recordID: String
    let sourceRecordID: String
    let term: String
    let termNormalized: String
    let definitionIndex: Int
    let definition: String
    let source: String
    let sourceURL: URL?
    let sourceURLs: [URL]
    let attributionStatus: String
    let authority: String
    let applicabilityStatus: LegalCorpusApplicabilityStatus
    let isActionable: Bool
    let allReferenceIDs: [String]
    let attributedReferenceIDs: [String]
    let pageRelatedReferenceIDs: [String]
    let unresolvedReferenceIDs: [String]
    let evidenceEdgeIDs: [String]
    let referenceEdgeIDs: [String]
    let evidence: [LegalDictionaryEvidenceLink]
    let scopeLabels: [String]
    let bestAttributableEdgeID: String?
    let bestAttributableEdgeScore: Double?
    let selectionEligible: Bool
    let isPrimary: Bool
    let selectionStatus: String
    let selectionReason: String
    let selectionConfidence: String
    let termSelectionStatus: String
    let definitionRole: String

    enum CodingKeys: String, CodingKey {
        case definitionID = "definition_id"
        case termGroupID = "term_group_id"
        case recordID = "record_id"
        case sourceRecordID = "source_record_id"
        case term
        case termNormalized = "term_normalized"
        case definitionIndex = "definition_index"
        case definition
        case source
        case sourceURL = "source_url"
        case sourceURLs = "source_urls"
        case attributionStatus = "attribution_status"
        case authority
        case applicabilityStatus = "applicability_status"
        case isActionable = "is_actionable"
        case allReferenceIDs = "all_reference_ids"
        case attributedReferenceIDs = "attributed_reference_ids"
        case pageRelatedReferenceIDs = "page_related_reference_ids"
        case unresolvedReferenceIDs = "unresolved_reference_ids"
        case evidenceEdgeIDs = "evidence_edge_ids"
        case referenceEdgeIDs = "reference_edge_ids"
        case evidence
        case scopeLabels = "scope_labels"
        case bestAttributableEdgeID = "best_attributable_edge_id"
        case bestAttributableEdgeScore = "best_attributable_edge_score"
        case selectionEligible = "selection_eligible"
        case isPrimary = "is_primary"
        case selectionStatus = "selection_status"
        case selectionReason = "selection_reason"
        case selectionConfidence = "selection_confidence"
        case termSelectionStatus = "term_selection_status"
        case definitionRole = "definition_role"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definitionID = try container.decode(String.self, forKey: .definitionID)
        termGroupID = try container.decode(String.self, forKey: .termGroupID)
        recordID = try container.decode(String.self, forKey: .recordID)
        sourceRecordID = try container.decodeIfPresent(String.self, forKey: .sourceRecordID) ?? recordID
        term = try container.decode(String.self, forKey: .term)
        termNormalized = try container.decodeIfPresent(String.self, forKey: .termNormalized) ?? ""
        definitionIndex = try container.decodeIfPresent(Int.self, forKey: .definitionIndex) ?? 1
        definition = try container.decode(String.self, forKey: .definition)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        sourceURLs = try container.decodeIfPresent([URL].self, forKey: .sourceURLs) ?? []
        attributionStatus = try container.decodeIfPresent(
            String.self,
            forKey: .attributionStatus
        ) ?? ""
        authority = try container.decodeIfPresent(String.self, forKey: .authority) ?? ""
        let rawApplicabilityStatus = try container.decodeIfPresent(
            String.self,
            forKey: .applicabilityStatus
        )
        applicabilityStatus = rawApplicabilityStatus.flatMap {
            LegalCorpusApplicabilityStatus(rawValue: $0)
        } ?? .unknown
        isActionable = try container.decodeIfPresent(Bool.self, forKey: .isActionable) ?? false
        allReferenceIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .allReferenceIDs
        ) ?? []
        attributedReferenceIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .attributedReferenceIDs
        ) ?? []
        pageRelatedReferenceIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .pageRelatedReferenceIDs
        ) ?? []
        unresolvedReferenceIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .unresolvedReferenceIDs
        ) ?? []
        evidenceEdgeIDs = try container.decodeIfPresent([String].self, forKey: .evidenceEdgeIDs) ?? []
        referenceEdgeIDs = try container.decodeIfPresent([String].self, forKey: .referenceEdgeIDs) ?? []
        evidence = try container.decodeIfPresent(
            [LegalDictionaryEvidenceLink].self,
            forKey: .evidence
        ) ?? []
        scopeLabels = try container.decodeIfPresent([String].self, forKey: .scopeLabels) ?? []
        bestAttributableEdgeID = try container.decodeIfPresent(
            String.self,
            forKey: .bestAttributableEdgeID
        )
        bestAttributableEdgeScore = try container.decodeIfPresent(
            Double.self,
            forKey: .bestAttributableEdgeScore
        )
        selectionEligible = try container.decodeIfPresent(
            Bool.self,
            forKey: .selectionEligible
        ) ?? false
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        selectionStatus = try container.decodeIfPresent(String.self, forKey: .selectionStatus) ?? ""
        selectionReason = try container.decodeIfPresent(String.self, forKey: .selectionReason) ?? ""
        selectionConfidence = try container.decodeIfPresent(
            String.self,
            forKey: .selectionConfidence
        ) ?? ""
        termSelectionStatus = try container.decodeIfPresent(
            String.self,
            forKey: .termSelectionStatus
        ) ?? ""
        definitionRole = try container.decodeIfPresent(String.self, forKey: .definitionRole) ?? ""
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
    let termGroupCount: Int
    let alternativeCount: Int
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
        case termGroupCount = "term_group_count"
        case alternativeCount = "alternative_count"
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
