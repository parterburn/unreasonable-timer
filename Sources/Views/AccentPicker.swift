import SwiftUI

/// Preset swatches plus a custom colour well. Stores the choice as "#RRGGBB".
struct AccentPicker: View {
    @Binding var hex: String
    /// Colour of the ring around the selected swatch.
    var ring: Color = .primary
    var swatchSize: CGFloat = 22

    private var selected: AccentColor { AccentColor(string: hex) ?? .teal }
    private var isCustom: Bool { !AccentColor.presets.contains { $0.accent == selected } }

    var body: some View {
        HStack(spacing: swatchSize * 0.25) {
            ForEach(AccentColor.presets) { preset in
                swatch(preset.accent, name: preset.name)
            }
            ColorPicker(
                "Custom",
                selection: Binding(
                    get: { selected.color },
                    set: { hex = AccentColor($0).string }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .help("Custom color")
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(ring, lineWidth: 1.5)
                    .padding(-3)
                    .opacity(isCustom ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .padding(.leading, swatchSize * 0.25)
        }
    }

    private func swatch(_ accent: AccentColor, name: String) -> some View {
        let isSelected = accent == selected
        return Button {
            hex = accent.string
        } label: {
            Circle()
                .fill(LinearGradient(
                    colors: [accent.shade(0x54bfc8).color, accent.shade(0x2a7c83).color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: swatchSize, height: swatchSize)
                .padding(3)
                .overlay(Circle().stroke(ring, lineWidth: 1.5).opacity(isSelected ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
