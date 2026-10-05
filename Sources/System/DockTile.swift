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

        init(text: String, progress: Double, expired: Bool, overtime: Bool) {
            self.text = text
            self.progress = (progress * 100).rounded() / 100
            self.expired = expired
            self.overtime = overtime
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

            ZStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()

                ZStack {
                    Circle().fill(Color(red: 0.043, green: 0.141, blue: 0.149).opacity(0.9))
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: ring)
                    Circle()
                        .trim(from: 0, to: state.expired ? 1 : state.progress)
                        .stroke(
                            Color(red: 0.33, green: 0.75, blue: 0.78),
                            style: StrokeStyle(lineWidth: ring, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(state.text)
                        .font(.system(size: dial * (state.overtime ? 0.25 : 0.3), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.expired && !state.overtime ? Color(red: 0.33, green: 0.75, blue: 0.78) : .white)
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
