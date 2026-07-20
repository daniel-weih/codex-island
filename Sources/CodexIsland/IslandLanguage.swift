import Foundation

enum IslandLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case chinese
    case english

    var id: String { rawValue }

    static func stored(_ rawValue: String?) -> IslandLanguagePreference {
        rawValue.flatMap(IslandLanguagePreference.init(rawValue:)) ?? .automatic
    }
}

enum IslandInterfaceLanguage: String, Sendable {
    case chinese
    case english

    func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese: return chinese
        case .english: return english
        }
    }
}

enum IslandLanguageResolver {
    static func resolve(
        preference: IslandLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> IslandInterfaceLanguage {
        switch preference {
        case .chinese:
            return .chinese
        case .english:
            return .english
        case .automatic:
            return automaticLanguage(from: preferredLanguages)
        }
    }

    private static func automaticLanguage(
        from preferredLanguages: [String]
    ) -> IslandInterfaceLanguage {
        guard let identifier = preferredLanguages.first else { return .english }
        let languageCode = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased()

        switch languageCode {
        case "zh": return .chinese
        case "en": return .english
        default: return .english
        }
    }
}
