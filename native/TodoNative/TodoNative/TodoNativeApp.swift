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
    #if os(macOS)
    @State private var quickCapture: QuickCapture
    #endif

    init() {
        let container: ModelContainer
        do {
            // Opens the store in the App Group container, first moving an existing on-device store
            // there. Throws (rather than using a private store) if the App Groups capability is missing.
            container = try TodoContainer.makeShared()
        } catch {
            fatalError("Failed to create TodoNativeCore model container: \(error)")
        }
        modelContainer = container

        let client = URLSessionSyncClient(secrets: KeychainStore())
        let engine = SyncEngine(modelContainer: container, client: client)
        // Items that predate manual ordering are numbered once, after the first sync has caught this
        // device up. The store here has no onMutation: the coordinator schedules the push itself.
        let context = container.mainContext
        let coordinator = SyncCoordinator(engine: engine, afterSync: {
            try TodoStore(context: context).backfillSortOrderIfNeeded()
        })
        _coordinator = State(initialValue: coordinator)
        #if os(macOS)
        _quickCapture = State(initialValue: QuickCapture(context: context, coordinator: coordinator))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        MenuBarExtra("Quick Capture", systemImage: "plus.circle") {
            CaptureField(
                capture: { quickCapture.capture($0) },
                dismiss: { quickCapture.dismissMenuBarPopover() }
            )
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
