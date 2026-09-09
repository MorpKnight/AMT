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
    let onImportDocument: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar Header (Back Button & Import Document Button)
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

                Button(action: onImportDocument) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Impor Dokumen Word")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()
                .overlay(Color.borderSubtle)

            // List of Existing Documents
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(documents) { doc in
                        EditorSidebarItem(
                            document: doc,
                            isSelected: selectedDocumentID == doc.id,
                            action: {
                                selectedDocumentID = doc.id
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct EditorSidebarItem: View {
    let document: DashboardDocument
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)

                Text(document.title)
                    .appFont(.callout, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.bgSelected : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
        onImportDocument: {}
    )
}
