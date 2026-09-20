#if os(iOS)
import AppIntents
import SwiftUI
import TodoNativeCore
import WidgetKit

/// Control Center / Lock Screen button that opens the app straight to the new-todo editor. `OpenURLIntent` is a
/// system intent, so the OS opens `todonative://new` itself and the app's `onOpenURL` shows the sheet.
/// The mac has the global hotkey instead, so this is iOS only.
struct NewTodoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.aurlaw.TodoNative.NewTodoControl") {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.new.url)) {
                Label("New Todo", systemImage: "plus")
            }
        }
        .displayName("New Todo")
        .description("Open TodoNative to add a todo.")
    }
}
#endif
