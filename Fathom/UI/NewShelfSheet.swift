import SwiftUI

struct NewShelfSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    var onCommit: (String, String) -> Void

    @State private var name: String
    @State private var selectedColorHex: String
    @State private var showNameError = false
    @FocusState private var nameFocused: Bool

    var isNameEmpty: Bool {
        name.allSatisfy(\.isWhitespace)
    }

    // Pre-compute the colors
    static let palette: [(hex: String, color: Color)] = [
        "4A7DB5", "C0392B", "2A6B3E", "7D3C98",
        "E67E22", "1ABC9C", "8B4513", "D4A017",
        "3A72D4", "C75B9B", "5B8A5E", "6C5CE7",
    ].map { ($0, Color(hex: $0)) }

    init(
        initialName: String = "",
        initialColorHex: String = "",
        isEditing: Bool = false,
        onCommit: @escaping (String, String) -> Void
    ) {
        self.isEditing = isEditing
        self.onCommit = onCommit

        // Add the fallback back in using the new tuple structure
        let hex = initialColorHex.isEmpty ? Self.palette[0].hex : initialColorHex

        _name = State(initialValue: initialName)
        _selectedColorHex = State(initialValue: hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(isEditing ? "Edit Shelf" : "New Shelf")
                .font(.title2.bold())
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                TextField("e.g. Favourites, To Read…", text: $name)
                    .font(.body)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red, lineWidth: 1.5)
                            .opacity(showNameError ? 1 : 0)
                    }
                    .onChange(of: name) { _, _ in
                        if showNameError { showNameError = false }
                    }

                if showNameError {
                    Text("Please enter a name for your shelf")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showNameError)

            ShelfColorPicker(selectedHex: $selectedColorHex).equatable()

            Spacer()
                .frame(maxHeight: showNameError ? 12 : 40)

            ShelfCreateButton(isEmpty: isNameEmpty, selectedHex: selectedColorHex, isEditing: isEditing) {
                if isNameEmpty {
                    showNameError = true
                    nameFocused = true
                    return
                }
                onCommit(name.trimmingCharacters(in: .whitespaces), selectedColorHex)
                dismiss()
            }
        }
        .padding(24)
    }
}

private struct ShelfColorPicker: View, Equatable {
    @Binding var selectedHex: String

    static func == (lhs: ShelfColorPicker, rhs: ShelfColorPicker) -> Bool {
        lhs.selectedHex == rhs.selectedHex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                spacing: 10
            ) {
                // Iterate using \.hex and pass both values to the swatch
                ForEach(NewShelfSheet.palette, id: \.hex) { item in
                    ShelfColorSwatch(
                        hex: item.hex,
                        themeColor: item.color,  // Pass pre-computed color
                        isSelected: item.hex == selectedHex
                    )
                    .onTapGesture { selectedHex = item.hex }
                }
            }
        }
    }
}

private struct ShelfColorSwatch: View {
    let hex: String
    let themeColor: Color  // Accept the pre-computed color
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(themeColor)  // Use it here
            .frame(width: 42, height: 42)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(themeColor, lineWidth: 2.5)  // And use it here
                    .padding(-5)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isSelected)
    }
}

private struct ShelfCreateButton: View {
    let isEmpty: Bool
    let selectedHex: String
    let isEditing: Bool
    let action: () -> Void

    // Look up the pre-computed color from our static palette
    private var themeColor: Color {
        NewShelfSheet.palette.first(where: { $0.hex == selectedHex })?.color ?? .blue
    }

    var body: some View {
        Button(action: action) {
            Label(
                isEditing ? "Save Changes" : "Create Shelf",
                systemImage: isEditing ? "checkmark" : "folder.badge.plus"
            )
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            // Use the looked-up color instead of Color(hex:)
            .background(isEmpty ? Color(.systemFill) : themeColor)
            .foregroundStyle(isEmpty ? Color.secondary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .animation(.easeInOut(duration: 0.15), value: selectedHex)
        .animation(.easeInOut(duration: 0.15), value: isEmpty)
    }
}
