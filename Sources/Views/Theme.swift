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
}

/// The CSS custom properties from the web timer (`.timer` / `.timer[data-theme="light"]`).
struct Palette {
    let isLight: Bool

    let background: Color
    let text: Color
    let textSoft: Color
    let textMuted: Color
    let textFaint: Color
    let teal: Color
    let tealBright: Color
    let tealSoft: Color
    let hairline: Color
    let onTeal: Color
    let glowTop: Color
    let glowBottom: Color
    let control: Color
    let grain: Double

    /// Base colours kept as components so they can be blended for animations.
    let tealBase: RGBA
    let textBase: RGBA
    let tealBrightBase: RGBA

    let tealTextStops: [Gradient.Stop]
    let tealFillStops: [Gradient.Stop]
    let surfaceTop: Color
    let surfaceBottom: Color
    let surfaceShadow: Color
    let flashInner: Color
    let flashOuter: Color

    /// `--teal-text`: top-to-bottom gradient used on big text.
    var tealText: LinearGradient {
        LinearGradient(stops: tealTextStops, startPoint: .top, endPoint: .bottom)
    }

    /// `--teal-fill`: 135° gradient used on buttons and selected controls.
    var tealFill: LinearGradient {
        LinearGradient(stops: tealFillStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// `--surface`: the form card.
    var surface: LinearGradient {
        LinearGradient(colors: [surfaceTop, surfaceBottom], startPoint: .top, endPoint: .bottom)
    }

    /// `rgba(var(--teal-rgb), x)`
    func teal(_ opacity: Double) -> Color { tealBase.color(opacity: opacity) }

    static func forMode(_ mode: TimerThemeMode) -> Palette {
        mode == .light ? light : dark
    }

    static let dark = Palette(
        isLight: false,
        background: RGBA(0x050505).color,
        text: RGBA(0xf4fbfb).color,
        textSoft: RGBA(0xf4fbfb, alpha: 0.85).color,
        textMuted: RGBA(0xf4fbfb, alpha: 0.5).color,
        textFaint: RGBA(0xf4fbfb, alpha: 0.28).color,
        teal: RGBA(0x41b8c2).color,
        tealBright: RGBA(0x54bfc8).color,
        tealSoft: RGBA(0x41b8c2, alpha: 0.75).color,
        hairline: RGBA(0x41b8c2, alpha: 0.22).color,
        onTeal: RGBA(0x0b2426).color,
        glowTop: RGBA(0x41b8c2, alpha: 0.12).color,
        glowBottom: RGBA(0x1d5559, alpha: 0.2).color,
        control: Color.white.opacity(0.06),
        grain: 0.05,
        tealBase: RGBA(0x41b8c2),
        textBase: RGBA(0xf4fbfb),
        tealBrightBase: RGBA(0x54bfc8),
        tealTextStops: [
            .init(color: RGBA(0xd3f1f3).color, location: 0),
            .init(color: RGBA(0x54bfc8).color, location: 0.55),
            .init(color: RGBA(0x2a7c83).color, location: 1),
        ],
        tealFillStops: [
            .init(color: RGBA(0xb9e6ea).color, location: 0),
            .init(color: RGBA(0x54bfc8).color, location: 0.4),
            .init(color: RGBA(0x41b8c2).color, location: 0.7),
            .init(color: RGBA(0x2a7c83).color, location: 1),
        ],
        surfaceTop: Color.white.opacity(0.04),
        surfaceBottom: Color.white.opacity(0.012),
        surfaceShadow: Color.black.opacity(0.7),
        flashInner: RGBA(0x54bfc8, alpha: 0.9).color,
        flashOuter: RGBA(0x2a7c83, alpha: 0.6).color
    )

    static let light = Palette(
        isLight: true,
        background: Color.white,
        text: Color.black,
        textSoft: Color.black.opacity(0.8),
        textMuted: Color.black.opacity(0.55),
        textFaint: Color.black.opacity(0.3),
        teal: RGBA(0x2a7c83).color,
        tealBright: RGBA(0x41b8c2).color,
        tealSoft: RGBA(0x2a7c83, alpha: 0.85).color,
        hairline: RGBA(0x2a7c83, alpha: 0.25).color,
        onTeal: Color.white,
        glowTop: RGBA(0x41b8c2, alpha: 0.14).color,
        glowBottom: RGBA(0x54bfc8, alpha: 0.12).color,
        control: Color.black.opacity(0.05),
        grain: 0.03,
        tealBase: RGBA(0x2a7c83),
        textBase: RGBA(0x000000),
        tealBrightBase: RGBA(0x41b8c2),
        tealTextStops: [
            .init(color: RGBA(0x41b8c2).color, location: 0),
            .init(color: RGBA(0x2a7c83).color, location: 0.55),
            .init(color: RGBA(0x1d5559).color, location: 1),
        ],
        tealFillStops: [
            .init(color: RGBA(0x41b8c2).color, location: 0),
            .init(color: RGBA(0x2a7c83).color, location: 0.55),
            .init(color: RGBA(0x1d5559).color, location: 1),
        ],
        surfaceTop: Color.white.opacity(0.85),
        surfaceBottom: Color.white.opacity(0.85),
        surfaceShadow: RGBA(0x1d5559, alpha: 0.35).color,
        flashInner: RGBA(0x54bfc8, alpha: 0.5).color,
        flashOuter: RGBA(0x41b8c2, alpha: 0.3).color
    )

    /// The progress bar fill, the same in both themes.
    static let progressGradient = LinearGradient(
        stops: [
            .init(color: RGBA(0x1d5559).color, location: 0),
            .init(color: RGBA(0x2a7c83).color, location: 0.3),
            .init(color: RGBA(0x41b8c2).color, location: 0.7),
            .init(color: RGBA(0x54bfc8).color, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
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
