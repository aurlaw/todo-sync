import Foundation

/// The category this device is showing. Per device and never synced, so the Mac and the iPhone can
/// sit on different categories. Kept in the App Group's defaults because the widgets read it too.
// UserDefaults is documented thread-safe but not annotated Sendable.
public struct ActiveCategoryStore: @unchecked Sendable {
    public static let key = "todonative.activeCategoryId"

    private let defaults: UserDefaults
    private let onChange: @Sendable () -> Void

    /// `onChange` runs after every write; by default it reloads the widgets, which are scoped to
    /// the active category.
    public init(
        defaults: UserDefaults = AppGroup.defaults(),
        onChange: @escaping @Sendable () -> Void = { WidgetReloader.reloadAll() }
    ) {
        self.defaults = defaults
        self.onChange = onChange
    }

    /// The stored id, whether or not it still names a live category. Absent means Unassigned.
    public var storedID: UUID? {
        defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
    }

    public func set(_ selection: CategorySelection) {
        if let id = selection.categoryID {
            defaults.set(id.uuidString.lowercased(), forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
        onChange()
    }

    /// The stored selection, falling back to Unassigned when the id no longer names a live
    /// category (deleted on another device, or nothing stored yet).
    public func effectiveSelection(in tree: CategoryTree) -> CategorySelection {
        Self.effectiveSelection(storedID: storedID, in: tree)
    }

    public static func effectiveSelection(storedID: UUID?, in tree: CategoryTree) -> CategorySelection {
        CategorySelection(tree.resolve(storedID)?.id)
    }
}
