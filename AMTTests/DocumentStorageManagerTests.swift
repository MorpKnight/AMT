import CryptoKit
import Foundation
import XCTest
@testable import AMT

@MainActor
final class DocumentStorageManagerTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUpWithError() throws {
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AMT-DocumentStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
    }

    func testContentFingerprintIsStableAndNormalizesOnlyRequestedDifferences() {
        let source = "Judul  dengan spasi\r\nBaris e\u{301}  \r\n\r\n"

        XCTAssertEqual(
            DocumentFingerprinting.normalizedContent(source),
            "Judul  dengan spasi\nBaris é"
        )
        XCTAssertEqual(
            DocumentFingerprinting.normalizedContent("kata  internal\nparagraf kedua"),
            "kata  internal\nparagraf kedua"
        )
        XCTAssertEqual(
            DocumentFingerprinting.contentSHA256("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertEqual(
            DocumentFingerprinting.contentSHA256(source),
            DocumentFingerprinting.contentSHA256("Judul  dengan spasi\nBaris é")
        )
    }

    func testFileFingerprintUsesStreamingRawSHA256AndNormalizedContentHash() throws {
        let firstURL = try writeFile(named: "first.txt", data: Data("Isi\r\n".utf8))
        let secondURL = try writeFile(named: "second.txt", data: Data("Isi\n".utf8))

        let firstFingerprint = try DocumentFingerprinting.make(
            fileURL: firstURL,
            convertedContent: "Isi\r\n"
        )
        let secondFingerprint = try DocumentFingerprinting.make(
            fileURL: secondURL,
            convertedContent: "Isi\n"
        )

        XCTAssertEqual(firstFingerprint.version, DocumentFingerprint.currentVersion)
        XCTAssertNotNil(firstFingerprint.sourceFileSHA256)
        XCTAssertNotEqual(
            firstFingerprint.sourceFileSHA256,
            secondFingerprint.sourceFileSHA256,
            "Line-ending changes alter the raw file hash."
        )
        XCTAssertEqual(
            firstFingerprint.normalizedContentSHA256,
            secondFingerprint.normalizedContentSHA256,
            "Line-ending changes do not alter the normalized content hash."
        )
        XCTAssertEqual(
            firstFingerprint.sourceFileSHA256,
            sha256Hex(Data("Isi\r\n".utf8))
        )
    }

    func testFirstImportPersistsExactlyOneDocumentAndFingerprint() throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "agreement.txt",
            data: Data("Perjanjian ini berlaku.\n".utf8)
        )

        let result = storage.importDocument(at: sourceURL)
        let document = try requireImportedDocument(from: result)

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
        XCTAssertEqual(document.fingerprint?.version, DocumentFingerprint.currentVersion)
        XCTAssertNotNil(document.fingerprint?.sourceFileSHA256)
        XCTAssertEqual(
            document.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(document.content)
        )

        let reloaded = makeStorage()
        XCTAssertEqual(reloaded.documents.count, 1)
        XCTAssertEqual(
            reloaded.documents.first?.fingerprint,
            document.fingerprint
        )
    }

    func testIdenticalSourceFileIsBlockedWithoutCreatingDocumentOrJSON() throws {
        let storage = makeStorage()
        let firstURL = try writeFile(
            named: "first.txt",
            data: Data("Isi yang sama.\n".utf8)
        )
        let secondURL = try writeFile(
            named: "renamed-copy.txt",
            data: Data("Isi yang sama.\n".utf8)
        )

        let firstDocument = try requireImportedDocument(
            from: storage.importDocument(at: firstURL)
        )
        let jsonCountBeforeDuplicate = try jsonFiles().count

        switch storage.importDocument(at: secondURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, firstDocument.id)
            XCTAssertEqual(matchKind, .sourceFile)
        default:
            XCTFail("File dengan byte identik harus dianggap duplicate source file.")
        }

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, jsonCountBeforeDuplicate)
        XCTAssertEqual(storage.documents.first?.id, firstDocument.id)
    }

    func testDifferentSourceWithSameNormalizedContentIsBlockedByContentHash() throws {
        let storage = makeStorage()
        let firstURL = try writeFile(
            named: "windows.txt",
            data: Data("Isi sama  \r\nBaris kedua\r\n".utf8)
        )
        let secondURL = try writeFile(
            named: "unix.txt",
            data: Data("Isi sama\nBaris kedua\n".utf8)
        )

        let firstDocument = try requireImportedDocument(
            from: storage.importDocument(at: firstURL)
        )

        switch storage.importDocument(at: secondURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, firstDocument.id)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Konten ternormalisasi yang sama harus dianggap duplicate content.")
        }

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testDifferentContentCanBeImportedAsAnotherDocument() throws {
        let storage = makeStorage()
        let firstURL = try writeFile(named: "first.txt", data: Data("Satu".utf8))
        let secondURL = try writeFile(named: "second.txt", data: Data("Dua".utf8))

        _ = try requireImportedDocument(from: storage.importDocument(at: firstURL))
        _ = try requireImportedDocument(from: storage.importDocument(at: secondURL))

        XCTAssertEqual(storage.documents.count, 2)
        XCTAssertEqual(try jsonFiles().count, 2)
    }

    func testLegacyJSONWithoutFingerprintLoadsAndGetsFingerprintOnNextSave() throws {
        let legacyID = UUID()
        let legacyContent = "Dokumen lama tanpa fingerprint."
        let legacy = LegacyDashboardDocument(
            id: legacyID,
            title: "Legacy",
            content: legacyContent,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let legacyURL = storageDirectory.appendingPathComponent("\(legacyID.uuidString).json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let storage = makeStorage()
        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertNil(storage.documents.first?.fingerprint?.sourceFileSHA256)
        XCTAssertEqual(
            storage.documents.first?.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(legacyContent)
        )

        storage.saveDocument(try XCTUnwrap(storage.documents.first))

        let reloaded = makeStorage()
        XCTAssertNotNil(reloaded.documents.first?.fingerprint)
        XCTAssertEqual(
            reloaded.documents.first?.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(legacyContent)
        )
    }

    func testLegacyDocumentParticipatesInContentDuplicateDetection() throws {
        let legacyID = UUID()
        let legacyContent = "Konten legacy yang sama."
        let legacy = LegacyDashboardDocument(
            id: legacyID,
            title: "Legacy",
            content: legacyContent,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try JSONEncoder().encode(legacy).write(
            to: storageDirectory.appendingPathComponent("\(legacyID.uuidString).json")
        )
        let storage = makeStorage()
        let importedURL = try writeFile(named: "new.txt", data: Data(legacyContent.utf8))

        switch storage.importDocument(at: importedURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, legacyID)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Legacy content harus ikut dalam pemeriksaan duplicate.")
        }

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testEarliestCreatedDuplicateIsUsedAsCanonicalExistingDocument() throws {
        let olderID = UUID()
        let newerID = UUID()
        let content = "Konten yang sengaja tersimpan dua kali."
        let older = LegacyDashboardDocument(
            id: olderID,
            title: "Older",
            content: content,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let newer = LegacyDashboardDocument(
            id: newerID,
            title: "Newer",
            content: content,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try JSONEncoder().encode(older).write(
            to: storageDirectory.appendingPathComponent("\(olderID.uuidString).json")
        )
        try JSONEncoder().encode(newer).write(
            to: storageDirectory.appendingPathComponent("\(newerID.uuidString).json")
        )

        let storage = makeStorage()
        let importedURL = try writeFile(named: "same-content.txt", data: Data(content.utf8))

        switch storage.importDocument(at: importedURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, olderID)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Dokumen canonical harus dipilih dari createdAt paling awal.")
        }

        XCTAssertEqual(storage.documents.count, 2)
        XCTAssertEqual(try jsonFiles().count, 2, "File sumber bukan JSON dan tidak boleh dihitung sebagai dokumen.")
    }

    func testEditingContentRefreshesContentHashButPreservesSourceHash() throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "editable.txt",
            data: Data("Versi awal".utf8)
        )
        let imported = try requireImportedDocument(
            from: storage.importDocument(at: sourceURL)
        )
        let originalSourceHash = imported.fingerprint?.sourceFileSHA256

        var edited = imported
        edited.content = "Versi yang sudah diedit"
        storage.saveDocument(edited)

        let saved = try XCTUnwrap(storage.documents.first { $0.id == imported.id })
        XCTAssertEqual(saved.fingerprint?.sourceFileSHA256, originalSourceHash)
        XCTAssertEqual(
            saved.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(edited.content)
        )

        let reloaded = makeStorage()
        let persisted = try XCTUnwrap(reloaded.documents.first { $0.id == imported.id })
        XCTAssertEqual(persisted.fingerprint?.sourceFileSHA256, originalSourceHash)
        XCTAssertEqual(
            persisted.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(edited.content)
        )
    }

    func testConversionOrEmptyContentFailureDoesNotPersistDocument() throws {
        let storage = makeStorage()
        let invalidDocxURL = try writeFile(
            named: "invalid.docx",
            data: Data([0xff, 0xfe, 0xfd])
        )
        let emptyTextURL = try writeFile(named: "empty.txt", data: Data())

        assertFailed(storage.importDocument(at: invalidDocxURL))
        assertFailed(storage.importDocument(at: emptyTextURL))

        XCTAssertTrue(storage.documents.isEmpty)
        XCTAssertTrue(try jsonFiles().isEmpty)
    }

    func testCompletedAnalysisSnapshotPersistsWithDocumentAndReloads() throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "analyzed.txt",
            data: Data("Pihak Kedua wajib untuk membayar.\n".utf8)
        )
        let imported = try requireImportedDocument(
            from: storage.importDocument(at: sourceURL)
        )
        let suggestion = makeSuggestion(
            in: imported.content,
            original: "wajib untuk",
            replacement: "wajib"
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(imported.content),
            analysisProfile: makeAnalysisProfile(),
            completedAt: Date(timeIntervalSince1970: 123),
            editorSuggestions: [suggestion]
        )

        let saved = try XCTUnwrap(
            storage.saveAnalysisSnapshot(snapshot, for: imported)
        )
        XCTAssertEqual(saved.analysisSnapshot, snapshot)

        let reloaded = makeStorage()
        XCTAssertEqual(
            reloaded.documents.first?.analysisSnapshot,
            snapshot
        )
        XCTAssertEqual(
            reloaded.documents.first?.analysisSnapshot?.editorSuggestions,
            [suggestion]
        )
    }

    func testMismatchedAnalysisSnapshotIsNotAttachedToDocument() throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "mismatched.txt",
            data: Data("Isi asli.".utf8)
        )
        let imported = try requireImportedDocument(
            from: storage.importDocument(at: sourceURL)
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256("Isi berbeda."),
            analysisProfile: makeAnalysisProfile(),
            completedAt: Date(timeIntervalSince1970: 456),
            editorSuggestions: []
        )

        XCTAssertNil(storage.saveAnalysisSnapshot(snapshot, for: imported))
        XCTAssertNil(storage.documents.first?.analysisSnapshot)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testEditingContentInvalidatesPersistedAnalysisSnapshot() throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "editable-analysis.txt",
            data: Data("Pihak Kedua wajib untuk membayar.".utf8)
        )
        let imported = try requireImportedDocument(
            from: storage.importDocument(at: sourceURL)
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256(imported.content),
            analysisProfile: makeAnalysisProfile(),
            completedAt: Date(timeIntervalSince1970: 789),
            editorSuggestions: [
                makeSuggestion(
                    in: imported.content,
                    original: "wajib untuk",
                    replacement: "wajib"
                )
            ]
        )
        let saved = try XCTUnwrap(
            storage.saveAnalysisSnapshot(snapshot, for: imported)
        )

        var edited = saved
        edited.content = "Pihak Kedua dapat membayar."
        let persistedEdited = try XCTUnwrap(storage.saveDocument(edited))

        XCTAssertNil(persistedEdited.analysisSnapshot)
        XCTAssertNil(storage.documents.first?.analysisSnapshot)
        XCTAssertEqual(
            persistedEdited.fingerprint?.sourceFileSHA256,
            imported.fingerprint?.sourceFileSHA256
        )
        XCTAssertNotEqual(
            persistedEdited.fingerprint?.normalizedContentSHA256,
            imported.fingerprint?.normalizedContentSHA256
        )
        XCTAssertNil(makeStorage().documents.first?.analysisSnapshot)
    }

    private func makeStorage() -> DocumentStorageManager {
        DocumentStorageManager(storageDirectoryURL: storageDirectory)
    }

    @discardableResult
    private func writeFile(named name: String, data: Data) throws -> URL {
        let url = storageDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func jsonFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "json" }
    }

    private func requireImportedDocument(
        from result: DocumentImportResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DashboardDocument {
        switch result {
        case let .imported(document):
            return document
        case let .failed(message):
            XCTFail("Import gagal: \(message)", file: file, line: line)
        default:
            XCTFail("Hasil import bukan imported: \(result)", file: file, line: line)
        }
        throw ImportTestError.unexpectedResult
    }

    private func assertFailed(
        _ result: DocumentImportResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed = result else {
            XCTFail("Import invalid harus menghasilkan failed.", file: file, line: line)
            return
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func makeAnalysisProfile() -> AIConnectorAnalysisProfile {
        AIConnectorAnalysisProfile(
            pipelineVersion: "test-pipeline-v1",
            reviewMode: .hybrid,
            modelVariant: .qwen35Base4B,
            thinkingEnabled: false,
            generationProfilePreset: .greedy,
            corpusVersion: "test-corpus-v1",
            semanticModelRevision: "test-semantic-revision",
            semanticEmbeddingSchema: "test-embedding-schema",
            semanticRetrievalProfile: "test-retrieval-profile"
        )
    }

    private func makeSuggestion(
        in text: String,
        original: String,
        replacement: String
    ) -> EditorSuggestion {
        let range = (text as NSString).range(of: original)
        XCTAssertNotEqual(range.location, NSNotFound)
        return EditorSuggestion(
            id: UUID(),
            sourceRange: range,
            original: original,
            replacement: replacement,
            category: .grammar,
            reason: "Perbaikan tata bahasa.",
            origin: .deterministic
        )
    }
}

private struct LegacyDashboardDocument: Codable {
    let id: UUID
    let title: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
}

private enum ImportTestError: Error {
    case unexpectedResult
}
