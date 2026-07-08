import SwiftUI
import UIKit

private struct NoteScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct NoteSheetView: View {
    let selectedText: String
    let locatorJSON: String
    let bookID: UUID
    let chapterTitle: String?
    let pageNumber: Int?
    let settings: ReaderSettings
    var existingNote: Note? = nil
    var onSave: (Note) -> Void
    var onDelete: (() -> Void)? = nil
    var onDismiss: () -> Void

    @State private var noteText: String
    @State private var selectedColor: HighlightColor
    @State private var isExpanded = false
    @State private var showDiscardAlert = false
    @State private var editorFocused = false
    @State private var scrollOffset: CGFloat = 0

    private let createdAt: Date
    private let initialNoteText: String
    private let initialColor: HighlightColor

    init(
        selectedText: String,
        locatorJSON: String,
        bookID: UUID,
        chapterTitle: String?,
        pageNumber: Int?,
        settings: ReaderSettings,
        existingNote: Note? = nil,
        onSave: @escaping (Note) -> Void,
        onDelete: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.locatorJSON = locatorJSON
        self.bookID = bookID
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
        self.settings = settings
        self.existingNote = existingNote
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        let text = existingNote?.noteContent ?? ""
        let color = existingNote?.highlightColor ?? .indigo
        _noteText = State(initialValue: text)
        _selectedColor = State(initialValue: color)
        self.initialNoteText = text
        self.initialColor = color
        self.createdAt = existingNote?.createdAt ?? Date()
    }

    private var theme: ReaderColorTheme { settings.colorTheme }
    private var bg: Color { theme.backgroundColor }
    private var fg: Color { theme.foregroundColor }
    private let accent = Color(hex: "4A7DB5")
    private var dim: Color { fg.opacity(0.42) }
    private var quoteBg: Color {
        theme.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    private var isLongText: Bool { selectedText.count > 240 }
    private var isEditMode: Bool { existingNote != nil }
    private var isHeaderCollapsed: Bool { scrollOffset > 24 }

    private var hasUnsavedChanges: Bool {
        noteText != initialNoteText || selectedColor != initialColor
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(fg.opacity(0.12))
                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: NoteScrollOffsetKey.self,
                                    value: geo.frame(in: .named("noteScroll")).minY
                                )
                            }
                        )
                }
                .coordinateSpace(name: "noteScroll")
                .onPreferenceChange(NoteScrollOffsetKey.self) { value in
                    scrollOffset = -value
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(bg)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                editorFocused = true
            }
        }
        .confirmationDialog(
            "You have unsaved changes.",
            isPresented: $showDiscardAlert,
            titleVisibility: .visible
        ) {
            Button("Save", action: save)
            Button("Discard Changes", role: .destructive, action: onDismiss)
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                if hasUnsavedChanges {
                    showDiscardAlert = true
                } else {
                    onDismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(fg.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(fg.opacity(0.6))
                }
            }

            Spacer()

            VStack(alignment: .center, spacing: 2) {
                Text(isEditMode ? "Edit Note" : "Note")
                    .font(.system(size: isHeaderCollapsed ? 15 : 17, weight: .semibold))
                    .foregroundStyle(fg)
                if !isHeaderCollapsed {
                    Text(createdAt, format: .dateTime.hour().minute())
                        .font(.system(size: 13))
                        .foregroundStyle(dim)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()

            Button(action: save) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, isHeaderCollapsed ? 10 : 16)
        .animation(.easeInOut(duration: 0.2), value: isHeaderCollapsed)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            quoteBlock
            colorPicker
            noteEditor
        }
        .padding(20)
    }

    // MARK: - Quote block

    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let chapter = chapterTitle {
                Text(chapter.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(dim)
            }

            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedText)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(fg.opacity(0.82))
                        .lineLimit(isExpanded ? nil : 4)
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLongText {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Text(isExpanded ? "Show less" : "Show more")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(quoteBg)
        )
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        HStack(spacing: 0) {
            Text("Highlight")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dim)

            Spacer()

            HStack(spacing: 10) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedColor = color
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.displayColor)
                                .frame(width: 28, height: 28)
                            if color == selectedColor {
                                Circle()
                                    .strokeBorder(fg.opacity(0.55), lineWidth: 2.5)
                                    .frame(width: 28, height: 28)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(fg.opacity(0.8))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(quoteBg)
        )
    }

    // MARK: - Note editor

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            if noteText.isEmpty {
                Text("Add a note…")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(dim)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            GrowingTextEditor(
                text: $noteText,
                isFocused: $editorFocused,
                font: .serif(ofSize: 16, weight: .regular),
                textColor: UIColor(fg),
                tintColor: UIColor(accent),
                // No floating bottom bar here (save lives in the header), so the caret
                // only needs a little breathing room above the keyboard.
                caretBottomInset: 24
            )
            .frame(minHeight: 180, alignment: .top)
        }
    }

    // MARK: - Save

    private func save() {
        if let existing = existingNote {
            if noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onDelete?()
                return
            }
            var updated = existing
            updated.noteContent = noteText
            updated.highlightColor = selectedColor
            onSave(updated)
        } else {
            let note = Note(
                bookID: bookID,
                locatorJSON: locatorJSON,
                selectedText: selectedText,
                noteContent: noteText,
                createdAt: createdAt,
                chapterTitle: chapterTitle,
                pageNumber: pageNumber,
                highlightColor: selectedColor
            )
            onSave(note)
        }
    }
}
