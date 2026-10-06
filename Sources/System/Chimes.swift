import AppKit
import AVFoundation

/// The sound set for the two chimes (15 seconds left, and zero).
enum ChimeSound: String, CaseIterable, Identifiable {
    /// macOS's Tink and Glass.
    case classic
    /// A small bowl at 15 seconds; at zero a deep bowl struck three times, about ten seconds
    /// apart, so it rings the room back to attention the way a meditation bowl does.
    case singingBowl
    /// A soft two-note "ding-dong", then a rising C–E–G–C played twice.
    case marimba

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .singingBowl: return "Singing bowl"
        case .marimba: return "Marimba"
        }
    }

    static var current: ChimeSound {
        ChimeSound(rawValue: UserDefaults.standard.string(forKey: AppSettings.chimeSound) ?? "") ?? .classic
    }
}

/// Plays the chimes, for a running timer and for the previews in Settings.
@MainActor
final class ChimePlayer: ObservableObject {
    enum Moment {
        case warning, zero
    }

    static let shared = ChimePlayer()

    /// The chime a preview button is playing, so that button can offer Stop instead.
    @Published private(set) var previewing: Moment?

    private var player: AVAudioPlayer?
    private var systemSound: NSSound?
    /// The singing bowl rings for half a minute; a timer's zero chime is cut short (gently)
    /// once that timer is reset or replaced.
    private var playingZeroForTimer = false
    private var finishTask: Task<Void, Never>?

    func play(_ moment: Moment, sound: ChimeSound = .current) {
        start(moment, sound: sound)
        playingZeroForTimer = moment == .zero
    }

    /// Plays `moment` in `sound`, or stops it if that preview is already playing.
    func togglePreview(_ moment: Moment, sound: ChimeSound = .current) {
        if previewing == moment {
            stop()
            return
        }
        start(moment, sound: sound)
        previewing = moment
    }

    /// Fades out a timer's zero chime that is still ringing. Previews keep playing.
    func timerNoLongerExpired() {
        if playingZeroForTimer { stop() }
    }

    func stop() {
        finishTask?.cancel()
        if let player = player, player.isPlaying {
            player.setVolume(0, fadeDuration: 1.2)
            let fading = player
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                fading.stop()
            }
        }
        player = nil
        systemSound?.stop()
        systemSound = nil
        playingZeroForTimer = false
        previewing = nil
    }

    private func start(_ moment: Moment, sound: ChimeSound) {
        stop()
        let duration: TimeInterval
        switch sound {
        case .classic:
            let chime = NSSound(named: NSSound.Name(moment == .warning ? "Tink" : "Glass"))
            chime?.play()
            systemSound = chime
            duration = chime?.duration ?? 1
        case .singingBowl, .marimba:
            let name = (sound == .singingBowl ? "singing-bowl-" : "marimba-") + (moment == .warning ? "warning" : "zero")
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { return }
            player.play()
            self.player = player
            duration = player.duration
        }
        // Clears the preview button's Stop state when the sound ends on its own.
        finishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            self.previewing = nil
            self.playingZeroForTimer = false
            self.player = nil
            self.systemSound = nil
        }
    }
}
