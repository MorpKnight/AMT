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

                        // Definition Cards (Numbered: 1, 2, ...)
                        ForEach(entry.definitions) { def in
                            definitionCard(def: def)
                        }

                        // "Lihat Juga" Section
                        if !entry.seeAlso.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Lihat Juga")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(sectionHeaderColor)

                                // Chips Flow / Row
                                HStack(spacing: 10) {
                                    ForEach(entry.seeAlso, id: \.self) { term in
                                        SeeAlsoChip(term: term) {
                                            viewModel.lookupTerm(term)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
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

    // MARK: - Definition Card View
    @ViewBuilder
    private func definitionCard(def: DefinitionItem) -> some View {
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
