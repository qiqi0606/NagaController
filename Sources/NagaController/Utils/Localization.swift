import Foundation

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let translation = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return translation }
        return String(format: translation, locale: Locale.current, arguments: arguments)
    }
}
