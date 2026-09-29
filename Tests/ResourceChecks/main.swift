import AppKit
import Foundation

@main
struct ResourceChecks {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fail("expected source resources directory") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-island-resource-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func fixture(
            _ name: String,
            location: String? = "Contents/Resources",
            structuredBundle: Bool = false,
            corrupt: [String] = [],
            missing: [String] = []
        ) throws -> AppResources {
            let app = root.appendingPathComponent("\(name).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(
                at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true
            )
            let plist: [String: String] = [
                "CFBundleIdentifier": "com.codexisland.resource-checks.\(name)",
                "CFBundleExecutable": "Fixture",
                "CFBundlePackageType": "APPL"
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try Data().write(to: contents.appendingPathComponent("MacOS/Fixture"))

            if let location {
                let bundleURL = app.appendingPathComponent(location)
                    .appendingPathComponent(AppResources.bundleName)
                let assets = structuredBundle
                    ? bundleURL.appendingPathComponent("Contents/Resources") : bundleURL
                try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                if structuredBundle {
                    let resourcePlist = ["CFBundlePackageType": "BNDL"]
                    try PropertyListSerialization.data(
                        fromPropertyList: resourcePlist, format: .xml, options: 0
                    ).write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
                }
                for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    let name = file.lastPathComponent
                    guard !missing.contains(name) else { continue }
                    let destination = assets.appendingPathComponent(name)
                    if corrupt.contains(name) {
                        try Data("not a valid media file".utf8).write(to: destination)
                    } else {
                        try FileManager.default.copyItem(at: file, to: destination)
                    }
                }
            }
            guard let bundle = Bundle(url: app) else { fail("fixture is an app bundle") }
            return AppResources(bundle: bundle)
        }

        // These apps are outside the checkout and have no compiled-in build path.
        for (name, location, structured) in [
            ("installed", "Contents/Resources", false),
            ("swift-build-bundle", "Contents/Resources", true),
            ("app-root", "", false),
            ("executable-sibling", "Contents/MacOS", false)
        ] {
            let resources = try fixture(name, location: location, structuredBundle: structured)
            for theme in IslandColorTheme.allCases {
                if let asset = theme.watermarkResourceName {
                    require(resources.image(named: asset) != nil, "\(name): decodes \(asset)")
                }
            }
            require(resources.sound(named: "TaskCompletion8Bit", withExtension: "wav") != nil,
                    "\(name): decodes completion WAV")
            require(resources.sound(named: "TaskCompletion", withExtension: "mp3") != nil,
                    "\(name): decodes fallback MP3")
            require(resources.sound(named: "TaskApprovalAlert", withExtension: "wav") != nil,
                    "\(name): decodes approval WAV")
            require(TaskSoundPlayer.loadCompletionSound(using: resources) != nil,
                    "\(name): task completion sound initializes")
        }

        let absent = try fixture("no-bundle", location: nil)
        require(absent.image(named: "AlibabaLogo") == nil, "missing bundle omits the watermark")
        require(TaskSoundPlayer.loadCompletionSound(using: absent) == nil,
                "missing bundle safely selects the system sound fallback")
        require(absent.sound(named: "TaskApprovalAlert", withExtension: "wav") == nil,
                "missing bundle safely handles approval sound initialization")

        for (name, corrupt, missing) in [
            ("corrupt", ["TaskCompletion8Bit.wav", "TaskApprovalAlert.wav", "AlibabaLogo.png"], []),
            ("missing", [], ["TaskCompletion8Bit.wav", "TaskApprovalAlert.wav", "AlibabaLogo.png"])
        ] {
            let resources = try fixture(name, corrupt: corrupt, missing: missing)
            require(resources.image(named: "AlibabaLogo") == nil, "\(name) image is optional")
            require(resources.sound(named: "TaskCompletion8Bit", withExtension: "wav") == nil,
                    "\(name) preferred sound is rejected")
            require(resources.sound(named: "TaskApprovalAlert", withExtension: "wav") == nil,
                    "\(name) approval sound is optional")
            let fallback = TaskSoundPlayer.loadCompletionSound(using: resources)
            require(fallback != nil, "\(name) preferred sound falls back to the MP3")
            require(fallback?.duration == resources.sound(named: "TaskCompletion", withExtension: "mp3")?.duration,
                    "\(name) preferred sound uses the working fallback")
            require(resources.image(named: "TencentLogoReverse") != nil,
                    "\(name) asset does not prevent other resources from loading")
        }

        let brokenSounds = try fixture("all-sounds-corrupt", corrupt: [
            "TaskCompletion8Bit.wav", "TaskCompletion.mp3", "TaskApprovalAlert.wav"
        ])
        require(TaskSoundPlayer.loadCompletionSound(using: brokenSounds) == nil,
                "all invalid completion sounds safely select the system sound fallback")
        print("All resource checks passed (relocated apps, both bundle layouts, absent and corrupt assets)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
