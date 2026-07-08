import SwiftUI

// MARK: - AppearanceMode

enum AppearanceMode: Hashable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
}

// MARK: - HomeViewStyle

enum HomeViewStyle: String, CaseIterable {
    case glassShelves = "Glass Shelves"
    case classicGrid = "Classic Grid"
}

// MARK: - AppearancePickerScreen

struct AppearancePickerScreen: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        Form {
            Section {
                ForEach([AppearanceMode.system, .light, .dark], id: \.self) { mode in
                    HStack {
                        Text(mode.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selection = mode
                    }
                }
            } footer: {
                Text("Choose how Fathom looks. \"System\" follows your device's appearance.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }
}
