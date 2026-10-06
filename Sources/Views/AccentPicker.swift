import SwiftUI

/// Preset swatches (Unreasonable's colours first) plus a custom colour well, with the name of
/// the swatch under the pointer, or of the current choice, written underneath. Stores the
/// choice as "#RRGGBB".
struct AccentPicker: View {
    @Binding var hex: String
    /// Colour of the ring around the selected swatch.
    var ring: Color = .primary
    var swatchSize: CGFloat = 22

    @State private var hovered: AccentColor.Preset?

    private var selected: AccentColor { AccentColor(string: hex) ?? .teal }
    private var selectedPreset: AccentColor.Preset? { AccentColor.presets.first { $0.accent == selected } }
    private var caption: String {
        hovered?.name ?? selectedPreset?.name ?? "Custom \(selected.string)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: swatchSize * 0.25) {
                ForEach(AccentColor.presets.filter(\.brand)) { preset in
                    swatch(preset)
                }
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: swatchSize)
                    .padding(.horizontal, swatchSize * 0.2)
                ForEach(AccentColor.presets.filter { !$0.brand }) { preset in
                    swatch(preset)
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
                        .opacity(selectedPreset == nil ? 1 : 0)
                        .allowsHitTesting(false)
                )
                .padding(.leading, swatchSize * 0.25)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 3)
                .animation(nil, value: caption)
        }
    }

    private func swatch(_ preset: AccentColor.Preset) -> some View {
        let accent = preset.accent
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
        .onHover { inside in
            if inside {
                hovered = preset
            } else if hovered?.id == preset.id {
                hovered = nil
            }
        }
        .help(preset.name)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
