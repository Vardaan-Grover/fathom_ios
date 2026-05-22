import AVFoundation
import Foundation

@MainActor
final class PronunciationService {
    static let shared = PronunciationService()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// Speak the given text. If `language` is provided, prefers a voice in
    /// that language; otherwise uses the user's default language from
    /// `VocabularySettingsStore`.
    ///
    /// `rate` overrides the stored rate when supplied.
    func speak(_ text: String, language: String? = nil, rate: Float? = nil) {
        let store = VocabularySettingsStore.shared
        let effectiveLang = language ?? store.defaultLanguage

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = store.resolvedVoice(forLanguage: effectiveLang)
        utterance.rate  = rate ?? store.rate

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
