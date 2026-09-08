//
//  DashboardSidebar.swift
//  AMT
//
//  Created by Antigravity on 2026/08/26.
//

import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case document = "Document"
    case dictionary = "Dictionary"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .document: return "doc.text"
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
        VStack(alignment: .leading, spacing: 14) {
            // Header Branding
            HStack(spacing: 8) {
                Image(logoImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                Text("Lawtionary")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)

            // Section Label
            Text("Header")
                .appFont(.caption, weight: .medium)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)

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
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 260)
        .sheet(isPresented: $showingTermsSheet) {
            termsSheetView
        }
        .sheet(isPresented: $showingAboutSheet) {
            aboutSheetView
        }
        
        Spacer()
        
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
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .appFont(.subheadline, weight: isSelected ? .semibold : .medium)

                Spacer()
            }
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, 12)
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
    DashboardSidebar(selectedTab: .constant(.document))
}
