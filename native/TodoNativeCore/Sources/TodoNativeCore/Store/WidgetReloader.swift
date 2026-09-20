import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Asks WidgetKit to rebuild every widget and control timeline. Called after each local write (through
/// `TodoStore`'s `onMutation`) and after a sync that changed rows, in whichever process made the change.
public enum WidgetReloader {
    public static func reloadAll() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
