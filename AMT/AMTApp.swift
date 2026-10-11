//
//  AMTApp.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

@main
struct AMTApp: App {
    private let qwenSuggestionService: QwenSuggestionService
    private let dictionaryStore: LegalDictionaryStore

    init() {
        let service = QwenSuggestionService()
        qwenSuggestionService = service
        dictionaryStore = LegalDictionaryStore(inferenceScheduler: service.inferenceScheduler)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                suggestionService: qwenSuggestionService,
                dictionaryStore: dictionaryStore
            )
                .navigationTitle("")
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AIConnectorDebugPanelCommands()
        }
    }
}
