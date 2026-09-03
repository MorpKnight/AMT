//
//  CustomTitleBar.swift
//  AMT
//
//  Created by Antigravity on 2026/08/30.
//

import SwiftUI

struct CustomTitleBar: View {
    @State private var searchText: String = ""
    let title: String
    @Binding var isSidebarVisible: Bool

    var body: some View {
        HStack {
            Text("Document")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 180)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 32)
        .frame(height: 64)
        .background(Color(nsColor: .windowBackgroundColor))

    }
}

#Preview {
    CustomTitleBar(title: "Lawtionary", isSidebarVisible: .constant(true))
}
