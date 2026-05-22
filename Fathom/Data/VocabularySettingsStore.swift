import AVFoundation
import Foundation

// MARK: - VocabularySettingsStore
//
// User preferences for pronunciation: voice identifier, default language,
// and speech rate. Stored in UserDefaults (small, device-local) — these
// are device-specific (the user's preferred voice may not even be
// installed on another device), so they intentionally don't sync.

final class VocabularySettingsStore {
    static let shared = VocabularySettingsStore()

    static let didChangeNotification = Notification.Name("VocabularySettingsStore.didChange")

    private let defaults: UserDefaults
    private let voiceKey    = "fathom.vocab.voiceIdentifier"
    private let languageKey = "fathom.vocab.defaultLanguage"
    private let rateKey     = "fathom.vocab.rate"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Voice identifier
    //
    // `nil` = system default for the language. When set, must be a valid
    // AVSpeechSynthesisVoice.identifier.

    var voiceIdentifier: String? {
        get { defaults.string(forKey: voiceKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: voiceKey)
            } else {
                defaults.removeObject(forKey: voiceKey)
            }
            notifyChange()
        }
    }

    // MARK: - Default language

    /// BCP-47 language code, e.g. "en-US". Falls back to "en-US".
    var defaultLanguage: String {
        get { defaults.string(forKey: languageKey) ?? "en-US" }
        set {
            defaults.set(newValue, forKey: languageKey)
            notifyChange()
        }
    }

    // MARK: - Speech rate

    /// Range matches `AVSpeechUtterance` — 0.0 to 1.0. 0.5 ≈ natural speed.
    var rate: Float {
        get {
            let stored = defaults.float(forKey: rateKey)
            return stored == 0 ? AVSpeechUtteranceDefaultSpeechRate : stored
        }
        set {
            defaults.set(newValue, forKey: rateKey)
            notifyChange()
        }
    }

    // MARK: - Resolved voice

    /// Returns the saved AVSpeechSynthesisVoice if its identifier still
    /// resolves; otherwise falls back to the language-default voice.
    func resolvedVoice(forLanguage language: String? = nil) -> AVSpeechSynthesisVoice? {
        let lang = language ?? defaultLanguage
        if let id = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: id),
           voice.language.hasPrefix(String(lang.prefix(2))) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: lang)
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
