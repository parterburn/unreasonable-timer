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
    /// "#RRGGBB"
    var accent: String
    var sound: TimerSound
    var chimeAtWarning: Bool

    init(config: TimerConfig) {
        minutes = String(format: "%02d", config.seconds / 60)
        seconds = String(format: "%02d", config.seconds % 60)
        done = config.doneText
        lead = config.leadText ?? ""
        warning = config.warningText
        people = config.people.map { String($0) } ?? ""
        countOver = config.countOver
        theme = config.theme
        accent = config.accent ?? TimerConfig.defaultAccent
        sound = config.sound
        chimeAtWarning = config.chimeAtWarning
    }

    var totalSeconds: Int { (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0) }

    /// nil until there is at least a second on the clock (Start stays disabled).
    func makeConfig() -> TimerConfig? {
        guard totalSeconds > 0 else { return nil }
        return config(seconds: totalSeconds)
    }

    /// What the preview draws, even while the time is still 0.
    var previewConfig: TimerConfig { config(seconds: max(totalSeconds, 1)) }

    private func config(seconds: Int) -> TimerConfig {
        TimerConfig(
            seconds: min(seconds, TimerConfig.maxSeconds),
            leadText: lead,
            warningText: warning,
            doneText: done,
            countOver: countOver,
            people: Int(people),
            theme: theme,
            accent: accent,
            sound: sound,
            chimeAtWarning: chimeAtWarning
        )
    }
}

/// What the sidebar has selected.
private enum SidebarItem: Hashable {
    case new
    case saved(UUID)
    case recent(Int)
}

/// The setup screen, laid out like System Settings: saved and recent timers in a sidebar, and
/// the timer's options in a grouped form under a live preview of the countdown, with Start
/// always in reach at the bottom.
struct SetupView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var store: PresetStore

    @State private var draft: Draft
    @State private var selection: SidebarItem?
    @State private var showSaveAlert = false
    /// Which moment of the countdown the preview shows; follows the field being edited.
    /// (`-UTPreviewMoment end` picks one for scripts/ci-screenshots.sh.)
    @State private var previewMoment = PreviewMoment(rawValue: UserDefaults.standard.string(forKey: "UTPreviewMoment") ?? "") ?? .start
    @State private var saveName = ""
    @FocusState private var focus: SetupField?
    @ObservedObject private var chimes = ChimePlayer.shared

    private static let quickMinutes = [1, 3, 5, 10, 15, 30, 60]

    init(controller: TimerController, store: PresetStore) {
        self.controller = controller
        self.store = store
        _draft = State(initialValue: Draft(config: controller.formPrefill ?? controller.config))
    }

    private var accent: AccentColor { AccentColor(string: draft.accent) ?? .teal }

    private var selectedPreset: NamedPreset? {
        guard case .saved(let id) = selection else { return nil }
        return store.presets.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
                .safeAreaInset(edge: .bottom, spacing: 0) { settingsButton }
        } detail: {
            if controller.showSettingsPane {
                settingsPane
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        previewHeader(height: min(240, max(120, geo.size.height * 0.3)))
                        form
                    }
                }
            }
        }
        .tint(accent.color)
        .onAppear {
            consumePrefill()
            // AppKit focuses the first text field on its own, selecting the minutes; start with
            // nothing focused so the form reads as a whole first.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                controller.mainWindow?.makeFirstResponder(nil)
            }
        }
        .onChange(of: controller.formPrefill) { _, _ in consumePrefill() }
        .onChange(of: selection) { _, item in
            // Picking a timer leaves settings for the form.
            if item != nil { controller.showSettingsPane = false }
            load(item)
        }
        .onChange(of: controller.showSettingsPane) { _, showing in
            // Nothing in the timer list stays highlighted while settings are up, so any timer
            // can be picked to go back.
            if showing { selection = nil }
        }
        .onChange(of: focus) { old, new in
            if old == .minutes || old == .seconds { normalizeTime() }
            // Show the moment the field being edited appears in.
            switch new {
            case .minutes, .seconds, .lead: previewMoment = .start
            case .warning: previewMoment = .warning
            case .done, .people: previewMoment = .end
            case nil: break
            }
        }
        .onChange(of: draft.countOver) { previewMoment = .end }
        .onChange(of: draft.sound) { chimes.stop() }
        .onDisappear { chimes.stop() }
        .alert("Name this timer", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved timers appear here, in the menu bar and in the Dock menu. The first nine get ⌘1–⌘9.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Label("New Timer", systemImage: "plus.circle")
                .tag(SidebarItem.new)

            Section("Saved") {
                if store.presets.isEmpty {
                    Text("Timers you save appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    SidebarRow(
                        icon: "timer",
                        title: preset.name,
                        subtitle: preset.config.durationLabel,
                        shortcut: index < 9 ? "⌘\(index + 1)" : nil
                    )
                    .tag(SidebarItem.saved(preset.id))
                }
            }

            if !store.recent.isEmpty {
                Section("Recent") {
                    ForEach(Array(store.recent.enumerated()), id: \.offset) { index, config in
                        SidebarRow(
                            icon: "clock.arrow.circlepath",
                            title: config.durationLabel,
                            subtitle: config.leadText ?? (config.warningText.isEmpty ? config.doneText : config.warningText),
                            shortcut: nil
                        )
                        .tag(SidebarItem.recent(index))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if let item = items.first, let config = config(for: item) {
                Button("Open Timer") { controller.open(config, autostart: false) }
                if case .recent = item {
                    Button("Save as Timer…") {
                        selection = item
                        saveName = ""
                        showSaveAlert = true
                    }
                }
                if case .saved(let id) = item, let preset = store.presets.first(where: { $0.id == id }) {
                    Divider()
                    Button("Delete “\(preset.name)”", role: .destructive) {
                        if selection == item { selection = nil }
                        store.delete(preset)
                    }
                }
            }
        } primaryAction: { items in
            // Double-click (or Return) opens that timer straight away.
            if let item = items.first, let config = config(for: item) {
                controller.open(config, autostart: false)
            }
        }
    }

    /// Bottom left of the sidebar: app settings, in place of the timer form.
    private var settingsButton: some View {
        let active = controller.showSettingsPane
        return Button {
            controller.showSettingsPane.toggle()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? AnyShapeStyle(accent.color.opacity(0.22)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .help("Settings (⌘,)")
    }

    /// App settings in the detail pane, with Done to go back to the timer being edited.
    private var settingsPane: some View {
        SettingsView(controller: controller, updater: Updater.shared)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        controller.showSettingsPane = false
                    } label: {
                        Text("Done").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
    }

    private func config(for item: SidebarItem) -> TimerConfig? {
        switch item {
        case .new:
            return TimerConfig(seconds: TimerConfig.defaultSeconds)
        case .saved(let id):
            return store.presets.first { $0.id == id }?.config
        case .recent(let index):
            return store.recent.indices.contains(index) ? store.recent[index] : nil
        }
    }

    private func load(_ item: SidebarItem?) {
        guard let item = item, let config = config(for: item) else { return }
        draft = Draft(config: config)
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                durationEditor
            }

            Section {
                textField("Under the timer", text: $draft.lead, prompt: "Optional", field: .lead, limit: TimerConfig.maxLeadLength)
                textField("At 15 seconds left", text: $draft.warning, prompt: "Optional", field: .warning, limit: TimerConfig.maxWarningLength)
                textField("At zero", text: $draft.done, prompt: TimerConfig.defaultDoneText, field: .done, limit: TimerConfig.maxDoneLength)
            } header: {
                Text("Text")
            } footer: {
                Text("The text under the timer gives way to the 15-second text, and the zero text appears when time is up. Paste a /timer link into any field to fill in the whole form.")
            }

            Section {
                Toggle("Count up after zero", isOn: $draft.countOver)
                TextField("Number of people in the room", text: $draft.people, prompt: Text("Optional"))
                    .focused($focus, equals: .people)
                    .onChange(of: draft.people) { _, new in
                        let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(5))
                        if digits != new { draft.people = digits }
                    }
            } header: {
                Text("When time is up")
            } footer: {
                Text("With the number of people set, the overtime shows how much of the room’s time is going by.")
            }

            Section {
                Picker("Theme", selection: $draft.theme) {
                    Text("Dark").tag(TimerThemeMode.dark)
                    Text("Light").tag(TimerThemeMode.light)
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent color") {
                    AccentPicker(hex: $draft.accent, swatchSize: 15)
                }
            } header: {
                Text("Look")
            }

            Section {
                LabeledContent {
                    Picker("Sound", selection: $draft.sound) {
                        ForEach(TimerSound.allCases, id: \.self) { sound in
                            Text(sound.title).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    HStack(spacing: 6) {
                        Text("Sound at zero")
                        previewButton(.zero, label: "the chime at zero")
                    }
                }
                Toggle(isOn: $draft.chimeAtWarning) {
                    HStack(spacing: 6) {
                        Text("Also chime at 15 seconds left")
                        previewButton(.warning, label: "the chime at 15 seconds")
                    }
                }
                .disabled(draft.sound == .none)
            } header: {
                Text("Sound")
            } footer: {
                Text(soundFootnote)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
    }

    /// The preview stays in view above the scrolling form, so every change shows as it's made.
    private func previewHeader(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            CountdownPreview(config: draft.previewConfig, moment: previewMoment)
                .frame(height: height)
            Picker("Preview", selection: $previewMoment) {
                ForEach(PreviewMoment.allCases, id: \.self) { moment in
                    Text(moment.title).tag(moment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Which moment of the countdown to preview")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Duration

    private var durationEditor: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                timeField(text: $draft.minutes, field: .minutes, maxDigits: 4, unit: "minutes")
                Text(":")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                timeField(text: $draft.seconds, field: .seconds, maxDigits: 2, unit: "seconds")
            }
            HStack(spacing: 6) {
                ForEach(Self.quickMinutes, id: \.self) { minutes in
                    let current = draft.totalSeconds == minutes * 60
                    Button("\(minutes) min") {
                        draft.minutes = String(format: "%02d", minutes)
                        draft.seconds = "00"
                        focus = nil
                        previewMoment = .start
                    }
                    .buttonStyle(QuickDurationStyle(selected: current, accent: accent.color))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func timeField(text: Binding<String>, field: SetupField, maxDigits: Int, unit: String) -> some View {
        VStack(spacing: 4) {
            // In a grouped Form a text field's title becomes a label beside it; the unit
            // caption below does that job here.
            TextField(unit, text: text, prompt: Text("00"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($focus, equals: field)
                .frame(width: maxDigits > 2 ? 116 : 84)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HierarchicalShapeStyle.quaternary.opacity(0.5)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(focus == field ? accent.color : Color.clear, lineWidth: 2)
                )
                .onChange(of: text.wrappedValue) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(maxDigits))
                    if digits != new { text.wrappedValue = digits }
                }
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Carries overflow (90 seconds becomes 1:30) and re-pads the two fields.
    private func normalizeTime() {
        let total = min(draft.totalSeconds, TimerConfig.maxSeconds)
        draft.minutes = String(format: "%02d", total / 60)
        draft.seconds = String(format: "%02d", total % 60)
    }

    // MARK: Sound

    private var soundFootnote: String {
        let bowl = draft.sound == .singingBowl
            ? "The singing bowl rings three times at zero, about ten seconds apart. " : ""
        return bowl + "A notification also appears at zero when the timer isn't in front."
    }

    /// Plays this timer's chime (or stops it), to hear the choice before starting.
    private func previewButton(_ moment: ChimePlayer.Moment, label: String) -> some View {
        let playing = chimes.previewing == moment
        return Button {
            chimes.togglePreview(moment, sound: draft.sound)
        } label: {
            Image(systemName: playing ? "stop.circle.fill" : "play.circle")
                .imageScale(.large)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .disabled(draft.sound == .none)
        .help(playing ? "Stop" : "Play \(label)")
        .accessibilityLabel(playing ? "Stop" : "Play \(label)")
    }

    // MARK: Text

    private func textField(_ label: String, text: Binding<String>, prompt: String, field: SetupField, limit: Int) -> some View {
        TextField(label, text: text, prompt: Text(prompt))
            .focused($focus, equals: field)
            .onChange(of: text.wrappedValue) { old, new in
                if let linked = timerLink(in: new) {
                    // A pasted /timer link fills the whole form instead of landing in this field.
                    text.wrappedValue = old
                    draft = Draft(config: linked)
                    selection = nil
                } else if new.count > limit {
                    text.wrappedValue = String(new.prefix(limit))
                }
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

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Save as Timer…") {
                saveName = selectedPreset?.name ?? ""
                showSaveAlert = true
            }
            .disabled(draft.makeConfig() == nil)

            if let preset = selectedPreset, let config = draft.makeConfig(), config != preset.config {
                Button("Update “\(preset.name)”") { store.update(preset, config: config) }
            }

            Spacer()

            // Opens the countdown paused, like the web page, so it can go up on screen before
            // the room is ready; click or Space starts it.
            Button(action: start) {
                Text("Open Timer").frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.makeConfig() == nil)
            .help("Opens the countdown, paused. Click it or press Space to start.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func start() {
        normalizeTime()
        guard let config = draft.makeConfig() else { return }
        controller.open(config, autostart: false)
    }

    private func saveCurrent() {
        guard let config = draft.makeConfig() else { return }
        let preset = store.save(name: saveName, config: config)
        selection = .saved(preset.id)
    }

    private func consumePrefill() {
        guard let prefill = controller.formPrefill else { return }
        draft = Draft(config: prefill)
        selection = nil
        controller.formPrefill = nil
    }
}

// MARK: - Pieces

private struct SidebarRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let shortcut: String?

    var body: some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .padding(.vertical, 2)
    }
}

/// The 1 / 3 / 5 … minute buttons; the one matching the current duration is filled.
private struct QuickDurationStyle: ButtonStyle {
    let selected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(HierarchicalShapeStyle.quaternary.opacity(0.7)))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A moment of the countdown for the preview to show.
private enum PreviewMoment: String, CaseIterable {
    case start, warning, end

    var title: String {
        switch self {
        case .start: return "Start"
        case .warning: return "15 seconds left"
        case .end: return "Time is up"
        }
    }
}

/// The countdown as it will look at `moment`: the real stage (same layout, wrapping, glow and
/// overtime lines), laid out for a typical 1280 × 800 window and scaled down to fit.
private struct CountdownPreview: View {
    let config: TimerConfig
    let moment: PreviewMoment

    private static let canvas = CGSize(width: 1280, height: 800)

    /// The engine's own state at that moment: 12 seconds left, or 42 seconds past zero.
    private var snapshot: TimerEngine.Snapshot {
        var engine = TimerEngine(config: config)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        engine.start(now: start)
        let elapsed: Int
        switch moment {
        case .start: elapsed = 0
        case .warning: elapsed = max(config.seconds - 12, 0)
        case .end: elapsed = config.seconds + 42
        }
        let now = start.addingTimeInterval(TimeInterval(elapsed))
        engine.tick(now: now)
        return engine.snapshot(now: now)
    }

    var body: some View {
        let palette = Palette.make(config.theme, accent: AccentColor(config: config))
        let snap = snapshot
        let canvas = Self.canvas
        GeometryReader { geo in
            ZStack {
                TimerBackground(palette: palette)
                HeatGlow(palette: palette, heat: snap.heat, expired: snap.isExpired)
                CountdownStage(snap: snap, config: config, palette: palette, size: canvas)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(palette.accent(0.08))
                        Rectangle()
                            .fill(palette.progressGradient)
                            .scaleEffect(x: max(snap.progress, 0.0001), y: 1, anchor: .leading)
                    }
                    .frame(height: canvas.height * 0.008)
                    .opacity(snap.isExpired ? 0 : 1)
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
            .scaleEffect(geo.size.width / canvas.width, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Preview at \(moment.title.lowercased()): \(snap.displayText)")
    }
}
