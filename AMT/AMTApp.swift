//
//  AMTApp.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

@main
struct AMTApp: App {
    private let qwenSuggestionService = QwenSuggestionService()
    private let dictionaryStore = LegalDictionaryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(
                suggestionService: qwenSuggestionService,
                dictionaryStore: dictionaryStore
            )
                .navigationTitle("")
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
