import CryptoKit
import Foundation

/// A UTF-16 range that can safely cross the persistence boundary.
struct DocumentTextRange: Codable, Equatable, Hashable, Sendable {
    let location: Int
    let length: Int

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    var endLocation: Int {
        location + length
    }

    func isValid(inUTF16Length length: Int) -> Bool {
        location >= 0 && self.length >= 0 && location <= length && self.length <= length - location
    }
}

enum DocumentReviewMappingIssue: String, Codable, Equatable, Hashable, Sendable {
    case missingFromAnalysis = "missing-from-analysis"
    case ambiguousInAnalysis = "ambiguous-in-analysis"
    case missingFromSource = "missing-from-source"
    case ambiguousInSource = "ambiguous-in-source"
    case invalidSourceRange = "invalid-source-range"
    case overlapsAnotherChange = "overlaps-another-change"

    var displayTitle: String {
        switch self {
        case .missingFromAnalysis, .missingFromSource:
            "Kutipan tidak ditemukan"
        case .ambiguousInAnalysis, .ambiguousInSource:
            "Kutipan muncul lebih dari sekali"
        case .invalidSourceRange:
            "Rentang sumber tidak valid"
        case .overlapsAnotherChange:
            "Perubahan bertumpuk"
        }
    }
}

enum DocumentReviewDecision: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case pending
    case accepted
    case rejected
    case unavailable

    var displayTitle: String {
        switch self {
        case .pending:
            "Belum ditinjau"
        case .accepted:
            "Diterima"
        case .rejected:
            "Ditolak"
        case .unavailable:
            "Tidak dapat dipetakan"
        }
    }
}

enum DocumentReviewAnalysisStatus: String, Codable, Equatable, Hashable, Sendable {
    case idle
    case analyzing
    case completed
    case cancelled
    case failed

    var displayTitle: String {
        switch self {
        case .idle:
            "Belum dianalisis"
        case .analyzing:
            "Sedang menganalisis"
        case .completed:
            "Analisis selesai"
        case .cancelled:
            "Analisis dibatalkan"
        case .failed:
            "Analisis gagal"
        }
    }
}

struct DocumentReviewReference: Codable, Equatable, Hashable, Sendable {
    let term: String
    let regulation: String
    let regulationTitle: String
    let sourceURL: URL?
}

/// A review candidate anchored to the original DOCX text, never to Markdown offsets.
struct DocumentReviewItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let segmentID: Int
    let original: String
    let replacement: String
    let category: AIReviewCategory
    let reason: String
    let origin: AIReviewOrigin
    let reference: DocumentReviewReference?
    let sourceRange: DocumentTextRange?
    var decision: DocumentReviewDecision
    var mappingIssue: DocumentReviewMappingIssue?

    init(
        id: UUID = UUID(),
        segmentID: Int,
        original: String,
        replacement: String,
        category: AIReviewCategory,
        reason: String,
        origin: AIReviewOrigin,
        reference: DocumentReviewReference? = nil,
        sourceRange: DocumentTextRange? = nil,
        decision: DocumentReviewDecision = .pending,
        mappingIssue: DocumentReviewMappingIssue? = nil
    ) {
        self.id = id
        self.segmentID = segmentID
        self.original = original
        self.replacement = replacement
        self.category = category
        self.reason = reason
        self.origin = origin
        self.reference = reference
        self.sourceRange = sourceRange
        self.decision = decision
        self.mappingIssue = mappingIssue
    }

    var isActionable: Bool {
        sourceRange != nil && mappingIssue == nil && decision != .unavailable
    }
}

struct DocumentReviewSnapshot: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceFingerprint: String
    let analysisStatus: DocumentReviewAnalysisStatus
    let reviewItems: [DocumentReviewItem]
    let timestamp: Date

    init(
        schemaVersion: Int = DocumentReviewSnapshot.currentSchemaVersion,
        sourceFingerprint: String,
        analysisStatus: DocumentReviewAnalysisStatus,
        reviewItems: [DocumentReviewItem],
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.sourceFingerprint = sourceFingerprint
        self.analysisStatus = analysisStatus
        self.reviewItems = reviewItems
        self.timestamp = timestamp
    }
}

enum DocumentFingerprint {
    static func sha256(data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256(fileURL: URL) throws -> String {
        sha256(data: try Data(contentsOf: fileURL))
    }
}
