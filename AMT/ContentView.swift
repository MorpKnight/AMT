//
//  ContentView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

struct ContentView: View {
    let suggestionService: QwenSuggestionService
    let dictionaryStore: LegalDictionaryStore

    var body: some View {
        DashboardView(
            suggestionService: suggestionService,
            dictionaryStore: dictionaryStore
        )
    }
}

#Preview {
    ContentView(
        suggestionService: QwenSuggestionService(),
        dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries)
    )
}
