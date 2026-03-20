import SwiftUI

struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 24) {
            Text("Reading Settings")
                .font(.headline)
                .padding(.top)
            
            // Font Size
            VStack(alignment: .leading, spacing: 8) {
                Label("Font Size", systemImage: "textformat.size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("A").font(.caption)
                    Slider(value: $settings.fontSize, in: 0.5...2.5, step: 0.1)
                    Text("A").font(.title2)
                }
            }

            // Line Spacing
            VStack(alignment: .leading, spacing: 8) {
                Label("Line Spacing", systemImage: "text.alignleft")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $settings.lineHeight, in: 1.0...2.0, step: 0.1)
            }

            // Theme
            VStack(alignment: .leading, spacing: 8) {
                Label("Theme", systemImage: "cicle.lefthalf.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(ReaderTheme.allCases, id: \.self) {
                        theme in Button {
                            settings.theme = theme
                        } label: {
                            Text(theme.rawValue.capitalized)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(settings.theme == theme ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(settings.theme == theme ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            // Spacer()
        }
        .padding(.horizontal)
    }
}
