import Foundation
import Testing
@testable import TodoNativeCore

private func color(_ hex: String) throws -> SRGB {
    try #require(CategoryColor.parse(hex))
}

/// The smallest angle between two hues, in radians.
private func hueDistance(_ lhs: SRGB, _ rhs: SRGB) -> Double {
    let difference = abs(CategoryColor.oklch(lhs).hue - CategoryColor.oklch(rhs).hue)
    return min(difference, 2 * .pi - difference)
}

@Suite("CategoryColor")
struct CategoryColorTests {
    @Test("hex round-trips and is always lowercase on output")
    func hexRoundTrip() throws {
        for hex in ["#000000", "#ffffff", "#1a2b3c", "#0a84ff", "#fe0102"] {
            #expect(CategoryColor.hex(try color(hex)) == hex)
        }
        #expect(CategoryColor.hex(try color("#1A2B3C")) == "#1a2b3c")
        #expect(CategoryColor.normalized("#ABCDEF") == "#abcdef")
        #expect(CategoryColor.normalized(" #abcdef ") == "#abcdef")
    }

    @Test("anything that is not #rrggbb is rejected")
    func rejectsBadHex() {
        for hex in ["", "abcdef", "#abc", "#abcdefg", "#abcdeg", "#abcdef00", "rgb(1,2,3)"] {
            #expect(CategoryColor.parse(hex) == nil, "\(hex)")
            #expect(CategoryColor.normalized(hex) == nil, "\(hex)")
        }
    }

    @Test("linear components are encoded and clamped, so an extended-range pick still gives a valid hex")
    func hexFromLinear() {
        #expect(CategoryColor.hex(linearRed: 0, linearGreen: 0, linearBlue: 0) == "#000000")
        #expect(CategoryColor.hex(linearRed: 1, linearGreen: 1, linearBlue: 1) == "#ffffff")
        let mid = CategoryColor.decode(128.0 / 255)
        #expect(abs(mid - 0.2159) < 0.0001)
        #expect(CategoryColor.hex(linearRed: mid, linearGreen: mid, linearBlue: mid) == "#808080")
        #expect(CategoryColor.hex(linearRed: 1.4, linearGreen: -0.2, linearBlue: 0) == "#ff0000")
    }

    @Test("contrast against white matches known WCAG values")
    func contrastOnWhite() throws {
        #expect(abs(CategoryColor.contrastOnLight(try color("#000000")) - 21) < 0.001)
        #expect(abs(CategoryColor.contrastOnLight(try color("#ffffff")) - 1) < 0.001)
        // The well-known AA boundary grays.
        #expect(abs(CategoryColor.contrastOnLight(try color("#767676")) - 4.54) < 0.01)
        #expect(abs(CategoryColor.contrastOnLight(try color("#777777")) - 4.48) < 0.01)
        #expect(abs(CategoryColor.contrast(try color("#0000ff"), try color("#ffffff")) - 8.59) < 0.01)
    }

    @Test("a colour that already passes on the dark background is returned unchanged")
    func alreadyPassing() throws {
        for hex in ["#ffcc00", "#ffffff", "#64d2ff", "#ff9f0a"] {
            let light = try color(hex)
            #expect(CategoryColor.contrastOnDark(light) >= 4.5)
            #expect(CategoryColor.darkVariant(of: light) == light)
        }
    }

    @Test("a mid blue is lightened to at least 4.5 with its hue preserved, and no further than needed")
    func midBlue() throws {
        let light = try color("#2a52be")
        #expect(CategoryColor.contrastOnDark(light) < 4.5)

        let dark = CategoryColor.darkVariant(of: light)
        let contrast = CategoryColor.contrastOnDark(dark)
        #expect(contrast >= 4.5)
        #expect(contrast < 4.7)
        #expect(hueDistance(light, dark) < 0.06)
        #expect(CategoryColor.oklch(dark).lightness > CategoryColor.oklch(light).lightness)
        // An exact 8-bit colour: storing it as hex does not cost any contrast.
        #expect(try color(CategoryColor.hex(dark)) == dark)
    }

    @Test("near-black becomes a light neutral gray")
    func nearBlack() throws {
        for hex in ["#000000", "#050505", "#1c1c1e"] {
            let dark = CategoryColor.darkVariant(of: try color(hex))
            #expect(CategoryColor.contrastOnDark(dark) >= 4.5, "\(hex)")
            #expect(CategoryColor.oklch(dark).chroma < 0.01, "\(hex)")
            #expect(CategoryColor.relativeLuminance(dark) > 0.2, "\(hex)")
        }
    }

    @Test("a gray stays achromatic")
    func grayStaysGray() throws {
        let dark = CategoryColor.darkVariant(of: try color("#444444"))
        #expect(dark.red == dark.green && dark.green == dark.blue)
        #expect(CategoryColor.contrastOnDark(dark) >= 4.5)
    }

    @Test("a saturated colour whose lightened form leaves sRGB comes back in gamut")
    func saturatedComesBackInGamut() throws {
        for hex in ["#0000ff", "#3300cc", "#8b0000", "#5500aa"] {
            let light = try color(hex)
            let dark = CategoryColor.darkVariant(of: light)
            for component in [dark.red, dark.green, dark.blue] {
                #expect((0...1).contains(component), "\(hex)")
            }
            #expect(CategoryColor.contrastOnDark(dark) >= 4.5, "\(hex)")
            #expect(hueDistance(light, dark) < 0.06, "\(hex)")
            #expect(CategoryColor.oklch(dark).chroma > 0.02, "\(hex) lost its colour")
        }
    }

    @Test("every colour gets a dark variant that passes")
    func alwaysPasses() {
        for red in stride(from: 0, through: 255, by: 51) {
            for green in stride(from: 0, through: 255, by: 51) {
                for blue in stride(from: 0, through: 255, by: 51) {
                    let light = SRGB(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
                    #expect(CategoryColor.contrastOnDark(CategoryColor.darkVariant(of: light)) >= 4.5)
                }
            }
        }
    }
}
