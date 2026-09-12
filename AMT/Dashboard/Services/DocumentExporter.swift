//
//  DocumentExporter.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum DocumentExportError: LocalizedError, Equatable, Sendable {
    case cancelled
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Ekspor dibatalkan."
        case .encodingFailed:
            "Isi dokumen tidak dapat disiapkan sebagai file Word."
        case .writeFailed:
            "Hasil ekspor tidak dapat ditulis ke lokasi yang dipilih."
        }
    }
}

@MainActor
final class DocumentExporter {
    static func exportAsDocx(
        title: String,
        document: StructuredDocument,
        completion: @escaping (Result<URL, DocumentExportError>) -> Void = { _ in }
    ) {
        exportAsDocx(
            title: title,
            attributedString: document.attributedString(),
            completion: completion
        )
    }

    static func exportOriginalDocument(
        sourceURL: URL,
        completion: @escaping (Result<URL, DocumentExportError>) -> Void = { _ in }
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Ekspor Dokumen Asli"
        savePanel.prompt = "Ekspor"
        savePanel.nameFieldStringValue = sourceURL.lastPathComponent

        if let type = UTType(filenameExtension: sourceURL.pathExtension) {
            savePanel.allowedContentTypes = [type]
        }

        savePanel.begin { response in
            guard response == .OK, let saveURL = savePanel.url else {
                completion(.failure(.cancelled))
                return
            }

            do {
                try FileManager.default.copyItem(at: sourceURL, to: saveURL)
                completion(.success(saveURL))
            } catch {
                completion(.failure(.writeFailed))
            }
        }
    }

    static func exportAsDocx(
        title: String,
        content: String,
        completion: @escaping (Result<URL, DocumentExportError>) -> Void = { _ in }
    ) {
        exportAsDocx(
            title: title,
            attributedString: NSAttributedString(string: content),
            completion: completion
        )
    }

    private static func exportAsDocx(
        title: String,
        attributedString: NSAttributedString,
        completion: @escaping (Result<URL, DocumentExportError>) -> Void
    ) {
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
            guard response == .OK, let saveURL = savePanel.url else {
                completion(.failure(.cancelled))
                return
            }

            let docxData: Data
            do {
                docxData = try attributedString.data(
                    from: NSRange(location: 0, length: attributedString.length),
                    documentAttributes: [
                        .documentType: NSAttributedString.DocumentType.officeOpenXML
                    ]
                )
            } catch {
                completion(.failure(.encodingFailed))
                return
            }

            do {
                try docxData.write(to: saveURL, options: .atomic)
                completion(.success(saveURL))
            } catch {
                completion(.failure(.writeFailed))
            }
        }
    }
}
