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
    
    private let fileManager = FileManager.default
    private let folderName = "AMT_Documents"

    func importedSourceURL(for document: DashboardDocument) -> URL? {
        guard let fileName = document.importedSourceFileName else { return nil }
        let url = storageURL.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private var storageURL: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let folderURL = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return folderURL
    }

    init() {
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
            self.documents = loadedDocs
        } catch {
            print("Error loading documents via Foundation FileManager: \(error.localizedDescription)")
            self.documents = []
        }
    }

    // MARK: - Import Document from Finder (.docx, .doc, .rtf, .md, .txt)

    func importWordDocumentFromFinder(completion: @escaping (DashboardDocument?) -> Void) {
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
                completion(nil)
                return
            }

            let title = url.deletingPathExtension().lastPathComponent
            var textContent = ""
            var richTextData: Data?
            var structuredDocument: StructuredDocument?
            let documentID = UUID()
            let sourceFileName = "\(documentID.uuidString).\(url.pathExtension.lowercased())"

            do {
                let ext = url.pathExtension.lowercased()
                if ["docx", "doc", "rtf", "html", "htm"].contains(ext) {
                    let attributedText = try DocxToMarkdownConverter.loadAttributedString(fileURL: url)
                    let payload = DocumentRenderNormalizer.fromNative(attributedText)
                    textContent = payload.plainText
                    richTextData = payload.richTextData ?? (try? DocxToMarkdownConverter.rtfData(from: attributedText))
                    structuredDocument = payload.structuredDocument
                } else if ["md", "markdown"].contains(ext) {
                    let markdown = try DocxToMarkdownConverter.convert(fileURL: url)
                    let payload = DocumentRenderNormalizer.fromMarkdown(markdown)
                    textContent = payload.plainText
                    richTextData = payload.richTextData
                    structuredDocument = payload.structuredDocument
                } else if ext == "txt" || ext.isEmpty {
                    let plainText = try String(contentsOf: url, encoding: .utf8)
                    let payload = DocumentRenderNormalizer.fromPlainText(plainText)
                    textContent = payload.plainText
                    richTextData = payload.richTextData
                    structuredDocument = payload.structuredDocument
                } else {
                    let text = try DocxToMarkdownConverter.convert(fileURL: url)
                    let payload = DocumentRenderNormalizer.fromPlainText(text)
                    textContent = payload.plainText
                    richTextData = payload.richTextData
                    structuredDocument = payload.structuredDocument
                }
            } catch {
                print("Error converting document to Markdown: \(error.localizedDescription)")
                if let rawString = try? String(contentsOf: url, encoding: .utf8) {
                    textContent = rawString
                    let payload = DocumentRenderNormalizer.fromPlainText(rawString)
                    richTextData = payload.richTextData
                    structuredDocument = payload.structuredDocument
                }
            }

            do {
                try self.fileManager.copyItem(
                    at: url,
                    to: self.storageURL.appendingPathComponent(sourceFileName)
                )
            } catch {
                print("Failed to preserve original imported document: \(error.localizedDescription)")
            }

            let sourceWasPreserved = self.fileManager.fileExists(
                atPath: self.storageURL.appendingPathComponent(sourceFileName).path
            )
            let newDoc = DashboardDocument(
                id: documentID,
                title: title.isEmpty ? "Untitled" : title,
                content: textContent,
                richTextData: richTextData,
                importedSourceFileName: sourceWasPreserved ? sourceFileName : nil,
                structuredDocument: structuredDocument,
                createdAt: Date(),
                updatedAt: Date()
            )

            self.saveDocument(newDoc)
            self.documents.insert(newDoc, at: 0)
            completion(newDoc)
        }
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

        saveDocument(newDoc)
        documents.insert(newDoc, at: 0)
        return newDoc
    }

    func saveDocument(_ document: DashboardDocument) {
        var updatedDoc = document
        updatedDoc.updatedAt = Date()

        // Built-in documents: do not persist to disk, but update the in-memory array safely
        if AIConnectorDummyDocument.isBuiltIn(updatedDoc) {
            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                let replacement = updatedDoc
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.documents[index] = replacement
                }
            }
            return
        }

        // Persist to disk
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(updatedDoc)
            let fileURL = storageURL.appendingPathComponent("\(updatedDoc.id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)

            // Safely publish changes after IO completes
            if let index = documents.firstIndex(where: { $0.id == updatedDoc.id }) {
                let replacement = updatedDoc
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.documents[index] = replacement
                    self.documents.sort { $0.updatedAt > $1.updatedAt }
                }
            }
        } catch {
            print("Failed to save document to Foundation storage: \(error.localizedDescription)")
        }
    }

    func deleteDocument(_ document: DashboardDocument) {
        guard !AIConnectorDummyDocument.isBuiltIn(document) else { return }

        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
        if let sourceURL = importedSourceURL(for: document) {
            try? fileManager.removeItem(at: sourceURL)
        }
        DispatchQueue.main.async { [weak self] in
            self?.documents.removeAll { $0.id == document.id }
        }
    }
}
