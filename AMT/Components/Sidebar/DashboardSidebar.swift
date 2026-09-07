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

    private var logoImageName: String {
        colorScheme == .dark ? "logo_white" : "logo_black"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Branding
            HStack(spacing: 8) {
                Image(logoImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text("Lawtionary")
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Sidebar Navigation List
            List(selection: $selectedTab) {
                ForEach(DashboardTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            Text(tab.rawValue)
                                .appFont(.subheadline, weight: .medium)
                                .foregroundStyle(selectedTab == tab ? Color.textTertiary : Color.textPrimary)
                                .background(selectedTab == tab ? Color.textTertiary : Color.black)

                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(selectedTab == tab ? Color.textTertiary : Color.textPrimary)
                        }
                    }
                    .tag(tab)
                }
            }
            .padding(10)
            .cornerRadius(8)
        }
        .frame(minWidth: 220, idealWidth: 270, maxWidth: 270)
        
    }
}

#Preview {
    DashboardSidebar(selectedTab: .constant(.document))
}
