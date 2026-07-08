import SwiftUI

struct ReorderShelvesSheet: View {
    // onCommit is called on every drag move — no explicit save needed
    let onCommit: ([HomeCategory]) -> Void

    @State private var shelves: [HomeCategory]
    @Environment(\.dismiss) private var dismiss

    init(shelves: [HomeCategory], onCommit: @escaping ([HomeCategory]) -> Void) {
        _shelves = State(initialValue: shelves)
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            shelfList
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Compact inline header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrange Shelves")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Drag to reorder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - List

    private var shelfList: some View {
        List {
            ForEach(shelves) { shelf in
                ShelfReorderRow(shelf: shelf)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .onMove { from, to in
                UISelectionFeedbackGenerator().selectionChanged()
                shelves.move(fromOffsets: from, toOffset: to)
                onCommit(shelves)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Row

private struct ShelfReorderRow: View {
    let shelf: HomeCategory

    var body: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [shelf.shelfColor, shelf.shelfColor.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 36)
                .shadow(color: shelf.shelfColor.opacity(0.35), radius: 3, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(shelf.books.count) \(shelf.books.count == 1 ? "book" : "books")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    let shelves = [
        HomeCategory(id: HomeViewModel.myLibraryID, name: "My Library",
                     books: [], shelfColor: Color(hex: "4A7DB5"), shelfColorHex: ""),
        HomeCategory(id: UUID(), name: "Finished Books", books: [],
                     shelfColor: Color(hex: "2A9D5C"), shelfColorHex: "2A9D5C"),
        HomeCategory(id: UUID(), name: "To Be Read", books: [],
                     shelfColor: Color(hex: "C0507A"), shelfColorHex: "C0507A"),
        HomeCategory(id: UUID(), name: "Classics", books: [],
                     shelfColor: Color(hex: "2A6B3E"), shelfColorHex: "2A6B3E"),
    ]
    ReorderShelvesSheet(shelves: shelves) { _ in }
}
