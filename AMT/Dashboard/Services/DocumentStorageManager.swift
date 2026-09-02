//
//  DocumentStorageManager.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentStorageManager: ObservableObject {
    @Published var documents: [DashboardDocument] = []

    private let fileManager: FileManager
    private let storageDirectoryURL: URL?
    private let folderName = "AMT_Documents"

    init(
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.storageDirectoryURL = storageDirectoryURL
        loadDocuments()
    }

    private var storageURL: URL {
        let folderURL: URL
        if let storageDirectoryURL {
            folderURL = storageDirectoryURL
        } else if let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            folderURL = documentsDirectory.appendingPathComponent(
                folderName,
                isDirectory: true
            )
        } else {
            folderURL = fileManager.temporaryDirectory.appendingPathComponent(
                folderName,
                isDirectory: true
            )
        }

        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }

        return folderURL
    }

    // MARK: - Foundation Persistence Operations

    func loadDocuments() {
        do {
            let directoryURL = storageURL
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "json" }

            var loadedDocs: [DashboardDocument] = []
            let decoder = JSONDecoder()

            for fileURL in fileURLs {
                guard let data = try? Data(contentsOf: fileURL),
                      var document = try? decoder.decode(DashboardDocument.self, from: data),
                      !AIConnectorDummyDocument.isBuiltIn(document)
                else {
                    continue
                }

                // Older JSON files do not have a fingerprint. Compute a
                // fallback in memory so they participate in duplicate checks;
                // the value is persisted the next time that document is saved.
                if document.fingerprint == nil {
                    document.fingerprint = DocumentFingerprinting.forStoredContent(
                        document.content
                    )
                }

                if let snapshot = document.analysisSnapshot,
                   snapshot.analyzedContentSHA256
                    != DocumentFingerprinting.contentSHA256(document.content) {
                    document.analysisSnapshot = nil
                }
                loadedDocs.append(document)
            }

            // Sort by latest updated first
            loadedDocs.sort { $0.updatedAt > $1.updatedAt }
            self.documents = loadedDocs
        } catch {
            print("Error loading documents via Foundation FileManager: \(error.localizedDescription)")
            self.documents = []
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

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(.cancelled)
                return
            }

            completion(self.importDocument(at: url))
        }
    }

    /// Imports a supported document without presenting Finder. This is the
    /// testable boundary used by the UI panel callback.
    func importDocument(at url: URL) -> DocumentImportResult {
        let textContent: String
        do {
            textContent = try DocxToMarkdownConverter.convert(fileURL: url)
        } catch {
            guard let fallbackContent = try? String(contentsOf: url, encoding: .utf8) else {
                return .failed("Dokumen tidak dapat dibaca: \(error.localizedDescription)")
            }
            textContent = fallbackContent
        }

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
            return .duplicate(
                existing: duplicate.document,
                matchKind: duplicate.matchKind
            )
        }

        let title = url.deletingPathExtension().lastPathComponent
        let newDocument = DashboardDocument(
            title: title.isEmpty ? "Untitled" : title,
            content: textContent,
            createdAt: Date(),
            updatedAt: Date(),
            fingerprint: fingerprint
        )

        do {
            try persist(newDocument)
        } catch {
            return .failed("Dokumen tidak dapat disimpan: \(error.localizedDescription)")
        }

        documents.insert(newDocument, at: 0)
        return .imported(newDocument)
    }

    @discardableResult
    func createNewDocument(title: String = "Untitled", content: String = "") -> DashboardDocument {
        var newDocument = DashboardDocument(
            id: UUID(),
            title: title,
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            fingerprint: DocumentFingerprinting.forStoredContent(content)
        )

        if title == "Untitled" {
            let untitledCount = documents.filter { $0.title.hasPrefix("Untitled") }.count
            if untitledCount > 0 {
                newDocument.title = "Untitled \(untitledCount + 1)"
            }
        }

        do {
            try persist(newDocument)
            documents.insert(newDocument, at: 0)
        } catch {
            print("Failed to create document in Foundation storage: \(error.localizedDescription)")
        }
        return newDocument
    }

    @discardableResult
    func saveDocument(_ document: DashboardDocument) -> DashboardDocument? {
        var updatedDoc = document
        updatedDoc.updatedAt = Date()

        if AIConnectorDummyDocument.isBuiltIn(updatedDoc) {
            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                documents[index] = updatedDoc
            }
            return updatedDoc
        }

        updatedDoc.fingerprint = DocumentFingerprinting.refreshingContent(
            updatedDoc.fingerprint,
            content: updatedDoc.content
        )
        if let snapshot = updatedDoc.analysisSnapshot,
           snapshot.analyzedContentSHA256
            != updatedDoc.fingerprint?.normalizedContentSHA256 {
            updatedDoc.analysisSnapshot = nil
        }

        do {
            try persist(updatedDoc)

            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                documents[index] = updatedDoc
                documents.sort { $0.updatedAt > $1.updatedAt }
            }
            return updatedDoc
        } catch {
            print("Failed to save document to Foundation storage: \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists the completed analysis without changing the document's edit
    /// timestamp. The content hash guard prevents stale results from being
    /// attached to a different document version.
    @discardableResult
    func saveAnalysisSnapshot(
        _ snapshot: DocumentAnalysisSnapshot,
        for document: DashboardDocument
    ) -> DashboardDocument? {
        guard !AIConnectorDummyDocument.isBuiltIn(document),
              snapshot.analyzedContentSHA256
                == DocumentFingerprinting.contentSHA256(document.content),
              let index = documents.firstIndex(where: { $0.id == document.id }) else {
            return nil
        }

        var updatedDoc = document
        updatedDoc.analysisSnapshot = snapshot
        updatedDoc.fingerprint = DocumentFingerprinting.refreshingContent(
            updatedDoc.fingerprint,
            content: updatedDoc.content
        )

        do {
            try persist(updatedDoc)
            documents[index] = updatedDoc
            return updatedDoc
        } catch {
            print("Failed to save analysis snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteDocument(_ document: DashboardDocument) {
        guard !AIConnectorDummyDocument.isBuiltIn(document) else { return }

        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
        documents.removeAll { $0.id == document.id }
    }

    private func persist(_ document: DashboardDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(document)
        let fileURL = storageURL.appendingPathComponent(
            "\(document.id.uuidString).json"
        )
        try data.write(to: fileURL, options: .atomic)
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
}
