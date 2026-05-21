import SwiftUI

struct BookCoverView: View {
    let book: HomeBook
    let width: CGFloat
    let height: CGFloat
    var userCategories: [HomeCategory] = []
    var onToggleCategory: ((UUID) -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showShelfPicker = false

    init(
        book: HomeBook,
        width: CGFloat = 120,
        height: CGFloat = 168,
        userCategories: [HomeCategory] = [],
        onToggleCategory: ((UUID) -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.book = book
        self.width = width
        self.height = height
        self.userCategories = userCategories
        self.onToggleCategory = onToggleCategory
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            coverBackground
            spineShading
            textOverlay
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)
        .contextMenu { contextMenuContent }
        .sheet(isPresented: $showShelfPicker) {
            ShelfPickerSheet(
                categories: userCategories,
                initialSelectedIDs: book.categoryIDs
            ) { added, removed in
                for id in added { onToggleCategory?(id) }
                for id in removed { onToggleCategory?(id) }
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            onEdit?()
        } label: {
            Label("Edit Book", systemImage: "pencil")
        }
        Button {
            showShelfPicker = true
        } label: {
            Label("Manage Shelves", systemImage: "books.vertical")
        }
        Button(role: .destructive) {
            onDelete?()
        } label: {
            Label("Delete Book", systemImage: "trash")
        }
    }

    // MARK: - Visual layers

    @ViewBuilder
    private var coverBackground: some View {
        if let filename = book.coverFilename,
            let url = BookFileStore.coverURL(for: filename),
            let uiImage = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            book.coverColor
                .frame(width: width, height: height)
        }
    }

    // Subtle left-edge spine shading — only visible on the color fallback,
    // but harmless over a real cover image.
    private var spineShading: some View {
        LinearGradient(
            colors: [.black.opacity(0.28), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 12)
    }

    // Title + author text is only shown when no real cover image is available.
    @ViewBuilder
    private var textOverlay: some View {
        if book.coverFilename == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(book.textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)

                Spacer()

                Text(book.author)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(book.textColor?.opacity(0.70))
                    .lineLimit(2)
            }
            .padding(10)
        }
    }
}

// MARK: - Flow layout for variable-width pills

private struct FlowLayout: Layout {
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

private struct ShelfPill: View, Equatable {
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

// MARK: - Sheet

private struct ShelfPickerSheet: View {
    let categories: [HomeCategory]
    let initialSelectedIDs: Set<UUID>
    let onCommit: (_ added: Set<UUID>, _ removed: Set<UUID>) -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var snapshot: Set<UUID> = []
    @State private var showDiscardAlert = false
    @Environment(\.dismiss) private var dismiss

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

#Preview {
    HStack(spacing: 10) {
        BookCoverView(
            book: HomeBook(
                id: UUID(),
                title: "The Design of Everyday Things",
                author: "Don Norman",
                coverColor: Color(hex: "F5C518"),
                textColor: .black,
                coverFilename: nil
            ))
        BookCoverView(
            book: HomeBook(
                id: UUID(),
                title: "Read People Like a Book",
                author: "Patrick King",
                coverColor: Color(hex: "1A3A6B"),
                textColor: Color(hex: "F5C518"),
                coverFilename: nil
            ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
