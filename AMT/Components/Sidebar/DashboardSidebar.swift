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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Branding
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Lawtionary")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Sidebar Navigation List
            List(selection: $selectedTab) {
                ForEach(DashboardTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
    }
}

#Preview {
    DashboardSidebar(selectedTab: .constant(.document))
}
