import Foundation

/// Runs before app startup: no services, account requests, UI, or sound playback.
@MainActor
enum CodexResourceProbe {
    static func run() -> Int32 {
        var missing: [String] = []
        let resources = AppResources.shared
        for theme in IslandColorTheme.allCases {
            if let name = theme.watermarkResourceName, resources.image(named: name) == nil {
                missing.append("\(name).png")
            }
        }
        for (name, extensionName) in [
            ("TaskCompletion8Bit", "wav"),
            ("TaskCompletion", "mp3"),
            ("TaskApprovalAlert", "wav")
        ] {
            if resources.sound(named: name, withExtension: extensionName) == nil {
                missing.append("\(name).\(extensionName)")
            }
        }
        // Exercise the same lazy initialization that runs on a thread change.
        if TaskSoundPlayer.completionSound == nil { missing.append("completion sound") }
        if TaskSoundPlayer.approvalSound == nil { missing.append("approval sound") }
        guard missing.isEmpty else {
            fputs("Missing or invalid app resources: \(missing.joined(separator: ", "))\n", stderr)
            return EXIT_FAILURE
        }
        print("All app resource checks passed")
        return EXIT_SUCCESS
    }
}
