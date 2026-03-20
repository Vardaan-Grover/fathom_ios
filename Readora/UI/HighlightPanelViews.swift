import SwiftUI

struct HighlightColorPickerView: View {
    let onSelect: (HighlightColor) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose a Color")
            .font(.headline)

            HStack(spacing: 24) {
                ForEach(HighlightColor.allCases, id: \.self) {
                    color in
                    Button {
                        onSelect(color)
                        dismiss()
                    } label: {
                        Circle()
                        .fill(color.displayColor)
                        .frame(width: 48, height: 48)
                        .shadow(color: color.displayColor.opacity(0.5), radius: 4, y:2)
                    }
                }
            }

            Button("Cancel") {dismiss()}
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
        .padding(.horizontal)
    }
}

// Shown when tapping an existing highlight — change colour or remove
struct HighlightMenuView: View {
    let onChangeColor: (HighlightColor) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("Highlight")
                .font(.headline)
                .padding(.vertical, 16)

            Divider()

            HStack(spacing: 24) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        onChangeColor(color)
                        dismiss()
                    } label: {
                        Circle()
                            .fill(color.displayColor)
                            .frame(width: 40, height: 40)
                            .shadow(color: color.displayColor.opacity(0.5), radius: 3, y: 2)
                    }
                }
            }
            .padding(.vertical, 20)

            Divider()

            Button(role: .destructive) {
                onRemove()
                dismiss()
            } label: {
                Label("Remove Highlight", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}