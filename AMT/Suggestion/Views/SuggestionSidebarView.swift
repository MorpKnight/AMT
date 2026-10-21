//
//  SuggestionSidebarView.swift
//  AMT
//
//  Created by Antigravity on 2026/10/19.
//

import SwiftUI

struct SuggestionSidebarView: View {
    let items: [EditorReviewItem]
    let selectedItemID: UUID?
    let isAnalyzing: Bool
    let onSelect: (UUID) -> Void
    let onAcceptSuggestion: (EditorSuggestion) -> Void
    let onAcceptAnnotation: (EditorReviewAnnotation) -> Void
    let onDismiss: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            HStack(alignment: .center) {
                Text("Sugestis Perbaikan")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                } else if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Scrollable List of Suggestion Cards
            if items.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in
                                SuggestionCardView(
                                    item: item,
                                    isSelected: item.id == selectedItemID,
                                    onSelect: {
                                        onSelect(item.id)
                                    },
                                    onAccept: {
                                        switch item {
                                        case let .suggestion(suggestion):
                                            onAcceptSuggestion(suggestion)
                                        case let .annotation(annotation):
                                            onAcceptAnnotation(annotation)
                                        }
                                    },
                                    onDismiss: {
                                        onDismiss(item.id)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: selectedItemID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            if isAnalyzing {
                ProgressView()
                    .controlSize(.regular)
                Text("Memeriksa dokumen…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.green.opacity(0.8))
                Text("Tidak ada saran perbaikan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Semua temuan sudah diperiksa atau dokumen telah sesuai acuan.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SuggestionCardView: View {
    let item: EditorReviewItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: headerIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(headerIconColor)

                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if isSelected || isActionableReview {
                    Circle()
                        .fill(Color(red: 0.28, green: 0.48, blue: 0.96))
                        .frame(width: 8, height: 8)
                }
            }

            // Preview / Snippet
            snippetView

            // Reason / Explanation
            if !reasonText.isEmpty {
                Text(reasonText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action Buttons (Terima / Abaikan)
            HStack(spacing: 14) {
                Button(action: onAccept) {
                    Text("Terima")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Abaikan")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.blue.opacity(0.75)
                        : (isHovered ? Color.primary.opacity(0.12) : Color.black.opacity(0.07)),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .shadow(
            color: isSelected
                ? Color.blue.opacity(0.12)
                : Color.black.opacity(0.03),
            radius: isSelected ? 4 : 2,
            x: 0,
            y: 1
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var headerIconName: String {
        switch item {
        case let .suggestion(s):
            switch s.category {
            case .spelling:
                return "text.badge.checkmark"
            case .grammar:
                return "bubble.left.and.exclamationmark.bubble.right"
            case .terminology:
                return "text.book.closed"
            case .clarity:
                return "sparkles"
            case .none:
                return "bubble.left.and.exclamationmark.bubble.right"
            }
        case let .annotation(a):
            switch a.kind {
            case .legalRisk:
                return "exclamationmark.shield"
            case .definition, .definedTerm:
                return "text.book.closed"
            case .needsReview:
                return "bubble.left.and.text.bubble.right"
            }
        }
    }

    private var headerIconColor: Color {
        if isSelected {
            return Color.blue
        }
        switch item {
        case .suggestion:
            return Color.textSecondary
        case let .annotation(a):
            switch a.definitionDiagnosticStatus {
            case .mismatch:
                return Color.red.opacity(0.85)
            case .needsReview, .none:
                return Color.orange.opacity(0.85)
            case .matches:
                return Color.green.opacity(0.85)
            }
        }
    }

    private var headerTitle: String {
        switch item {
        case let .suggestion(s):
            switch s.category {
            case .spelling:
                return "Perbaikan Ejaan"
            case .grammar:
                return "Perbaikan Tata Bahasa"
            case .terminology:
                return "Terminologi Hukum"
            case .clarity:
                return "Kejelasan Kalimat"
            case .none:
                return s.kind.title
            }
        case let .annotation(a):
            if let title = a.title, !title.isEmpty {
                return title
            }
            switch a.kind {
            case .legalRisk, .needsReview:
                return "Analisis Peraturan"
            case .definition:
                return "Pemeriksaan Definisi"
            case .definedTerm:
                return "Istilah Terdefinisi"
            }
        }
    }

    private var isActionableReview: Bool {
        switch item {
        case .suggestion:
            return false
        case let .annotation(a):
            return a.definitionDiagnosticStatus == .mismatch || a.kind == .legalRisk || a.kind == .needsReview
        }
    }

    @ViewBuilder
    private var snippetView: some View {
        switch item {
        case let .suggestion(s):
            suggestionSnippet(for: s)
        case let .annotation(a):
            annotationSnippet(for: a)
        }
    }

    private func suggestionSnippet(for suggestion: EditorSuggestion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let prefix = suggestion.prefixContext, !prefix.isEmpty {
                Text(prefix)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            Text(suggestion.original)
                .font(.system(size: 12, weight: .bold))
                .strikethrough(true, color: Color.primary.opacity(0.6))
                .foregroundStyle(Color.textPrimary)

            Text(suggestion.replacement)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.65, blue: 0.28))

            if let suffix = suggestion.suffixContext, !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .lineLimit(3)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func annotationSnippet(for annotation: EditorReviewAnnotation) -> some View {
        Text(annotation.original)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color(red: 0.72, green: 0.15, blue: 0.15))
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.opacity(0.05))
            )
    }

    private var reasonText: String {
        let raw: String
        switch item {
        case let .suggestion(s):
            raw = s.reason
        case let .annotation(a):
            raw = a.reason
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("*") {
            return trimmed
        }
        return "*\(trimmed)"
    }
}
