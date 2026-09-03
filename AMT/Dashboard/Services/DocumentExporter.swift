//
//  DocumentExporter.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentExporter {
    static func exportAsDocx(title: String, document: StructuredDocument) {
        exportAsDocx(title: title, attributedString: document.attributedString())
    }

    static func exportOriginalDocument(sourceURL: URL) {
        let savePanel = NSSavePanel()
        savePanel.title = "Ekspor Dokumen Asli"
        savePanel.prompt = "Ekspor"
        savePanel.nameFieldStringValue = sourceURL.lastPathComponent

        if let type = UTType(filenameExtension: sourceURL.pathExtension) {
            savePanel.allowedContentTypes = [type]
        }

        savePanel.begin { response in
            guard response == .OK, let saveURL = savePanel.url else { return }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: saveURL)
            } catch {
                print("Failed to export original document: \(error.localizedDescription)")
            }
        }
    }

    static func exportAsDocx(title: String, content: String) {
        exportAsDocx(title: title, attributedString: NSAttributedString(string: content))
    }

    private static func exportAsDocx(title: String, attributedString: NSAttributedString) {
        let savePanel = NSSavePanel()
        savePanel.title = "Ekspor Dokumen ke Word (.docx)"
        savePanel.prompt = "Ekspor"
        
        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = sanitizedTitle.isEmpty ? "Dokumen.docx" : "\(sanitizedTitle).docx"
        savePanel.nameFieldStringValue = filename

        if let docxType = UTType(filenameExtension: "docx") {
            savePanel.allowedContentTypes = [docxType]
        }

        savePanel.begin { response in
            guard response == .OK, let saveURL = savePanel.url else { return }

            do {
                let docxData = try attributedString.data(
                    from: NSRange(location: 0, length: attributedString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
                )
                try docxData.write(to: saveURL, options: .atomic)
                print("Document successfully exported as .docx to \(saveURL.path)")
            } catch {
                print("Failed to export document to .docx: \(error.localizedDescription)")
            }
        }
    }
}
