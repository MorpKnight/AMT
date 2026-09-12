import CryptoKit
import Foundation

/// The conservative block vocabulary used by the Phase 4 structure pass.
nonisolated enum AIConnectorDocumentBlockKind: String, Codable, Hashable, Sendable {
    case heading
    case paragraph
    case numberedClause
    case listItem
    case tableCell
    case footnote
    case unknown
}

nonisolated enum AIConnectorDocumentContextOrigin: String, Codable, Hashable, Sendable {
    case local
    case qwen
    case fallback
}

nonisolated enum AIConnectorDocumentContextConfidence: String, Codable, Hashable, Sendable {
    case explicit
    case inferred
    case unknown
}

nonisolated enum AIConnectorDocumentContextClassificationStatus: String, Codable, Hashable, Sendable {
    case notRequired
    case required
    case succeeded
    case fallback
    case failed
    case cancelled
}

/// A lossless, editor-relative block map. Ranges always use UTF-16 offsets so
/// they can be used directly with AppKit text storage and review anchors.
nonisolated struct AIConnectorDocumentBlock: Hashable, Sendable {
    let id: String
    let kind: AIConnectorDocumentBlockKind
    let sourceRange: NSRange
    let text: String
    let parentSectionID: String?
    let headingPath: [String]
    let numberingLabel: String?
    let previousBlockID: String?
    let nextBlockID: String?
}

nonisolated struct AIConnectorDocumentSection: Hashable, Sendable {
    let id: String
    let title: String
    let headingBlockID: String
    let sourceRange: NSRange
    let parentSectionID: String?
    let headingPath: [String]
}

nonisolated struct AIConnectorDocumentStructure: Hashable, Sendable {
    static let currentVersion = "structure-v1"

    let blocks: [AIConnectorDocumentBlock]
    let sections: [AIConnectorDocumentSection]
    let headingCount: Int
    let parserVersion: String
    let fingerprint: String

    var sectionIDs: Set<String> { Set(sections.map(\.id)) }

    func section(for id: String?) -> AIConnectorDocumentSection? {
        guard let id else { return nil }
        return sections.first { $0.id == id }
    }

    func block(for id: String) -> AIConnectorDocumentBlock? {
        blocks.first { $0.id == id }
    }
}

nonisolated struct AIConnectorContextFact: Hashable, Sendable {
    let id: String
    let value: String
    let origin: AIConnectorDocumentContextOrigin
    let confidence: AIConnectorDocumentContextConfidence
    let evidenceRanges: [NSRange]
    let sectionID: String?

    init(
        id: String,
        value: String,
        origin: AIConnectorDocumentContextOrigin = .local,
        confidence: AIConnectorDocumentContextConfidence,
        evidenceRanges: [NSRange] = [],
        sectionID: String? = nil
    ) {
        self.id = id
        self.value = value
        self.origin = origin
        self.confidence = confidence
        self.evidenceRanges = evidenceRanges
        self.sectionID = sectionID
    }
}

nonisolated struct AIConnectorContextCoverage: Hashable, Sendable {
    let totalUTF16Length: Int
    let sampledUTF16Length: Int
    let sampledSectionIDs: [String]
    let evidenceIDs: [String]

    var fraction: Double {
        guard totalUTF16Length > 0 else { return 1 }
        return min(Double(sampledUTF16Length) / Double(totalUTF16Length), 1)
    }
}

nonisolated struct AIConnectorDocumentContextProfile: Hashable, Sendable {
    static let extractorVersion = "context-extractor-v1"
    static let classifierVersion = "qwen-context-classifier-v1"

    let documentTypeCandidates: [AIConnectorContextFact]
    let legalDomains: [AIConnectorContextFact]
    let parties: [AIConnectorContextFact]
    let definedTerms: [AIConnectorContextFact]
    let jurisdictions: [AIConnectorContextFact]
    let regulationReferences: [AIConnectorContextFact]
    let effectiveDates: [AIConnectorContextFact]
    let currencies: [AIConnectorContextFact]
    let sectionOutline: [AIConnectorDocumentSection]
    let coverage: AIConnectorContextCoverage
    let classificationStatus: AIConnectorDocumentContextClassificationStatus
    let sourceFingerprint: String
    let structureFingerprint: String
    let extractorVersion: String
    let classifierVersion: String
    let modelCallCount: Int
    let classificationDuration: TimeInterval

    var requiresClassification: Bool {
        let knownTypes = documentTypeCandidates.filter { $0.value != "unknown" }
        let knownDomains = legalDomains.filter { $0.value != "unknown" }
        return knownTypes.isEmpty || knownTypes.count > 1 || knownDomains.isEmpty
    }

    var fingerprint: String {
        let material = [
            sourceFingerprint,
            structureFingerprint,
            extractorVersion,
            classifierVersion,
            documentTypeCandidates.map(\.value).joined(separator: ","),
            legalDomains.map(\.value).joined(separator: ","),
            parties.map(\.value).joined(separator: ","),
            definedTerms.map(\.value).joined(separator: ","),
            regulationReferences.map(\.value).joined(separator: ",")
        ].joined(separator: "|")
        return Self.sha256(material)
    }

    func withClassification(
        documentTypes: [AIConnectorContextFact],
        domains: [AIConnectorContextFact],
        status: AIConnectorDocumentContextClassificationStatus,
        modelCallCount: Int,
        duration: TimeInterval
    ) -> AIConnectorDocumentContextProfile {
        AIConnectorDocumentContextProfile(
            documentTypeCandidates: documentTypes.isEmpty ? documentTypeCandidates : documentTypes,
            legalDomains: domains.isEmpty ? legalDomains : domains,
            parties: parties,
            definedTerms: definedTerms,
            jurisdictions: jurisdictions,
            regulationReferences: regulationReferences,
            effectiveDates: effectiveDates,
            currencies: currencies,
            sectionOutline: sectionOutline,
            coverage: coverage,
            classificationStatus: status,
            sourceFingerprint: sourceFingerprint,
            structureFingerprint: structureFingerprint,
            extractorVersion: extractorVersion,
            classifierVersion: classifierVersion,
            modelCallCount: modelCallCount,
            classificationDuration: duration
        )
    }

    func withCoverage(_ coverage: AIConnectorContextCoverage) -> AIConnectorDocumentContextProfile {
        AIConnectorDocumentContextProfile(
            documentTypeCandidates: documentTypeCandidates,
            legalDomains: legalDomains,
            parties: parties,
            definedTerms: definedTerms,
            jurisdictions: jurisdictions,
            regulationReferences: regulationReferences,
            effectiveDates: effectiveDates,
            currencies: currencies,
            sectionOutline: sectionOutline,
            coverage: coverage,
            classificationStatus: classificationStatus,
            sourceFingerprint: sourceFingerprint,
            structureFingerprint: structureFingerprint,
            extractorVersion: extractorVersion,
            classifierVersion: classifierVersion,
            modelCallCount: modelCallCount,
            classificationDuration: classificationDuration
        )
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Context passed to candidate and definition review. It is deliberately a
/// small, structured package rather than a second copy of the document.
nonisolated struct AIConnectorSegmentContext: Hashable, Sendable {
    let sectionID: String?
    let headingPath: [String]
    let parentClause: String?
    let relevantDefinedTerms: [String]
    let relevantParties: [String]
    let sectionRegulationReferences: [String]
    let documentTypeCandidates: [String]
    let legalDomainCandidates: [String]
    let profileFingerprint: String
    let structureFingerprint: String

    var fingerprint: String {
        [
            sectionID ?? "-",
            headingPath.joined(separator: ">"),
            parentClause ?? "-",
            relevantDefinedTerms.joined(separator: ","),
            relevantParties.joined(separator: ","),
            sectionRegulationReferences.joined(separator: ","),
            documentTypeCandidates.joined(separator: ","),
            legalDomainCandidates.joined(separator: ","),
            profileFingerprint,
            structureFingerprint
        ].joined(separator: "|")
    }

    /// The prompt formatter keeps source context separate from ORIGINAL and
    /// labels all values as document data, never as model instructions.
    func promptText(maxCharacters: Int = 1_800) -> String {
        let lines = [
            "SECTION_ID: \(sectionID ?? "-")",
            "HEADING_PATH: \(headingPath.joined(separator: " > "))",
            "PARENT_CLAUSE: \(parentClause ?? "-")",
            "DEFINED_TERMS: \(relevantDefinedTerms.joined(separator: ", "))",
            "PARTIES: \(relevantParties.joined(separator: ", "))",
            "SECTION_REFERENCES: \(sectionRegulationReferences.joined(separator: ", "))",
            "DOCUMENT_TYPE_CANDIDATES: \(documentTypeCandidates.joined(separator: ", "))",
            "LEGAL_DOMAIN_CANDIDATES: \(legalDomainCandidates.joined(separator: ", "))"
        ]
        let result = lines.joined(separator: "\n")
        guard result.utf16.count > maxCharacters else { return result }
        return String(result.prefix(maxCharacters)) + "…"
    }
}

nonisolated struct AIConnectorDocumentContextClassificationRequest: Sendable {
    let sampledText: String
    let evidenceIDs: [String]
    let sectionIDs: [String]
    let allowedDocumentTypes: [String]
    let allowedDomains: [String]
    let modelVariant: AIConnectorModelVariant
    let generationProfile: AIConnectorGenerationProfile
}

nonisolated struct AIConnectorDocumentContextClassificationResult: Hashable, Sendable {
    let documentType: String?
    let domains: [String]
    let evidenceIDs: [String]
    let sectionIDs: [String]
    let confidence: AIConnectorDocumentContextConfidence
    let metrics: AIConnectorGenerationMetrics

    func withMetrics(_ metrics: AIConnectorGenerationMetrics) -> Self {
        Self(
            documentType: documentType,
            domains: domains,
            evidenceIDs: evidenceIDs,
            sectionIDs: sectionIDs,
            confidence: confidence,
            metrics: metrics
        )
    }
}

nonisolated struct AIConnectorDocumentContextPreparation: Sendable {
    let structure: AIConnectorDocumentStructure
    let profile: AIConnectorDocumentContextProfile
    let segmentation: AITextSegmentationResult
    let structureDuration: TimeInterval
    let extractionDuration: TimeInterval
    let segmentationDuration: TimeInterval
    let preparationDuration: TimeInterval
    let classificationDuration: TimeInterval
    let cacheKey: String
}
