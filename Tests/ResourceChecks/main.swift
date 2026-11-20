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
            let card = CodexCreditConfiguration.load(resources: resources)
            require(card?.rate(for: "gpt-6.1-terra")?.cachedInput == 1.25,
                    "\(name): loads the bundled Terra rate without build-machine paths")
            require(card?.fastPolicy(for: "gpt-6.1-terra")?.includedSubscription == 2.5
                    && card?.fastPolicy(for: "gpt-6.1-terra")?.purchasedCredits == 2,
                    "\(name): subscription and purchased-credit multipliers remain separate")
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
            let sounds = TaskSoundPlayer.loadCompletionSounds(using: resources)
            require(sounds.map(\.duration) == [
                resources.sound(named: "TaskCompletion8Bit", withExtension: "wav")?.duration,
                resources.sound(named: "TaskCompletion", withExtension: "mp3")?.duration
            ].compactMap { $0 }, "\(name): preferred WAV plays before the fallback MP3")
        }

        let absent = try fixture("no-bundle", location: nil)
        require(CodexCreditConfiguration.load(resources: absent) == nil,
                "missing configuration leaves usage unpriced without trapping")
        for (name, corrupt, missing) in [
            ("corrupt-card", ["CodexCreditRates.json"], []),
            ("missing-card", [], ["CodexCreditRates.json"])
        ] {
            let resources = try fixture(name, corrupt: corrupt, missing: missing)
            require(CodexCreditConfiguration.load(resources: resources) == nil,
                    "\(name): invalid or missing rate data never invents zero consumption")
            require(resources.image(named: "AlibabaLogo") != nil,
                    "\(name): invalid rate data does not prevent UI resources loading")
        }

        let original = try Data(contentsOf: source.appendingPathComponent("CodexCreditRates.json"))
        let json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        func rejects(_ label: String, _ mutate: (inout [String: Any]) -> Void) throws {
            var candidate = json
            mutate(&candidate)
            let data = try JSONSerialization.data(withJSONObject: candidate)
            require((try? CodexCreditConfiguration.decode(data)) == nil, label)
        }
        try rejects("unsupported schema rejected") { $0["schemaVersion"] = 2 }
        try rejects("wrong currency or units rejected") { $0["unit"] = "usd_per_million_tokens" }
        try rejects("missing model prices rejected") { $0.removeValue(forKey: "models") }
        try rejects("invalid verification date rejected") { $0["revision"] = "2026-02-30" }
        try rejects("missing sources rejected") { $0["sources"] = [] }
        try rejects("duplicate model prices rejected") { card in
            var models = card["models"] as! [[String: Any]]
            models.append(models[0])
            card["models"] = models
        }
        for invalidRate in [-1.0, 0.0, 999_999.0] {
            try rejects("invalid cached-input price rejected: \(invalidRate)") { card in
                var models = card["models"] as! [[String: Any]]
                var rate = models[0]["rate"] as! [String: Any]
                rate["cachedInput"] = invalidRate
                models[0]["rate"] = rate
                card["models"] = models
            }
        }
        try rejects("invalid speed multiplier rejected") { card in
            var policies = card["fastPolicies"] as! [[String: Any]]
            policies[0]["includedSubscription"] = 0
            card["fastPolicies"] = policies
        }
        try rejects("duplicate speed policies rejected") { card in
            var policies = card["fastPolicies"] as! [[String: Any]]
            policies.append(policies[0])
            card["fastPolicies"] = policies
        }
        // Prove a newly configured model works without changing a Swift table.
        var extended = json
        var models = extended["models"] as! [[String: Any]]
        models.append(["id": "fixture-model", "verifiedOn": "2026-10-27",
                       "rate": ["input": 20, "cachedInput": 2, "output": 100]])
        extended["models"] = models
        var policies = extended["fastPolicies"] as! [[String: Any]]
        policies.append(["family": "fixture-model", "verifiedOn": "2026-10-27",
                         "includedSubscription": 3, "purchasedCredits": 2])
        extended["fastPolicies"] = policies
        let extendedCard = try CodexCreditConfiguration.decode(JSONSerialization.data(withJSONObject: extended))
        require(extendedCard.rate(for: " openai/FIXTURE-MODEL-2026-10-27 ")?.output == 100
                && extendedCard.fastPolicy(for: "fixture-model")?.includedSubscription == 3,
                "new models and multipliers are loaded solely from configuration")
        require(extendedCard.rate(for: "fixture-model-mini") == nil,
                "undocumented variants do not inherit a family's configured price")
        require(absent.image(named: "AlibabaLogo") == nil, "missing bundle omits the watermark")
        require(TaskSoundPlayer.loadCompletionSounds(using: absent).isEmpty,
                "missing bundle leaves completion playback silent")
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
            let sounds = TaskSoundPlayer.loadCompletionSounds(using: resources)
            require(sounds.count == 1, "\(name) preferred sound falls back to the MP3")
            require(sounds.first?.duration == resources.sound(named: "TaskCompletion", withExtension: "mp3")?.duration,
                    "\(name) preferred sound uses the working fallback")
            require(resources.image(named: "TencentLogoReverse") != nil,
                    "\(name) asset does not prevent other resources from loading")
        }

        let brokenSounds = try fixture("all-sounds-corrupt", corrupt: [
            "TaskCompletion8Bit.wav", "TaskCompletion.mp3", "TaskApprovalAlert.wav"
        ])
        require(TaskSoundPlayer.loadCompletionSounds(using: brokenSounds).isEmpty,
                "corrupt completion sounds leave completion playback silent")

        let sounds = TaskSoundPlayer.loadCompletionSounds(using: try fixture("playback"))
        require(sounds.count == 2, "playback fixture has both completion sounds")
        let outputID = "fixture-output-device"
        var gains: [Float] = []
        let played = TaskSoundPlayer.playCompletion(sounds, volume: 0.2, playback: { limit in
            require(limit == 0.2, "the saved cap is passed to the output volume calculation")
            return .init(deviceIdentifier: outputID, gain: 0.15)
        }) { sound in
            require(sound.playbackDeviceIdentifier == outputID, "both sounds use the device that was calibrated")
            gains.append(sound.volume)
            return sound === sounds[1]
        }
        require(played && gains == [0.15, 0.15],
                "both WAV and MP3 attempts use the gain calculated for the current output")

        gains.removeAll()
        TaskSoundPlayer.playCompletion(sounds, volume: 1, playback: { _ in
            .init(deviceIdentifier: outputID, gain: 1)
        }) { sound in
            gains.append(sound.volume)
            return true
        }
        require(gains == [1],
                "the preferred sound plays without attenuation with a 100% cap")

        for volume in [0, -0.1] {
            let played = TaskSoundPlayer.playCompletion(sounds, volume: volume, start: { _ in
                fail("zero or lower gains must skip playback")
            })
            require(!played, "muted preview reports no playback")
        }
        require(TaskSoundPlayer.clampedCompletionVolume(1.2) == 1, "gain above 100% is clamped")
        require(TaskSoundPlayer.clampedCompletionVolume(.nan) == 0.2, "invalid gain uses the 20% default")

        let skipped = TaskSoundPlayer.playCompletion(sounds, volume: 0.2, playback: { _ in nil }) { _ in
            fail("playback must stop when the device cannot verify safe attenuation")
        }
        require(!skipped, "an unavailable output is reported to the preview")
        let failed = TaskSoundPlayer.playCompletion(sounds, volume: 0.2, playback: { _ in
            .init(deviceIdentifier: outputID, gain: 0.15)
        }) { _ in false }
        require(!failed, "the preview reports failure if neither sound starts")
        require(CompletionSoundOutputVolume.cappedGain(limit: 0.2, systemVolume: nil) { nil } == 0,
                "an unknown system volume cannot establish a low cap")
        require(CompletionSoundOutputVolume.cappedGain(limit: 0.2, systemVolume: 0.5) { nil } == 0,
                "output above the cap requires verified attenuation")
        require(CompletionSoundOutputVolume.cappedGain(limit: 0.2, systemVolume: 0.1) { nil } == 1,
                "output below the cap keeps its system volume without attenuation")
        require(CompletionSoundOutputVolume.cappedGain(limit: 1, systemVolume: nil) { nil } == 1,
                "the 100% cap allows playback when the device has no readable volume")

        let minimumDB: Float = -50
        let maximumDB: Float = 10
        func referenceDB(_ scalar: Float) -> Float {
            minimumDB + (maximumDB - minimumDB) * sqrt(scalar)
        }
        func referenceVolume(_ db: Float) -> Float {
            let position = max(0, (db - minimumDB) / (maximumDB - minimumDB))
            return position * position
        }
        let expectations: [(system: Float, limit: Float, effective: Float)] = [
            (0, 0.20, 0), (0.005, 0.20, 0.005), (0.01, 0.20, 0.01),
            (0.02, 0.20, 0.02), (0.19, 0.20, 0.19), (0.20, 0.20, 0.20),
            (0.50, 0.20, 0.20), (1.00, 0.20, 0.20),
            (0.50, 0, 0), (0.50, 1.00, 0.50),
            (0.20, 0.50, 0.20), (0.80, 0.50, 0.50), (0.50, 0.01, 0.01),
        ]
        for (system, limit, expected) in expectations {
            let currentDB = referenceDB(system)
            let gain = CompletionSoundOutputVolume.cappedGain(limit: limit, systemVolume: system) {
                require(system > limit, "only system volumes above the cap need conversion")
                guard let targetDB = CompletionSoundOutputVolume.decibelsAtLimit(
                    limit, currentScalar: system, currentDB: currentDB,
                    minimumDB: minimumDB, scalarAtDecibels: referenceVolume
                ) else { fail("expected a dB target for system volume \(system)") }
                return CompletionSoundOutputVolume.gain(targetDB: targetDB, currentDB: currentDB)
            }
            let effective = gain == 0 ? 0 : referenceVolume(currentDB + 20 * log10(gain))
            require(abs(effective - expected) < 0.00001,
                    "system volume \(system) and cap \(limit) map to \(expected)")
        }
        require(CompletionSoundOutputVolume.decibelsAtLimit(
            0.20, currentScalar: 0.5, currentDB: -20, minimumDB: minimumDB,
            scalarAtDecibels: referenceVolume
        ) == nil, "a device curve that disagrees with the live volume is rejected")

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
