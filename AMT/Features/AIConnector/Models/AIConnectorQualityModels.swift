#if DEBUG
import CryptoKit
import Darwin
import Foundation

nonisolated enum AIConnectorQualityCategory: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case spelling
    case grammar
    case terminology
    case definition
    case definedTerm
    case internalReference
    case legalRisk
    case definitionResolution
    case incremental
    case hardNegative = "hard-negative"

    var id: Self { self }

    var title: String {
        switch self {
        case .spelling: "Ejaan"
        case .grammar: "Tata bahasa"
        case .terminology: "Terminologi"
        case .definition: "Definisi"
        case .definedTerm: "Defined term"
        case .internalReference: "Rujukan internal"
        case .legalRisk: "Legal risk"
        case .definitionResolution: "Resolusi definisi"
        case .incremental: "Incremental"
        case .hardNegative: "Hard-negative"
        }
    }
}

nonisolated enum AIConnectorQualityFixtureSplit: String, Codable, CaseIterable, Hashable, Sendable {
    case calibration
    case regression
    case holdout
}

nonisolated enum AIConnectorQualityFixtureProvenance: String, Codable, Hashable, Sendable {
    case synthetic
    case anonymized
}

nonisolated enum AIConnectorQualityFixtureReviewStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case changesRequested
    case approved
}

nonisolated enum AIConnectorQualityGateStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pass
    case fail
    case insufficientEvidence
}

nonisolated enum AIConnectorQualityRunStatus: String, Codable, Hashable, Sendable {
    case completed
    case partial
    case failed
}

nonisolated struct AIConnectorQualityExpectedSource: Codable, Hashable, Sendable {
    let id: String
    let corpusEntryID: String?
    let referenceID: String?
    let evidenceID: String?
    let applicabilityStatus: String
    let verified: Bool
    let isActionable: Bool
}

nonisolated struct AIConnectorQualityExpectedFinding: Codable, Hashable, Sendable {
    let occurrence: Int
    let category: AIConnectorQualityCategory
    let status: String
    let original: String?
    let replacement: String?
    let classification: String?
    let sourceID: String?
    let readOnly: Bool

    init(
        occurrence: Int = 0,
        category: AIConnectorQualityCategory,
        status: String,
        original: String? = nil,
        replacement: String? = nil,
        classification: String? = nil,
        sourceID: String? = nil,
        readOnly: Bool = false
    ) {
        self.occurrence = occurrence
        self.category = category
        self.status = status
        self.original = original
        self.replacement = replacement
        self.classification = classification
        self.sourceID = sourceID
        self.readOnly = readOnly
    }
}

nonisolated struct AIConnectorQualityExpectation: Codable, Hashable, Sendable {
    let findings: [AIConnectorQualityExpectedFinding]
    let noChange: Bool
    let requiredSourceIDs: [String]

    init(
        findings: [AIConnectorQualityExpectedFinding] = [],
        noChange: Bool = false,
        requiredSourceIDs: [String] = []
    ) {
        self.findings = findings
        self.noChange = noChange
        self.requiredSourceIDs = requiredSourceIDs
    }
}

nonisolated struct AIConnectorQualityFixture: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = "phase8-quality-fixture-v1"

    let id: String
    let revision: Int
    let scenarioID: String
    let category: AIConnectorQualityCategory
    let split: AIConnectorQualityFixtureSplit
    let provenance: AIConnectorQualityFixtureProvenance
    let text: String
    let expected: AIConnectorQualityExpectation
    let sources: [AIConnectorQualityExpectedSource]
    let question: String
    let rightsDeclared: Bool
    let anonymizationChecked: Bool
    let reviewStatus: AIConnectorQualityFixtureReviewStatus

    var contentDigest: String {
        Self.digest(text)
    }

    var expectationDigest: String {
        Self.digest(expected)
    }

    var fixtureDigest: String {
        Self.digest(
            FixtureDigestPayload(
                id: id,
                revision: revision,
                scenarioID: scenarioID,
                category: category,
                split: split,
                provenance: provenance,
                text: text,
                expected: expected,
                sources: sources,
                question: question,
                rightsDeclared: rightsDeclared,
                anonymizationChecked: anonymizationChecked
            )
        )
    }

    init(
        id: String,
        revision: Int = 1,
        scenarioID: String,
        category: AIConnectorQualityCategory,
        split: AIConnectorQualityFixtureSplit,
        provenance: AIConnectorQualityFixtureProvenance = .synthetic,
        text: String,
        expected: AIConnectorQualityExpectation,
        sources: [AIConnectorQualityExpectedSource] = [],
        question: String,
        rightsDeclared: Bool = true,
        anonymizationChecked: Bool = false,
        reviewStatus: AIConnectorQualityFixtureReviewStatus = .pending
    ) {
        self.id = id
        self.revision = max(revision, 1)
        self.scenarioID = scenarioID
        self.category = category
        self.split = split
        self.provenance = provenance
        self.text = text
        self.expected = expected
        self.sources = sources
        self.question = question
        self.rightsDeclared = rightsDeclared
        self.anonymizationChecked = anonymizationChecked
        self.reviewStatus = reviewStatus
    }

    func withReviewStatus(_ status: AIConnectorQualityFixtureReviewStatus) -> Self {
        Self(
            id: id,
            revision: revision,
            scenarioID: scenarioID,
            category: category,
            split: split,
            provenance: provenance,
            text: text,
            expected: expected,
            sources: sources,
            question: question,
            rightsDeclared: rightsDeclared,
            anonymizationChecked: anonymizationChecked,
            reviewStatus: status
        )
    }

    private struct FixtureDigestPayload: Codable {
        let id: String
        let revision: Int
        let scenarioID: String
        let category: AIConnectorQualityCategory
        let split: AIConnectorQualityFixtureSplit
        let provenance: AIConnectorQualityFixtureProvenance
        let text: String
        let expected: AIConnectorQualityExpectation
        let sources: [AIConnectorQualityExpectedSource]
        let question: String
        let rightsDeclared: Bool
        let anonymizationChecked: Bool
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct AIConnectorLawyerReviewRecord: Codable, Hashable, Sendable {
    let fixtureID: String
    let fixtureRevision: Int
    let fixtureDigest: String
    let reviewerID: String
    let reviewedAt: Date
    let status: AIConnectorQualityFixtureReviewStatus
    let classificationApproved: Bool
    let replacementApproved: Bool
    let sourceApproved: Bool
    let applicabilityApproved: Bool
    let hardNegativeApproved: Bool
    let safetyApproved: Bool
    let notes: String?

    var isApproved: Bool {
        status == .approved
            && classificationApproved
            && replacementApproved
            && sourceApproved
            && applicabilityApproved
            && hardNegativeApproved
            && safetyApproved
    }
}

nonisolated struct AIConnectorQualityThreshold: Codable, Hashable, Sendable {
    let minimumPrecision: Double?
    let minimumRecall: Double?
    let minimumF1: Double?
    let maximumHardNegativeFalsePositiveRate: Double?
    let minimumGroundingRate: Double?
    let minimumExactSpanAccuracy: Double?

    static let uncalibrated = AIConnectorQualityThreshold(
        minimumPrecision: nil,
        minimumRecall: nil,
        minimumF1: nil,
        maximumHardNegativeFalsePositiveRate: nil,
        minimumGroundingRate: nil,
        minimumExactSpanAccuracy: nil
    )
}

nonisolated struct AIConnectorQualityHardwareProfile: Codable, Hashable, Sendable {
    let chip: String
    let memoryGB: Int
    let operatingSystem: String
    let modelVariant: AIConnectorModelVariant
    let repetitions: Int

    static func current(
        modelVariant: AIConnectorModelVariant,
        repetitions: Int = 4
    ) -> Self {
        Self(
            chip: chipName(),
            memoryGB: max(Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)), 0),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            modelVariant: modelVariant,
            repetitions: max(repetitions, 1)
        )
    }

    private static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 1 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct AIConnectorQualityPolicy: Codable, Hashable, Sendable {
    static let schemaVersion = "phase8-quality-policy-v1"

    let schemaVersion: String
    let policyID: String
    let revision: Int
    let approved: Bool
    let approvedBy: String?
    let approvedAt: Date?
    let releaseMode: AIConnectorReviewMode
    let requiredCategories: [AIConnectorQualityCategory]
    let minimumSamplesByCategory: [String: Int]
    let thresholdsByCategory: [String: AIConnectorQualityThreshold]
    let requiredFixtureSplits: [AIConnectorQualityFixtureSplit]
    let requiredCoverageFraction: Double
    let hardwareProfile: AIConnectorQualityHardwareProfile?

    var isCalibrated: Bool {
        requiredCategories.allSatisfy { category in
            guard let threshold = thresholdsByCategory[category.rawValue] else { return false }
            let hasThreshold = threshold.minimumPrecision != nil
                || threshold.minimumRecall != nil
                || threshold.minimumF1 != nil
                || threshold.maximumHardNegativeFalsePositiveRate != nil
                || threshold.minimumGroundingRate != nil
                || threshold.minimumExactSpanAccuracy != nil
            let minimumSamples = minimumSamplesByCategory[category.rawValue] ?? 0
            return hasThreshold && minimumSamples > 0
        }
    }

    static let uncalibrated = AIConnectorQualityPolicy(
        policyID: "amt-document-phase8-default",
        revision: 1,
        approved: false,
        approvedBy: nil,
        approvedAt: nil,
        releaseMode: .hybrid,
        requiredCategories: AIConnectorQualityCategory.allCases,
        minimumSamplesByCategory: [:],
        thresholdsByCategory: [:],
        requiredFixtureSplits: [.calibration, .regression, .holdout],
        requiredCoverageFraction: 1,
        hardwareProfile: nil
    )

    static func diagnosticDefault(
        modelVariant: AIConnectorModelVariant = .qwen35Base4B
    ) -> Self {
        Self(
            policyID: uncalibrated.policyID,
            revision: uncalibrated.revision,
            approved: uncalibrated.approved,
            approvedBy: uncalibrated.approvedBy,
            approvedAt: uncalibrated.approvedAt,
            releaseMode: uncalibrated.releaseMode,
            requiredCategories: uncalibrated.requiredCategories,
            minimumSamplesByCategory: uncalibrated.minimumSamplesByCategory,
            thresholdsByCategory: uncalibrated.thresholdsByCategory,
            requiredFixtureSplits: uncalibrated.requiredFixtureSplits,
            requiredCoverageFraction: uncalibrated.requiredCoverageFraction,
            hardwareProfile: AIConnectorQualityHardwareProfile.current(modelVariant: modelVariant)
        )
    }

    init(
        policyID: String,
        revision: Int,
        approved: Bool,
        approvedBy: String?,
        approvedAt: Date?,
        releaseMode: AIConnectorReviewMode,
        requiredCategories: [AIConnectorQualityCategory],
        minimumSamplesByCategory: [String: Int],
        thresholdsByCategory: [String: AIConnectorQualityThreshold],
        requiredFixtureSplits: [AIConnectorQualityFixtureSplit],
        requiredCoverageFraction: Double,
        hardwareProfile: AIConnectorQualityHardwareProfile?
    ) {
        self.schemaVersion = Self.schemaVersion
        self.policyID = policyID
        self.revision = max(revision, 1)
        self.approved = approved
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.releaseMode = releaseMode
        self.requiredCategories = requiredCategories
        self.minimumSamplesByCategory = minimumSamplesByCategory
        self.thresholdsByCategory = thresholdsByCategory
        self.requiredFixtureSplits = requiredFixtureSplits
        self.requiredCoverageFraction = min(max(requiredCoverageFraction, 0), 1)
        self.hardwareProfile = hardwareProfile
    }
}

nonisolated struct AIConnectorQualityCandidateManifest: Codable, Hashable, Sendable {
    static let schemaVersion = "phase8-quality-candidate-v1"

    let schemaVersion: String
    let candidateID: String
    let sourceRevision: String
    let pipelineVersion: String
    let rulePackVersion: String
    let corpusVersion: String
    let modelVariants: [String]
    let promptVersions: [String]
    let fixtureCatalogVersion: String
    let fixtureManifestDigest: String
    let policyID: String
    let policyRevision: Int
    let worktreeDirty: Bool

    init(
        candidateID: String,
        sourceRevision: String,
        pipelineVersion: String,
        rulePackVersion: String,
        corpusVersion: String,
        modelVariants: [String],
        promptVersions: [String],
        fixtureCatalogVersion: String,
        fixtureManifestDigest: String,
        policyID: String,
        policyRevision: Int,
        worktreeDirty: Bool
    ) {
        self.schemaVersion = Self.schemaVersion
        self.candidateID = candidateID
        self.sourceRevision = sourceRevision
        self.pipelineVersion = pipelineVersion
        self.rulePackVersion = rulePackVersion
        self.corpusVersion = corpusVersion
        self.modelVariants = modelVariants
        self.promptVersions = promptVersions
        self.fixtureCatalogVersion = fixtureCatalogVersion
        self.fixtureManifestDigest = fixtureManifestDigest
        self.policyID = policyID
        self.policyRevision = policyRevision
        self.worktreeDirty = worktreeDirty
    }
}

nonisolated struct AIConnectorQualityObservedFinding: Codable, Hashable, Sendable {
    let occurrence: Int
    let category: AIConnectorQualityCategory
    let status: String
    let original: String?
    let replacement: String?
    let classification: String?
    let sourceID: String?
    let sourceEvidenceID: String?
    let sourceVerified: Bool
    let sourceActionable: Bool
    let readOnly: Bool
    let anchorValid: Bool
}

nonisolated struct AIConnectorQualitySafetyObservation: Codable, Hashable, Sendable {
    let staleApplyAttempts: Int
    let outOfRangeApplyAttempts: Int
    let readOnlyApplyAttempts: Int
    let ungroundedReplacementAttempts: Int

    static let zero = AIConnectorQualitySafetyObservation(
        staleApplyAttempts: 0,
        outOfRangeApplyAttempts: 0,
        readOnlyApplyAttempts: 0,
        ungroundedReplacementAttempts: 0
    )

    var violationCount: Int {
        max(staleApplyAttempts, 0)
            + max(outOfRangeApplyAttempts, 0)
            + max(readOnlyApplyAttempts, 0)
            + max(ungroundedReplacementAttempts, 0)
    }
}

nonisolated struct AIConnectorQualityObservedOutput: Codable, Hashable, Sendable {
    let fixtureID: String
    let complete: Bool
    let findings: [AIConnectorQualityObservedFinding]
    let safety: AIConnectorQualitySafetyObservation
    let firstResultLatency: TimeInterval?
    let totalDuration: TimeInterval
    let stageDurations: [String: TimeInterval]
    let reusedSegmentCount: Int
    let recomputedSegmentCount: Int
    let modelCallCount: Int
    let resourcePreparationDuration: TimeInterval
    let incrementalEquivalentToFresh: Bool?
}

nonisolated struct AIConnectorQualityRunProgress: Hashable, Sendable {
    let mode: AIConnectorReviewMode
    let completedFixtureCount: Int
    let totalFixtureCount: Int
}

nonisolated struct AIConnectorQualityCategorySummary: Codable, Hashable, Sendable {
    let category: AIConnectorQualityCategory
    let sampleCount: Int
    let completedSampleCount: Int
    let expectedFindingCount: Int
    let observedFindingCount: Int
    let truePositive: Int
    let falsePositive: Int
    let falseNegative: Int
    let precision: Double?
    let recall: Double?
    let f1: Double?
    let exactSpanAccuracy: Double?
    let noChangeAccuracy: Double?
    let hardNegativeFalsePositiveRate: Double?
    let groundingRate: Double?
    let safetyViolationCount: Int
    let thresholdViolations: [String]
}

nonisolated struct AIConnectorQualityStageSummary: Codable, Hashable, Sendable {
    let stage: String
    let invocationCount: Int
    let medianDuration: TimeInterval?
    let p95Duration: TimeInterval?
}

nonisolated struct AIConnectorQualityModeReport: Codable, Hashable, Sendable, Identifiable {
    let mode: AIConnectorReviewMode
    let status: AIConnectorQualityGateStatus
    let sampleCount: Int
    let completedSampleCount: Int
    let coverageFraction: Double?
    let safetyViolationCount: Int
    let categories: [AIConnectorQualityCategorySummary]
    let stages: [AIConnectorQualityStageSummary]
    let firstResultLatencyP50: TimeInterval?
    let totalDurationP50: TimeInterval?
    let totalDurationP95: TimeInterval?
    let reusedSegmentCount: Int
    let recomputedSegmentCount: Int
    let modelCallCount: Int
    let resourcePreparationDuration: TimeInterval
    let incrementalEquivalentCount: Int
    let incrementalComparisonCount: Int

    var id: String { mode.rawValue }
}

nonisolated struct AIConnectorQualityEvaluationReport: Codable, Hashable, Sendable {
    static let schemaVersion = "phase8-quality-report-v1"

    let schemaVersion: String
    let generatedAt: Date
    let runID: UUID
    let terminalStatus: AIConnectorQualityRunStatus
    let overallStatus: AIConnectorQualityGateStatus
    let statusReasons: [String]
    let candidateManifestDigest: String
    let policyID: String
    let policyRevision: Int
    let fixtureCatalogVersion: String
    let fixtureCount: Int
    let approvedFixtureCount: Int
    let approvedCoverageFraction: Double
    let pipelineVersion: String
    let rulePackVersion: String
    let corpusVersion: String
    let modes: [AIConnectorQualityModeReport]
    let hardware: AIConnectorQualityHardwareProfile?
}

nonisolated struct AIConnectorQualityReviewPackageManifest: Codable, Hashable, Sendable {
    static let schemaVersion = "phase8-review-package-v1"

    let schemaVersion: String
    let packageID: UUID
    let generatedAt: Date
    let fixtureCatalogVersion: String
    let fixtureCount: Int
    let fixtureJSONDigest: String
    let reviewGuideDigest: String
    let includedFiles: [String]
}

nonisolated struct AIConnectorQualityReviewPackage: Codable, Hashable, Sendable {
    let manifest: AIConnectorQualityReviewPackageManifest
    let fixtures: [AIConnectorQualityFixture]
    let reviews: [AIConnectorLawyerReviewRecord]
    let reviewGuideMarkdown: String
}

nonisolated struct AIConnectorQualityReviewPackageResult: Hashable, Sendable {
    let fixtures: [AIConnectorQualityFixture]
    let reviews: [AIConnectorLawyerReviewRecord]
}

nonisolated enum AIConnectorQualityPackageError: LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidDirectory
    case missingFile(String)
    case invalidSchema
    case invalidManifest
    case duplicateFixtureID(String)
    case unknownReviewFixture(String)
    case staleReview(String)
    case invalidFixture(String)
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "Operasi paket review dibatalkan."
        case .invalidDirectory: "Lokasi paket review bukan directory yang valid."
        case let .missingFile(file): "Paket review tidak memiliki file \(file)."
        case .invalidSchema: "Schema paket review tidak didukung."
        case .invalidManifest: "Manifest paket review tidak cocok dengan isinya."
        case let .duplicateFixtureID(id): "Fixture duplikat: \(id)."
        case let .unknownReviewFixture(id): "Keputusan merujuk fixture yang tidak tersedia: \(id)."
        case let .staleReview(id): "Keputusan lawyer sudah stale untuk fixture \(id)."
        case let .invalidFixture(id): "Fixture tidak valid: \(id)."
        case .encodingFailed: "Paket review tidak dapat diserialisasi."
        case .writeFailed: "Paket review tidak dapat ditulis secara atomic."
        }
    }
}

nonisolated struct AIConnectorQualityFixtureCatalog {
    static let version = "phase8-fixtures-v1"

    #if DEBUG
    static var fixtures: [AIConnectorQualityFixture] {
        var result = AIConnectorPhaseZeroFixtureCatalog.fixtures.enumerated().map { index, fixture in
            AIConnectorQualityFixture(
                id: "phase8-\(fixture.id)",
                scenarioID: fixture.id,
                category: category(for: fixture.category),
                split: split(for: fixture.id, fallbackIndex: index),
                text: fixture.text,
                expected: expectation(for: fixture),
                question: "Apakah klasifikasi dan rekomendasi pada fixture ini tepat untuk penggunaan drafting hukum?"
            )
        }
        result.append(contentsOf: documentFixtures)
        return result
    }

    private static func category(for category: AIConnectorPhaseZeroFixtureCategory) -> AIConnectorQualityCategory {
        switch category {
        case .spelling: .spelling
        case .grammar: .grammar
        case .terminology: .terminology
        case .definition: .definition
        case .hardNegative: .hardNegative
        }
    }

    private static func split(for fixtureID: String, fallbackIndex: Int) -> AIConnectorQualityFixtureSplit {
        let normalized = fixtureID.lowercased()
        if normalized.contains("spelling") || normalized.contains("definition") {
            return .calibration
        }
        if normalized.contains("grammar") || normalized.contains("resolution") {
            return .regression
        }
        if normalized.contains("terminology") || normalized.contains("hard-negative") {
            return .holdout
        }
        return fallbackIndex % 3 == 0 ? .holdout : (fallbackIndex % 3 == 1 ? .regression : .calibration)
    }

    private static func expectation(for fixture: AIConnectorPhaseZeroFixture) -> AIConnectorQualityExpectation {
        switch fixture.expected {
        case let .findings(findings):
            return AIConnectorQualityExpectation(
                findings: findings.enumerated().map { index, finding in
                    AIConnectorQualityExpectedFinding(
                        occurrence: index,
                        category: category(for: finding.category),
                        status: finding.status.rawValue,
                        original: finding.original,
                        replacement: finding.replacement
                    )
                }
            )
        case let .definition(definition):
            guard definition.classification != .notDefinition else {
                return AIConnectorQualityExpectation(noChange: true)
            }
            return AIConnectorQualityExpectation(
                findings: [AIConnectorQualityExpectedFinding(
                    category: .definition,
                    status: definition.classification.rawValue,
                    original: definitionTerm(in: fixture.text),
                    classification: definition.alignment.rawValue,
                    readOnly: true
                )]
            )
        case .noChange:
            return AIConnectorQualityExpectation(noChange: true)
        }
    }

    private static func definitionTerm(in text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let definedTermPrefix = "Yang dimaksud dengan "
        if normalized.hasPrefix(definedTermPrefix),
           let range = normalized.range(of: " adalah ") {
            let start = normalized.index(normalized.startIndex, offsetBy: definedTermPrefix.count)
            let term = normalized[start..<range.lowerBound]
            return term.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for separator in [" adalah ", " merupakan "] {
            guard let range = normalized.range(of: separator) else { continue }
            let term = normalized[..<range.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return term.isEmpty ? nil : term
        }
        return nil
    }

    private static let documentFixtures: [AIConnectorQualityFixture] = [
        AIConnectorQualityFixture(
            id: "phase8-defined-term-casing",
            scenarioID: "defined-term-casing",
            category: .definedTerm,
            split: .calibration,
            text: "Para Pihak menyepakati bahwa Data Pribadi wajib dilindungi. data pribadi dapat diproses sesuai Perjanjian.",
            expected: AIConnectorQualityExpectation(findings: [AIConnectorQualityExpectedFinding(
                category: .definedTerm,
                status: "flagged",
                original: "data pribadi",
                readOnly: true
            )]),
            question: "Apakah penggunaan defined term dan perbedaan casing ditandai dengan bukti yang tepat?"
        ),
        AIConnectorQualityFixture(
            id: "phase8-internal-reference-missing",
            scenarioID: "internal-reference-missing",
            category: .internalReference,
            split: .regression,
            text: "Pihak Kedua wajib memenuhi Pasal 99 dan Lampiran C yang tidak tersedia pada dokumen ini.",
            expected: AIConnectorQualityExpectation(findings: [AIConnectorQualityExpectedFinding(
                category: .internalReference,
                status: "flagged",
                original: "Pasal 99",
                readOnly: true
            )]),
            question: "Apakah rujukan internal yang tidak ditemukan dibedakan dari rujukan eksternal?"
        ),
        AIConnectorQualityFixture(
            id: "phase8-risk-hard-negative-modal",
            scenarioID: "isolated-modal-hard-negative",
            category: .hardNegative,
            split: .holdout,
            text: "Pihak Pertama dapat menyampaikan pemberitahuan kepada Pihak Kedua.",
            expected: AIConnectorQualityExpectation(noChange: true),
            question: "Apakah kata modalitas yang berdiri sendiri tidak menghasilkan legal-risk finding?"
        ),
        AIConnectorQualityFixture(
            id: "phase8-definition-resolution-source",
            scenarioID: "definition-resolution-source",
            category: .definitionResolution,
            split: .regression,
            text: "\"Data Pribadi\" adalah data mengenai pelanggan korporat.",
            expected: AIConnectorQualityExpectation(findings: [AIConnectorQualityExpectedFinding(
                category: .definitionResolution,
                status: "EXPLICIT_DEFINITION",
                original: "Data Pribadi",
                classification: "MISMATCH",
                sourceID: "term:b5f759d772843a00fa7c",
                readOnly: true
            )], requiredSourceIDs: ["phase8-data-pribadi-source"]),
            sources: [AIConnectorQualityExpectedSource(
                id: "phase8-data-pribadi-source",
                corpusEntryID: "term:b5f759d772843a00fa7c",
                referenceID: "peraturan.go.id:uu-no-27-tahun-2022",
                evidenceID: "peraturan.go.id:uu-no-27-tahun-2022:combined#body-chapter_heading-2-0002",
                applicabilityStatus: "in_force",
                verified: false,
                isActionable: false
            )],
            question: "Apakah pilihan resolusi definisi mempertahankan anchor istilah dan body serta sumber yang terverifikasi?"
        ),
        AIConnectorQualityFixture(
            id: "phase8-incremental-definition-change",
            scenarioID: "incremental-definition-change",
            category: .incremental,
            split: .holdout,
            text: "BAB I\n\"Data\" adalah informasi umum.\nBAB II\nPihak Kedua wajib menjaga Data.",
            expected: AIConnectorQualityExpectation(noChange: true),
            question: "Apakah perubahan definisi memperluas pemeriksaan ke seluruh dependensi yang relevan?"
        )
    ]
    #else
    static let fixtures: [AIConnectorQualityFixture] = []
    #endif
}

#if DEBUG
private extension AIConnectorQualityFixtureCatalog {
    nonisolated static func category(for category: AIReviewCategory) -> AIConnectorQualityCategory {
        switch category {
        case .spelling: .spelling
        case .grammar: .grammar
        case .terminology: .terminology
        case .clarity, .none: .hardNegative
        }
    }
}
#endif
#endif
