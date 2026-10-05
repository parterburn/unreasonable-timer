import Foundation
import TimerCore

struct NamedPreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var config: TimerConfig
}

/// Saved, named timers plus the last few runs, kept as JSON in Application Support.
@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var presets: [NamedPreset] = []
    @Published private(set) var recent: [TimerConfig] = []

    private let fileURL: URL

    private struct Payload: Codable {
        var presets: [NamedPreset]
        var recent: [TimerConfig]
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? PresetStore.defaultFileURL()
        load()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Unreasonable Timer", isDirectory: true)
            .appendingPathComponent("timers.json")
    }

    // MARK: Recent runs

    func remember(_ config: TimerConfig) {
        recent = TimerHistory.remembering(config, in: recent)
        persist()
    }

    // MARK: Named timers

    /// Saves under `name`; a timer with the same name (ignoring case) is replaced.
    @discardableResult
    func save(name: String, config: TimerConfig) -> NamedPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "\(config.durationLabel) timer" : trimmed

        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            presets[index].name = finalName
            presets[index].config = config
            persist()
            return presets[index]
        }
        let preset = NamedPreset(name: finalName, config: config)
        presets.append(preset)
        persist()
        return preset
    }

    func delete(_ preset: NamedPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func preset(withID id: String) -> NamedPreset? {
        presets.first { $0.id.uuidString == id }
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            presets = payload.presets
            recent = Array(payload.recent.prefix(TimerHistory.limit))
        } catch {
            // Keep the unreadable file for inspection instead of overwriting it with an empty list.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Payload(presets: presets, recent: recent)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Unreasonable Timer: could not save timers: \(error.localizedDescription)")
        }
    }
}
