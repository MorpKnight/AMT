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
    
    private static let folderName = "AMT_Documents"
    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.storageURL = storageDirectory ?? Self.defaultStorageURL(fileManager: fileManager)
        try? fileManager.createDirectory(
            at: self.storageURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        loadDocuments()
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
                if let data = try? Data(contentsOf: fileURL),
                   let document = try? decoder.decode(DashboardDocument.self, from: data),
                   !AIConnectorDummyDocument.isBuiltIn(document) {
                    loadedDocs.append(document)
                }
            }

            // Sort by latest updated first
            loadedDocs.sort { $0.updatedAt > $1.updatedAt }
            loadedDocs.insert(contentsOf: AIConnectorDummyDocument.builtInDocuments, at: 0)
            self.documents = loadedDocs
        } catch {
            print("Error loading documents via Foundation FileManager: \(error.localizedDescription)")
            self.documents = AIConnectorDummyDocument.builtInDocuments
        }
    }

    // MARK: - Import Document from Finder (.docx)

    func importWordDocumentFromFinder(completion: @escaping (DashboardDocument?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Impor Dokumen"
        panel.message = "Pilih file dokumen Word (.docx)"
        panel.allowedContentTypes = UTType(filenameExtension: "docx").map { [$0] } ?? []

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }

            do {
                let newDoc = try self.importWordDocument(from: url)
                completion(newDoc)
            } catch {
                print("Error importing DOCX: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    /// Imports a DOCX, stores an immutable working copy, and persists only a safe relative path.
    @discardableResult
    func importWordDocument(from sourceURL: URL) throws -> DashboardDocument {
        guard sourceURL.pathExtension.lowercased() == "docx" else {
            throw DocumentStorageError.unsupportedFileType
        }

        let documentID = UUID()
        let sidecarFilename = "\(documentID.uuidString).original.docx"
        let sidecarURL = storageURL.appendingPathComponent(sidecarFilename)
        try fileManager.copyItem(at: sourceURL, to: sidecarURL)

        do {
            let extraction = try DocxToMarkdownConverter.extract(fileURL: sidecarURL)
            let fingerprint = try DocumentFingerprint.sha256(fileURL: sidecarURL)
            let sourceTitle = sourceURL.deletingPathExtension().lastPathComponent
            let document = DashboardDocument(
                id: documentID,
                title: sourceTitle.isEmpty ? "Untitled" : sourceTitle,
                content: extraction.analysisText,
                createdAt: Date(),
                updatedAt: Date(),
                originalFileName: sourceURL.lastPathComponent,
                originalSidecarRelativePath: "\(Self.folderName)/\(sidecarFilename)",
                originalFingerprint: fingerprint,
                reviewSnapshot: nil
            )

            let savedDocument = saveDocument(document)
            documents.insert(savedDocument, at: 0)
            return savedDocument
        } catch {
            try? fileManager.removeItem(at: sidecarURL)
            throw error
        }
    }

    /// Resolves a stored original only inside the app-owned document directory.
    func originalFileURL(for document: DashboardDocument) -> URL? {
        guard let relativePath = document.originalSidecarRelativePath,
              let filename = Self.safeSidecarFilename(from: relativePath)
        else {
            return nil
        }

        let sidecarURL = storageURL.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: sidecarURL.path) ? sidecarURL : nil
    }

    @discardableResult
    func createNewDocument(title: String = "Untitled", content: String = "") -> DashboardDocument {
        var newDoc = DashboardDocument(
            id: UUID(),
            title: title,
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        if title == "Untitled" {
            let untitledCount = documents.filter { $0.title.hasPrefix("Untitled") }.count
            if untitledCount > 0 {
                newDoc.title = "Untitled \(untitledCount + 1)"
            }
        }

        let savedDocument = saveDocument(newDoc)
        documents.insert(savedDocument, at: 0)
        return savedDocument
    }

    @discardableResult
    func saveDocument(_ document: DashboardDocument) -> DashboardDocument {
        var updatedDoc = document
        updatedDoc.updatedAt = Date()

        if AIConnectorDummyDocument.isBuiltIn(updatedDoc) {
            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                documents[index] = updatedDoc
            }
            return updatedDoc
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(updatedDoc)
            let fileURL = storageURL.appendingPathComponent("\(updatedDoc.id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)

            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                documents[index] = updatedDoc
                documents.sort { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            print("Failed to save document to Foundation storage: \(error.localizedDescription)")
        }

        return updatedDoc
    }

    func deleteDocument(_ document: DashboardDocument) {
        guard !AIConnectorDummyDocument.isBuiltIn(document) else { return }

        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        if let sidecarURL = originalFileURL(for: document) {
            try? fileManager.removeItem(at: sidecarURL)
        }
        try? fileManager.removeItem(at: fileURL)
        documents.removeAll { $0.id == document.id }
    }

    // MARK: - Private Helpers

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func safeSidecarFilename(from relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        let filename: String

        switch components.count {
        case 1:
            filename = components[0]
        case 2 where components[0] == folderName:
            filename = components[1]
        default:
            return nil
        }

        guard filename.hasSuffix(".original.docx"),
              !filename.contains(".."),
              !filename.contains("\\")
        else {
            return nil
        }
        return filename
    }
}

enum DocumentStorageError: LocalizedError, Equatable {
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "AMT hanya dapat mengimpor dokumen DOCX pada tahap ini."
        }
    }
}
