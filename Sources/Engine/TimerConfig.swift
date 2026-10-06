import Foundation

public enum TimerThemeMode: String, Codable, CaseIterable, Sendable {
    case dark
    case light
}

/// The chime a timer plays at zero (and at 15 seconds left, if it asks for that). The web page
/// is silent, so these only come from the Mac app and its links.
public enum TimerSound: String, Codable, CaseIterable, Sendable {
    case none
    /// macOS's Glass (and Tink at 15 seconds).
    case classic
    case singingBowl = "singing-bowl"
    case marimba
}

/// How large each part of the countdown is drawn, in percent of the web page's size. Mac-only,
/// like the accent: the web page always draws 100%.
public struct TimerSizes: Codable, Hashable, Sendable {
    public static let range = 50...200
    public static let step = 10

    /// The digits (and the overtime count).
    public var timer: Int
    /// The text under the timer.
    public var lead: Int
    /// The text at 15 seconds left.
    public var warning: Int
    /// The text at zero.
    public var done: Int
    /// The "N people waiting" line.
    public var people: Int

    public init(timer: Int = 100, lead: Int = 100, warning: Int = 100, done: Int = 100, people: Int = 100) {
        self.timer = TimerSizes.clamped(timer)
        self.lead = TimerSizes.clamped(lead)
        self.warning = TimerSizes.clamped(warning)
        self.done = TimerSizes.clamped(done)
        self.people = TimerSizes.clamped(people)
    }

    /// All at 100%.
    public var isStandard: Bool { self == TimerSizes() }

    /// One step up (`direction` > 0) or down from `percent`, to the next multiple of `step`
    /// (a typed 55 steps to 60 or 50), within `range`.
    public static func stepped(_ percent: Int, by direction: Int) -> Int {
        let next = direction > 0
            ? (percent / step + 1) * step
            : ((percent + step - 1) / step - 1) * step
        return clamped(next)
    }

    public static func clamped(_ percent: Int) -> Int {
        min(max(percent, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case timer, lead, warning, done, people
    }

    /// Missing sizes are 100%; out-of-range ones are held to `range`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timer: try c.decodeIfPresent(Int.self, forKey: .timer) ?? 100,
            lead: try c.decodeIfPresent(Int.self, forKey: .lead) ?? 100,
            warning: try c.decodeIfPresent(Int.self, forKey: .warning) ?? 100,
            done: try c.decodeIfPresent(Int.self, forKey: .done) ?? 100,
            people: try c.decodeIfPresent(Int.self, forKey: .people) ?? 100
        )
    }
}

/// Everything that defines one timer. Mirrors the params of the web `/timer` page
/// (`StaticController#timer`), including its limits and defaults.
public struct TimerConfig: Codable, Hashable, Sendable {
    public static let maxSeconds = 86_400
    public static let maxPeople = 10_000
    public static let maxLeadLength = 120
    public static let maxWarningLength = 120
    public static let maxDoneLength = 60
    public static let defaultWarningText = "Please take your seats."
    public static let defaultDoneText = "Time is up!"
    /// What the setup form shows before anything has been chosen.
    public static let defaultSeconds = 600
    /// The web page's teal; `accent` is nil for it.
    public static let defaultAccent = "#41B8C2"

    /// 1...86_400
    public var seconds: Int
    /// Shown under the digits until 15 seconds are left.
    public var leadText: String?
    /// Replaces the lead text from 15 seconds left. Empty means none.
    public var warningText: String
    /// Shown when time is up. Empty means none, only the overtime count (or nothing): the Mac
    /// app's own choice, since the web page shows its default for a blank `done`.
    public var doneText: String
    /// Keep counting up ("+m:ss") after zero instead of stopping.
    public var countOver: Bool
    /// Room size for the "N people waiting" cost line.
    public var people: Int?
    public var theme: TimerThemeMode
    /// "#RRGGBB" the countdown is drawn in, or nil for the default teal.
    public var accent: String?
    public var sound: TimerSound
    /// Also chime at 15 seconds left (zero always chimes unless `sound` is `.none`).
    public var chimeAtWarning: Bool
    public var sizes: TimerSizes

    public init(
        seconds: Int,
        leadText: String? = nil,
        warningText: String = TimerConfig.defaultWarningText,
        doneText: String = TimerConfig.defaultDoneText,
        countOver: Bool = true,
        people: Int? = nil,
        theme: TimerThemeMode = .dark,
        accent: String? = nil,
        sound: TimerSound = .classic,
        chimeAtWarning: Bool = false,
        sizes: TimerSizes = TimerSizes()
    ) {
        self.seconds = min(max(seconds, 1), TimerConfig.maxSeconds)

        let lead = TimerConfig.clean(leadText ?? "", limit: TimerConfig.maxLeadLength)
        self.leadText = lead.isEmpty ? nil : lead

        self.warningText = TimerConfig.clean(warningText, limit: TimerConfig.maxWarningLength)

        self.doneText = TimerConfig.clean(doneText, limit: TimerConfig.maxDoneLength)

        self.countOver = countOver

        if let people = people, people > 0 {
            self.people = min(people, TimerConfig.maxPeople)
        } else {
            self.people = nil
        }

        self.theme = theme
        self.accent = TimerConfig.normalizedAccent(accent)
        self.sound = sound
        self.chimeAtWarning = chimeAtWarning
        self.sizes = sizes
    }

    /// "#RRGGBB" in capitals from "#rrggbb" or "rrggbb"; nil for the default teal or anything else.
    static func normalizedAccent(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let digits = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").uppercased()
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        let hex = "#" + digits
        return hex == TimerConfig.defaultAccent ? nil : hex
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, leadText, warningText, doneText, countOver, people, theme, accent, sound, chimeAtWarning, sizes
    }

    /// Tolerant decoding so presets saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            seconds: try c.decodeIfPresent(Int.self, forKey: .seconds) ?? TimerConfig.defaultSeconds,
            leadText: try c.decodeIfPresent(String.self, forKey: .leadText),
            warningText: try c.decodeIfPresent(String.self, forKey: .warningText) ?? TimerConfig.defaultWarningText,
            doneText: try c.decodeIfPresent(String.self, forKey: .doneText) ?? TimerConfig.defaultDoneText,
            countOver: try c.decodeIfPresent(Bool.self, forKey: .countOver) ?? true,
            people: try c.decodeIfPresent(Int.self, forKey: .people),
            theme: try c.decodeIfPresent(TimerThemeMode.self, forKey: .theme) ?? .dark,
            accent: try c.decodeIfPresent(String.self, forKey: .accent),
            sound: (try? c.decodeIfPresent(TimerSound.self, forKey: .sound)) ?? .classic,
            chimeAtWarning: try c.decodeIfPresent(Bool.self, forKey: .chimeAtWarning) ?? false,
            sizes: (try? c.decodeIfPresent(TimerSizes.self, forKey: .sizes)) ?? TimerSizes()
        )
    }

    /// Ruby's `squish.first(limit)`: collapse whitespace runs, trim, truncate.
    static func clean(_ text: String, limit: Int) -> String {
        let squished = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(squished.prefix(limit))
    }
}

// MARK: - Presentation

extension TimerConfig {
    /// "1hr 5min 30sec", as the web history list shows it.
    public var durationLabel: String { TimerFormat.durationLabel(seconds) }

    /// The second line of a history row on the web form.
    public var summary: String {
        let texts = [leadText ?? "", warningText]
            .filter { !$0.isEmpty }
            .map { "“\($0)”" }
            .joined(separator: " then ")

        var parts = [
            texts.isEmpty ? "No text under timer" : texts,
            doneText.isEmpty ? "No text at 00:00" : "“\(doneText)” at 00:00",
            countOver ? "Keeps counting" : "Stops at 00:00",
        ]
        if let people = people {
            parts.append("\(people) \(people == 1 ? "person" : "people")")
        }
        if theme == .light {
            parts.append("Light mode")
        }
        switch sound {
        case .none: parts.append("Silent")
        case .singingBowl: parts.append("Singing bowl")
        case .marimba: parts.append("Marimba")
        case .classic: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sharing

extension TimerConfig {
    /// The Eco web timer. Shared links point here: the Mac app opens them where it's installed
    /// (as universal links), and the web page runs them everywhere else.
    public static let webTimerURL = "https://unreasonable.eco/timer"

    /// A link to this timer on the Eco web page, with its params as the web form writes them
    /// (time, text, lead, done, over, people, theme), then the Mac app's own where they aren't
    /// the default (accent, sound, chime15, sizes), which the web page ignores, and `name`.
    public func shareLink(name: String? = nil) -> String {
        var params: [(String, String)] = [("time", String(seconds)), ("text", warningText)]
        if let lead = leadText { params.append(("lead", lead)) }
        if doneText != TimerConfig.defaultDoneText { params.append(("done", doneText)) }
        if !countOver { params.append(("over", "0")) }
        if let people = people { params.append(("people", String(people))) }
        if theme == .light { params.append(("theme", "light")) }
        if let accent = accent { params.append(("accent", String(accent.dropFirst()))) }
        if sound != .classic { params.append(("sound", sound.rawValue)) }
        if chimeAtWarning { params.append(("chime15", "1")) }
        let sizeParams = [
            ("timersize", sizes.timer), ("leadsize", sizes.lead), ("textsize", sizes.warning),
            ("donesize", sizes.done), ("peoplesize", sizes.people),
        ]
        for (param, percent) in sizeParams where percent != 100 {
            params.append((param, String(percent)))
        }
        if let name = name.map({ TimerConfig.clean($0, limit: 80) }), !name.isEmpty {
            params.append(("name", name))
        }
        let query = params.map { "\($0)=\(TimerConfig.encode($1))" }.joined(separator: "&")
        return TimerConfig.webTimerURL + "?" + query
    }

    /// The value of `param` in a `/timer` or `untimer://` link, decoded as the web page does.
    public static func parameter(_ param: String, inLink link: String) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return nil }
        return decodeQuery(components.percentEncodedQuery ?? "").last { $0.name == param }?.value
    }

    /// Percent-encodes everything but letters, digits and `-._~`, so `&`, `=`, `+` and `#` in
    /// a text survive the trip.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - Parsing /timer URLs

extension TimerConfig {
    /// Builds a config from `/timer` query params, applying the controller's rules.
    /// Returns nil when `time` is missing or not positive (the web page shows its form then).
    public init?(queryItems: [URLQueryItem]) {
        var params: [String: String] = [:]
        for item in queryItems { params[item.name] = item.value ?? "" }

        let seconds = TimerFormat.rubyToI(params["time"] ?? "")
        guard seconds > 0 else { return nil }

        let people = TimerFormat.rubyToI(params["people"] ?? "")
        // A size given as a positive whole percentage; anything else is 100%.
        func size(_ name: String) -> Int {
            let percent = TimerFormat.rubyToI(params[name] ?? "")
            return percent > 0 ? percent : 100
        }

        self.init(
            seconds: seconds,
            leadText: params["lead"],
            // `text` present (even empty) overrides the default; absent keeps it.
            warningText: params["text"] ?? TimerConfig.defaultWarningText,
            // `done` absent is the default text. The web form never writes it empty, so an empty
            // `done=` means none (the web page still shows its default for it).
            doneText: params["done"] ?? TimerConfig.defaultDoneText,
            countOver: params["over"] != "0",
            people: people > 0 ? people : nil,
            theme: params["theme"] == "light" ? .light : .dark,
            // Mac-only extras, ignored by the web page: accent=E8743B, sound=singing-bowl,
            // chime15=1, and sizes in percent (timersize, leadsize, textsize, donesize, peoplesize).
            accent: params["accent"],
            sound: params["sound"].flatMap { TimerSound(rawValue: $0.lowercased()) } ?? .classic,
            chimeAtWarning: params["chime15"] == "1",
            sizes: TimerSizes(
                timer: size("timersize"),
                lead: size("leadsize"),
                warning: size("textsize"),
                done: size("donesize"),
                people: size("peoplesize")
            )
        )
    }

    /// Accepts a pasted Eco `/timer?...` link or an `untimer://...?...` link.
    public init?(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else { return nil }

        let scheme = components.scheme?.lowercased() ?? ""
        switch scheme {
        case "untimer":
            break
        case "http", "https":
            let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
            guard path == "/timer" || path.hasSuffix("/timer") else { return nil }
        default:
            return nil
        }

        self.init(queryItems: TimerConfig.decodeQuery(components.percentEncodedQuery ?? ""))
    }

    /// Form-style decoding: `+` is a space (the web form builds links with `URLSearchParams`).
    static func decodeQuery(_ query: String) -> [URLQueryItem] {
        func decode(_ s: String) -> String {
            s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
        }
        return query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = decode(String(halves[0]))
            let value = halves.count > 1 ? decode(String(halves[1])) : ""
            return URLQueryItem(name: name, value: value)
        }
    }
}
