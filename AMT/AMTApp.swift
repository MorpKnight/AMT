//
//  AMTApp.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI

@main
struct AMTApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .navigationTitle("")
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
