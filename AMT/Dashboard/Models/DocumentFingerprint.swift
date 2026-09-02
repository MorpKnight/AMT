import CryptoKit
import Foundation

/// Identifies an imported document by both its source bytes and its stored
/// textual representation.
struct DocumentFingerprint: Codable, Equatable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sourceFileSHA256: String?
    var normalizedContentSHA256: String

    init(
        sourceFileSHA256: String? = nil,
        normalizedContentSHA256: String,
        version: Int = currentVersion
    ) {
        self.version = version
        self.sourceFileSHA256 = sourceFileSHA256
        self.normalizedContentSHA256 = normalizedContentSHA256
    }
}

enum DocumentFingerprinting {
    private static let fileReadChunkSize = 1_048_576

    static func make(
        fileURL: URL,
        convertedContent: String
    ) throws -> DocumentFingerprint {
        DocumentFingerprint(
            sourceFileSHA256: try sourceFileSHA256(at: fileURL),
            normalizedContentSHA256: contentSHA256(convertedContent)
        )
    }

    static func forStoredContent(_ content: String) -> DocumentFingerprint {
        DocumentFingerprint(normalizedContentSHA256: contentSHA256(content))
    }

    static func refreshingContent(
        _ fingerprint: DocumentFingerprint?,
        content: String
    ) -> DocumentFingerprint {
        DocumentFingerprint(
            sourceFileSHA256: fingerprint?.sourceFileSHA256,
            normalizedContentSHA256: contentSHA256(content),
            version: fingerprint?.version ?? DocumentFingerprint.currentVersion
        )
    }

    static func normalizedContent(_ content: String) -> String {
        let canonicalContent = content
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let normalizedLines = canonicalContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimTrailingWhitespace(String($0)) }

        return normalizedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentSHA256(_ content: String) -> String {
        sha256Hex(Data(normalizedContent(content).utf8))
    }

    private static func sourceFileSHA256(at url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        while let chunk = try fileHandle.read(upToCount: fileReadChunkSize),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func trimTrailingWhitespace(_ value: String) -> String {
        var endIndex = value.endIndex
        while endIndex > value.startIndex {
            let previousIndex = value.index(before: endIndex)
            guard value[previousIndex].isWhitespace else { break }
            endIndex = previousIndex
        }
        return String(value[..<endIndex])
    }
}
