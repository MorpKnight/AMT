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
                   let document = try? decoder.decode(DashboardDocument.self, from: data) {
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

    // MARK: - Import Word Document from Finder

    func importWordDocumentFromFinder(completion: @escaping (DashboardDocument?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Impor Dokumen"
        panel.message = "Pilih file Word (.docx, .doc, .rtf, .txt)"

        var types: [UTType] = [.plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        panel.allowedContentTypes = types

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }

            let title = url.deletingPathExtension().lastPathComponent
            var textContent = ""

            if let attributedString = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                textContent = attributedString.string
            } else if let rawString = try? String(contentsOf: url, encoding: .utf8) {
                textContent = rawString
            }

            let newDoc = DashboardDocument(
                id: UUID(),
                title: title.isEmpty ? "Untitled" : title,
                content: textContent,
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
    }

    func deleteDocument(_ document: DashboardDocument) {
        let fileURL = storageURL.appendingPathComponent("\(document.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
        documents.removeAll { $0.id == document.id }
    }
}
