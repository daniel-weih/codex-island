import AppKit
import Foundation

/// Optional UI assets must never use SwiftPM's trapping Bundle.module accessor.
/// Resolve only relative to the running app/executable, never a build-machine path.
struct AppResources {
    static let bundleName = "CodexIsland_CodexIsland.bundle"
    static let shared = AppResources()

    private let bundles: [Bundle]

    init(bundle: Bundle = .main) {
        let directories = [
            bundle.resourceURL,
            bundle.bundleURL,
            bundle.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }
        var seen = Set<URL>()
        bundles = directories.compactMap { directory in
            let url = directory.appendingPathComponent(Self.bundleName).standardizedFileURL
            guard seen.insert(url).inserted else { return nil }
            return Bundle(url: url)
        }
    }

    @MainActor
    func image(named name: String) -> NSImage? {
        for bundle in bundles {
            guard let url = bundle.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url), image.isValid else { continue }
            return image
        }
        return nil
    }

    @MainActor
    func sound(named name: String, withExtension extensionName: String) -> NSSound? {
        for bundle in bundles {
            guard let url = bundle.url(forResource: name, withExtension: extensionName),
                  let sound = NSSound(contentsOf: url, byReference: false),
                  sound.duration > 0 else { continue }
            return sound
        }
        return nil
    }
}
