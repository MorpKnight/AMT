//
//  ContentView.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

struct ContentView: View {
    let suggestionService: QwenSuggestionService

    var body: some View {
        DashboardView(suggestionService: suggestionService)
    }
}

#Preview {
    ContentView(suggestionService: QwenSuggestionService())
}
