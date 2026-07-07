import SwiftUI

// MARK: - Flow layout for variable-width pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (frame, subview) in zip(layout(in: bounds.width, subviews: subviews).frames, subviews) {
            subview.place(
                at: CGPoint(x: frame.minX + bounds.minX, y: frame.minY + bounds.minY),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (
        frames: [CGRect], size: CGSize
    ) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: .init(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

// MARK: - Shelf pill

struct ShelfPill: View, Equatable {
    let category: HomeCategory
    let isSelected: Bool
    let onTap: () -> Void

    // Closures are never equal, so compare only the inputs that affect rendering.
    static func == (lhs: ShelfPill, rhs: ShelfPill) -> Bool {
        lhs.category.id == rhs.category.id && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark" : "books.vertical.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, alignment: .center)
                    .contentTransition(.symbolEffect(.replace.offUp.byLayer))
                Text(category.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? category.shelfColor : category.shelfColor.opacity(0.12))
            .foregroundStyle(isSelected ? .white : category.shelfColor)
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule()
                        .strokeBorder(category.shelfColor.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
    }
}

// MARK: - "Add new shelf" pill

struct AddShelfPill: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, alignment: .center)
                Text("Add new shelf")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet

struct ShelfPickerSheet: View {
    let initialSelectedIDs: Set<UUID>
    let onCreateShelf: (String, String) -> HomeCategory?
    let onCommit: (_ added: Set<UUID>, _ removed: Set<UUID>) -> Void

    @State private var categories: [HomeCategory]
    @State private var selectedIDs: Set<UUID> = []
    @State private var snapshot: Set<UUID> = []
    @State private var showDiscardAlert = false
    @State private var showNewShelfSheet = false
    @Environment(\.dismiss) private var dismiss

    init(
        categories: [HomeCategory],
        initialSelectedIDs: Set<UUID>,
        onCreateShelf: @escaping (String, String) -> HomeCategory?,
        onCommit: @escaping (_ added: Set<UUID>, _ removed: Set<UUID>) -> Void
    ) {
        self.initialSelectedIDs = initialSelectedIDs
        self.onCreateShelf = onCreateShelf
        self.onCommit = onCommit
        _categories = State(initialValue: categories)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header — title centered, X button anchored top-right
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    Text("Manage Shelves")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: selectedIDs.count)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 20)

                Button {
                    if hasChanges { showDiscardAlert = true } else { dismiss() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(16)
            }

            Divider()

            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(categories) { category in
                        ShelfPill(
                            category: category,
                            isSelected: selectedIDs.contains(category.id)
                        ) {
                            if selectedIDs.contains(category.id) {
                                selectedIDs.remove(category.id)
                            } else {
                                selectedIDs.insert(category.id)
                            }
                        }
                        .equatable()
                    }

                    AddShelfPill { showNewShelfSheet = true }
                }
                .padding(20)
            }

            Divider()

            Button {
                onCommit(selectedIDs.subtracting(snapshot), snapshot.subtracting(selectedIDs))
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .onAppear {
            selectedIDs = initialSelectedIDs
            snapshot = initialSelectedIDs
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "Discard Changes?", isPresented: $showDiscardAlert, titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your shelf changes will be lost.")
        }
        .sheet(isPresented: $showNewShelfSheet) {
            NewShelfSheet { name, colorHex in
                guard let newCategory = onCreateShelf(name, colorHex) else { return }
                categories.append(newCategory)
                selectedIDs.insert(newCategory.id)
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
    }

    private var hasChanges: Bool { selectedIDs != snapshot }

    private var subtitle: String {
        switch selectedIDs.count {
        case 0: "Tap a shelf to add this book"
        case 1: "1 shelf selected"
        default: "\(selectedIDs.count) shelves selected"
        }
    }
}
