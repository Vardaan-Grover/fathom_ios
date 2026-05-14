import SwiftUI

struct HighlightColorPickerView: View {
    let onSelect: (HighlightColor) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 16) {
            ForEach(HighlightColor.highlightCases, id: \.self) { color in
                Button {
                    onSelect(color)
                    dismiss()
                } label: {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

struct NoteHighlightColorPickerView: View {
    let currentColor: HighlightColor
    let onSelect: (HighlightColor) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 14) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    onSelect(color)
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(color.displayColor)
                            .frame(width: 34, height: 34)
                        if color == currentColor {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

struct HighlightMenuView: View {
    let onChangeColor: (HighlightColor) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 14) {
            ForEach(HighlightColor.highlightCases, id: \.self) { color in
                Button {
                    onChangeColor(color)
                    dismiss()
                } label: {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 4)

            Button(role: .destructive) {
                onRemove()
                dismiss()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}
