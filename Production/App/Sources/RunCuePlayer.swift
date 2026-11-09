import AVFoundation
import UIKit

@MainActor
final class RunCuePlayer: NSObject, AVAudioPlayerDelegate {
    enum Cue: String {
        case warmUp = "warm_up", run, walk, coolDown = "cool_down"
        case sessionComplete = "session_complete", pause, resume
        case freeRunStart = "free_run_start", runSaved = "run_saved", weekCompleted = "week_completed"

        var firstTrack: Int {
            switch self {
            case .warmUp: 1
            case .run: 5
            case .walk: 9
            case .coolDown: 13
            case .sessionComplete: 17
            case .pause: 21
            case .resume: 25
            case .freeRunStart: 29
            case .runSaved: 33
            case .weekCompleted: 37
            }
        }
    }

    private var player: AVAudioPlayer?
    private let defaults = UserDefaults.standard
    private var followUp: Cue?

    func play(_ cue: Cue, voice: Bool, haptics: Bool, followedBy nextCue: Cue? = nil) {
        guard voice || (haptics && UIApplication.shared.applicationState == .active) else { return }
        if haptics && UIApplication.shared.applicationState == .active {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        guard voice else { return }
        stop()
        followUp = nextCue
        let key = "runCues.rotation.\(cue.rawValue)"
        let index = defaults.integer(forKey: key) % 4
        let filename = String(format: "%02d-%@", cue.firstTrack + index, cue.rawValue)
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
            print("Missing run cue: \(filename)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            player = audio
            if audio.play() { defaults.set((index + 1) % 4, forKey: key) }
            else { player = nil; deactivate() }
        } catch {
            player = nil
            deactivate()
            print("Could not play run cue: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        followUp = nil
        deactivate()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
            self.deactivate()
            if let next = self.followUp {
                self.followUp = nil
                self.play(next, voice: true, haptics: false)
            }
        }
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
