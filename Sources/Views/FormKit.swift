import AppKit
import SwiftUI

// Grouped sections in the style of System Settings, laid out by hand. Form's grouped style
// stops growing at 600 points wide on macOS 15, which leaves the setup screen and settings
// narrow in a wide window; these grow with the window up to a readable width.

/// A scrolling page of sections, centred, at most `maxWidth` wide.
struct FormPage<Content: View>: View {
    var maxWidth: CGFloat = 880
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(FormColors.page)
    }
}

/// A titled group of rows on a rounded panel, with an optional note underneath.
struct FormSection<Content: View, Footer: View>: View {
    let title: String?
    let content: Content
    let footer: Footer

    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            // Every row draws a divider along its bottom; the last one falls outside and is
            // clipped, so dividers only appear between rows.
            .padding(.bottom, -1)
            .clipShape(Self.panel)
            .background(Self.panel.fill(FormColors.section))
            .overlay(Self.panel.strokeBorder(FormColors.border, lineWidth: 1))
            footer
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
        }
    }

    private static var panel: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }
}

extension FormSection where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, footer: { EmptyView() })
    }
}

/// One row of a section: the label on the left, the control on the right.
struct FormRow<Label: View, Control: View>: View {
    let label: Label
    let control: Control

    init(@ViewBuilder control: () -> Control, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            label
                .layoutPriority(1)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) { FormDivider() }
    }
}

extension FormRow where Label == Text {
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.init(control: control) { Text(title) }
    }
}

/// A row with a switch, like a Toggle in a grouped Form.
struct FormToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        FormRow {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        } label: {
            // The switch carries the title for VoiceOver.
            Text(title).accessibilityHidden(true)
        }
    }
}

/// A full-width panel inside a section, for content that isn't a label and a control.
struct FormPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(10)
            .overlay(alignment: .bottom) { FormDivider() }
    }
}

private struct FormDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(FormColors.divider)
            .frame(height: 1 / displayScale)
            .padding(.horizontal, 10)
    }
}

/// The colours of the grouped Form on macOS 15, light and dark.
enum FormColors {
    static let page = dynamic(light: 246, dark: 40)
    static let section = dynamic(light: 242, dark: 43)
    static let border = dynamic(light: 230, dark: 75)
    static let divider = dynamic(light: 231, dark: 53)

    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: (isDark ? dark : light) / 255, alpha: 1)
        })
    }
}
