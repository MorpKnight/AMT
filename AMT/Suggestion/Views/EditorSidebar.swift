//
//  EditorSidebar.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dictionary = "Dictionary"
    case suggestion = "Suggestion"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dictionary: return "book"
        case .suggestion: return "lightbulb"
        }
    }
}

struct EditorSidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Tools") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    EditorSidebar(selection: .constant(.dictionary))
        .frame(width: 200)
}
