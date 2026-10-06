import AppKit
import CoreText
import SwiftUI
import TimerCore

/// An sRGB colour that can be tinted or blended (SwiftUI's `Color` can't be interpolated
/// before macOS 15).
struct RGBA: Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func color(opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a * opacity) }

    func mixed(with other: RGBA, by t: Double) -> Color {
        let t = min(max(t, 0), 1)
        return Color(
            .sRGB,
            red: r + (other.r - r) * t,
            green: g + (other.g - g) * t,
            blue: b + (other.b - b) * t,
            opacity: a + (other.a - a) * t
        )
    }

    var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    // MARK: HSL

    /// Hue 0..<1, saturation and lightness 0...1.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxV == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    init(h: Double, s: Double, l: Double, a: Double = 1) {
        guard s > 0 else {
            self.init(r: l, g: l, b: l, a: a)
            return
        }
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(r: channel(p, q, h + 1.0 / 3), g: channel(p, q, h), b: channel(p, q, h - 1.0 / 3), a: a)
    }
}

/// The colour the whole interface is drawn in.
///
/// The web timer's teal is one hue at one saturation, used at several lightnesses (#d3f1f3,
/// #b9e6ea, #54bfc8, #41b8c2, #2A7C83, #1D5559, #0b2426). Any accent gets the same family:
/// each shade keeps the accent's hue and saturation, and sits as far from the teal shade's
/// lightness as the accent sits from teal's. So the accent itself shows exactly as chosen (a
/// brand colour stays the brand colour) and the family keeps the web design's spread of
/// contrast. Teal itself maps back to the exact web values.
struct AccentColor: Hashable {
    let hex: UInt32

    static let teal = AccentColor(hex: 0x41B8C2)

    struct Preset: Identifiable {
        let name: String
        let accent: AccentColor
        /// Unreasonable's own colours, listed first.
        var brand = false
        var id: UInt32 { accent.hex }
    }

    static let presets: [Preset] = [
        Preset(name: "Unreasonable Teal", accent: .teal, brand: true),
        Preset(name: "Unreasonable Impact", accent: AccentColor(hex: 0x36A0CE), brand: true),
        Preset(name: "Unreasonable Food", accent: AccentColor(hex: 0x00D6B8), brand: true),
        Preset(name: "Eco Purple", accent: AccentColor(hex: 0x6926E3), brand: true),
        Preset(name: "Blue", accent: AccentColor(hex: 0x3B8FD9)),
        Preset(name: "Indigo", accent: AccentColor(hex: 0x5C6BD6)),
        Preset(name: "Violet", accent: AccentColor(hex: 0x8E5CD6)),
        Preset(name: "Pink", accent: AccentColor(hex: 0xD65C9C)),
        Preset(name: "Red", accent: AccentColor(hex: 0xD9534F)),
        Preset(name: "Orange", accent: AccentColor(hex: 0xE8743B)),
        Preset(name: "Amber", accent: AccentColor(hex: 0xE0A83A)),
        Preset(name: "Green", accent: AccentColor(hex: 0x4CB87A)),
        Preset(name: "Graphite", accent: AccentColor(hex: 0x8A9295)),
    ]

    init(hex: UInt32) {
        self.hex = hex & 0xFFFFFF
    }

    /// "#RRGGBB" (the stored form).
    init?(string: String) {
        let digits = string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.255, green: 0.722, blue: 0.761, alpha: 1)
        self.init(hex: RGBA(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent).hex)
    }

    var string: String { String(format: "#%06X", hex) }

    /// The accent as it appears on screen (the dark theme's main shade).
    var color: Color { shade(0x41B8C2).color }

    /// A timer's accent (nil in the config means teal).
    init(config: TimerConfig) {
        self = AccentColor(string: config.accent ?? "") ?? .teal
    }

    /// The web teal shade `tealHex`, translated into this accent.
    func shade(_ tealHex: UInt32, alpha: Double = 1) -> RGBA {
        if self == .teal { return RGBA(tealHex, alpha: alpha) }
        let base = RGBA(AccentColor.teal.hex).hsl
        let mine = RGBA(hex).hsl
        let target = RGBA(tealHex).hsl
        let saturation = base.s > 0 ? min(1, mine.s * target.s / base.s) : mine.s
        let lightness = min(max(target.l + (mine.l - base.l), 0.04), 0.96)
        return RGBA(h: mine.h, s: saturation, l: lightness, a: alpha)
    }
}

/// The CSS custom properties from the web timer (`.timer` / `.timer[data-theme="light"]`),
/// with every teal value taken from the chosen accent.
struct Palette {
    let isLight: Bool

    let background: Color
    let text: Color
    let textSoft: Color
    let textMuted: Color
    let textFaint: Color
    let accent: Color
    let accentBright: Color
    let accentSoft: Color
    let hairline: Color
    let onAccent: Color
    let glowTop: Color
    let glowBottom: Color
    let control: Color
    let grain: Double

    /// Base colours kept as components so they can be blended for animations.
    let accentBase: RGBA
    let textBase: RGBA
    let accentBrightBase: RGBA

    let accentTextStops: [Gradient.Stop]
    let accentFillStops: [Gradient.Stop]
    let progressStops: [Gradient.Stop]
    let surfaceTop: Color
    let surfaceBottom: Color
    let surfaceShadow: Color

    /// `--teal-text`: top-to-bottom gradient used on big text.
    var accentText: LinearGradient {
        LinearGradient(stops: accentTextStops, startPoint: .top, endPoint: .bottom)
    }

    /// `--teal-fill`: 135° gradient used on buttons and selected controls.
    var accentFill: LinearGradient {
        LinearGradient(stops: accentFillStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The countdown's progress bar fill.
    var progressGradient: LinearGradient {
        LinearGradient(stops: progressStops, startPoint: .leading, endPoint: .trailing)
    }

    /// `--surface`: the form card.
    var surface: LinearGradient {
        LinearGradient(colors: [surfaceTop, surfaceBottom], startPoint: .top, endPoint: .bottom)
    }

    /// `rgba(var(--teal-rgb), x)`
    func accent(_ opacity: Double) -> Color { accentBase.color(opacity: opacity) }

    /// Colour of the running digits: from 15 seconds they flash between white and the accent;
    /// in the last ten each second's `beat` is a quick flash of the bright accent that settles
    /// back to white (see `CountdownView.digits`).
    func digitColor(flash: Double, beat: Double) -> Color {
        beat > 0
            ? textBase.mixed(with: accentBrightBase, by: beat)
            : textBase.mixed(with: accentBase, by: flash)
    }

    @MainActor private static var cache: [String: Palette] = [:]

    /// The palette for a theme and accent. Views ask for it many times a second, so it is cached.
    @MainActor
    static func make(_ mode: TimerThemeMode, accent: AccentColor = .teal) -> Palette {
        let key = "\(mode.rawValue)-\(accent.hex)"
        if let cached = cache[key] { return cached }
        let palette = mode == .light ? light(accent) : dark(accent)
        cache[key] = palette
        return palette
    }

    private static func progress(_ a: AccentColor) -> [Gradient.Stop] {
        [
            .init(color: a.shade(0x1d5559).color, location: 0),
            .init(color: a.shade(0x2a7c83).color, location: 0.3),
            .init(color: a.shade(0x41b8c2).color, location: 0.7),
            .init(color: a.shade(0x54bfc8).color, location: 1),
        ]
    }

    private static func dark(_ a: AccentColor) -> Palette {
        Palette(
            isLight: false,
            background: RGBA(0x050505).color,
            text: RGBA(0xf4fbfb).color,
            textSoft: RGBA(0xf4fbfb, alpha: 0.85).color,
            textMuted: RGBA(0xf4fbfb, alpha: 0.5).color,
            textFaint: RGBA(0xf4fbfb, alpha: 0.28).color,
            accent: a.shade(0x41b8c2).color,
            accentBright: a.shade(0x54bfc8).color,
            accentSoft: a.shade(0x41b8c2, alpha: 0.75).color,
            hairline: a.shade(0x41b8c2, alpha: 0.22).color,
            onAccent: a.shade(0x0b2426).color,
            glowTop: a.shade(0x41b8c2, alpha: 0.12).color,
            glowBottom: a.shade(0x1d5559, alpha: 0.2).color,
            control: Color.white.opacity(0.06),
            grain: 0.05,
            accentBase: a.shade(0x41b8c2),
            textBase: RGBA(0xf4fbfb),
            accentBrightBase: a.shade(0x54bfc8),
            accentTextStops: [
                .init(color: a.shade(0xd3f1f3).color, location: 0),
                .init(color: a.shade(0x54bfc8).color, location: 0.55),
                .init(color: a.shade(0x2a7c83).color, location: 1),
            ],
            accentFillStops: [
                .init(color: a.shade(0xb9e6ea).color, location: 0),
                .init(color: a.shade(0x54bfc8).color, location: 0.4),
                .init(color: a.shade(0x41b8c2).color, location: 0.7),
                .init(color: a.shade(0x2a7c83).color, location: 1),
            ],
            progressStops: progress(a),
            surfaceTop: Color.white.opacity(0.04),
            surfaceBottom: Color.white.opacity(0.012),
            surfaceShadow: Color.black.opacity(0.7)
        )
    }

    private static func light(_ a: AccentColor) -> Palette {
        Palette(
            isLight: true,
            background: Color.white,
            text: Color.black,
            textSoft: Color.black.opacity(0.8),
            textMuted: Color.black.opacity(0.55),
            textFaint: Color.black.opacity(0.3),
            accent: a.shade(0x2a7c83).color,
            accentBright: a.shade(0x41b8c2).color,
            accentSoft: a.shade(0x2a7c83, alpha: 0.85).color,
            hairline: a.shade(0x2a7c83, alpha: 0.25).color,
            onAccent: Color.white,
            glowTop: a.shade(0x41b8c2, alpha: 0.14).color,
            glowBottom: a.shade(0x54bfc8, alpha: 0.12).color,
            control: Color.black.opacity(0.05),
            grain: 0.03,
            accentBase: a.shade(0x2a7c83),
            textBase: RGBA(0x000000),
            accentBrightBase: a.shade(0x41b8c2),
            accentTextStops: [
                .init(color: a.shade(0x41b8c2).color, location: 0),
                .init(color: a.shade(0x2a7c83).color, location: 0.55),
                .init(color: a.shade(0x1d5559).color, location: 1),
            ],
            accentFillStops: [
                .init(color: a.shade(0x41b8c2).color, location: 0),
                .init(color: a.shade(0x2a7c83).color, location: 0.55),
                .init(color: a.shade(0x1d5559).color, location: 1),
            ],
            progressStops: progress(a),
            surfaceTop: Color.white.opacity(0.85),
            surfaceBottom: Color.white.opacity(0.85),
            surfaceShadow: a.shade(0x1d5559, alpha: 0.35).color
        )
    }
}

// MARK: - Fonts

enum FontLoader {
    private(set) static var interAvailable = false

    /// Registers the bundled Inter files for this process. Call once at launch.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        if !urls.isEmpty {
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        }
        interAvailable = NSFont(name: "Inter-Regular", size: 12) != nil
    }
}

extension Font {
    /// Inter at a fixed point size, falling back to the system font if the files are missing.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard FontLoader.interAvailable else { return .system(size: size, weight: weight) }
        let name: String
        if weight == .light || weight == .thin || weight == .ultraLight {
            name = "Inter-Light"
        } else if weight == .medium {
            name = "Inter-Medium"
        } else if weight == .semibold {
            name = "Inter-SemiBold"
        } else if weight == .bold || weight == .heavy || weight == .black {
            name = "Inter-Bold"
        } else {
            name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }
}

// MARK: - Background

/// Film grain, so the background reads as a material rather than an empty screen.
enum Grain {
    static let image: Image = {
        let side = 160
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for i in 0..<(side * side) {
            let v = UInt8.random(in: 0...255)
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return Image(decorative: cgImage, scale: 2)
    }()
}

/// The two soft glows over the base colour, plus grain. Used behind both screens.
struct TimerBackground: View {
    let palette: Palette

    var body: some View {
        ZStack {
            palette.background

            // radial-gradient(1100px 620px at 50% -10%, glow-top, transparent 65%)
            EllipticalGradient(
                stops: [
                    .init(color: palette.glowTop, location: 0),
                    .init(color: palette.glowTop.opacity(0), location: 0.65),
                ],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadiusFraction: 0,
                endRadiusFraction: 1
            )

            // radial-gradient(900px 600px at 50% 115%, glow-bottom, transparent 70%)
            EllipticalGradient(
                stops: [
                    .init(color: palette.glowBottom, location: 0),
                    .init(color: palette.glowBottom.opacity(0), location: 0.7),
                ],
                center: UnitPoint(x: 0.5, y: 1.15),
                startRadiusFraction: 0,
                endRadiusFraction: 0.9
            )

            Grain.image
                .resizable(resizingMode: .tile)
                .opacity(palette.grain)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
