import Foundation

/// Interface strings live in Localization/<code>.json (copied into the app's
/// Resources). English is the reference and the fallback for missing keys.
/// The "language" setting is "system" (follow macOS, including the per-app
/// language in System Settings) or a language code.
enum L10n {
    static let languageKey = "language"
    static let system = "system"

    /// The 24 official languages of the European Union, by language code.
    static let supported = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "ga", "hr",
        "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "sk", "sl", "sv",
    ]

    /// Languages that have a strings file in the app bundle.
    static let available: [String] = supported.filter { url(for: $0) != nil }

    /// The language in use: the chosen one, or the first of the user's
    /// preferred macOS languages that the app has, or English.
    static var language: String {
        let choice = UserDefaults.standard.string(forKey: languageKey) ?? system
        if choice != system, available.contains(choice) { return choice }
        for id in Locale.preferredLanguages {
            if let code = Locale(identifier: id).language.languageCode?.identifier,
               available.contains(code) {
                return code
            }
        }
        return "en"
    }

    /// Name of a language in that language, e.g. "Deutsch".
    static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func t(_ key: String, _ args: [Any] = []) -> String {
        var s = table(language)[key] ?? table("en")[key] ?? key
        for (i, a) in args.enumerated() {
            s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)")
        }
        return s
    }

    static func error(_ e: EngineError) -> String {
        let key = "err." + e.code
        if table("en")[key] != nil { return t(key, e.args) }
        return t("err.generic", [e.raw])
    }

    // MARK: Loading

    nonisolated(unsafe) private static var cache: [String: [String: String]] = [:]
    private static let lock = NSLock()

    private static func url(for code: String) -> URL? {
        Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Localization")
    }

    private static func table(_ code: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let t = cache[code] { return t }
        var t: [String: String] = [:]
        if let u = url(for: code), let data = try? Data(contentsOf: u),
           let d = try? JSONDecoder().decode([String: String].self, from: data) {
            t = d
        }
        cache[code] = t
        return t
    }
}

/// Shorthand used by the views.
func L(_ key: String, _ args: Any...) -> String { L10n.t(key, args) }
