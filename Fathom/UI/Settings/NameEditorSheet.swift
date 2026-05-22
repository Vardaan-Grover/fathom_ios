import SwiftUI

// MARK: - NameEditorSheet
//
// Minimal sheet for editing the user's display name. Uses a native
// .insetGrouped form so it matches Apple's "name editor" pattern.

struct NameEditorSheet: View {
    @Binding var name: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    @State private var workingName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $workingName)
                        .focused($fieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .onSubmit { commit() }
                } footer: {
                    Text("Shown on your profile. Synced across your devices.")
                }
            }
            .navigationTitle("Display Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { commit() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            workingName = name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                fieldFocused = true
            }
        }
    }

    private func commit() {
        name = workingName.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}
