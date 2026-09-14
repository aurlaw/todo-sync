//
//  TodoNativeApp.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import SwiftData
import TodoNativeCore

@main
struct TodoNativeApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try TodoContainer.make()
        } catch {
            fatalError("Failed to create TodoNativeCore model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
