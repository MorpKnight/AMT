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

    var body: some Scene {
        WindowGroup {
            ContentView(suggestionService: qwenSuggestionService)
                .navigationTitle("")
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
