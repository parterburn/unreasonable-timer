import AppIntents
import TimerCore

// Shortcuts, Spotlight and Siri.

enum TimerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case timerNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .timerNotFound: return "That saved timer no longer exists."
        }
    }
}

/// A saved timer, as Shortcuts sees it.
struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved Timer")
    static let defaultQuery = PresetQuery()

    let id: String
    let name: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ preset: NamedPreset) {
        id = preset.id.uuidString
        name = preset.name
        detail = preset.config.durationLabel
    }
}

struct PresetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        await MainActor.run {
            PresetStore.shared.presets
                .filter { identifiers.contains($0.id.uuidString) }
                .map(PresetEntity.init)
        }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        await MainActor.run {
            PresetStore.shared.presets.map(PresetEntity.init)
        }
    }
}

struct StartSavedTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Saved Timer"
    static let description = IntentDescription("Starts one of your saved timers.")
    static let openAppWhenRun = true

    @Parameter(title: "Timer")
    var timer: PresetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$timer)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let preset = PresetStore.shared.preset(withID: timer.id) else {
            throw TimerIntentError.timerNotFound
        }
        TimerController.shared.open(preset.config, autostart: true)
        return .result()
    }
}

struct StartMinutesIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a countdown for a number of minutes.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 5)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes)-minute timer")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let seconds = min(max(minutes, 1), TimerConfig.maxSeconds / 60) * 60
        TimerController.shared.open(TimerConfig(seconds: seconds), autostart: true)
        return .result()
    }
}

struct PauseResumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Timer"
    static let description = IntentDescription("Pauses or resumes the current timer, or starts your most recent one.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerController.shared.toggleOrStartLast()
        return .result()
    }
}

struct TimerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSavedTimerIntent(),
            phrases: [
                "Start \(\.$timer) in \(.applicationName)",
                "Start a saved timer in \(.applicationName)",
            ],
            shortTitle: "Start Saved Timer",
            systemImageName: "hourglass"
        )
        AppShortcut(
            intent: StartMinutesIntent(),
            phrases: ["Start a timer in \(.applicationName)"],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: PauseResumeIntent(),
            phrases: ["Pause or resume my timer in \(.applicationName)"],
            shortTitle: "Pause or Resume",
            systemImageName: "playpause"
        )
    }
}
