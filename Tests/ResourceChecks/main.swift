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
            require(TaskSoundPlayer.loadCompletionSound(using: resources) != nil,
                    "\(name): task completion sound initializes")
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
