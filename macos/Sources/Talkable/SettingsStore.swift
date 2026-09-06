import Foundation
import Carbon.HIToolbox
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let hotkeyKeyCode = UInt32(kVK_RightCommand)

    @Published var localeID: String {
        didSet { UserDefaults.standard.set(localeID, forKey: "localeID") }
    }
    @Published var onDeviceOnly: Bool {
        didSet { UserDefaults.standard.set(onDeviceOnly, forKey: "onDeviceOnly") }
    }
    @Published var sound: Bool {
        didSet { UserDefaults.standard.set(sound, forKey: "sound") }
    }
    @Published var punctuation: Bool {
        didSet { UserDefaults.standard.set(punctuation, forKey: "punctuation") }
    }
    @Published var polishWithAI: Bool {
        didSet { UserDefaults.standard.set(polishWithAI, forKey: "polishWithAI") }
    }

    private init() {
        let d = UserDefaults.standard
        let system = Locale.current.identifier.replacingOccurrences(of: "-", with: "_")
        localeID = d.string(forKey: "localeID") ?? Self.fallbackLocaleID(forSystem: system)
        onDeviceOnly = d.object(forKey: "onDeviceOnly") as? Bool ?? true
        sound = d.object(forKey: "sound") as? Bool ?? true
        punctuation = d.object(forKey: "punctuation") as? Bool ?? true
        polishWithAI = d.object(forKey: "polishWithAI") as? Bool ?? false
    }

    /// Picks the default dictation language from the system locale, or US
    /// English when the system language isn't supported.
    static func fallbackLocaleID(forSystem system: String) -> String {
        let supported = ["en", "es", "fr", "pt", "it"]
        return supported.contains(where: system.hasPrefix) ? system : "en_US"
    }

    static let languages: [(id: String, name: String)] = [
        ("en_US", "English (US)"),
        ("es_AR", "Spanish (Argentina)"),
        ("es_ES", "Spanish (Spain)"),
        ("es_MX", "Spanish (Mexico)"),
        ("es_CO", "Spanish (Colombia)"),
        ("es_CL", "Spanish (Chile)"),
        ("pt_BR", "Portuguese (Brazil)"),
        ("fr_FR", "French (France)"),
        ("it_IT", "Italian (Italy)"),
    ]
}
