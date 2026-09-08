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

    func testFirstImportPersistsExactlyOneDocumentAndFingerprint() async throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "agreement.txt",
            data: Data("Perjanjian ini berlaku.\n".utf8)
        )

        let result = await storage.importDocument(at: sourceURL)
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

    func testIdenticalSourceFileIsBlockedWithoutCreatingDocumentOrJSON() async throws {
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
            from: await storage.importDocument(at: firstURL)
        )
        let jsonCountBeforeDuplicate = try jsonFiles().count

        switch await storage.importDocument(at: secondURL) {
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

    func testDifferentSourceWithSameNormalizedContentIsBlockedByContentHash() async throws {
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
            from: await storage.importDocument(at: firstURL)
        )

        switch await storage.importDocument(at: secondURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, firstDocument.id)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Konten ternormalisasi yang sama harus dianggap duplicate content.")
        }

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testDifferentContentCanBeImportedAsAnotherDocument() async throws {
        let storage = makeStorage()
        let firstURL = try writeFile(named: "first.txt", data: Data("Satu".utf8))
        let secondURL = try writeFile(named: "second.txt", data: Data("Dua".utf8))

        _ = try requireImportedDocument(from: await storage.importDocument(at: firstURL))
        _ = try requireImportedDocument(from: await storage.importDocument(at: secondURL))

        XCTAssertEqual(storage.documents.count, 2)
        XCTAssertEqual(try jsonFiles().count, 2)
    }

    func testLegacyJSONWithoutFingerprintLoadsAndGetsFingerprintOnNextSave() async throws {
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

        _ = storage.updateDraft(try XCTUnwrap(storage.documents.first))
        _ = try requireSavedDocument(
            from: await storage.flushPendingSave(for: legacyID)
        )

        let reloaded = makeStorage()
        XCTAssertNotNil(reloaded.documents.first?.fingerprint)
        XCTAssertEqual(
            reloaded.documents.first?.fingerprint?.normalizedContentSHA256,
            DocumentFingerprinting.contentSHA256(legacyContent)
        )
    }

    func testLegacyDocumentParticipatesInContentDuplicateDetection() async throws {
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

        switch await storage.importDocument(at: importedURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, legacyID)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Legacy content harus ikut dalam pemeriksaan duplicate.")
        }

        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testEarliestCreatedDuplicateIsUsedAsCanonicalExistingDocument() async throws {
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

        switch await storage.importDocument(at: importedURL) {
        case let .duplicate(existing, matchKind):
            XCTAssertEqual(existing.id, olderID)
            XCTAssertEqual(matchKind, .normalizedContent)
        default:
            XCTFail("Dokumen canonical harus dipilih dari createdAt paling awal.")
        }

        XCTAssertEqual(storage.documents.count, 2)
        XCTAssertEqual(try jsonFiles().count, 2, "File sumber bukan JSON dan tidak boleh dihitung sebagai dokumen.")
    }

    func testEditingContentRefreshesContentHashButPreservesSourceHash() async throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "editable.txt",
            data: Data("Versi awal".utf8)
        )
        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        let originalSourceHash = imported.fingerprint?.sourceFileSHA256

        var edited = imported
        edited.content = "Versi yang sudah diedit"
        _ = storage.updateDraft(edited)
        _ = try requireSavedDocument(
            from: await storage.flushPendingSave(for: imported.id)
        )

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

    func testConversionOrEmptyContentFailureDoesNotPersistDocument() async throws {
        let storage = makeStorage()
        let invalidDocxURL = try writeFile(
            named: "invalid.docx",
            data: Data([0xff, 0xfe, 0xfd])
        )
        let emptyTextURL = try writeFile(named: "empty.txt", data: Data())

        assertFailed(await storage.importDocument(at: invalidDocxURL))
        assertFailed(await storage.importDocument(at: emptyTextURL))

        XCTAssertTrue(storage.documents.isEmpty)
        XCTAssertTrue(try jsonFiles().isEmpty)
    }

    func testCompletedAnalysisSnapshotPersistsWithDocumentAndReloads() async throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "analyzed.txt",
            data: Data("Pihak Kedua wajib untuk membayar.\n".utf8)
        )
        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        let originalUpdatedAt = imported.updatedAt
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

        let saved = try requireSavedDocument(
            from: await storage.saveAnalysisSnapshot(snapshot, for: imported)
        )
        XCTAssertEqual(saved.analysisSnapshot, snapshot)
        XCTAssertEqual(saved.updatedAt, originalUpdatedAt)

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

    func testMismatchedAnalysisSnapshotIsNotAttachedToDocument() async throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "mismatched.txt",
            data: Data("Isi asli.".utf8)
        )
        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        let snapshot = DocumentAnalysisSnapshot(
            analyzedContentSHA256: DocumentFingerprinting.contentSHA256("Isi berbeda."),
            analysisProfile: makeAnalysisProfile(),
            completedAt: Date(timeIntervalSince1970: 456),
            editorSuggestions: []
        )

        guard case .failure(.analysisSnapshotMismatch) = await storage.saveAnalysisSnapshot(
            snapshot,
            for: imported
        ) else {
            XCTFail("Snapshot yang tidak cocok harus ditolak.")
            return
        }
        XCTAssertNil(storage.documents.first?.analysisSnapshot)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testEditingContentInvalidatesPersistedAnalysisSnapshot() async throws {
        let storage = makeStorage()
        let sourceURL = try writeFile(
            named: "editable-analysis.txt",
            data: Data("Pihak Kedua wajib untuk membayar.".utf8)
        )
        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
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
        let saved = try requireSavedDocument(
            from: await storage.saveAnalysisSnapshot(snapshot, for: imported)
        )

        var edited = saved
        edited.content = "Pihak Kedua dapat membayar."
        _ = storage.updateDraft(edited)
        let persistedEdited = try requireSavedDocument(
            from: await storage.flushPendingSave(for: imported.id)
        )

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

    func testRapidDraftEditsCoalesceIntoOneFinalPersistedRevision() async throws {
        let storage = makeStorage()
        let sourceURL = try writeExternalFile(
            named: "rapid-edits.txt",
            data: Data("Versi awal".utf8)
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        var firstEdit = imported
        firstEdit.content = "Versi pertama"
        let firstDraft = storage.updateDraft(firstEdit)
        var finalEdit = firstDraft
        finalEdit.content = "Versi final"
        _ = storage.updateDraft(finalEdit)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        let reloaded = makeStorage()
        XCTAssertEqual(reloaded.documents.first?.content, "Versi final")
        guard case .saved = storage.saveState(for: finalEdit) else {
            return XCTFail("Edit cepat harus berakhir pada status Tersimpan lokal.")
        }
    }

    func testOlderRevisionCannotMarkNewerDraftAsSaved() async throws {
        let storage = makeStorage(persistenceDelayNanoseconds: 150_000_000)
        let sourceURL = try writeExternalFile(
            named: "stale-revision.txt",
            data: Data("Versi awal".utf8)
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        var firstEdit = imported
        firstEdit.content = "Versi sedang ditulis"
        let firstDraft = storage.updateDraft(firstEdit)
        let flushTask = Task { @MainActor in
            await storage.flushPendingSave(for: imported.id)
        }

        await Task.yield()
        try await Task.sleep(nanoseconds: 25_000_000)

        var newerEdit = firstDraft
        newerEdit.content = "Versi terbaru"
        _ = storage.updateDraft(newerEdit)

        _ = await flushTask.value
        let finalResult = await storage.flushPendingSave(for: imported.id)
        _ = try requireSavedDocument(from: finalResult)
        XCTAssertEqual(storage.documents.first?.content, "Versi terbaru")
        XCTAssertEqual(makeStorage().documents.first?.content, "Versi terbaru")
    }

    func testFailedSaveKeepsDraftAndRetryPersistsLatestVersion() async throws {
        let storage = makeStorage()
        let sourceURL = try writeExternalFile(
            named: "failed-save.txt",
            data: Data("Versi awal".utf8)
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let imported = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        var edited = imported
        edited.content = "Draft yang belum tersimpan"

        try FileManager.default.removeItem(at: storageDirectory)
        try Data("bukan folder".utf8).write(to: storageDirectory)
        _ = storage.updateDraft(edited)

        guard case .failure(.writeFailed) = await storage.flushPendingSave(for: imported.id) else {
            return XCTFail("Write ke path yang bukan folder harus gagal.")
        }
        XCTAssertEqual(storage.documents.first?.content, "Draft yang belum tersimpan")
        guard case .failed = storage.saveState(for: edited) else {
            return XCTFail("Kegagalan write harus terlihat sebagai Gagal menyimpan.")
        }

        try FileManager.default.removeItem(at: storageDirectory)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        storage.retrySave(for: imported.id)
        try await Task.sleep(nanoseconds: 25_000_000)
        _ = await storage.flushPendingSave(for: imported.id)

        XCTAssertEqual(makeStorage().documents.first?.content, "Draft yang belum tersimpan")
        guard case .saved = storage.saveState(for: edited) else {
            return XCTFail("Retry setelah storage pulih harus berhasil.")
        }
    }

    func testDeleteRemovesAMTCopyButLeavesExternalOriginalUntouched() async throws {
        let storage = makeStorage()
        let sourceURL = try writeExternalFile(
            named: "external-original.txt",
            data: Data("File asli eksternal".utf8)
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        let preservedSourceURL = storage.importedSourceURL(for: document)
        XCTAssertNotNil(preservedSourceURL)

        guard case .success = await storage.deleteDocument(document) else {
            return XCTFail("Delete dokumen yang valid harus berhasil.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        if let preservedSourceURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: preservedSourceURL.path))
        }
        XCTAssertTrue(storage.documents.isEmpty)
        XCTAssertTrue(try jsonFiles().isEmpty)
    }

    func testDeleteFailureLeavesDocumentAndAMTCopyAvailable() async throws {
        let fileManager = FailingMoveFileManager()
        let storage = makeStorage(fileManager: fileManager)
        let sourceURL = try writeExternalFile(
            named: "rollback-original.txt",
            data: Data("File untuk rollback".utf8)
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try requireImportedDocument(
            from: await storage.importDocument(at: sourceURL)
        )
        let preservedSourceURL = try XCTUnwrap(storage.importedSourceURL(for: document))

        guard case .failure(.deleteFailed) = await storage.deleteDocument(document) else {
            return XCTFail("Kegagalan staging harus dilaporkan.")
        }
        XCTAssertEqual(storage.documents.count, 1)
        XCTAssertTrue(try jsonFiles().contains { $0.lastPathComponent == "\(document.id.uuidString).json" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedSourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testInvalidSourceReferenceCannotEscapeAMTStorageDirectory() async throws {
        let documentID = UUID()
        let document = DashboardDocument(
            id: documentID,
            title: "Unsafe",
            content: "Isi",
            importedSourceFileName: "../outside.txt"
        )
        try JSONEncoder().encode(document).write(
            to: storageDirectory.appendingPathComponent("\(documentID.uuidString).json")
        )

        let storage = makeStorage()
        XCTAssertNil(storage.importedSourceURL(for: document))
        guard case .failure(.invalidSourceReference) = await storage.deleteDocument(document) else {
            return XCTFail("Nama sumber yang keluar dari storage harus ditolak.")
        }
        XCTAssertEqual(storage.documents.first?.id, documentID)
    }

    private func makeStorage(
        fileManager: FileManager = .default,
        persistenceDelayNanoseconds: UInt64 = 0
    ) -> DocumentStorageManager {
        DocumentStorageManager(
            fileManager: fileManager,
            storageDirectoryURL: storageDirectory,
            persistenceDelayNanoseconds: persistenceDelayNanoseconds
        )
    }

    @discardableResult
    private func writeFile(named name: String, data: Data) throws -> URL {
        let url = storageDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @discardableResult
    private func writeExternalFile(named name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AMT-DocumentStorageExternal-\(UUID().uuidString)-\(name)")
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

    private func requireSavedDocument(
        from result: Result<DashboardDocument, DocumentStorageError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DashboardDocument {
        switch result {
        case let .success(document):
            return document
        case let .failure(error):
            XCTFail("Penyimpanan gagal: \(error.localizedDescription)", file: file, line: line)
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

private final class FailingMoveFileManager: FileManager {
    private var moveCount = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moveCount += 1
        if moveCount == 2 {
            throw NSError(
                domain: "AMTTests.FailingMoveFileManager",
                code: 1,
                userInfo: nil
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
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
