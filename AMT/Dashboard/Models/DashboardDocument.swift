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
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
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
