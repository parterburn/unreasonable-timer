import Foundation

public enum TimerThemeMode: String, Codable, CaseIterable, Sendable {
    case dark
    case light
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

    /// 1...86_400
    public var seconds: Int
    /// Shown under the digits until 15 seconds are left.
    public var leadText: String?
    /// Replaces the lead text from 15 seconds left. Empty means none.
    public var warningText: String
    public var doneText: String
    /// Keep counting up ("+m:ss") after zero instead of stopping.
    public var countOver: Bool
    /// Room size for the "N people waiting" cost line.
    public var people: Int?
    public var theme: TimerThemeMode

    public init(
        seconds: Int,
        leadText: String? = nil,
        warningText: String = TimerConfig.defaultWarningText,
        doneText: String = TimerConfig.defaultDoneText,
        countOver: Bool = true,
        people: Int? = nil,
        theme: TimerThemeMode = .dark
    ) {
        self.seconds = min(max(seconds, 1), TimerConfig.maxSeconds)

        let lead = TimerConfig.clean(leadText ?? "", limit: TimerConfig.maxLeadLength)
        self.leadText = lead.isEmpty ? nil : lead

        self.warningText = TimerConfig.clean(warningText, limit: TimerConfig.maxWarningLength)

        let done = TimerConfig.clean(doneText, limit: TimerConfig.maxDoneLength)
        self.doneText = done.isEmpty ? TimerConfig.defaultDoneText : done

        self.countOver = countOver

        if let people = people, people > 0 {
            self.people = min(people, TimerConfig.maxPeople)
        } else {
            self.people = nil
        }

        self.theme = theme
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, leadText, warningText, doneText, countOver, people, theme
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
            theme: try c.decodeIfPresent(TimerThemeMode.self, forKey: .theme) ?? .dark
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
            "“\(doneText)” at 00:00",
            countOver ? "Keeps counting" : "Stops at 00:00",
        ]
        if let people = people {
            parts.append("\(people) \(people == 1 ? "person" : "people")")
        }
        if theme == .light {
            parts.append("Light mode")
        }
        return parts.joined(separator: " · ")
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

        self.init(
            seconds: seconds,
            leadText: params["lead"],
            // `text` present (even empty) overrides the default; absent keeps it.
            warningText: params["text"] ?? TimerConfig.defaultWarningText,
            doneText: params["done"] ?? "",
            countOver: params["over"] != "0",
            people: people > 0 ? people : nil,
            theme: params["theme"] == "light" ? .light : .dark
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
