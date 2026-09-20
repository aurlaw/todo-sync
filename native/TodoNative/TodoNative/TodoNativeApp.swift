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
    @State private var coordinator: SyncCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try TodoContainer.make()
        } catch {
            fatalError("Failed to create TodoNativeCore model container: \(error)")
        }
        modelContainer = container

        let client = URLSessionSyncClient(secrets: KeychainStore())
        let engine = SyncEngine(modelContainer: container, client: client)
        // Items that predate manual ordering are numbered once, after the first sync has caught this
        // device up. The store here has no onMutation: the coordinator schedules the push itself.
        let context = container.mainContext
        _coordinator = State(initialValue: SyncCoordinator(engine: engine, afterSync: {
            try TodoStore(context: context).backfillSortOrderIfNeeded()
        }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .modelContainer(modelContainer)
    }
}
