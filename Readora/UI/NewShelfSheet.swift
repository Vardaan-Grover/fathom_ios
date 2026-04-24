import SwiftUI

struct NewShelfSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var selectedColorHex = Self.palette[0]
    @State private var isNameEmpty = true
    @FocusState private var nameFocused: Bool

    static let palette: [String] = [
        "4A7DB5", "C0392B", "2A6B3E", "7D3C98",
        "E67E22", "1ABC9C", "8B4513", "D4A017",
        "3A72D4", "C75B9B", "5B8A5E", "6C5CE7",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("New Shelf")
                .font(.title2.bold())
                .padding(.top, 4)

            TextField("e.g. Favourites, To Read…", text: $name)
                .font(.body)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: name) { _, new in
                    // Only flip the bool on empty<->non-empty transitions, not every keystroke
                    let empty = new.trimmingCharacters(in: .whitespaces).isEmpty
                    if empty != isNameEmpty { isNameEmpty = empty }
                }

            ShelfColorPicker(selectedHex: $selectedColorHex)

            Spacer()

            ShelfCreateButton(isEmpty: isNameEmpty, selectedHex: selectedColorHex) {
                onCreate(name.trimmingCharacters(in: .whitespaces), selectedColorHex)
                dismiss()
            }
        }
        .padding(24)
        .onAppear { nameFocused = true }
    }
}

// Isolated struct — only re-renders when selectedHex changes, never on typing
private struct ShelfColorPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                spacing: 10
            ) {
                ForEach(NewShelfSheet.palette, id: \.self) { hex in
                    ShelfColorSwatch(hex: hex, isSelected: hex == selectedHex)
                        .onTapGesture { selectedHex = hex }
                }
            }
        }
    }
}

// Isolated struct — only re-renders when isSelected flips for this specific swatch
private struct ShelfColorSwatch: View {
    let hex: String
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: hex))
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
                    .strokeBorder(Color(hex: hex), lineWidth: 2.5)
                    .padding(-5)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isSelected)
    }
}

// Isolated struct — only re-renders on isEmpty transitions or color changes
private struct ShelfCreateButton: View {
    let isEmpty: Bool
    let selectedHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Create Shelf", systemImage: "folder.badge.plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isEmpty ? Color(.systemFill) : Color(hex: selectedHex))
                .foregroundStyle(isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isEmpty)
        .animation(.easeInOut(duration: 0.15), value: selectedHex)
        .animation(.easeInOut(duration: 0.15), value: isEmpty)
    }
}
