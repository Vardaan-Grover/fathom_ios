import SwiftUI

struct NotesListView: View {
    let bookID: UUID
    var onSelect: (String) -> Void

    @State private var notes: [Note] = []
    @State private var selectedColor: HighlightColor? = nil
    @Environment(\.dismiss) private var dismiss

    private var presentColors: [HighlightColor] {
        HighlightColor.allCases.filter { c in notes.contains { $0.highlightColor == c } }
    }

    private var filtered: [Note] {
        guard let color = selectedColor else { return notes }
        return notes.filter { $0.highlightColor == color }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.4)
            if !notes.isEmpty {
                colorFilterBar
            }
            if filtered.isEmpty {
                emptyState
            } else {
                notesList
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedColor)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .onAppear { loadNotes() }
        .onReceive(
            NotificationCenter.default.publisher(for: NoteStore.didChangeNotification)
        ) { notification in
            guard let changedID = notification.object as? UUID, changedID == bookID else { return }
            loadNotes()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Notes")
                    .font(.system(size: 22, weight: .bold))
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filtered.count)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var countLabel: String {
        let n = filtered.count
        return "\(n) \(n == 1 ? "note" : "notes")"
    }

    // MARK: - Color Filter Bar

    private var colorFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NoteColorChip(label: "All", color: nil, isSelected: selectedColor == nil) {
                    selectedColor = nil
                }
                ForEach(presentColors, id: \.self) { color in
                    NoteColorChip(
                        label: color.rawValue.capitalized,
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filtered) { note in
                    NoteCard(note: note) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(note.locatorJSON)
                        dismiss()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            NoteStore.shared.delete(id: note.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        selectedColor != nil
                            ? selectedColor!.displayColor.opacity(0.12)
                            : Color.accentColor.opacity(0.1)
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "note.text")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(
                        selectedColor != nil
                            ? selectedColor!.displayColor
                            : Color.accentColor
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text(
                    selectedColor == nil
                        ? "No Notes Yet" : "No \(selectedColor!.rawValue.capitalized) Notes"
                )
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 24)
                Text(
                    selectedColor == nil
                        ? "Select text while reading and tap\n\"Note\" to add your first note."
                        : "Try a different color filter."
                )
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - Helpers

    private func loadNotes() {
        notes = NoteStore.shared.notes(forBookID: bookID)
        if let color = selectedColor, !notes.contains(where: { $0.highlightColor == color }) {
            selectedColor = nil
        }
    }
}

// MARK: - Color Filter Chip

private struct NoteColorChip: View {
    let label: String
    let color: HighlightColor?
    let isSelected: Bool
    let action: () -> Void

    private var chipAccent: Color { color?.displayColor ?? Color.accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 10, height: 10)
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? chipAccent.opacity(0.15) : Color(.secondarySystemGroupedBackground)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? chipAccent.opacity(0.5)
                                    : Color(.opaqueSeparator).opacity(0.7),
                                lineWidth: 1
                            )
                    )
            )
        }
        .foregroundStyle(isSelected ? chipAccent : Color.secondary)
        .buttonStyle(SpringPressStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - Note Card

private struct NoteCard: View {
    let note: Note
    let onTap: () -> Void

    private var hasNote: Bool {
        !note.noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(note.highlightColor.displayColor)
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 0) {
                    // Meta row
                    HStack(spacing: 0) {
                        if let chapter = note.chapterTitle, !chapter.isEmpty {
                            Text(chapter)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let page = note.pageNumber {
                            let hasChapter = note.chapterTitle?.isEmpty == false
                            Text((hasChapter ? " · " : "") + "p. \(page)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(note.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 13)
                    .padding(.bottom, 9)
                    .padding(.trailing, 14)

                    // Selected text (serif)
                    Text(note.selectedText)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 14)
                        .padding(.bottom, hasNote ? 12 : 14)

                    if hasNote {
                        Divider()
                            .padding(.trailing, 14)
                            .opacity(0.5)

                        Text(note.noteContent)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .padding(.trailing, 14)
                            .padding(.bottom, 14)
                    }
                }
                .padding(.leading, 12)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(note.highlightColor.displayColor.opacity(0.05))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(note.highlightColor.displayColor.opacity(0.22), lineWidth: 1)
                )
            )
        }
        .buttonStyle(SpringPressStyle())
    }
}
