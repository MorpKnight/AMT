//
//  DashboardSidebar.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case document = "Dokumen"
    case dictionary = "Kamus"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .document: return "doc"
        case .dictionary: return "book"
        }
    }
}

struct DashboardSidebar: View {
    @Binding var selectedTab: DashboardTab?
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingTermsSheet = false
    @State private var showingAboutSheet = false

    private var logoImageName: String {
        colorScheme == .dark ? "logo_white" : "logo_black"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Branding
            HStack(spacing: 8) {
                Image(logoImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)

                Text("Lawtionary")
                    .appFont(.callout, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Sidebar Navigation List
            VStack(spacing: 4) {
                ForEach(DashboardTab.allCases) { tab in
                    SidebarTabItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: {
                            selectedTab = tab
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            Spacer()

            // Footer Links
            VStack(alignment: .leading, spacing: 10) {
                SidebarFooterLink(title: "Term and Condition") {
                    showingTermsSheet = true
                }

                SidebarFooterLink(title: "About Lawtionary") {
                    showingAboutSheet = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingTermsSheet) {
            termsSheetView
        }
        .sheet(isPresented: $showingAboutSheet) {
            aboutSheetView
        }
    }

    private var termsSheetView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Terms and Conditions")
                    .font(.headline)
                Spacer()
                Button("Tutup") {
                    showingTermsSheet = false
                }
            }
            Divider()
            ScrollView {
                Text("Lawtionary adalah alat bantu penelaahan dokumen hukum dan glosarium hukum. Seluruh rekomendasi dan glosarium disediakan sebagai referensi pendukung dan tidak menggantikan nasihat hukum profesional.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 180)
        }
        .padding(20)
        .frame(width: 440)
    }

    private var aboutSheetView: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button("Tutup") {
                    showingAboutSheet = false
                }
            }
            Image(logoImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            Text("Lawtionary")
                .font(.title2.weight(.bold))
            Text("Aplikasi Penelaahan Dokumen & Glosarium Hukum Terpadu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct SidebarTabItem: View {
    let tab: DashboardTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)

                Text(tab.rawValue)
                    .appFont(.callout, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)

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

private struct SidebarFooterLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.caption, weight: .regular)
                .foregroundStyle(isHovered ? Color.textPrimary : Color.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    DashboardSidebar(selectedTab: .constant(.document))
}
