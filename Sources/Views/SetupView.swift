import SwiftUI
import TimerCore

private enum SetupField: Hashable {
    case minutes, seconds, done, lead, warning, people
}

/// The form's raw text, kept as strings so half-typed values don't fight the user.
private struct Draft: Equatable {
    var minutes: String
    var seconds: String
    var done: String
    var lead: String
    var warning: String
    var people: String
    var countOver: Bool
    var theme: TimerThemeMode

    init(config: TimerConfig) {
        minutes = String(format: "%02d", config.seconds / 60)
        seconds = String(format: "%02d", config.seconds % 60)
        done = config.doneText
        lead = config.leadText ?? ""
        warning = config.warningText
        people = config.people.map { String($0) } ?? ""
        countOver = config.countOver
        theme = config.theme
    }

    var totalSeconds: Int { (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0) }

    /// nil until there is at least a second on the clock (the Start button stays disabled).
    func makeConfig() -> TimerConfig? {
        guard totalSeconds > 0 else { return nil }
        return TimerConfig(
            seconds: totalSeconds,
            leadText: lead,
            warningText: warning,
            doneText: done,
            countOver: countOver,
            people: Int(people),
            theme: theme
        )
    }
}

/// The setup form: a port of the web `/timer` form, plus saved timers.
struct SetupView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var store: PresetStore

    @State private var draft: Draft
    @State private var appeared = false
    @State private var showSaveAlert = false
    @State private var saveName = ""
    @FocusState private var focus: SetupField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.accentColor) private var accentHex = AccentColor.teal.string

    init(controller: TimerController, store: PresetStore) {
        self.controller = controller
        self.store = store
        _draft = State(initialValue: Draft(config: controller.formPrefill ?? controller.config))
    }

    private var palette: Palette { Palette.make(draft.theme, accent: AccentColor(string: accentHex) ?? .teal) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimerBackground(palette: palette)
                ScrollViewReader { proxy in
                    ScrollView {
                        card
                            .frame(width: min(520, geo.size.width * 0.92))
                            .padding(.vertical, 48)
                            // Centred when short, scrollable from the top when the lists grow.
                            .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        // For scripted screenshots further down the form (scripts/ci-screenshots.sh).
                        if let target = UserDefaults.standard.string(forKey: "UTSetupScroll"),
                           target == "bottom" || target == "controls" {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                proxy.scrollTo(target, anchor: target == "bottom" ? .bottom : .center)
                            }
                        }
                    }
                }
            }
        }
        // Edge to edge, under the transparent title bar, like the web page.
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: draft.theme)
        .preferredColorScheme(draft.theme == .light ? .light : .dark)
        .onAppear {
            appeared = true
            consumePrefill()
            // AppKit gives the first text field focus on its own, which selects the minutes in
            // a blue highlight; the web form starts with nothing focused.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                controller.mainWindow?.makeFirstResponder(nil)
            }
        }
        .onChange(of: accentHex) { controller.settingsChanged() }
        .onChange(of: controller.formPrefill) { _, _ in consumePrefill() }
        .onChange(of: focus) { old, _ in
            if old == .minutes || old == .seconds { normalizeTime() }
        }
        .alert("Name this timer", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved timers appear in the menu bar and Dock menu, and the first nine get ⌘1–⌘9.")
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 32) {
            header.rise(0, appeared)
            timeRow.rise(1, appeared)
            textField(
                "Timer at 00:00",
                hint: "Flashes and shown when time is up.",
                placeholder: TimerConfig.defaultDoneText,
                text: $draft.done,
                limit: TimerConfig.maxDoneLength,
                field: .done
            ).rise(2, appeared)
            textField(
                "Text under timer",
                hint: "Shown under timer until 15 seconds left. Leave blank for none.",
                placeholder: "Optional",
                text: $draft.lead,
                limit: TimerConfig.maxLeadLength,
                field: .lead
            ).rise(3, appeared)
            textField(
                "Text at 15 seconds left",
                hint: "Replaces the text above starting with 15 seconds left. Leave blank for none.",
                placeholder: "Optional",
                text: $draft.warning,
                limit: TimerConfig.maxWarningLength,
                field: .warning
            ).rise(4, appeared)
            peopleField.rise(5, appeared)
            Toggle("Keep counting after time is up", isOn: $draft.countOver)
                .toggleStyle(PillToggleStyle(palette: palette))
                .rise(6, appeared)
            themePicker.id("controls").rise(7, appeared)
            accentRow.rise(8, appeared)
            VStack(spacing: 14) {
                startButton
                saveButton
            }
            .rise(9, appeared)
            lists.rise(10, appeared)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.hairline, lineWidth: 1)
        )
        .shadow(color: palette.surfaceShadow, radius: 50, y: 30)
    }

    private var header: some View {
        VStack(spacing: 22) {
            // The web title clips the teal text gradient to the emoji, which turns the hourglass
            // into an accent-coloured silhouette; masking the gradient with the emoji does the same.
            palette.accentText
                .frame(width: 40, height: 44)
                .mask { Text("⏳").font(.system(size: 32)) }
            Rectangle()
                .fill(LinearGradient(colors: [palette.accent(0), palette.accent, palette.accent(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 64, height: 1)
        }
        .padding(.top, 24)
    }

    // MARK: Time

    private var timeRow: some View {
        HStack(alignment: .top, spacing: 0) {
            timeColumn("Minutes", text: $draft.minutes, field: .minutes, maxDigits: 4)
            Text(":")
                .font(.inter(72, .light))
                .foregroundStyle(palette.accentSoft)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            timeColumn("Seconds", text: $draft.seconds, field: .seconds, maxDigits: 2)
        }
        .padding(.bottom, 8)
    }

    private func timeColumn(_ label: String, text: Binding<String>, field: SetupField, maxDigits: Int) -> some View {
        VStack(spacing: 6) {
            TextField("00", text: text)
                .textFieldStyle(.plain)
                .font(.inter(88, .light))
                .monospacedDigit()
                .tracking(-2.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(focus == field ? palette.accent : palette.text)
                .focused($focus, equals: field)
                .onChange(of: text.wrappedValue) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(maxDigits))
                    if digits != new { text.wrappedValue = digits }
                }
            fieldLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    /// Carries overflow (90 seconds becomes 1:30) and re-pads the two fields.
    private func normalizeTime() {
        let total = min(draft.totalSeconds, TimerConfig.maxSeconds)
        draft.minutes = String(format: "%02d", total / 60)
        draft.seconds = String(format: "%02d", total % 60)
    }

    // MARK: Text fields

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.inter(10.56, .semibold))
            .tracking(2.96)
            .foregroundStyle(palette.accentSoft)
    }

    private func underline(focused: Bool) -> some View {
        Rectangle()
            .fill(focused ? palette.accent : palette.hairline)
            .frame(height: 1)
            .shadow(color: focused ? palette.accent : .clear, radius: 0, y: 1)
    }

    private func textField(
        _ label: String,
        hint: String?,
        placeholder: String,
        text: Binding<String>,
        limit: Int,
        field: SetupField
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel(label).padding(.bottom, 6).zIndex(1)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(palette.textFaint))
                .textFieldStyle(.plain)
                .font(.inter(17.6))
                .foregroundStyle(palette.text)
                .focused($focus, equals: field)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .onChange(of: text.wrappedValue) { old, new in
                    if let linked = timerLink(in: new) {
                        // A pasted /timer link fills the whole form instead of landing in this field.
                        text.wrappedValue = old
                        draft = Draft(config: linked)
                    } else if new.count > limit {
                        text.wrappedValue = String(new.prefix(limit))
                    }
                }
            underline(focused: focus == field)
            if let hint = hint {
                Text(hint)
                    .font(.inter(13.6))
                    .foregroundStyle(palette.textMuted)
                    .padding(.top, 8)
            }
        }
    }

    private var peopleField: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("People in the room").padding(.bottom, 6)
            TextField("", text: $draft.people, prompt: Text("Optional").foregroundStyle(palette.textFaint))
                .textFieldStyle(.plain)
                .font(.inter(17.6))
                .foregroundStyle(palette.text)
                .focused($focus, equals: .people)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .onChange(of: draft.people) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(5))
                    if digits != new { draft.people = digits }
                }
            underline(focused: focus == .people)
            Text("Calculates the room’s combined wasted time when time is up.")
                .font(.inter(13.6))
                .foregroundStyle(palette.textMuted)
                .padding(.top, 8)
        }
    }

    /// Finds a `/timer` or `untimer://` link among the whitespace-separated words of `text`.
    private func timerLink(in text: String) -> TimerConfig? {
        guard text.contains("timer") else { return nil }
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if let config = TimerConfig(link: String(word)) { return config }
        }
        return nil
    }

    // MARK: Theme

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Theme")
            HStack(spacing: 4) {
                themeSegment("Light", mode: .light)
                themeSegment("Dark", mode: .dark)
            }
            .padding(4)
            .background(Capsule().fill(palette.control))
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
        }
    }

    /// Not part of the timer link: the accent is an app-wide setting (also in Settings).
    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Accent")
            AccentPicker(hex: $accentHex, ring: palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func themeSegment(_ title: String, mode: TimerThemeMode) -> some View {
        let selected = draft.theme == mode
        return Button {
            draft.theme = mode
        } label: {
            Text(title)
                .font(.inter(14.4, .medium))
                .foregroundStyle(selected ? palette.onAccent : palette.textSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9.6)
                .background(Capsule().fill(selected ? AnyShapeStyle(palette.accentFill) : AnyShapeStyle(Color.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var startButton: some View {
        Button(action: start) {
            Text("START TIMER")
                .font(.inter(12.8, .bold))
                .tracking(4.86)
                .foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(palette.accentFill))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: palette.accent(0.45), radius: 20, y: 12)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(draft.makeConfig() == nil)
        .opacity(draft.makeConfig() == nil ? 0.5 : 1)
    }

    private var saveButton: some View {
        Button {
            saveName = ""
            showSaveAlert = true
        } label: {
            Text("Save as named timer…")
                .font(.inter(13.6, .medium))
                .foregroundStyle(palette.accentSoft)
        }
        .buttonStyle(.plain)
        .disabled(draft.makeConfig() == nil)
    }

    private func start() {
        normalizeTime()
        guard let config = draft.makeConfig() else { return }
        controller.open(config, autostart: false)
    }

    private func saveCurrent() {
        guard let config = draft.makeConfig() else { return }
        store.save(name: saveName, config: config)
    }

    private func consumePrefill() {
        guard let prefill = controller.formPrefill else { return }
        draft = Draft(config: prefill)
        controller.formPrefill = nil
    }

    // MARK: Lists

    @ViewBuilder
    private var lists: some View {
        VStack(spacing: 28) {
            if !store.presets.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("Saved timers")
                    ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                        if index > 0 { rowDivider }
                        TimerRow(
                            palette: palette,
                            title: preset.name,
                            subtitle: "\(preset.config.durationLabel) · \(preset.config.summary)",
                            trailing: index < 9 ? "⌘\(index + 1)" : nil
                        ) {
                            controller.open(preset.config, autostart: false)
                        }
                        .contextMenu {
                            Button("Load into Form") { draft = Draft(config: preset.config) }
                            Divider()
                            Button("Delete", role: .destructive) { store.delete(preset) }
                        }
                    }
                }
            }

            if !store.recent.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("Previous timers")
                    ForEach(Array(store.recent.enumerated()), id: \.offset) { index, config in
                        if index > 0 { rowDivider }
                        TimerRow(
                            palette: palette,
                            title: config.durationLabel,
                            subtitle: config.summary,
                            trailing: nil
                        ) {
                            controller.open(config, autostart: false)
                        }
                        .contextMenu {
                            Button("Load into Form") { draft = Draft(config: config) }
                            Button("Save as Named Timer…") {
                                draft = Draft(config: config)
                                saveName = ""
                                showSaveAlert = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.accent(0.12)).frame(height: 1)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(LinearGradient(colors: [palette.hairline.opacity(0), palette.hairline], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            fieldLabel(title)
            Rectangle()
                .fill(LinearGradient(colors: [palette.hairline, palette.hairline.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Pieces

/// A row in "Saved timers" / "Previous timers": big duration, small description, accent on hover.
private struct TimerRow: View {
    let palette: Palette
    let title: String
    let subtitle: String
    let trailing: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.inter(20, .semibold))
                        .foregroundStyle(hovering ? palette.accent : palette.text)
                    Text(subtitle)
                        .font(.inter(12.8))
                        .foregroundStyle(palette.textMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if let trailing = trailing {
                    Text(trailing)
                        .font(.inter(12))
                        .foregroundStyle(palette.textFaint)
                }
            }
            .padding(.vertical, 13.6)
            .padding(.leading, hovering ? 9.6 : 4)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.25), value: hovering)
    }
}

/// The pill switch from the web form's "Keep counting" toggle.
private struct PillToggleStyle: ToggleStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 16) {
                configuration.label
                    .font(.inter(15.2))
                    .foregroundStyle(palette.textSoft)
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? AnyShapeStyle(palette.accentFill) : AnyShapeStyle(palette.control))
                    Capsule()
                        .stroke(configuration.isOn ? Color.clear : palette.hairline, lineWidth: 1)
                    Circle()
                        .fill(configuration.isOn ? palette.onAccent : palette.textMuted)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
                .frame(width: 46, height: 26)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

/// `timer-form-rise`: each block fades up into place, staggered 60 ms apart.
private struct Rise: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = appeared || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(
                reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.8).delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

private extension View {
    func rise(_ index: Int, _ appeared: Bool) -> some View {
        modifier(Rise(index: index, appeared: appeared))
    }
}
