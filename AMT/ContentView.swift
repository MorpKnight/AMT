//
//  ContentView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: AMTDocument

    var body: some View {
        DocumentEditorView(document: $document)
    }
}

#Preview {
    ContentView(document: .constant(AMTDocument()))
}
