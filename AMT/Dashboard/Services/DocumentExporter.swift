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
    static func exportAsDocx(title: String, content: String) {
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

            let attributedString = NSAttributedString(string: content)
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
