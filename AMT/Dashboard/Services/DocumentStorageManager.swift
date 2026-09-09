//
//  DocumentStorageManager.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum DocumentSaveState: Equatable {
    case dirty
    case saving
    case saved(Date)
    case failed(String)

    var title: String {
        switch self {
        case .dirty:
            "Belum tersimpan"
        case .saving:
            "Menyimpan…"
        case .saved:
            "Tersimpan lokal"
        case .failed:
            "Gagal menyimpan"
        }
    }

    var systemImage: String {
        switch self {
        case .dirty:
            "circle"
        case .saving:
            "arrow.triangle.2.circlepath"
        case .saved:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum DocumentStorageError: LocalizedError, Equatable, Sendable {
    case cancelled
    case documentNotFound
    case builtInDocument
    case directoryUnavailable
    case encodingFailed
    case readFailed
    case writeFailed
    case deleteFailed
    case invalidSourceReference
    case analysisSnapshotMismatch

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Penyimpanan dibatalkan."
        case .documentNotFound:
            "Dokumen tidak lagi tersedia di workspace."
        case .builtInDocument:
            "Dokumen bawaan tidak dapat dihapus."
        case .directoryUnavailable:
            "Folder penyimpanan lokal AMT tidak dapat diakses."
        case .encodingFailed:
            "Data dokumen tidak dapat disiapkan untuk disimpan."
        case .readFailed:
            "Data dokumen tidak dapat dibaca dari penyimpanan lokal."
        case .writeFailed:
            "Dokumen tidak dapat disimpan ke penyimpanan lokal."
        case .deleteFailed:
            "Dokumen tidak dapat dihapus secara utuh. Draft dan salinan lokal tetap dipertahankan."
        case .invalidSourceReference:
            "Referensi file sumber tidak valid untuk penyimpanan lokal AMT."
        case .analysisSnapshotMismatch:
            "Hasil analisis tidak lagi cocok dengan isi dokumen saat ini."
        }
    }
}

/// Performs JSON encoding and file-system mutations away from the main actor.
private actor DocumentPersistenceActor {
    private let fileManager: FileManager
    private let storageURL: URL
    private let writeDelayNanoseconds: UInt64

    init(
        fileManager: FileManager,
        storageURL: URL,
        writeDelayNanoseconds: UInt64 = 0
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL
        self.writeDelayNanoseconds = writeDelayNanoseconds
    }

    func persist(_ document: DashboardDocument) async throws {
        if writeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: writeDelayNanoseconds)
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            data = try encoder.encode(document)
        } catch {
            throw DocumentStorageError.encodingFailed
        }

        do {
            try data.write(
                to: jsonURL(for: document.id),
                options: .atomic
            )
        } catch {
            throw DocumentStorageError.writeFailed
        }
    }

    /// Moves AMT-owned files into a private staging directory before removing
    /// that directory. If any step fails, all moved files are restored.
    func delete(documentID: UUID, sourceFileName: String?) throws {
        guard sourceFileName.map(isSafeSourceFileName) ?? true else {
            throw DocumentStorageError.invalidSourceReference
        }

        let stagingURL = storageURL.appendingPathComponent(
            ".deleting-\(UUID().uuidString)",
            isDirectory: true
        )
        let jsonSource = jsonURL(for: documentID)
        let sourceURL = sourceFileName.map {
            storageURL.appendingPathComponent($0, isDirectory: false)
        }
        var movedFiles: [(original: URL, staged: URL)] = []

        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false,
                attributes: nil
            )

            if fileManager.fileExists(atPath: jsonSource.path) {
                let stagedJSON = stagingURL.appendingPathComponent("document.json")
                try fileManager.moveItem(at: jsonSource, to: stagedJSON)
                movedFiles.append((jsonSource, stagedJSON))
            }

            if let sourceURL,
               fileManager.fileExists(atPath: sourceURL.path) {
                let stagedSource = stagingURL.appendingPathComponent("source")
                try fileManager.moveItem(at: sourceURL, to: stagedSource)
                movedFiles.append((sourceURL, stagedSource))
            }

            try fileManager.removeItem(at: stagingURL)
        } catch {
            for move in movedFiles.reversed() {
                guard fileManager.fileExists(atPath: move.staged.path) else { continue }
                do {
                    try fileManager.moveItem(at: move.staged, to: move.original)
                } catch {
                    // The original error remains the actionable one. The
                    // document stays in memory and is never removed below.
                }
            }

            if fileManager.fileExists(atPath: stagingURL.path) {
                do {
                    try fileManager.removeItem(at: stagingURL)
                } catch {
                    // A leftover private staging directory is safer than
                    // deleting a document whose rollback could not complete.
                }
            }
            throw DocumentStorageError.deleteFailed
        }
    }

    private func jsonURL(for documentID: UUID) -> URL {
        storageURL.appendingPathComponent(
            "\(documentID.uuidString).json",
            isDirectory: false
        )
    }

    private func isSafeSourceFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\\") else {
            return false
        }
        return URL(fileURLWithPath: fileName).lastPathComponent == fileName
    }
}

@MainActor
final class DocumentStorageManager: ObservableObject {
    @Published private(set) var documents: [DashboardDocument] = []
    @Published private(set) var saveStates: [UUID: DocumentSaveState] = [:]

    private let fileManager: FileManager
    private let storageURL: URL
    private let persistenceActor: DocumentPersistenceActor
    private let debounceNanoseconds: UInt64 = 750_000_000

    private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingDrafts: [UUID: DashboardDocument] = [:]
    private var revisions: [UUID: UInt64] = [:]

    init(
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil,
        persistenceDelayNanoseconds: UInt64 = 0
    ) {
        self.fileManager = fileManager
        self.storageURL = Self.resolveStorageURL(
            fileManager: fileManager,
            requestedURL: storageDirectoryURL,
            folderName: "AMT_Documents"
        )
        self.persistenceActor = DocumentPersistenceActor(
            fileManager: fileManager,
            storageURL: self.storageURL,
            writeDelayNanoseconds: persistenceDelayNanoseconds
        )
        loadDocuments()
    }

    func saveState(for document: DashboardDocument) -> DocumentSaveState {
        saveStates[document.id] ?? .saved(document.updatedAt)
    }

    func importedSourceURL(for document: DashboardDocument) -> URL? {
        guard let fileName = document.importedSourceFileName,
              let url = validatedSourceURL(for: fileName),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    // MARK: - Loading

    func loadDocuments() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: storageURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "json" }

            var loadedDocs: [DashboardDocument] = []
            let decoder = JSONDecoder()

            for fileURL in fileURLs {
                let document: DashboardDocument
                do {
                    let data = try Data(contentsOf: fileURL)
                    document = try decoder.decode(DashboardDocument.self, from: data)
                } catch {
                    continue
                }

                guard !AIConnectorDummyDocument.isBuiltIn(document) else { continue }

                var normalizedDocument = document
                if normalizedDocument.fingerprint == nil {
                    normalizedDocument.fingerprint = DocumentFingerprinting.forStoredContent(
                        normalizedDocument.content
                    )
                }

                if let snapshot = normalizedDocument.analysisSnapshot,
                   snapshot.analyzedContentSHA256
                    != DocumentFingerprinting.contentSHA256(normalizedDocument.content) {
                    normalizedDocument.analysisSnapshot = nil
                }
                loadedDocs.append(normalizedDocument)
            }

            loadedDocs.sort { $0.updatedAt > $1.updatedAt }
            documents = loadedDocs
            saveStates = Dictionary(
                uniqueKeysWithValues: loadedDocs.map {
                    ($0.id, DocumentSaveState.saved($0.updatedAt))
                }
            )
        } catch {
            documents = []
            saveStates = [:]
        }
    }

    // MARK: - Import Document from Finder (.docx, .doc, .rtf, .md, .txt)

    func importWordDocumentFromFinder(completion: @escaping (DocumentImportResult) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Impor Dokumen"
        panel.message = "Pilih file dokumen (.docx, .doc, .rtf, .md, .txt)"

        var types: [UTType] = [.plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        panel.allowedContentTypes = types

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion(.cancelled)
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    completion(.failed("Workspace AMT sudah tidak tersedia."))
                    return
                }
                completion(await self.importDocument(at: url))
            }
        }
    }

    /// Imports a supported document without presenting Finder. This is the
    /// testable boundary used by the UI panel callback.
    func importDocument(at url: URL) async -> DocumentImportResult {
        let payload: DocumentRenderPayload
        let fileExtension = url.pathExtension.lowercased()

        do {
            switch fileExtension {
            case "docx", "doc", "rtf", "html", "htm":
                let native = try DocxToMarkdownConverter.loadAttributedString(fileURL: url)
                payload = DocumentRenderNormalizer.fromNative(native)
            case "md", "markdown":
                let markdown = try String(contentsOf: url, encoding: .utf8)
                payload = DocumentRenderNormalizer.fromMarkdown(markdown)
            case "txt", "":
                let plainText = try String(contentsOf: url, encoding: .utf8)
                payload = DocumentRenderNormalizer.fromPlainText(plainText)
            default:
                let converted = try DocxToMarkdownConverter.convert(fileURL: url)
                payload = DocumentRenderNormalizer.fromPlainText(converted)
            }
        } catch {
            guard let fallbackContent = try? String(contentsOf: url, encoding: .utf8) else {
                return .failed("Dokumen tidak dapat dibaca: \(error.localizedDescription)")
            }
            payload = DocumentRenderNormalizer.fromPlainText(fallbackContent)
        }

        let textContent = payload.plainText
        guard !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("Dokumen tidak memiliki isi yang dapat diimpor.")
        }

        let fingerprint: DocumentFingerprint
        do {
            fingerprint = try DocumentFingerprinting.make(
                fileURL: url,
                convertedContent: textContent
            )
        } catch {
            return .failed("Fingerprint dokumen tidak dapat dibuat: \(error.localizedDescription)")
        }

        if let duplicate = duplicateMatch(for: fingerprint) {
            return .duplicate(existing: duplicate.document, matchKind: duplicate.matchKind)
        }

        let title = url.deletingPathExtension().lastPathComponent
        let documentID = UUID()
        let sourceFileName = fileExtension.isEmpty
            ? documentID.uuidString
            : "\(documentID.uuidString).\(fileExtension)"
        let sourceURL = storageURL.appendingPathComponent(sourceFileName, isDirectory: false)
        let preservedSourceFileName: String?

        do {
            try fileManager.copyItem(at: url, to: sourceURL)
            preservedSourceFileName = sourceFileName
        } catch {
            preservedSourceFileName = nil
        }

        let now = Date()
        let newDocument = DashboardDocument(
            id: documentID,
            title: title.isEmpty ? "Untitled" : title,
            content: textContent,
            richTextData: payload.richTextData,
            importedSourceFileName: preservedSourceFileName,
            structuredDocument: payload.structuredDocument,
            createdAt: now,
            updatedAt: now,
            fingerprint: fingerprint
        )

        do {
            try await persistenceActor.persist(newDocument)
        } catch let error as DocumentStorageError {
            if fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.removeItem(at: sourceURL)
                } catch {
                    // The JSON record was not published, so a remaining source
                    // copy is harmless and is never treated as a document.
                }
            }
            return .failed(error.localizedDescription)
        } catch {
            if fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.removeItem(at: sourceURL)
                } catch {
                    // The JSON record was not published, so a remaining source
                    // copy is harmless and is never treated as a document.
                }
            }
            return .failed("Dokumen tidak dapat disimpan ke workspace lokal.")
        }

        documents.insert(newDocument, at: 0)
        saveStates[newDocument.id] = .saved(newDocument.updatedAt)
        return .imported(newDocument)
    }

    // MARK: - Draft and Analysis Persistence

    /// Updates the main-actor draft immediately and schedules a debounced save.
    @discardableResult
    func updateDraft(_ document: DashboardDocument) -> DashboardDocument {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else {
            return document
        }

        if AIConnectorDummyDocument.isBuiltIn(document) {
            documents[index] = document
            saveStates[document.id] = .saved(document.updatedAt)
            return document
        }

        if documents[index] == document {
            return documents[index]
        }

        var updatedDocument = document
        updatedDocument.updatedAt = Date()
        updatedDocument.fingerprint = DocumentFingerprinting.refreshingContent(
            updatedDocument.fingerprint,
            content: updatedDocument.content
        )

        if let snapshot = updatedDocument.analysisSnapshot,
           snapshot.analyzedContentSHA256
            != updatedDocument.fingerprint?.normalizedContentSHA256 {
            updatedDocument.analysisSnapshot = nil
        }

        documents[index] = updatedDocument
        pendingDrafts[updatedDocument.id] = updatedDocument
        revisions[updatedDocument.id, default: 0] &+= 1
        saveStates[updatedDocument.id] = .dirty
        scheduleSave(for: updatedDocument.id)
        return updatedDocument
    }

    /// Flushes the newest in-memory revision without waiting for the debounce.
    @discardableResult
    func flushPendingSave(
        for documentID: UUID
    ) async -> Result<DashboardDocument, DocumentStorageError> {
        pendingSaveTasks[documentID]?.cancel()
        pendingSaveTasks[documentID] = nil
        return await persistLatestDraft(for: documentID)
    }

    /// Retries the latest failed draft immediately.
    func retrySave(for documentID: UUID) {
        pendingSaveTasks[documentID]?.cancel()
        pendingSaveTasks[documentID] = Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingSaveTasks[documentID] = nil
            _ = await self.persistLatestDraft(for: documentID)
        }
    }

    func flushAllPendingSaves() async {
        let documentIDs = Array(pendingDrafts.keys)
        for documentID in documentIDs {
            _ = await flushPendingSave(for: documentID)
        }
    }

    /// Persists a completed analysis without changing the document timestamp.
    @discardableResult
    func saveAnalysisSnapshot(
        _ snapshot: DocumentAnalysisSnapshot,
        for document: DashboardDocument
    ) async -> Result<DashboardDocument, DocumentStorageError> {
        guard !AIConnectorDummyDocument.isBuiltIn(document),
              let index = documents.firstIndex(where: { $0.id == document.id }) else {
            return .failure(.documentNotFound)
        }

        var updatedDocument = pendingDrafts[document.id] ?? documents[index]
        guard snapshot.analyzedContentSHA256
            == DocumentFingerprinting.contentSHA256(updatedDocument.content) else {
            return .failure(.analysisSnapshotMismatch)
        }

        updatedDocument.analysisSnapshot = snapshot
        updatedDocument.fingerprint = DocumentFingerprinting.refreshingContent(
            updatedDocument.fingerprint,
            content: updatedDocument.content
        )
        documents[index] = updatedDocument
        pendingDrafts[updatedDocument.id] = updatedDocument
        revisions[updatedDocument.id, default: 0] &+= 1
        saveStates[updatedDocument.id] = .dirty
        return await flushPendingSave(for: updatedDocument.id)
    }

    /// Deletes only AMT's JSON record and preserved source copy. Staging in the
    /// persistence actor guarantees that an incomplete delete is rolled back.
    @discardableResult
    func deleteDocument(
        _ document: DashboardDocument
    ) async -> Result<Void, DocumentStorageError> {
        guard !AIConnectorDummyDocument.isBuiltIn(document) else {
            return .failure(.builtInDocument)
        }
        guard documents.contains(where: { $0.id == document.id }) else {
            return .failure(.documentNotFound)
        }
        if let sourceFileName = document.importedSourceFileName,
           validatedSourceURL(for: sourceFileName) == nil {
            return .failure(.invalidSourceReference)
        }

        if pendingDrafts[document.id] != nil {
            switch await flushPendingSave(for: document.id) {
            case .success:
                break
            case let .failure(error):
                return .failure(error)
            }
        }

        do {
            try await persistenceActor.delete(
                documentID: document.id,
                sourceFileName: document.importedSourceFileName
            )
        } catch let error as DocumentStorageError {
            return .failure(error)
        } catch {
            return .failure(.deleteFailed)
        }

        pendingSaveTasks[document.id]?.cancel()
        pendingSaveTasks[document.id] = nil
        pendingDrafts[document.id] = nil
        revisions[document.id] = nil
        saveStates[document.id] = nil
        documents.removeAll { $0.id == document.id }
        return .success(())
    }

    // MARK: - Private Persistence Helpers

    private func scheduleSave(for documentID: UUID) {
        pendingSaveTasks[documentID]?.cancel()
        pendingSaveTasks[documentID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 0)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingSaveTasks[documentID] = nil
            _ = await self.persistLatestDraft(for: documentID)
        }
    }

    private func persistLatestDraft(
        for documentID: UUID
    ) async -> Result<DashboardDocument, DocumentStorageError> {
        while true {
            guard let document = pendingDrafts[documentID]
                    ?? documents.first(where: { $0.id == documentID }) else {
                return .failure(.documentNotFound)
            }
            guard !AIConnectorDummyDocument.isBuiltIn(document) else {
                return .success(document)
            }

            let revision = revisions[documentID, default: 0]
            saveStates[documentID] = .saving

            do {
                try Task.checkCancellation()
                try await persistenceActor.persist(document)
                try Task.checkCancellation()
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch let error as DocumentStorageError {
                guard revisions[documentID, default: 0] == revision else { continue }
                saveStates[documentID] = .failed(error.localizedDescription)
                return .failure(error)
            } catch {
                guard revisions[documentID, default: 0] == revision else { continue }
                saveStates[documentID] = .failed(DocumentStorageError.writeFailed.localizedDescription)
                return .failure(.writeFailed)
            }

            guard revisions[documentID, default: 0] == revision else { continue }
            pendingDrafts[documentID] = nil
            saveStates[documentID] = .saved(document.updatedAt)
            return .success(document)
        }
    }

    private func validatedSourceURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\\"),
              URL(fileURLWithPath: fileName).lastPathComponent == fileName else {
            return nil
        }

        let root = storageURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root
            .appendingPathComponent(fileName)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    private func duplicateMatch(
        for fingerprint: DocumentFingerprint
    ) -> (document: DashboardDocument, matchKind: DocumentDuplicateMatchKind)? {
        let orderedDocuments = documents.sorted(by: canonicalDocumentOrder)

        if let sourceFileSHA256 = fingerprint.sourceFileSHA256,
           let existing = orderedDocuments.first(where: { document in
               effectiveFingerprint(for: document).sourceFileSHA256 == sourceFileSHA256
           }) {
            return (existing, .sourceFile)
        }

        if let existing = orderedDocuments.first(where: { document in
            effectiveFingerprint(for: document).normalizedContentSHA256
                == fingerprint.normalizedContentSHA256
        }) {
            return (existing, .normalizedContent)
        }

        return nil
    }

    private func effectiveFingerprint(for document: DashboardDocument) -> DocumentFingerprint {
        document.fingerprint ?? DocumentFingerprinting.forStoredContent(document.content)
    }

    private func canonicalDocumentOrder(
        _ lhs: DashboardDocument,
        _ rhs: DashboardDocument
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func resolveStorageURL(
        fileManager: FileManager,
        requestedURL: URL?,
        folderName: String
    ) -> URL {
        let folderURL: URL
        if let requestedURL {
            folderURL = requestedURL
        } else if let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            folderURL = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        } else {
            folderURL = fileManager.temporaryDirectory.appendingPathComponent(
                folderName,
                isDirectory: true
            )
        }

        if !fileManager.fileExists(atPath: folderURL.path) {
            do {
                try fileManager.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                // The persistence actor will return a typed error on the next
                // write; no in-memory draft is discarded here.
            }
        }
        return folderURL.standardizedFileURL
    }
}
