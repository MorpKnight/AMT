//
//  EditorSidebar.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import SwiftUI

struct EditorSidebar: View {
    let documents: [DashboardDocument]
    @Binding var selectedDocumentID: UUID?
    let onBackToDashboard: () -> Void
    let onCreateNewDocument: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar Header (Back Button & New Document Button)
            HStack {
                Button(action: onBackToDashboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Dashboard")
                    }
                    .appFont(.callout, weight: .medium)
                    .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onCreateNewDocument) {
                    Image(systemName: "square.and.pencil")
                        .appFont(size: 14, weight: .medium)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Impor Dokumen Word")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()
                .overlay(Color.borderSubtle)

            // List of Existing Documents
            List(selection: $selectedDocumentID) {
                Section {
                    ForEach(documents) { doc in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title)
                                    .appFont(.callout, weight: selectedDocumentID == doc.id ? .semibold : .regular)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(doc.id)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 270, maxWidth: 270)
    }
}

#Preview {
    EditorSidebar(
        documents: [
            DashboardDocument(title: "Dokumen 1", content: "Isi dokumen 1"),
            DashboardDocument(title: "Dokumen 2", content: "Isi dokumen 2"),
                DashboardDocument(title: "Dokumen 1", content: "Isi dokumen 1"),
                DashboardDocument(title: "Dokumen 2", content: "Isi dokumen 2"),
                DashboardDocument(title: "Dokumen 1", content: "Isi dokumen 1"),
                DashboardDocument(title: "Dokumen 2", content: "Isi dokumen 2"),
        ],
        selectedDocumentID: .constant(nil),
        onBackToDashboard: {},
        onCreateNewDocument: {}
    )
}
