import Foundation

/// The two document mutations offered by definition resolution. Rejection is
/// represented as a resolution action so the UI and diagnostics share one
/// vocabulary, but it never carries an editable replacement.
nonisolated enum AIConnectorDefinitionResolutionAction: String, Codable, Hashable, Sendable {
    case useDefinition
    case replaceTerm
    case rejectRecommendation
}

nonisolated enum AIConnectorDefinitionResolutionOptionStatus: String, Codable, Hashable, Sendable {
    case actionable
    case informational
    case needsReview
}

nonisolated enum AIConnectorDefinitionResolutionDecision: String, Codable, Hashable, Sendable {
    case termFits = "TERM_FITS"
    case termMayFit = "TERM_MAY_FIT"
    case contractTermOverride = "CONTRACT_TERM_OVERRIDE"
    case wrongTerm = "WRONG_TERM"
    case notApplicable = "NOT_APPLICABLE"
    case ambiguous = "AMBIGUOUS"
}

/// A source-backed option shown by the definition resolution card. The range
/// is absolute in the current editor text and `original` is the stale-result
/// guard for applying the option.
nonisolated struct AIConnectorDefinitionResolutionOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let action: AIConnectorDefinitionResolutionAction
    let title: String
    let targetRange: NSRange
    let original: String
    let replacement: String?
    let term: String?
    let reference: EditorSuggestionReference?
    let sourceCandidateID: String?
    let status: AIConnectorDefinitionResolutionOptionStatus
    let statusMessage: String?
    let requiresModelReview: Bool

    var isActionable: Bool {
        status == .actionable
            && replacement?.isEmpty == false
            && action != .rejectRecommendation
    }

    init(
        id: String,
        action: AIConnectorDefinitionResolutionAction,
        title: String,
        targetRange: NSRange,
        original: String,
        replacement: String? = nil,
        term: String? = nil,
        reference: EditorSuggestionReference? = nil,
        sourceCandidateID: String? = nil,
        status: AIConnectorDefinitionResolutionOptionStatus,
        statusMessage: String? = nil,
        requiresModelReview: Bool = false
    ) {
        self.id = id
        self.action = action
        self.title = title
        self.targetRange = targetRange
        self.original = original
        self.replacement = replacement
        self.term = term
        self.reference = reference
        self.sourceCandidateID = sourceCandidateID
        self.status = status
        self.statusMessage = statusMessage
        self.requiresModelReview = requiresModelReview
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case action
        case title
        case targetRangeLocation = "target_range_location"
        case targetRangeLength = "target_range_length"
        case original
        case replacement
        case term
        case reference
        case sourceCandidateID
        case status
        case statusMessage
        case requiresModelReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(Int.self, forKey: .targetRangeLocation)
        let length = try container.decode(Int.self, forKey: .targetRangeLength)
        guard location >= 0, length >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .targetRangeLocation,
                in: container,
                debugDescription: "Resolution option range must not be negative."
            )
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            action: try container.decode(AIConnectorDefinitionResolutionAction.self, forKey: .action),
            title: try container.decode(String.self, forKey: .title),
            targetRange: NSRange(location: location, length: length),
            original: try container.decode(String.self, forKey: .original),
            replacement: try container.decodeIfPresent(String.self, forKey: .replacement),
            term: try container.decodeIfPresent(String.self, forKey: .term),
            reference: try container.decodeIfPresent(EditorSuggestionReference.self, forKey: .reference),
            sourceCandidateID: try container.decodeIfPresent(String.self, forKey: .sourceCandidateID),
            status: try container.decode(AIConnectorDefinitionResolutionOptionStatus.self, forKey: .status),
            statusMessage: try container.decodeIfPresent(String.self, forKey: .statusMessage),
            requiresModelReview: try container.decodeIfPresent(Bool.self, forKey: .requiresModelReview) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action, forKey: .action)
        try container.encode(title, forKey: .title)
        try container.encode(targetRange.location, forKey: .targetRangeLocation)
        try container.encode(targetRange.length, forKey: .targetRangeLength)
        try container.encode(original, forKey: .original)
        try container.encodeIfPresent(replacement, forKey: .replacement)
        try container.encodeIfPresent(term, forKey: .term)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(sourceCandidateID, forKey: .sourceCandidateID)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
        try container.encode(requiresModelReview, forKey: .requiresModelReview)
    }

    func isAnchored(to documentText: String) -> Bool {
        guard targetRange.location >= 0,
              targetRange.length > 0,
              NSMaxRange(targetRange) <= documentText.utf16.count else {
            return false
        }
        return (documentText as NSString).substring(with: targetRange) == original
    }
}

/// All resolution state for one definition occurrence. The source references
/// are kept separately from options so an ineligible source remains visible
/// to the lawyer without accidentally becoming an edit.
nonisolated struct AIConnectorDefinitionResolution: Codable, Hashable, Identifiable, Sendable {
    static let version = "phase6-definition-resolution-v1"

    let id: String
    let assessmentID: String
    let annotationID: UUID?
    let primaryRange: NSRange
    let primaryOriginal: String
    let termRange: NSRange?
    let termOriginal: String?
    let bodyRange: NSRange?
    let bodyOriginal: String?
    let options: [AIConnectorDefinitionResolutionOption]
    let sourceReferences: [EditorSuggestionReference]
    let contractDefined: Bool
    let sourceFingerprint: String
    let corpusVersion: String
    let resolverVersion: String

    var hasActionableOption: Bool {
        options.contains(where: { $0.isActionable })
    }

    init(
        id: String,
        assessmentID: String,
        annotationID: UUID? = nil,
        primaryRange: NSRange,
        primaryOriginal: String,
        termRange: NSRange?,
        termOriginal: String?,
        bodyRange: NSRange?,
        bodyOriginal: String?,
        options: [AIConnectorDefinitionResolutionOption],
        sourceReferences: [EditorSuggestionReference],
        contractDefined: Bool,
        sourceFingerprint: String,
        corpusVersion: String,
        resolverVersion: String = Self.version
    ) {
        self.id = id
        self.assessmentID = assessmentID
        self.annotationID = annotationID
        self.primaryRange = primaryRange
        self.primaryOriginal = primaryOriginal
        self.termRange = termRange
        self.termOriginal = termOriginal
        self.bodyRange = bodyRange
        self.bodyOriginal = bodyOriginal
        self.options = options
        self.sourceReferences = sourceReferences
        self.contractDefined = contractDefined
        self.sourceFingerprint = sourceFingerprint
        self.corpusVersion = corpusVersion
        self.resolverVersion = resolverVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case assessmentID
        case annotationID
        case primaryRangeLocation = "primary_range_location"
        case primaryRangeLength = "primary_range_length"
        case primaryOriginal
        case termRangeLocation = "term_range_location"
        case termRangeLength = "term_range_length"
        case termOriginal
        case bodyRangeLocation = "body_range_location"
        case bodyRangeLength = "body_range_length"
        case bodyOriginal
        case options
        case sourceReferences
        case contractDefined
        case sourceFingerprint
        case corpusVersion
        case resolverVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primaryLocation = try container.decode(Int.self, forKey: .primaryRangeLocation)
        let primaryLength = try container.decode(Int.self, forKey: .primaryRangeLength)
        guard primaryLocation >= 0, primaryLength > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .primaryRangeLocation,
                in: container,
                debugDescription: "Resolution primary range must be positive."
            )
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            assessmentID: try container.decode(String.self, forKey: .assessmentID),
            annotationID: try container.decodeIfPresent(UUID.self, forKey: .annotationID),
            primaryRange: NSRange(location: primaryLocation, length: primaryLength),
            primaryOriginal: try container.decode(String.self, forKey: .primaryOriginal),
            termRange: try Self.decodeOptionalRange(
                locationKey: .termRangeLocation,
                lengthKey: .termRangeLength,
                container: container
            ),
            termOriginal: try container.decodeIfPresent(String.self, forKey: .termOriginal),
            bodyRange: try Self.decodeOptionalRange(
                locationKey: .bodyRangeLocation,
                lengthKey: .bodyRangeLength,
                container: container
            ),
            bodyOriginal: try container.decodeIfPresent(String.self, forKey: .bodyOriginal),
            options: try container.decode([AIConnectorDefinitionResolutionOption].self, forKey: .options),
            sourceReferences: try container.decode([EditorSuggestionReference].self, forKey: .sourceReferences),
            contractDefined: try container.decodeIfPresent(Bool.self, forKey: .contractDefined) ?? false,
            sourceFingerprint: try container.decode(String.self, forKey: .sourceFingerprint),
            corpusVersion: try container.decode(String.self, forKey: .corpusVersion),
            resolverVersion: try container.decodeIfPresent(String.self, forKey: .resolverVersion) ?? Self.version
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(assessmentID, forKey: .assessmentID)
        try container.encodeIfPresent(annotationID, forKey: .annotationID)
        try container.encode(primaryRange.location, forKey: .primaryRangeLocation)
        try container.encode(primaryRange.length, forKey: .primaryRangeLength)
        try container.encode(primaryOriginal, forKey: .primaryOriginal)
        try Self.encodeOptionalRange(termRange, locationKey: .termRangeLocation, lengthKey: .termRangeLength, into: &container)
        try container.encodeIfPresent(termOriginal, forKey: .termOriginal)
        try Self.encodeOptionalRange(bodyRange, locationKey: .bodyRangeLocation, lengthKey: .bodyRangeLength, into: &container)
        try container.encodeIfPresent(bodyOriginal, forKey: .bodyOriginal)
        try container.encode(options, forKey: .options)
        try container.encode(sourceReferences, forKey: .sourceReferences)
        try container.encode(contractDefined, forKey: .contractDefined)
        try container.encode(sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(corpusVersion, forKey: .corpusVersion)
        try container.encode(resolverVersion, forKey: .resolverVersion)
    }

    func isAnchored(to documentText: String) -> Bool {
        guard primaryRange.location >= 0,
              primaryRange.length > 0,
              NSMaxRange(primaryRange) <= documentText.utf16.count,
              (documentText as NSString).substring(with: primaryRange) == primaryOriginal else {
            return false
        }
        return Self.matchesOptionalAnchor(termRange, original: termOriginal, in: documentText)
            && Self.matchesOptionalAnchor(bodyRange, original: bodyOriginal, in: documentText)
    }

    private static func decodeOptionalRange(
        locationKey: CodingKeys,
        lengthKey: CodingKeys,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NSRange? {
        guard let location = try container.decodeIfPresent(Int.self, forKey: locationKey),
              let length = try container.decodeIfPresent(Int.self, forKey: lengthKey) else {
            return nil
        }
        guard location >= 0, length > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: locationKey,
                in: container,
                debugDescription: "Optional resolution range must be positive."
            )
        }
        return NSRange(location: location, length: length)
    }

    private static func encodeOptionalRange(
        _ range: NSRange?,
        locationKey: CodingKeys,
        lengthKey: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encodeIfPresent(range?.location, forKey: locationKey)
        try container.encodeIfPresent(range?.length, forKey: lengthKey)
    }

    private static func matchesOptionalAnchor(
        _ range: NSRange?,
        original: String?,
        in documentText: String
    ) -> Bool {
        guard let range, let original else { return range == nil && original == nil }
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= documentText.utf16.count else {
            return false
        }
        return (documentText as NSString).substring(with: range) == original
    }
}

nonisolated struct AIConnectorDefinitionResolutionMetrics: Hashable, Sendable {
    let retrievalQueryCount: Int
    let candidateCount: Int
    let modelCallCount: Int
    let fallbackCount: Int
    let cacheHit: Bool
    let duration: TimeInterval
    let status: String

    init(
        retrievalQueryCount: Int = 0,
        candidateCount: Int = 0,
        modelCallCount: Int = 0,
        fallbackCount: Int = 0,
        cacheHit: Bool = false,
        duration: TimeInterval = 0,
        status: String = "completed"
    ) {
        self.retrievalQueryCount = max(0, retrievalQueryCount)
        self.candidateCount = max(0, candidateCount)
        self.modelCallCount = max(0, modelCallCount)
        self.fallbackCount = max(0, fallbackCount)
        self.cacheHit = cacheHit
        self.duration = max(0, duration)
        self.status = status
    }

    func cacheHitMetrics() -> Self {
        Self(
            retrievalQueryCount: 0,
            candidateCount: candidateCount,
            modelCallCount: 0,
            fallbackCount: 0,
            cacheHit: true,
            duration: 0,
            status: status
        )
    }
}

nonisolated struct AIConnectorDefinitionResolutionResult: Sendable {
    let resolution: AIConnectorDefinitionResolution
    let metrics: AIConnectorDefinitionResolutionMetrics
}

struct AIConnectorDefinitionResolutionReviewRequest: Sendable {
    let candidateID: String
    let targetTerm: String
    let documentDefinition: String
    let candidateTerm: String
    let candidateDefinition: String
    let context: AIConnectorSegmentContext?
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile

    init(
        candidateID: String,
        targetTerm: String,
        documentDefinition: String,
        candidateTerm: String,
        candidateDefinition: String,
        context: AIConnectorSegmentContext? = nil,
        modelVariant: AIConnectorModelVariant = .qwen35Base4B,
        generationProfile: AIConnectorGenerationProfile = AIConnectorDefinitionResolutionReviewRequest.defaultProfile
    ) {
        self.candidateID = candidateID
        self.targetTerm = targetTerm
        self.documentDefinition = documentDefinition
        self.candidateTerm = candidateTerm
        self.candidateDefinition = candidateDefinition
        self.context = context
        self.modelVariant = modelVariant
        self.generationProfile = generationProfile
    }

    static let defaultProfile = AIConnectorGenerationProfile(
        maxTokens: 192,
        temperature: 0,
        topP: 1,
        topK: 0,
        presencePenalty: nil,
        seed: 42
    )
}

struct AIConnectorDefinitionResolutionReviewResult: Sendable {
    let candidateID: String
    let decision: AIConnectorDefinitionResolutionDecision
    let metrics: AIConnectorGenerationMetrics
}
