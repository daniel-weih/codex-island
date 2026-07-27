import AppKit
import Combine
import CoreGraphics
import Foundation

enum IslandDisplayTargetPreference: Hashable, Sendable {
    case automatic
    case builtIn
    case external(identifier: String)

    static let defaultsKey = "codexIsland.displayTarget"

    static func stored(_ rawValue: String?) -> IslandDisplayTargetPreference {
        guard let rawValue else { return .automatic }
        switch rawValue {
        case "automatic":
            return .automatic
        case "built-in":
            return .builtIn
        default:
            let prefix = "external:"
            guard rawValue.hasPrefix(prefix) else { return .automatic }
            let identifier = String(rawValue.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return identifier.isEmpty ? .automatic : .external(identifier: identifier)
        }
    }

    var storedValue: String {
        switch self {
        case .automatic:
            return "automatic"
        case .builtIn:
            return "built-in"
        case .external(let identifier):
            return "external:\(identifier)"
        }
    }
}

struct IslandDisplayDescriptor: Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let isBuiltIn: Bool
    let sortIndex: Int

    var id: String { identifier }
}

struct IslandDisplayChoice: Hashable, Identifiable, Sendable {
    let target: IslandDisplayTargetPreference
    let display: IslandDisplayDescriptor?
    let duplicateIndex: Int?
    let isAvailable: Bool

    var id: String { target.storedValue }
}

enum IslandDisplayChoiceBuilder {
    static func makeChoices(
        displays: [IslandDisplayDescriptor],
        selection: IslandDisplayTargetPreference
    ) -> [IslandDisplayChoice] {
        let ordered = displays.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            return $0.identifier < $1.identifier
        }
        var choices = [
            IslandDisplayChoice(
                target: .automatic,
                display: nil,
                duplicateIndex: nil,
                isAvailable: true
            )
        ]

        let builtIn = ordered.first(where: \.isBuiltIn)
        if let builtIn {
            choices.append(
                IslandDisplayChoice(
                    target: .builtIn,
                    display: builtIn,
                    duplicateIndex: nil,
                    isAvailable: true
                )
            )
        } else if selection == .builtIn {
            choices.append(
                IslandDisplayChoice(
                    target: .builtIn,
                    display: nil,
                    duplicateIndex: nil,
                    isAvailable: false
                )
            )
        }

        let externalDisplays = ordered.filter { !$0.isBuiltIn }
        let duplicateCounts = Dictionary(
            grouping: externalDisplays,
            by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        ).mapValues(\.count)
        var occurrenceByName: [String: Int] = [:]

        for display in externalDisplays {
            let normalizedName = display.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let occurrence = (occurrenceByName[normalizedName] ?? 0) + 1
            occurrenceByName[normalizedName] = occurrence
            choices.append(
                IslandDisplayChoice(
                    target: .external(identifier: display.identifier),
                    display: display,
                    duplicateIndex: duplicateCounts[normalizedName, default: 0] > 1
                        ? occurrence
                        : nil,
                    isAvailable: true
                )
            )
        }

        if case .external(let identifier) = selection,
           !externalDisplays.contains(where: { $0.identifier == identifier }) {
            choices.append(
                IslandDisplayChoice(
                    target: selection,
                    display: nil,
                    duplicateIndex: nil,
                    isAvailable: false
                )
            )
        }

        return choices
    }
}

enum IslandDisplaySelectionResolver {
    static func resolveIdentifier(
        preference: IslandDisplayTargetPreference,
        displays: [IslandDisplayDescriptor],
        automaticIdentifier: String?
    ) -> String? {
        let fallbackIdentifier: String? = {
            if let automaticIdentifier,
               displays.contains(where: { $0.identifier == automaticIdentifier }) {
                return automaticIdentifier
            }
            return displays.sorted { $0.sortIndex < $1.sortIndex }.first?.identifier
        }()

        switch preference {
        case .automatic:
            return fallbackIdentifier
        case .builtIn:
            return displays.first(where: \.isBuiltIn)?.identifier
                ?? fallbackIdentifier
        case .external(let identifier):
            return displays.first(where: { $0.identifier == identifier })?.identifier
                ?? fallbackIdentifier
        }
    }
}

@MainActor
final class IslandDisplaySelectionModel: ObservableObject {
    @Published var preference: IslandDisplayTargetPreference {
        didSet {
            guard preference != oldValue else { return }
            defaults?.set(
                preference.storedValue,
                forKey: IslandDisplayTargetPreference.defaultsKey
            )
            onPreferenceChange?()
        }
    }
    @Published private(set) var displays: [IslandDisplayDescriptor]

    var onPreferenceChange: (() -> Void)?

    private let defaults: UserDefaults?
    private var screensByIdentifier: [String: NSScreen]

    init(
        defaults: UserDefaults? = .standard,
        screens: [NSScreen] = NSScreen.screens,
        initialPreference: IslandDisplayTargetPreference? = nil
    ) {
        let records = Self.screenRecords(from: screens)
        self.defaults = defaults
        self.preference = initialPreference
            ?? IslandDisplayTargetPreference.stored(
                defaults?.string(forKey: IslandDisplayTargetPreference.defaultsKey)
            )
        self.displays = records.map(\.descriptor)
        self.screensByIdentifier = Dictionary(
            uniqueKeysWithValues: records.map { ($0.descriptor.identifier, $0.screen) }
        )
    }

    init(
        initialPreference: IslandDisplayTargetPreference,
        previewDisplays: [IslandDisplayDescriptor]
    ) {
        defaults = nil
        preference = initialPreference
        displays = previewDisplays
        screensByIdentifier = [:]
    }

    var choices: [IslandDisplayChoice] {
        IslandDisplayChoiceBuilder.makeChoices(
            displays: displays,
            selection: preference
        )
    }

    func refresh(screens: [NSScreen] = NSScreen.screens) {
        let records = Self.screenRecords(from: screens)
        screensByIdentifier = Dictionary(
            uniqueKeysWithValues: records.map { ($0.descriptor.identifier, $0.screen) }
        )
        let updatedDisplays = records.map(\.descriptor)
        guard updatedDisplays != displays else { return }
        displays = updatedDisplays
    }

    func resolveScreen(
        in screens: [NSScreen] = NSScreen.screens,
        automaticScreen: NSScreen?
    ) -> NSScreen? {
        let automaticIdentifier = automaticScreen.flatMap { automatic in
            screensByIdentifier.first(where: { $0.value === automatic })?.key
                ?? Self.identifier(for: automatic)
        }
        guard let resolvedIdentifier = IslandDisplaySelectionResolver.resolveIdentifier(
            preference: preference,
            displays: displays,
            automaticIdentifier: automaticIdentifier
        ) else {
            return automaticScreen ?? screens.first
        }
        return screensByIdentifier[resolvedIdentifier]
            ?? automaticScreen
            ?? screens.first
    }

    private struct ScreenRecord {
        let screen: NSScreen
        let descriptor: IslandDisplayDescriptor
    }

    private static func screenRecords(from screens: [NSScreen]) -> [ScreenRecord] {
        screens.enumerated().compactMap { index, screen in
            guard let identifier = identifier(for: screen),
                  let displayID = displayID(for: screen) else {
                return nil
            }
            return ScreenRecord(
                screen: screen,
                descriptor: IslandDisplayDescriptor(
                    identifier: identifier,
                    name: screen.localizedName,
                    isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                    sortIndex: index
                )
            )
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func identifier(for screen: NSScreen) -> String? {
        guard let displayID = displayID(for: screen),
              let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}
