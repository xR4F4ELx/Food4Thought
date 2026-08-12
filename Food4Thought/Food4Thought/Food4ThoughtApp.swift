//
//  Food4ThoughtApp.swift
//  Food4Thought
//
//  Created by Rafael Macam on 11/8/26.
//

import SwiftUI

@main
struct Food4ThoughtApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
