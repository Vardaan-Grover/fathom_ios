import AVFoundation
import SwiftUI

// MARK: - VocabularySettingsScreen
//
// Lets the user pick a default pronunciation language and a specific
// voice from the system's installed AVSpeechSynthesisVoice list, and
// adjust the speech rate.

struct VocabularySettingsScreen: View {
    @State private var defaultLanguage: String = VocabularySettingsStore.shared.defaultLanguage
    @State private var voiceIdentifier: String? = VocabularySettingsStore.shared.voiceIdentifier
    @State private var rate: Float = VocabularySettingsStore.shared.rate
    @State private var showVoicePicker = false

    private let sampleText = "Hello — this is how words will sound."

    private var resolvedVoice: AVSpeechSynthesisVoice? {
        VocabularySettingsStore.shared.resolvedVoice(forLanguage: defaultLanguage)
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LanguagePickerScreen(selection: $defaultLanguage)
                } label: {
                    LabeledContent("Language") {
                        Text(LanguageNames.displayName(for: defaultLanguage))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showVoicePicker = true
                } label: {
                    HStack {
                        Text("Voice")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(resolvedVoice?.name ?? "System Default")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            } header: {
                SectionHeader("Voice")
            } footer: {
                Text("Used when speaking saved words and looked-up definitions.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(rateLabel)
                            .font(.system(size: 14, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "tortoise.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                        Slider(
                            value: $rate,
                            in: AVSpeechUtteranceMinimumSpeechRate ... AVSpeechUtteranceMaximumSpeechRate,
                            step: 0.05
                        )
                        Image(systemName: "hare.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                SectionHeader("Speed")
            }

            Section {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    PronunciationService.shared.speak(sampleText, language: defaultLanguage, rate: rate)
                } label: {
                    HStack {
                        Spacer()
                        Label("Preview", systemImage: "play.fill")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Pronunciation")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerSheet(
                language: defaultLanguage,
                selectedID: $voiceIdentifier
            )
        }
        .onChange(of: defaultLanguage) { _, newValue in
            VocabularySettingsStore.shared.defaultLanguage = newValue
            // If the selected voice no longer matches the new language,
            // clear it back to system default.
            if let id = voiceIdentifier,
               let voice = AVSpeechSynthesisVoice(identifier: id),
               !voice.language.hasPrefix(String(newValue.prefix(2))) {
                voiceIdentifier = nil
                VocabularySettingsStore.shared.voiceIdentifier = nil
            }
        }
        .onChange(of: voiceIdentifier) { _, newValue in
            VocabularySettingsStore.shared.voiceIdentifier = newValue
        }
        .onChange(of: rate) { _, newValue in
            VocabularySettingsStore.shared.rate = newValue
        }
    }

    private var rateLabel: String {
        let normalized = (rate - AVSpeechUtteranceMinimumSpeechRate)
            / (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        return "\(Int(normalized * 100))%"
    }
}

// MARK: - LanguagePickerScreen

private struct LanguagePickerScreen: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    private var languages: [String] {
        let codes = Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))
        return codes.sorted { LanguageNames.displayName(for: $0).localizedCaseInsensitiveCompare(LanguageNames.displayName(for: $1)) == .orderedAscending }
    }

    var body: some View {
        List(languages, id: \.self) { code in
            HStack {
                Text(LanguageNames.displayName(for: code))
                    .foregroundStyle(.primary)
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selection = code
                UISelectionFeedbackGenerator().selectionChanged()
                dismiss()
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LanguageNames

enum LanguageNames {
    static func displayName(for bcp47: String) -> String {
        let locale = Locale.current
        if let name = locale.localizedString(forIdentifier: bcp47) {
            return name
        }
        return bcp47
    }
}
