//
//  DocumentEditorView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/25.
//

import SwiftUI

struct DocumentEditorView: View {
    @Binding var document: AMTDocument

    @State private var selectedSidebarItem: SidebarItem? = .dictionary
    @State private var documentTitle = "Untitled"

    var body: some View {
        NavigationSplitView {
            EditorSidebar(selection: $selectedSidebarItem)
        } detail: {
            VStack(spacing: 0) {
                if selectedSidebarItem == .suggestion || selectedSidebarItem == nil {
                    EditorToolbar(documentTitle: $documentTitle)
                    Divider()
                }

                switch selectedSidebarItem {
                case .dictionary:
                    DictionaryView()
                case .suggestion, .none:
                    TextEditor(text: $document.text)
                        .font(.body)
                        .scrollContentBackground(.visible)
                }
            }
        }
    }
}

#Preview {
    DocumentEditorView(document: .constant(AMTDocument()))
}
