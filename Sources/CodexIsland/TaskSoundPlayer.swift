import AppKit

@MainActor
enum TaskSoundPlayer {
    static let completionSound = loadCompletionSound(using: .shared)
    static let approvalSound = AppResources.shared.sound(
        named: "TaskApprovalAlert", withExtension: "wav"
    )

    static func loadCompletionSound(using resources: AppResources) -> NSSound? {
        // A corrupt preferred sound should also fall back to the older sound.
        resources.sound(named: "TaskCompletion8Bit", withExtension: "wav")
            ?? resources.sound(named: "TaskCompletion", withExtension: "mp3")
    }

    static func playCompletion() {
        play(completionSound)
    }

    static func playApproval() {
        play(approvalSound)
    }

    private static func play(_ sound: NSSound?) {
        sound?.stop()
        if sound?.play() != true {
            NSSound.beep()
        }
    }
}
