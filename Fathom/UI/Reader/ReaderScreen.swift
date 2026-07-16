import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import Translation

struct ReaderScreen: View {
    let bookFileURL: URL
    let bookTitle: String
    let bookID: UUID
    var book: Book? = nil
    var bookRepository: BookRepository? = nil
    var backendBookID: UUID? = nil
    var aiEnabled: Bool = false
    var ingestionStatus: PreprocessingStatus = .pending
    var onEnableAI: () -> Void = {}

    @StateObject private var commands = NavigatorCommands()

    @State private var isShowingBars = true
    @State private var isShowingSettings = false
    @State private var isShowingAIChats = false
    @State private var isShowingAIProcessingAlert = false
    @State private var isShowingTOC = false
    @State private var pendingTOCLocatorJSON: String? = nil
    @State private var isShowingNotesList = false
    @State private var pendingNotesListLocatorJSON: String? = nil
    @State private var isShowingHighlightsList = false
    @State private var pendingHighlightsLocatorJSON: String? = nil
    @State private var isShowingBookmarksList = false
    @State private var pendingBookmarksLocatorJSON: String? = nil
    @State private var bookmarks: [Bookmark] = []
    @State private var parsedBookmarkLocators: [ParsedBookmarkLocator] = []

    // Vocabulary State
    @State private var definedWord: String?
    @State private var definedLocatorJSON: String?
    @State private var definedSentenceContext: SentenceContext?

    // Note State
    @State private var pendingNoteText: String?
    @State private var pendingNoteLocatorJSON: String?
    // Highlight the pending note is being created on top of, if any. The
    // highlight is deleted only when the note is saved, so cancelling the
    // note sheet leaves the original highlight intact.
    @State private var pendingNoteHighlightID: UUID?
    @State private var pendingEditNote: Note?
    @State private var notesVersion: Int = 0

    @State private var isActionButtonPresented = false
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var positions: [Locator] = []
    @State private var currentProgression: Double = 0.0
    @State private var currentLocator: Locator?
    @StateObject private var navigationHistory = ReaderNavigationHistory()
    @StateObject private var searchState = BookSearchState()
    @State private var isShowingSearch = false
    @State private var pendingSearchLocatorJSON: String? = nil
    @State private var isScrubbing: Bool = false
    @State private var scrubTargetProgression: Double = 0.0
    @State private var isShowingCompletion = false
    @State private var hasTriggeredCompletion = false
    @StateObject private var loader = PublicationLoader()
    @State private var tableOfContents: [ReadiumShared.Link] = []
    @State private var aiSelectedText: String?
    @State private var aiSelectedLocatorJSON: String?

    // Translate State
    @State private var translateText: String?
    @State private var isShowingTranslation = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Reading-session tracking. The timer only runs while the app is active:
    // `sessionStartTime` is nil whenever the app is inactive/backgrounded, and
    // time accrued so far is banked in `accumulatedReadingTime`.
    @State private var sessionStartTime: Date? = nil
    @State private var accumulatedReadingTime: TimeInterval = 0

    /// Sessions shorter than this are noise (accidental opens), not reading.
    private static let minimumLoggedSession: TimeInterval = 60

    private var aiReady: Bool { aiEnabled && ingestionStatus == .completed }

    private var isCurrentPageBookmarked: Bool {
        bookmarkOnCurrentPage(
            parsedLocators: parsedBookmarkLocators,
            currentLocator: currentLocator,
            currentProgression: currentProgression,
            positions: positions,
            isScrolling: settings.layout == .scrolling
        )
    }

    private var chapterTitle: String? {
        let prog = currentLocator?.locations.totalProgression ?? currentProgression
        return tocChapterTitle(
            atTotalProgression: prog,
            positions: positions,
            tableOfContents: tableOfContents
        ) ?? currentLocator?.title
    }

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Opening book…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        AppLogger.log(tag: "ReaderScreen", "Triggering loader for: \(bookFileURL)")
                        await loader.load(fromLocalFileURL: bookFileURL)
                    }
                }

            case .failed(let message):
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 12) {
                        Text("Couldn't open book")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                            .padding()
                    }
                }

            case .loaded(let publication):
                loadedView(publication: publication)
            }
        }
        .statusBarHidden(!isShowingBars)
        .alert("AI Analysis in Progress", isPresented: $isShowingAIProcessingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The AI companion is still being set up for this book. Please check back soon.")
        }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsView(settings: $settings)
                .onChange(of: settings) { _, newSettings in
                    ReaderSettingsStore.shared.save(newSettings)
                }
        }
        .sheet(isPresented: $isShowingAIChats) {
            AIChatsListScreen(bookID: bookID, backendBookID: backendBookID, bookTitle: bookTitle)
        }
        .sheet(
            isPresented: Binding(
                get: { definedWord != nil },
                set: {
                    if !$0 {
                        definedWord = nil
                        definedLocatorJSON = nil
                        definedSentenceContext = nil
                    }
                }
            )
        ) {
            if let word = definedWord {
                VocabularySheetView(
                    viewModel: VocabularySheetViewModel(
                        word: word,
                        bookID: bookID,
                        bookTitle: bookTitle,
                        chapter: chapterTitle,
                        pageNumber: currentPage > 0 ? currentPage : nil,
                        locatorJSON: definedLocatorJSON,
                        sentenceContext: definedSentenceContext,
                        repository: AppContainer.shared.vocabularyRepo
                    )
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { pendingNoteText != nil || pendingEditNote != nil },
                set: {
                    if !$0 {
                        pendingNoteText = nil
                        pendingNoteLocatorJSON = nil
                        pendingEditNote = nil
                    }
                }
            )
        ) {
            noteSheetContent
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { aiSelectedText != nil && aiEnabled && backendBookID != nil },
                set: { if !$0 { aiSelectedText = nil } }
            )
        ) {
            if let text = aiSelectedText, let backendID = backendBookID {
                AICompanionScreen(
                    bookID: bookID,
                    backendBookID: backendID,
                    selectedText: text,
                    locatorJSON: aiSelectedLocatorJSON,
                    bookTitle: bookTitle,
                    onDismiss: {
                        aiSelectedText = nil
                        aiSelectedLocatorJSON = nil
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isShowingCompletion) {
            if let b = book, let repo = bookRepository {
                BookCompletionScreen(book: b, bookRepository: repo)
            }
        }
        .onChange(of: currentProgression) { _, newValue in
            guard
                !hasTriggeredCompletion,
                newValue >= 0.98,
                let b = book,
                b.finishedAt == nil,
                bookRepository != nil
            else { return }
            hasTriggeredCompletion = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                isShowingCompletion = true
            }
        }
        .onAppear {
            sessionStartTime = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if sessionStartTime == nil { sessionStartTime = Date() }
            } else {
                // Pause while inactive/backgrounded — a locked phone with the
                // reader open must not count as reading time.
                if let start = sessionStartTime {
                    accumulatedReadingTime += Date().timeIntervalSince(start)
                    sessionStartTime = nil
                }
            }
        }
        .onDisappear {
            var duration = accumulatedReadingTime
            if let start = sessionStartTime {
                duration += Date().timeIntervalSince(start)
            }
            sessionStartTime = nil
            accumulatedReadingTime = 0

            if duration >= Self.minimumLoggedSession {
                Task {
                    await bookRepository?.logReadingSession(for: bookID, duration: duration)
                    // Signal *after* the write commits so listeners (e.g. the
                    // home observatory) refresh against fresh data, not a race.
                    NotificationCenter.default.post(name: .fathomReadingSessionLogged, object: nil)
                }
            }
        }
    }
}
// MARK: - Loaded State View

extension ReaderScreen {
    // Split into two functions so the type-checker handles each in isolation.
    // Swift overflows when inferring the type of 6+ chained .sheet modifiers
    // stacked on a complex base — splitting the chain into base + sheets fixes it.

    /// Jump to a stored locator, remembering where we came from so Undo can return.
    func jump(toLocatorJSON json: String) {
        if let currentLocator { navigationHistory.push(currentLocator) }
        Task { @MainActor in await commands.goToLocatorJSON?(json) }
    }

    func loadedView(publication: Publication) -> some View {
        navigatorCore(publication: publication)
            .sheet(isPresented: $isShowingTOC, onDismiss: {
                guard let json = pendingTOCLocatorJSON else { return }
                pendingTOCLocatorJSON = nil
                jump(toLocatorJSON: json)
            }) {
                TableOfContentsSheet(
                    bookID: bookID,
                    bookTitle: bookTitle,
                    publication: publication,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    currentLocator: ReadingStateStore.shared.loadLocator(forBookID: bookID),
                    settings: settings,
                    onSelect: { link in
                        let tocURL = link.url()
                        let fragment = tocURL.fragment
                        let hrefToMatch = tocURL.removingFragment()
                        if let roLink = publication.readingOrder.first(where: {
                            $0.url().isEquivalentTo(hrefToMatch)
                        }), let mediaType = roLink.mediaType {
                            let locator = Locator(
                                href: roLink.url(),
                                mediaType: mediaType,
                                title: link.title ?? roLink.title,
                                locations: Locator.Locations(
                                    fragments: fragment.map { [$0] } ?? [],
                                    progression: fragment == nil ? 0.0 : nil
                                )
                            )
                            pendingTOCLocatorJSON = locator.jsonString
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingNotesList, onDismiss: {
                guard let json = pendingNotesListLocatorJSON else { return }
                pendingNotesListLocatorJSON = nil
                jump(toLocatorJSON: json)
            }) {
                NotesListView(bookID: bookID) { pendingNotesListLocatorJSON = $0 }
            }
            .sheet(isPresented: $isShowingHighlightsList, onDismiss: {
                guard let json = pendingHighlightsLocatorJSON else { return }
                pendingHighlightsLocatorJSON = nil
                jump(toLocatorJSON: json)
            }) {
                HighlightsListView(bookID: bookID) { pendingHighlightsLocatorJSON = $0 }
            }
            .sheet(isPresented: $isShowingBookmarksList, onDismiss: {
                guard let json = pendingBookmarksLocatorJSON else { return }
                pendingBookmarksLocatorJSON = nil
                jump(toLocatorJSON: json)
            }) {
                BookmarksListView(bookID: bookID) { pendingBookmarksLocatorJSON = $0 }
            }
            .sheet(isPresented: $isShowingSearch, onDismiss: {
                guard let json = pendingSearchLocatorJSON else { return }
                pendingSearchLocatorJSON = nil
                if let currentLocator { navigationHistory.push(currentLocator) }
                Task { @MainActor in
                    await commands.goToLocatorJSON?(json)
                    commands.applySearchHighlight?(json)
                }
            }) {
                SearchBookView(state: searchState) { pendingSearchLocatorJSON = $0 }
            }
    }

    func navigatorCore(publication: Publication) -> some View {
        ReadiumNavigatorView(
            publication: publication,
            initialLocation: ReadingStateStore.shared.loadLocator(forBookID: bookID),
            isOverlayInteractive: isActionButtonPresented || pendingNoteText != nil,
            onLocationChange: onLocationChange,
            onPositionsLoaded: { positions = $0; totalPages = $0.count },
            commands: commands,
            settings: settings,
            bookID: bookID,
            aiQueryLocatorJSON: aiSelectedText != nil ? aiSelectedLocatorJSON : nil,
            aiEnabled: aiEnabled && backendBookID != nil,
            notesVersion: notesVersion,
            overlayForLocator: { locator in
                AnyView(self.readerOverlayContent(for: locator))
            }
        )
        .ignoresSafeArea()
        .task {
            if let links = try? await publication.tableOfContents().get() {
                self.tableOfContents = links
                self.searchState.tableOfContents = links
            }
            self.searchState.publication = publication
        }
        .onReceive(
            NotificationCenter.default.publisher(for: BookmarkStore.didChangeNotification)
        ) { notification in
            guard let changedID = notification.object as? UUID, changedID == bookID else { return }
            bookmarks = BookmarkStore.shared.bookmarks(forBookID: bookID)
            parsedBookmarkLocators = parseBookmarkLocators(bookmarks)
        }
        .onAppear { setupOnAppear() }
        
        .translationPresentation(
            isPresented: $isShowingTranslation,
            text: translateText ?? ""
        )
    }

    func onLocationChange(_ locator: Locator) {
        ReadingStateStore.shared.saveLocator(locator, forBookID: bookID)
        currentLocator = locator
        if let page = locator.locations.position {
            currentPage = page
        } else if let prog = locator.locations.totalProgression, totalPages > 0 {
            currentPage = max(1, Int(prog * Double(totalPages)))
        }
        if let prog = locator.locations.totalProgression {
            currentProgression = prog
        }
    }

    func setupOnAppear() {
        bookmarks = BookmarkStore.shared.bookmarks(forBookID: bookID)
        parsedBookmarkLocators = parseBookmarkLocators(bookmarks)
        commands.onExplain = { text, locatorJSON in
            guard aiEnabled && backendBookID != nil else { return }
            if ingestionStatus == .completed {
                aiSelectedLocatorJSON = locatorJSON
                aiSelectedText = text
            } else {
                isShowingAIProcessingAlert = true
            }
        }
        commands.onDefine = { text, locatorJSON, sentenceContext in
            definedLocatorJSON = locatorJSON
            definedWord = text
            definedSentenceContext = sentenceContext
        }
        // Load the sense-embedding model while the user reads, so the first
        // definition lookup doesn't pay the cold-start cost.
        Task.detached(priority: .utility) {
            await EmbeddingSenseRanker.shared.prewarm()
        }
        commands.onTranslate = { text in
            translateText = text
            isShowingTranslation = true
        }
        commands.onSearchText = { text in
            searchState.query = text
            searchState.scheduleSearch()
            isShowingSearch = true
        }
        commands.onAddNote = { text, locatorJSON, highlightID in
            pendingNoteLocatorJSON = locatorJSON
            pendingNoteText = text
            pendingNoteHighlightID = highlightID
        }
        commands.onEditNote = { noteID, _, _ in
            pendingEditNote = NoteStore.shared
                .notes(forBookID: bookID)
                .first(where: { $0.id == noteID })
        }
        commands.onTap = { point, size in
            let leftEdge = size.width * 0.1
            let rightEdge = size.width * 0.9
            if point.x < leftEdge {
                Task { await commands.goLeft?() }
            } else if point.x > rightEdge {
                Task { await commands.goRight?() }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { isShowingBars.toggle() }
            }
        }
    }

    @ViewBuilder
    func readerOverlayContent(for locator: Locator?) -> some View {
        let overlayCurrentPage: Int = {
            if let page = locator?.locations.position {
                return page
            } else if let prog = locator?.locations.totalProgression, totalPages > 0 {
                return max(1, Int(prog * Double(totalPages)))
            }
            return currentPage
        }()

        let overlayProgression: Double = {
            if let prog = locator?.locations.totalProgression {
                return prog
            }
            return currentProgression
        }()

        let overlayIsBookmarked = bookmarkOnCurrentPage(
            parsedLocators: parsedBookmarkLocators,
            currentLocator: locator ?? currentLocator,
            currentProgression: overlayProgression,
            positions: positions,
            isScrolling: settings.layout == .scrolling
        )

        ZStack {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(settings.colorTheme.dimColor.opacity(isActionButtonPresented ? 1 : 0))
                    .ignoresSafeArea()
                    .allowsHitTesting(isActionButtonPresented)
                    .onTapGesture { isActionButtonPresented = false }
                    .animation(.smooth(duration: 0.5, extraBounce: 0), value: isActionButtonPresented)

                ReaderOverlay(
                    bookTitle: bookTitle,
                    currentPage: overlayCurrentPage,
                    totalPages: totalPages,
                    isActive: isShowingBars,
                    foregroundColor: settings.colorTheme.foregroundColor,
                    backgroundColor: settings.colorTheme.backgroundColor,
                    isScrolling: settings.layout == .scrolling,
                    onDismiss: { dismiss() },
                    lastUndoJSON: navigationHistory.history.last,
                    onUndo: handleUndo
                )

                ReaderActionMenu(
                    isPresented: $isActionButtonPresented,
                    settings: $settings,
                    isScrubbing: $isScrubbing,
                    scrubTargetProgression: $scrubTargetProgression,
                    currentProgression: overlayProgression,
                    positions: positions,
                    tableOfContents: tableOfContents,
                    aiEnabled: aiEnabled,
                    ingestionReady: aiReady,
                    hasBackendBookID: backendBookID != nil,
                    isCurrentPageBookmarked: overlayIsBookmarked,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenAIChats: {
                        if aiReady {
                            isShowingAIChats = true
                        } else if aiEnabled {
                            isShowingAIProcessingAlert = true
                        } else {
                            dismiss()
                            onEnableAI()
                        }
                    },
                    onOpenTOC: { isShowingTOC = true },
                    onOpenSearch: { isShowingSearch = true },
                    onOpenNotes: { isShowingNotesList = true },
                    onOpenHighlights: { isShowingHighlightsList = true },
                    onOpenBookmarks: { isShowingBookmarksList = true },
                    onBookmark: { handleBookmarkToggle() },
                    onScrubReleased: { handleScrubReleased(progression: $0) }
                )
                .opacity(isShowingBars ? 1 : 0)
                .allowsHitTesting(isShowingBars)
            }

            BookmarkVisualOverlay(
                bookmarks: bookmarks,
                parsedLocators: parsedBookmarkLocators,
                positions: positions,
                currentLocator: locator ?? currentLocator,
                currentProgression: overlayProgression,
                isScrolling: settings.layout == .scrolling,
                isShowingBars: isShowingBars
            )
        }
    }
}

// MARK: - Note Sheet Content

extension ReaderScreen {
    @ViewBuilder
    var noteSheetContent: some View {
        if let existing = pendingEditNote {
            NoteSheetView(
                selectedText: existing.selectedText,
                locatorJSON: existing.locatorJSON,
                bookID: bookID,
                chapterTitle: existing.chapterTitle,
                pageNumber: existing.pageNumber,
                settings: settings,
                existingNote: existing,
                onSave: { updated in
                    NoteStore.shared.update(updated)
                    pendingEditNote = nil
                    notesVersion += 1
                },
                onDelete: {
                    NoteStore.shared.delete(id: existing.id)
                    pendingEditNote = nil
                },
                onDismiss: { pendingEditNote = nil }
            )
        } else if let text = pendingNoteText {
            NoteSheetView(
                selectedText: text,
                locatorJSON: pendingNoteLocatorJSON ?? "",
                bookID: bookID,
                chapterTitle: chapterTitle,
                pageNumber: currentPage > 0 ? currentPage : nil,
                settings: settings,
                onSave: { note in
                    NoteStore.shared.add(note)
                    // The note now owns this passage's decoration, so retire the
                    // standalone highlight it was created on top of (if any).
                    if let highlightID = pendingNoteHighlightID {
                        HighlightStore.shared.delete(id: highlightID)
                    }
                    pendingNoteText = nil
                    pendingNoteLocatorJSON = nil
                    pendingNoteHighlightID = nil
                    notesVersion += 1
                },
                onDismiss: {
                    pendingNoteText = nil
                    pendingNoteLocatorJSON = nil
                    pendingNoteHighlightID = nil
                }
            )
        }
    }
}

// MARK: - Bookmarks & Navigation

extension ReaderScreen {
    func handleBookmarkToggle() {
        guard let locator = currentLocator, let locatorJSON = locator.jsonString else { return }
        let added = BookmarkStore.shared.toggle(
            bookID: bookID,
            progression: currentProgression,
            locatorJSON: locatorJSON,
            chapterTitle: chapterTitle,
            pageNumber: currentPage > 0 ? currentPage : nil
        )
        let generator = UIImpactFeedbackGenerator(style: added ? .medium : .light)
        generator.impactOccurred()
    }

    func handleScrubReleased(progression: Double) {
        guard totalPages > 0, !positions.isEmpty else { return }
        let targetIndex = max(0, min(Int(progression * Double(totalPages)), totalPages - 1))
        guard let json = positions[targetIndex].jsonString else { return }
        jump(toLocatorJSON: json)
    }

    func handleUndo() {
        guard let poppedJSON = navigationHistory.pop() else { return }
        Task { @MainActor in
            await commands.goToLocatorJSON?(poppedJSON)
        }
    }
}
