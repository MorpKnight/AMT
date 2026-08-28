//
//  DocumentCardView.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import SwiftUI

struct DocumentCardView: View {
    let document: DashboardDocument
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Card Preview Thumbnail
            Button(action: onSelect) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(isHovered ? 0.07 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                }
                .frame(width: 110, height: 110)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .contextMenu {
                Button(action: onSelect) {
                    Label("Buka Dokumen", systemImage: "doc.text.fill")
                }
                Button(action: {
                    DocumentExporter.exportAsDocx(title: document.title, content: document.content)
                }) {
                    Label("Ekspor ke Word (.docx)", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Hapus Dokumen", systemImage: "trash")
                }
            }

            // Title & Subtitle Info below card
            VStack(spacing: 2) {
                Text(document.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    AIConnectorDummyDocument.isBuiltIn(document)
                        ? "Built-in · reset saat dibuka"
                        : document.formattedRelativeDate
                )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110)
        }
    }
}

#Preview {
    DocumentCardView(
        document: DashboardDocument(title: "Untitled", content: "Sample text content"),
        onSelect: {},
        onDelete: {}
    )
    .padding()
}
