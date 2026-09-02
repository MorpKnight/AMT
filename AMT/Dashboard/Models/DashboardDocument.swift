//
//  DashboardDocument.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import Foundation

struct DashboardDocument: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var content: String
    /// The editable AppKit rich-text payload for imported or formatted documents.
    /// `content` remains plain text for search and AI review.
    var richTextData: Data?
    /// File name of the untouched imported document kept in AMT's private storage.
    /// It lets the document preview use macOS's native renderer instead of the
    /// lossy Word-to-RTF conversion used by the editable surface.
    var importedSourceFileName: String?
    /// Versioned WYSIWYG payload. This is the canonical presentation model.
    var structuredDocument: StructuredDocument?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        content: String = "",
        richTextData: Data? = nil,
        importedSourceFileName: String? = nil,
        structuredDocument: StructuredDocument? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.richTextData = richTextData
        self.importedSourceFileName = importedSourceFileName
        self.structuredDocument = structuredDocument
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedRelativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            return "Hari ini"
        } else if calendar.isDateInYesterday(updatedAt) {
            return "Kemarin"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: updatedAt)
        }
    }
}
