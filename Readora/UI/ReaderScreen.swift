import ReadiumNavigator
import ReadiumShared
import SwiftUI

struct ReaderScreen: View {
    let bookFileURL: URL
    let bookTitle: String
    let bookID: UUID

    private let commands = NavigatorCommands()

    @State private var isShowingBars = true

    @State private var activeThreadID: UUID? = nil
    @State private var draftThreadID: UUID? = nil
    @State private var isShowingThreadsList = false

    @State private var isShowingSettings = false
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()

    @State private var selectedText: String = ""
    @State private var isShowingSelectionPanel = false
    @State private var noteQuoteText: String = ""
    @State private var isShowingNoteEditor = false

    @StateObject private var loader = PublicationLoader()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch loader.state {
                case .idle, .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Opening book…")
                            .foregroundStyle(.secondary)
                    }
                    .task {
                        await loader.load(fromLocalFileURL: bookFileURL)
                    }

                case .failed(let message):
                    VStack(spacing: 12) {
                        Text("Couldn't open book")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                case .loaded(let publication):
                    ReadiumNavigatorView(
                        publication: publication,
                        initialLocation: ReadingStateStore.shared.loadLocator(
                            forBookID: bookID),
                        onLocationChange: { locator in
                            ReadingStateStore.shared.saveLocator(locator, forBookID: bookID)
                        },
                        commands: commands,
                        settings: settings,
                        bookID: bookID
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        commands.onTap = { point, size in
                            let leftEdge = size.width * 0.2
                            let rightEdge = size.width * 0.8
                            if point.x < leftEdge {
                                Task { await commands.goLeft?() }
                            } else if point.x > rightEdge {
                                Task { await commands.goRight?() }
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingBars.toggle()
                                }
                            }
                        }

                        commands.onExplain = { text in
                            let thread = AIThread(
                                id: UUID(),
                                bookID: bookID,
                                passageText: text,
                                locatorJSON: nil,
                                chapterTitle: nil,
                                createdAt: Date(),
                                messages: []
                            )

                            AIThreadStore.shared.createThread(thread)
                            draftThreadID = thread.id
                            activeThreadID = thread.id
                        }

                        commands.onAddNote = { text in
                            noteQuoteText = text
                            isShowingNoteEditor = true
                        }
                    }
                }
            }
            .toolbar(isShowingBars ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "textformat")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingThreadsList = true
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                }
            }
            .sheet(isPresented: $isShowingNoteEditor) {
                NoteEditorSheet(quoteText: noteQuoteText)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingSettings) {
                ReaderSettingsView(settings: $settings)
                    .presentationDetents([.medium])
                    .onChange(of: settings) { _, newSettings in
                        ReaderSettingsStore.shared.save(newSettings)
                    }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { activeThreadID != nil },
                    set: { if !$0 { activeThreadID = nil } }
                ),
                onDismiss: {
                    cleanupDraftThreadIfNeeded()
                }
            ) {
                if let threadID = activeThreadID {
                    NavigationStack {
                        AIThreadView(threadID: threadID, bookID: bookID)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        activeThreadID = nil
                                    } label: {
                                        Image(systemName: "chevron.left")
                                    }
                                }
                            }
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingThreadsList) {
                AIThreadsListView(bookID: bookID, bookTitle: bookTitle)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $isShowingSelectionPanel) {
                VStack(alignment: .leading, spacing: 0) {
                    // Drag handle
                    HStack {
                        Capsule()
                            .fill(.tertiary)
                            .frame(width: 36, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // Selected text preview
                    Text(selectedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.horizontal)
                        .padding(.bottom, 16)

                    Divider()

                    // Action buttons
                    Button {
                        UIPasteboard.general.string = selectedText
                        isShowingSelectionPanel = false
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    Divider()

                    Button {
                        // AI explanation — coming soon
                        isShowingSelectionPanel = false
                    } label: {
                        Label("Explain with AI", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    Spacer()
                }
                .presentationDetents([.fraction(0.35)])
                .presentationDragIndicator(.hidden)
            }
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cleanupDraftThreadIfNeeded() {
        guard let draftThreadID else { return }
        defer { self.draftThreadID = nil }

        guard let thread = AIThreadStore.shared.thread(id: draftThreadID) else { return }
        let visibleMessages = thread.messages.filter { $0.role != .system }
        if visibleMessages.isEmpty {
            AIThreadStore.shared.deleteThread(id: draftThreadID)
        }
    }
}

// MARK: - Note Editor Sheet

private struct NoteEditorSheet: View {
    let quoteText: String
    @State private var noteBody: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Quote from the book
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 3)
                    Text(quoteText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding()

                Divider()

                // Note text field
                TextField("Write your note…", text: $noteBody, axis: .vertical)
                    .font(.body)
                    .lineLimit(5...)
                    .padding()

                Spacer()
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Notes persistence coming soon
                        dismiss()
                    }
                    .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
