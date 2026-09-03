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
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onCreateNewDocument) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Impor Dokumen Word")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            // List of Existing Documents
            List(selection: $selectedDocumentID) {
                Section("Dokumen Saya") {
                    ForEach(documents) { doc in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                                .foregroundStyle(selectedDocumentID == doc.id ? Color.accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title)
                                    .font(.system(size: 13, weight: selectedDocumentID == doc.id ? .semibold : .regular))
                                    .lineLimit(1)

                                Text(doc.formattedRelativeDate)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(doc.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
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
