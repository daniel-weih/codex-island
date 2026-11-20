import AppKit

@MainActor
enum TaskSoundPlayer {
    nonisolated static let completionVolumeKey = "codexIsland.completionSoundVolume"
    nonisolated static let defaultCompletionVolume = 0.20
    nonisolated static let completionVolumeRange = 0.0 ... 1.0

    static let completionSounds = loadCompletionSounds(using: .shared)
    static let approvalSound = AppResources.shared.sound(
        named: "TaskApprovalAlert", withExtension: "wav"
    )

    nonisolated static func clampedCompletionVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return defaultCompletionVolume }
        return min(max(volume, completionVolumeRange.lowerBound), completionVolumeRange.upperBound)
    }

    static func loadCompletionSounds(using resources: AppResources) -> [NSSound] {
        [
            resources.sound(named: "TaskCompletion8Bit", withExtension: "wav"),
            resources.sound(named: "TaskCompletion", withExtension: "mp3")
        ].compactMap { $0 }
    }

    @discardableResult
    static func playCompletion(volume: Double) -> Bool {
        playCompletion(completionSounds, volume: volume)
    }

    static func stopCompletion() {
        for sound in completionSounds { sound.stop() }
    }

    @discardableResult
    static func playCompletion(
        _ sounds: [NSSound],
        volume: Double,
        playback: (Float) -> CompletionSoundOutputVolume.Playback? = CompletionSoundOutputVolume.playback,
        start: (NSSound) -> Bool = { $0.play() }
    ) -> Bool {
        for sound in sounds { sound.stop() }
        let limit = Float(clampedCompletionVolume(volume))
        guard limit > 0, !sounds.isEmpty, let output = playback(limit) else { return false }

        for sound in sounds {
            sound.playbackDeviceIdentifier = output.deviceIdentifier
            sound.volume = output.gain
            if start(sound) { return true }
        }
        return false
    }

    static func playApproval() {
        approvalSound?.stop()
        if approvalSound?.play() != true {
            NSSound.beep()
        }
    }
}
