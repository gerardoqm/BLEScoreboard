import Foundation

/// The language the app uses: the phone's own, or one picked inside the app (saved on the phone, and sent to the watch).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", spanish = "es"
    
    static let storeKey = "appLanguage"
    
    var id: String { rawValue }
    
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storeKey) ?? "") ?? .system
    }
    
    /// For dates, ordinals ("2nd" / "2.º") and the SwiftUI environment.
    var locale: Locale { self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue) }
    
    /// "es" or "en", also when the language follows the phone.
    var code: String {
        self == .system ? (Locale.current.language.languageCode?.identifier == "es" ? "es" : "en") : rawValue
    }
    
    /// Where the strings come from. English is the source language, so its bundle is an empty one: a missing translation returns the English key.
    var bundle: Bundle {
        switch self {
        case .system: return .main
        case .spanish: return Bundle.main.path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        case .english: return Bundle(path: NSTemporaryDirectory()) ?? .main
        }
    }
}

/// A translated string in the app's language (use it instead of `String(localized:)`, which always follows the phone).
func tr(_ value: String.LocalizationValue, in language: AppLanguage = .current) -> String {
    String(localized: value, bundle: language.bundle)
}
