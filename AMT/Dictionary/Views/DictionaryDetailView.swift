//
//  DictionaryDetailView.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import SwiftUI

struct DictionaryDetailView: View {
    @Bindable var viewModel: DictionaryViewModel
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Adaptive Theme Colors
    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.14, blue: 0.21)
            : Color(red: 0.93, green: 0.957, blue: 0.992)
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.25, blue: 0.35)
            : Color(red: 0.85, green: 0.89, blue: 0.96)
    }

    private var bannerColor: Color {
        Color(red: 0.05, green: 0.26, blue: 0.65)
    }

    private var definitionTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.88, green: 0.92, blue: 0.98)
            : Color(red: 0.08, green: 0.18, blue: 0.42)
    }

    private var innerBoxBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.09, blue: 0.14)
            : Color.white
    }

    private var innerBoxBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    private var sectionHeaderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.85)
            : Color(red: 0.22, green: 0.25, blue: 0.32)
    }

    private var lawTitleColor: Color {
        colorScheme == .dark
            ? Color.white
            : Color(red: 0.12, green: 0.15, blue: 0.22)
    }

    private var metadataLabelColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.6)
            : Color(red: 0.35, green: 0.38, blue: 0.44)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Back Navigation Bar
            HStack {
                Button(action: {
                    viewModel.backToHome()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Dictionary")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 12)

            // MARK: - Scrollable Content Area (Full Responsive Width)
            if let entry = viewModel.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Term Title Heading
                        Text(entry.term)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.top, 4)

                        // Top 5 RAG Matches Bar
                        if !viewModel.topMatches.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(viewModel.topMatches.prefix(5).enumerated()), id: \.offset) { index, match in
                                            Button(action: {
                                                viewModel.selectMatch(match)
                                            }) {
                                                HStack(spacing: 6) {
                                                    Text("#\(index + 1)")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(viewModel.selectedEntry?.term == match.term ? Color.white : Color.accentColor)
                                                    Text(match.term)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(viewModel.selectedEntry?.term == match.term ? Color.white : Color.primary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(viewModel.selectedEntry?.term == match.term ? Color.accentColor : Color.primary.opacity(0.06))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }



                        // Definition Cards (Numbered: 1, 2, ...)
                        ForEach(entry.definitions) { def in
                            definitionCard(def: def, entry: entry)
                        }

                        // "Lihat Juga" Section
                        if !entry.seeAlso.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Lihat Juga")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(sectionHeaderColor)

                                // Chips Flow / Row
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(entry.seeAlso, id: \.self) { term in
                                            SeeAlsoChip(term: term) {
                                                viewModel.lookupTerm(term)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 16)
                        }

                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func definitionCard(
        def: DefinitionItem,
        entry: LegalGlossaryEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Blue Ribbon with Number Badge
            HStack(spacing: 8) {
                // Circle Number Badge
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)

                    Text("\(def.id)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(bannerColor)
                }

                Text("Definisi")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bannerColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Definition Text
            Text(def.text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(definitionTextColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .fixedSize(horizontal: false, vertical: true)

            definitionHistory(for: def, in: entry)

            if !def.sources.isEmpty || !def.sourceURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sumber kamus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sectionHeaderColor)

                    if !def.sources.isEmpty {
                        Label(
                            def.sources.joined(separator: " • "),
                            systemImage: "books.vertical"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    ForEach(def.sourceURLs, id: \.self) { sourceURL in
                        Link(destination: sourceURL) {
                            Label("Buka halaman sumber", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Inner "Referensi Hukum" Card
            if let ref = def.reference {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Referensi Hukum")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(sectionHeaderColor)

                    Divider()
                        .padding(.vertical, 2)

                    Text(ref.lawName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(lawTitleColor)

                    if let lawTitle = ref.lawTitle {
                        Text(lawTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if let institution = ref.institution {
                        Text(institution)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Enacted & Effective Metadata Line
                    HStack(spacing: 6) {
                        if let enacted = ref.dateEnacted {
                            HStack(spacing: 4) {
                                Text("Ditetapkan")
                                    .fontWeight(.bold)
                                    .foregroundStyle(metadataLabelColor)
                                Text(enacted)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if ref.dateEnacted != nil && ref.dateEffective != nil {
                            Text("•")
                                .foregroundStyle(.secondary)
                        }

                        if let effective = ref.dateEffective {
                            HStack(spacing: 4) {
                                Text("Berlaku")
                                    .fontWeight(.bold)
                                    .foregroundStyle(metadataLabelColor)
                                    Text(effective)
                                        .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.system(size: 11))
                    .padding(.top, 2)

                    if let articleLocator = ref.articleLocator {
                        Label("Pasal \(articleLocator)", systemImage: "text.book.closed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let pageStart = ref.pageStart {
                        let pageText = ref.pageEnd.map { "Halaman \(pageStart)–\($0)" }
                            ?? "Halaman \(pageStart)"
                        Label(pageText, systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let sourceURL = ref.sourceURL {
                        Link(destination: sourceURL) {
                            Label("Buka sumber", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .padding(.top, 2)
                    }

                    if let officialDocumentURL = ref.officialDocumentURL,
                       officialDocumentURL != ref.sourceURL {
                        Link(destination: officialDocumentURL) {
                            Label("Buka dokumen resmi", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(innerBoxBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(innerBoxBorder, lineWidth: 1)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func definitionHistory(
        for definition: DefinitionItem,
        in entry: LegalGlossaryEntry
    ) -> some View {
        let events = historyEvents(for: definition, in: entry)
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Riwayat & status sumber")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(sectionHeaderColor)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events.indices, id: \.self) { index in
                        definitionHistoryRow(
                            events[index],
                            isLast: index == events.count - 1
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    private func historyEvents(
        for definition: DefinitionItem,
        in entry: LegalGlossaryEntry
    ) -> [DefinitionHistoryEvent] {
        let references = definition.allReferences
        let referenceIDs = Set(references.compactMap(\.referenceID))
        let relations = entry.regulationRelations.filter { relation in
            referenceIDs.contains(relation.sourceReferenceID)
                || referenceIDs.contains(relation.targetReferenceID)
        }

        var events: [DefinitionHistoryEvent] = []

        for (index, reference) in references.enumerated() {
            let hasKnownStatus = referenceStatus(for: reference) != nil
            let hasRelation = relations.contains {
                $0.sourceReferenceID == reference.referenceID
                    || $0.targetReferenceID == reference.referenceID
            }
            guard hasKnownStatus || hasRelation || references.count > 1 else {
                continue
            }

            events.append(
                DefinitionHistoryEvent(
                    id: "reference-\(index)-\(reference.referenceID ?? reference.lawName)",
                    label: referenceStatus(for: reference) ?? "Sumber definisi",
                    sourceName: reference.lawName,
                    metadata: referenceMetadata(for: reference),
                    explanation: nil,
                    isInactive: isInactive(reference)
                )
            )
        }

        for relation in relations {
            let isSource = referenceIDs.contains(relation.sourceReferenceID)
            let isTarget = referenceIDs.contains(relation.targetReferenceID)
            let relatedReferenceID: String
            let rawRelationType: String

            if isSource {
                relatedReferenceID = relation.targetReferenceID
                rawRelationType = relation.relationType
            } else if isTarget {
                relatedReferenceID = relation.sourceReferenceID
                rawRelationType = relation.inverseRelationType
            } else {
                continue
            }

            let relatedRegulation = viewModel.regulation(for: relatedReferenceID)
            events.append(
                DefinitionHistoryEvent(
                    id: "relation-\(relation.relationID)",
                    label: relationTitle(for: rawRelationType),
                    sourceName: regulationName(relatedRegulation),
                    metadata: regulationMetadata(for: relatedRegulation),
                    explanation: nonEmpty(relation.evidenceText),
                    isInactive: false
                )
            )
        }

        return events
    }

    private func definitionHistoryRow(
        _ event: DefinitionHistoryEvent,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 0) {
                Circle()
                    .fill(event.isInactive ? Color.secondary.opacity(0.35) : Color.accentColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.isInactive ? .secondary : .primary)

                Text(event.sourceName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(event.isInactive ? .secondary : lawTitleColor)

                if let metadata = event.metadata {
                    Text(metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let explanation = event.explanation {
                    Text(explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func referenceStatus(for reference: LegalReference) -> String? {
        if let officialStatus = nonEmpty(reference.officialStatus) {
            return officialStatus
        }
        return reference.applicabilityStatus == .unknown
            ? nil
            : reference.applicabilityStatus.displayTitle
    }

    private func isInactive(_ reference: LegalReference) -> Bool {
        if reference.applicabilityStatus == .notInForce {
            return true
        }
        guard let status = nonEmpty(reference.officialStatus)?.lowercased() else {
            return false
        }
        return status.contains("tidak berlaku") || status.contains("dicabut")
    }

    private func referenceMetadata(for reference: LegalReference) -> String? {
        var parts: [String] = []

        if let number = nonEmpty(reference.number), let year = reference.year {
            parts.append("Nomor \(number) Tahun \(year)")
        } else if let number = nonEmpty(reference.number) {
            parts.append("Nomor \(number)")
        } else if let year = reference.year {
            parts.append("Tahun \(year)")
        }

        if let articleLocator = nonEmpty(reference.articleLocator) {
            parts.append("Pasal \(articleLocator)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func regulationMetadata(for regulation: LegalRegulation?) -> String? {
        guard let regulation else { return nil }

        if let number = nonEmpty(regulation.number), let year = regulation.year {
            return "Nomor \(number) Tahun \(year)"
        }
        if let number = nonEmpty(regulation.number) {
            return "Nomor \(number)"
        }
        if let year = regulation.year {
            return "Tahun \(year)"
        }
        return nil
    }

    private func regulationName(_ regulation: LegalRegulation?) -> String {
        guard let regulation else { return "Sumber hukum terkait" }
        return nonEmpty(regulation.referenceName)
            ?? nonEmpty(regulation.officialTitle)
            ?? "Sumber hukum terkait"
    }

    private func relationTitle(for rawValue: String) -> String {
        switch rawValue {
        case "amends":
            return "Mengubah"
        case "amended_by":
            return "Diubah oleh"
        case "repeals":
            return "Mencabut"
        case "repealed_by":
            return "Dicabut oleh"
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

private struct DefinitionHistoryEvent {
    let id: String
    let label: String
    let sourceName: String
    let metadata: String?
    let explanation: String?
    let isInactive: Bool
}

// MARK: - "Lihat Juga" Chip Component

private struct SeeAlsoChip: View {
    let term: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(term)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    DictionaryDetailView(
        viewModel: {
            let vm = DictionaryViewModel()
            vm.selectedEntry = PopularTerm.sampleGlossaryEntries["jaksa"]
            vm.isShowingDetail = true
            return vm
        }()
    )
}
