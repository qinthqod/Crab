import Foundation

public enum CrabLanguage: String, Equatable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static func resolve(preferredLanguages: [String]) -> CrabLanguage {
        guard let primary = preferredLanguages.first?.lowercased() else { return .english }
        return primary.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    public static var system: CrabLanguage {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    public func choose(chinese: String, english: String) -> String {
        switch self {
        case .simplifiedChinese: chinese
        case .english: english
        }
    }
}

public enum CrabLanguagePreference: String, CaseIterable, Equatable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let defaultsKey = "dev.crab.language-preference.v1"

    public init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    public func resolve(preferredLanguages: [String]) -> CrabLanguage {
        switch self {
        case .system:
            CrabLanguage.resolve(preferredLanguages: preferredLanguages)
        case .simplifiedChinese:
            .simplifiedChinese
        case .english:
            .english
        }
    }
}
