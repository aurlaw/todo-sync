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
        // A sync that applied rows changes what the widgets show.
        let engine = SyncEngine(modelContainer: container, client: client, onChangesApplied: { WidgetReloader.reloadAll() })
        // Items that predate manual ordering are numbered once, after the first sync has caught this
        // device up. The store here has no onMutation: the coordinator schedules the push itself.
        let context = container.mainContext
        let coordinator = SyncCoordinator(engine: engine, afterSync: {
            let changed = try TodoStore(context: context).backfillSortOrderIfNeeded()
            if changed { WidgetReloader.reloadAll() }
            return changed
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
        // Send widget/control URLs to the existing window instead of opening a new one. [NEEDS VERIFICATION]
        .handlesExternalEvents(matching: ["*"])
        #endif

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
