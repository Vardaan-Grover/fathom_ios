import AVFoundation
import SwiftUI

// MARK: - VoicePickerSheet
//
// Sheet listing all installed AVSpeechSynthesisVoice voices for the
// selected language, with a play button to preview each one.

struct VoicePickerSheet: View {
    let language: String
    @Binding var selectedID: String?

    @Environment(\.dismiss) private var dismiss

    @State private var voices: [AVSpeechSynthesisVoice] = []

    private var langPrefix: String { String(language.prefix(2)).lowercased() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System Default")
                            Text("Use the device-default voice")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedID = nil
                    }
                }

                if !groupedVoices.isEmpty {
                    ForEach(groupedVoices, id: \.0) { group in
                        Section(header: Text(group.0)) {
                            ForEach(group.1, id: \.identifier) { voice in
                                voiceRow(voice)
                            }
                        }
                    }
                }
            }
            .navigationTitle(LanguageNames.displayName(for: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.lowercased().hasPrefix(langPrefix) }
        }
    }

    // MARK: - Grouped voices
    //
    // Group by quality so high-quality / premium voices are easier to find.

    private var groupedVoices: [(String, [AVSpeechSynthesisVoice])] {
        var premium: [AVSpeechSynthesisVoice] = []
        var enhanced: [AVSpeechSynthesisVoice] = []
        var standard: [AVSpeechSynthesisVoice] = []
        for v in voices {
            switch v.quality {
            case .premium:  premium.append(v)
            case .enhanced: enhanced.append(v)
            case .default:  standard.append(v)
            @unknown default: standard.append(v)
            }
        }
        var groups: [(String, [AVSpeechSynthesisVoice])] = []
        if !premium.isEmpty  { groups.append(("Premium",  premium.sorted  { $0.name < $1.name })) }
        if !enhanced.isEmpty { groups.append(("Enhanced", enhanced.sorted { $0.name < $1.name })) }
        if !standard.isEmpty { groups.append(("Standard", standard.sorted { $0.name < $1.name })) }
        return groups
    }

    // MARK: - Row

    @ViewBuilder
    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                Text(qualityDescription(voice))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                preview(voice)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)

            if selectedID == voice.identifier {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedID = voice.identifier
        }
    }

    private func qualityDescription(_ voice: AVSpeechSynthesisVoice) -> String {
        let qualityText: String = switch voice.quality {
        case .premium:  "Premium"
        case .enhanced: "Enhanced"
        case .default:  "Standard"
        @unknown default: "Standard"
        }
        return "\(LanguageNames.displayName(for: voice.language)) · \(qualityText)"
    }

    private func preview(_ voice: AVSpeechSynthesisVoice) {
        let utterance = AVSpeechUtterance(string: "Hello — this is how words will sound.")
        utterance.voice = voice
        utterance.rate = VocabularySettingsStore.shared.rate
        let s = AVSpeechSynthesizer()
        s.speak(utterance)
        Self.previewSynth = s   // retain until system finishes
    }

    // Static retain so the synthesizer survives past the button tap.
    private static var previewSynth: AVSpeechSynthesizer?
}
