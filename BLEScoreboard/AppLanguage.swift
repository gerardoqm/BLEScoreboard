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

/// The ordinal of a period as the scoreboard says it: "1st", "2nd", "3rd", "4th" in English and
/// "1er", "2do", "3er", "4to", "5to", "6to", "7mo", "8vo", "9no" in Spanish (the unit names, "tiempo", "periodo" and "cuarto", are masculine).
func ordinal(_ number: Int, in language: AppLanguage = .current) -> String {
    if language.code == "es" {
        let forms = [1: "1er", 2: "2do", 3: "3er", 4: "4to", 5: "5to", 6: "6to", 7: "7mo", 8: "8vo", 9: "9no", 10: "10mo"]
        return forms[number] ?? "\(number).º"
    }
    let suffix: String
    switch (number % 100, number % 10) {
    case (11...13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(number)\(suffix)"
}
