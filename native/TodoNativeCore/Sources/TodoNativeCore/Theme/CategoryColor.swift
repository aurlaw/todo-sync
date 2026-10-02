import Foundation

/// A colour as gamma-encoded sRGB components in 0...1.
public struct SRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Category colours: the stored hex form, WCAG contrast, and the derived dark-mode variant.
/// Only the light colour is stored and synced; the dark one is computed here, the same on every device.
public enum CategoryColor {
    public static let lightBackground = SRGB(red: 1, green: 1, blue: 1)
    /// `#1c1c1e`, the dark-mode background the derived variant is tuned against.
    public static let darkBackground = SRGB(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)
    /// WCAG AA for normal text.
    public static let minimumContrast = 4.5

    // MARK: Hex

    /// Parses `#rrggbb` in either case. Nil for anything else.
    public static func parse(_ hex: String) -> SRGB? {
        guard hex.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil, let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        return SRGB(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    /// Lowercase `#rrggbb`, the only form the Worker accepts. Components are clamped to 0...1 first.
    public static func hex(_ color: SRGB) -> String {
        func byte(_ component: Double) -> Int { Int((clamp(component) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(color.red), byte(color.green), byte(color.blue))
    }

    /// The stored form of a user-supplied hex string, or nil if it is not `#rrggbb`.
    public static func normalized(_ hex: String) -> String? {
        parse(hex.trimmingCharacters(in: .whitespaces)).map(Self.hex)
    }

    /// Hex from linear-light sRGB components, which may be outside 0...1 (a colour picker can
    /// return extended-range values).
    public static func hex(linearRed: Double, linearGreen: Double, linearBlue: Double) -> String {
        hex(SRGB(red: encode(clamp(linearRed)), green: encode(clamp(linearGreen)), blue: encode(clamp(linearBlue))))
    }

    // MARK: Contrast (WCAG 2.x)

    public static func relativeLuminance(_ color: SRGB) -> Double {
        0.2126 * decode(color.red) + 0.7152 * decode(color.green) + 0.0722 * decode(color.blue)
    }

    /// The contrast ratio, from 1 (identical) to 21 (black on white).
    public static func contrast(_ lhs: SRGB, _ rhs: SRGB) -> Double {
        let (first, second) = (relativeLuminance(lhs), relativeLuminance(rhs))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    public static func contrastOnLight(_ color: SRGB) -> Double { contrast(color, lightBackground) }
    public static func contrastOnDark(_ color: SRGB) -> Double { contrast(color, darkBackground) }

    // MARK: Dark variant

    /// Below this OKLCH chroma a colour is treated as a neutral gray and stays one.
    static let achromaticChroma = 0.01

    /// The colour to use on the dark background: `light` unchanged if it already reaches
    /// `minimumContrast` there, otherwise the same hue lightened just far enough to reach it.
    /// Chroma is kept where sRGB allows and reduced where it does not. The result is always an exact
    /// 8-bit colour, so it survives a trip through `hex` without losing contrast.
    public static func darkVariant(of light: SRGB) -> SRGB {
        if contrastOnDark(light) >= minimumContrast { return light }

        let start = oklch(light)
        let chroma = start.chroma < achromaticChroma ? 0 : start.chroma
        func candidate(_ lightness: Double) -> SRGB {
            quantized(fitted(lightness: lightness, chroma: chroma, hue: start.hue))
        }

        // The smallest lightness that reaches the target. White always does, so `high` is always valid.
        var (low, high) = (start.lightness, 1.0)
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if contrastOnDark(candidate(middle)) >= minimumContrast {
                high = middle
            } else {
                low = middle
            }
        }
        return candidate(high)
    }

    /// The colour at this lightness and hue with as much of `chroma` as fits inside sRGB.
    private static func fitted(lightness: Double, chroma: Double, hue: Double) -> SRGB {
        if let color = srgb(lightness: lightness, chroma: chroma, hue: hue) { return color }
        // Zero chroma is a gray, which is always in gamut for a lightness in 0...1.
        var (low, high) = (0.0, chroma)
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if srgb(lightness: lightness, chroma: middle, hue: hue) != nil {
                low = middle
            } else {
                high = middle
            }
        }
        return srgb(lightness: lightness, chroma: low, hue: hue)
            ?? SRGB(red: clamp(lightness), green: clamp(lightness), blue: clamp(lightness))
    }

    private static func quantized(_ color: SRGB) -> SRGB {
        func snap(_ component: Double) -> Double { (clamp(component) * 255).rounded() / 255 }
        return SRGB(red: snap(color.red), green: snap(color.green), blue: snap(color.blue))
    }

    // MARK: OKLCH (Björn Ottosson's OKLab, polar form)

    static func oklch(_ color: SRGB) -> (lightness: Double, chroma: Double, hue: Double) {
        let (red, green, blue) = (decode(color.red), decode(color.green), decode(color.blue))
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)

        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return (lightness, (a * a + b * b).squareRoot(), atan2(b, a))
    }

    /// Nil when the colour falls outside the sRGB gamut.
    private static func srgb(lightness: Double, chroma: Double, hue: Double) -> SRGB? {
        let (a, b) = (chroma * cos(hue), chroma * sin(hue))
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)

        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        let tolerance = 1e-5
        guard linear.allSatisfy({ $0 >= -tolerance && $0 <= 1 + tolerance }) else { return nil }
        return SRGB(red: encode(clamp(linear[0])), green: encode(clamp(linear[1])), blue: encode(clamp(linear[2])))
    }

    // MARK: Transfer function

    /// Gamma-encoded sRGB to linear light.
    static func decode(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    /// Linear light to gamma-encoded sRGB.
    static func encode(_ component: Double) -> Double {
        component <= 0.0031308 ? component * 12.92 : 1.055 * pow(component, 1 / 2.4) - 0.055
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
