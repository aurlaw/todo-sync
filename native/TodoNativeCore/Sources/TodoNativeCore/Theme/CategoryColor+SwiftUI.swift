import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// A category colour that follows the appearance: `hex` itself in light mode and its derived
    /// variant in dark mode. Nil if `hex` is not `#rrggbb`.
    public init?(categoryHex hex: String) {
        guard let light = CategoryColor.parse(hex) else { return nil }
        let dark = CategoryColor.darkVariant(of: light)
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
        #endif
    }

    /// A fixed colour, for previews that must show one variant regardless of the appearance.
    public init(_ color: SRGB) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
    }
}

extension CategoryColor {
    /// The tint for a category, or nil when it has no custom colour (or there is no category) and
    /// the app accent applies.
    public static func tint(for category: TodoCategory?) -> Color? {
        category?.color.flatMap(Color.init(categoryHex:))
    }

    /// The stored hex for a colour picked in a `ColorPicker`. Goes through the linear components,
    /// which are unambiguous, and clamps them: a picker can return extended-range values.
    public static func hex(_ resolved: Color.Resolved) -> String {
        hex(
            linearRed: Double(resolved.linearRed),
            linearGreen: Double(resolved.linearGreen),
            linearBlue: Double(resolved.linearBlue)
        )
    }
}
