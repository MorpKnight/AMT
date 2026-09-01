//
//  DocumentExporter.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum DocumentExportError: LocalizedError, Equatable {
    case sourceMissing
    case sourceChanged
    case noAcceptedChanges
    case invalidSourceRange
    case overlappingChanges
    case destinationIsOriginal

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "Salinan DOCX asli tidak ditemukan."
        case .sourceChanged:
            "Salinan DOCX berubah sejak impor."
        case .noAcceptedChanges:
            "Belum ada perubahan yang diterima untuk diekspor."
        case .invalidSourceRange:
            "Salah satu perubahan tidak memiliki rentang sumber yang aman."
        case .overlappingChanges:
            "Perubahan yang diterima saling bertumpuk."
        case .destinationIsOriginal:
            "File asli tidak boleh ditimpa. Pilih nama file ekspor baru."
        }
    }
}

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

    /// Presents a save panel and exports only accepted review items to a new DOCX.
    static func exportReviewedAsDocx(
        title: String,
        originalURL: URL,
        expectedFingerprint: String,
        acceptedItems: [DocumentReviewItem],
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Ekspor Dokumen Review ke Word (.docx)"
        savePanel.prompt = "Ekspor Review"
        let sanitizedTitle = safeFilenameComponent(title)
        savePanel.nameFieldStringValue = "\(sanitizedTitle) - Reviewed.docx"

        if let docxType = UTType(filenameExtension: "docx") {
            savePanel.allowedContentTypes = [docxType]
        }

        savePanel.begin { response in
            guard response == .OK, let saveURL = savePanel.url else { return }

            guard saveURL.standardizedFileURL != originalURL.standardizedFileURL else {
                completion?(.failure(DocumentExportError.destinationIsOriginal))
                return
            }

            do {
                let data = try makeReviewedDocxData(
                    originalURL: originalURL,
                    expectedFingerprint: expectedFingerprint,
                    acceptedItems: acceptedItems
                )
                try data.write(to: saveURL, options: .atomic)
                completion?(.success(saveURL))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    /// Builds a formatted DOCX without presenting UI, which also keeps export testable.
    static func makeReviewedDocxData(
        originalURL: URL,
        expectedFingerprint: String,
        acceptedItems: [DocumentReviewItem],
        fileManager: FileManager = .default
    ) throws -> Data {
        guard fileManager.fileExists(atPath: originalURL.path) else {
            throw DocumentExportError.sourceMissing
        }

        guard try DocumentFingerprint.sha256(fileURL: originalURL) == expectedFingerprint else {
            throw DocumentExportError.sourceChanged
        }

        guard !acceptedItems.isEmpty else {
            throw DocumentExportError.noAcceptedChanges
        }

        let original = try DocxToMarkdownConverter.loadAttributedString(fileURL: originalURL)
        let sortedItems = acceptedItems.sorted {
            ($0.sourceRange?.location ?? 0) < ($1.sourceRange?.location ?? 0)
        }

        guard sortedItems.allSatisfy({ $0.decision == .accepted }) else {
            throw DocumentExportError.noAcceptedChanges
        }

        for item in sortedItems {
            guard item.isActionable,
                  let sourceRange = item.sourceRange,
                  sourceRange.isValid(inUTF16Length: original.length),
                  sourceRange.length > 0,
                  (original.string as NSString).substring(with: sourceRange.nsRange) == item.original
            else {
                throw DocumentExportError.invalidSourceRange
            }
        }

        for pair in zip(sortedItems, sortedItems.dropFirst()) {
            guard let left = pair.0.sourceRange?.nsRange,
                  let right = pair.1.sourceRange?.nsRange
            else {
                throw DocumentExportError.invalidSourceRange
            }
            if NSIntersectionRange(left, right).length > 0 {
                throw DocumentExportError.overlappingChanges
            }
        }

        let mutable = NSMutableAttributedString(attributedString: original)
        for item in sortedItems.reversed() {
            guard let range = item.sourceRange?.nsRange else {
                throw DocumentExportError.invalidSourceRange
            }

            let attributes = original.attributes(at: range.location, effectiveRange: nil)
            let replacement = NSAttributedString(
                string: item.replacement,
                attributes: attributes
            )
            mutable.replaceCharacters(in: range, with: replacement)
        }

        return try mutable.data(
            from: NSRange(location: 0, length: mutable.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
        )
    }

    private static func safeFilenameComponent(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(
            of: "/",
            with: "-"
        )
        return sanitized.isEmpty ? "Dokumen" : sanitized
    }
}
