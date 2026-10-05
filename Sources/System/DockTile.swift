import AppKit
import SwiftUI

/// Draws the running timer into the Dock icon: a dial with a progress ring and the time.
/// Reverts to the normal icon when no timer is loaded.
@MainActor
final class DockTile {
    struct State: Equatable {
        var text: String
        /// 0...1, rounded so the tile only redraws when something visible changed.
        var progress: Double
        var expired: Bool
        var overtime: Bool
        var accent: AccentColor

        init(text: String, progress: Double, expired: Bool, overtime: Bool, accent: AccentColor) {
            self.text = text
            self.progress = (progress * 100).rounded() / 100
            self.expired = expired
            self.overtime = overtime
            self.accent = accent
        }
    }

    private var lastShown: State?

    func update(_ state: State?) {
        guard let state = state else {
            if lastShown != nil {
                lastShown = nil
                NSApp.dockTile.contentView = nil
                NSApp.dockTile.display()
            }
            return
        }
        guard state != lastShown else { return }
        lastShown = state

        let tile = NSApp.dockTile
        let host = NSHostingView(rootView: DockTileView(state: state))
        host.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = host
        tile.display()
    }
}

private struct DockTileView: View {
    let state: DockTile.State

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let dial = side * 0.66
            let ring = side * 0.055
            let bright = state.accent.shade(0x54bfc8).color

            ZStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()

                ZStack {
                    Circle().fill(state.accent.shade(0x0b2426, alpha: 0.9).color)
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: ring)
                    Circle()
                        .trim(from: 0, to: state.expired ? 1 : state.progress)
                        .stroke(bright, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(state.text)
                        .font(.system(size: dial * (state.overtime ? 0.25 : 0.3), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.expired && !state.overtime ? bright : .white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, ring * 1.6)
                }
                .padding(ring / 2)
                .frame(width: dial, height: dial)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
