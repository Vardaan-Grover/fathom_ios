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
    @State private var definedContextSentence: String?

    // Note State
    @State private var pendingNoteText: String?
    @State private var pendingNoteLocatorJSON: String?
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
        guard !tableOfContents.isEmpty else { return currentLocator?.title }

        let prog = currentLocator?.locations.totalProgression ?? currentProgression

        var markers: [(prog: Double, title: String)] = []
        for entry in flattenedTOCEntries(tableOfContents) {
            guard !entry.breadcrumbTitle.isEmpty else { continue }
            let linkHref = "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
            let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

            let match =
                positions.first(where: { "\($0.href)" == linkHref })
                ?? positions.first(where: {
                    let fn = "\($0.href)".split(separator: "/").last.map(String.init) ?? ""
                    return !linkFilename.isEmpty && fn == linkFilename
                })

            if let pos = match, let p = pos.locations.totalProgression {
                markers.append((prog: p, title: entry.breadcrumbTitle))
            }
        }

        guard !markers.isEmpty else { return currentLocator?.title }
        markers.sort { $0.prog < $1.prog }

        return markers.last(where: { $0.prog <= prog })?.title ?? markers.first?.title
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
                        definedContextSentence = nil
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
                        contextSentence: definedContextSentence,
                        repository: VocabularyRepositorySQLite(
                            dbQueue: DatabaseManager.shared.dbQueue)
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

    func loadedView(publication: Publication) -> some View {
        navigatorCore(publication: publication)
            .sheet(isPresented: $isShowingTOC, onDismiss: {
                guard let json = pendingTOCLocatorJSON else { return }
                pendingTOCLocatorJSON = nil
                if let currentLocator { navigationHistory.push(currentLocator) }
                Task { @MainActor in await commands.goToLocatorJSON?(json) }
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
                if let currentLocator { navigationHistory.push(currentLocator) }
                Task { @MainActor in await commands.goToLocatorJSON?(json) }
            }) {
                NotesListView(bookID: bookID) { pendingNotesListLocatorJSON = $0 }
            }
            .sheet(isPresented: $isShowingHighlightsList, onDismiss: {
                guard let json = pendingHighlightsLocatorJSON else { return }
                pendingHighlightsLocatorJSON = nil
                if let currentLocator { navigationHistory.push(currentLocator) }
                Task { @MainActor in await commands.goToLocatorJSON?(json) }
            }) {
                HighlightsListView(bookID: bookID) { pendingHighlightsLocatorJSON = $0 }
            }
            .sheet(isPresented: $isShowingBookmarksList, onDismiss: {
                guard let json = pendingBookmarksLocatorJSON else { return }
                pendingBookmarksLocatorJSON = nil
                if let currentLocator { navigationHistory.push(currentLocator) }
                Task { @MainActor in await commands.goToLocatorJSON?(json) }
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
            onLocationChange: onLocationChange,
            onPositionsLoaded: { positions = $0; totalPages = $0.count },
            commands: commands,
            settings: settings,
            bookID: bookID,
            aiQueryLocatorJSON: aiSelectedText != nil ? aiSelectedLocatorJSON : nil,
            aiEnabled: aiEnabled && backendBookID != nil,
            notesVersion: notesVersion
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
        .overlay { readerOverlayContent }
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
        commands.onDefine = { text, locatorJSON, contextSentence in
            definedLocatorJSON = locatorJSON
            definedWord = text
            definedContextSentence = contextSentence
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
        commands.onAddNote = { text, locatorJSON in
            pendingNoteLocatorJSON = locatorJSON
            pendingNoteText = text
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
    var readerOverlayContent: some View {
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
                    currentPage: currentPage,
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
                    currentProgression: currentProgression,
                    positions: positions,
                    tableOfContents: tableOfContents,
                    aiEnabled: aiEnabled,
                    ingestionReady: aiReady,
                    hasBackendBookID: backendBookID != nil,
                    isCurrentPageBookmarked: isCurrentPageBookmarked,
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
                currentLocator: currentLocator,
                currentProgression: currentProgression,
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
                    pendingNoteText = nil
                    pendingNoteLocatorJSON = nil
                    notesVersion += 1
                },
                onDismiss: {
                    pendingNoteText = nil
                    pendingNoteLocatorJSON = nil
                }
            )
        }
    }
}

// MARK: - Bookmark Toggle

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
}

extension ReaderScreen {
    func handleScrubReleased(progression: Double) {
        guard totalPages > 0, !positions.isEmpty else { return }

        // Find best position
        let targetIndex = max(0, min(Int(progression * Double(totalPages)), totalPages - 1))
        let targetLocator = positions[targetIndex]

        // Push current locator to history BEFORE jumping
        if let currentLocator = currentLocator {
            navigationHistory.push(currentLocator)
        }

        Task { @MainActor in
            guard let json = targetLocator.jsonString else { return }
            await commands.goToLocatorJSON?(json)
        }
    }
}

extension ReaderScreen {
    func handleUndo() {
        guard let poppedJSON = navigationHistory.pop() else { return }
        Task { @MainActor in
            await commands.goToLocatorJSON?(poppedJSON)
        }
    }
}

struct ScrubPreviewPopover: View {
    let progression: Double
    let positions: [Locator]
    let tableOfContents: [ReadiumShared.Link]
    let foregroundColor: SwiftUI.Color
    let backgroundColor: SwiftUI.Color

    private var projectedLocator: Locator? {
        guard !positions.isEmpty else { return nil }
        let index = max(0, min(Int(progression * Double(positions.count - 1)), positions.count - 1))
        return positions[index]
    }

    private var chapterTitle: String? {
        guard !positions.isEmpty else { return nil }
        guard !tableOfContents.isEmpty else { return projectedLocator?.title }

        var markers: [(prog: Double, title: String)] = []
        for entry in flattenedTOCEntries(tableOfContents) {
            guard !entry.breadcrumbTitle.isEmpty else { continue }
            let linkHref = "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
            let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

            let match =
                positions.first(where: { "\($0.href)" == linkHref })
                ?? positions.first(where: {
                    let fn = "\($0.href)".split(separator: "/").last.map(String.init) ?? ""
                    return !linkFilename.isEmpty && fn == linkFilename
                })

            if let pos = match, let prog = pos.locations.totalProgression {
                markers.append((prog: prog, title: entry.breadcrumbTitle))
            }
        }

        guard !markers.isEmpty else { return projectedLocator?.title }
        markers.sort { $0.prog < $1.prog }

        return markers.last(where: { $0.prog <= progression })?.title ?? markers.first?.title
    }

    var body: some View {
        if let locator = projectedLocator {
            VStack(spacing: 6) {
                if let title = chapterTitle, !title.isEmpty {
                    Text(title.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(foregroundColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if let position = locator.locations.position, positions.count > 0 {
                    Text("Page \(position)")
                        .font(.body)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                } else {
                    Text("\(Int(progression * 100))%")
                        .font(.body)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            EmptyView()
        }
    }
}

@MainActor
final class ReaderNavigationHistory: ObservableObject {
    @Published var history: [String] = []

    private let maxDepth = 20

    func push(_ locator: Locator) {
        guard let json = locator.jsonString else { return }
        if history.last != json {
            history.append(json)
            if history.count > maxDepth {
                history.removeFirst()
            }
        }
    }

    func pop() -> String? {
        guard !history.isEmpty else { return nil }
        return history.removeLast()
    }

    func clear() {
        history.removeAll()
    }
}

// MARK: - Bookmark Locator Helpers

struct ParsedBookmarkLocator {
    let id: UUID
    let href: String
    let inChapterProg: Double
    let totalProg: Double
}

/// Parse bookmark locators once; called only when the bookmarks array changes.
private func parseBookmarkLocators(_ bookmarks: [Bookmark]) -> [ParsedBookmarkLocator] {
    bookmarks.compactMap { b in
        guard let loc = try? Locator(jsonString: b.locatorJSON) else { return nil }
        return ParsedBookmarkLocator(
            id: b.id,
            href: "\(loc.href)",
            inChapterProg: loc.locations.progression ?? 0,
            totalProg: b.progression
        )
    }
}

/// Returns true if any parsed bookmark falls on the current rendered page.
///
/// Paginated mode: uses the positions array to determine the exact in-chapter
/// progression range for the current page, then checks if any bookmark's
/// in-chapter progression falls within that range. Self-corrects after font-size
/// changes because both the stored progression and the current positions list
/// use the same (pageIndex / totalPages) formula.
///
/// Scroll mode: matches by same chapter + in-chapter progression within 5%.
private func bookmarkOnCurrentPage(
    parsedLocators: [ParsedBookmarkLocator],
    currentLocator: Locator?,
    currentProgression: Double,
    positions: [Locator],
    isScrolling: Bool
) -> Bool {
    guard !parsedLocators.isEmpty else { return false }

    guard let current = currentLocator else {
        // No locator yet — tight totalProgression fallback
        return parsedLocators.contains { abs($0.totalProg - currentProgression) <= 0.003 }
    }

    let currentHref = "\(current.href)"

    if isScrolling {
        // Scroll mode: same chapter + in-chapter progression within 5%
        let currentProg = current.locations.progression ?? currentProgression
        return parsedLocators.contains { b in
            b.href == currentHref && abs(b.inChapterProg - currentProg) <= 0.05
        }
    }

    // Paginated mode: range check using current positions list
    let resourcePositions = positions.filter { "\($0.href)" == currentHref }
    guard !resourcePositions.isEmpty,
          let idx = resourcePositions.firstIndex(where: {
              $0.locations.position == current.locations.position
          }) else {
        // Positions not yet loaded or page not found — tight fallback
        return parsedLocators.contains { abs($0.totalProg - currentProgression) <= 0.003 }
    }

    let rangeStart = resourcePositions[idx].locations.progression ?? 0.0
    let rangeEnd = idx + 1 < resourcePositions.count
        ? (resourcePositions[idx + 1].locations.progression ?? 1.0)
        : 1.0

    return parsedLocators.contains { b in
        b.href == currentHref &&
        b.inChapterProg >= rangeStart &&
        b.inChapterProg < rangeEnd
    }
}

// MARK: - Bookmark Visual Overlay

struct BookmarkVisualOverlay: View {
    let bookmarks: [Bookmark]
    let parsedLocators: [ParsedBookmarkLocator]
    let positions: [Locator]
    let currentLocator: Locator?
    let currentProgression: Double
    let isScrolling: Bool
    let isShowingBars: Bool

    private static let crimson = Color(red: 0.78, green: 0.08, blue: 0.15)

    private var isBookmarked: Bool {
        bookmarkOnCurrentPage(
            parsedLocators: parsedLocators,
            currentLocator: currentLocator,
            currentProgression: currentProgression,
            positions: positions,
            isScrolling: isScrolling
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let yOffset = isShowingBars ? topInset : 0.0

            Group {
                if isScrolling {
                    scrollContent(proxy: proxy, yOffset: yOffset)
                } else {
                    paginatedContent(yOffset: yOffset)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isBookmarked)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func paginatedContent(yOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                if isBookmarked {
                    BookmarkRibbonShape()
                        .fill(Self.crimson)
                        .frame(width: 18, height: 52)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: -1, y: 2)
                        .padding(.trailing, 22)
                        .offset(y: yOffset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func scrollContent(proxy: GeometryProxy, yOffset: CGFloat) -> some View {
        ZStack {
            // Side-rail mini markers at proportional positions along right edge
            ForEach(bookmarks) { bookmark in
                BookmarkRibbonShape()
                    .fill(Self.crimson.opacity(0.65))
                    .frame(width: 10, height: 20)
                    .position(
                        x: proxy.size.width - 6,
                        y: max(10, proxy.size.height * bookmark.progression)
                    )
            }

            // Full corner ribbon when near a bookmark
            if isBookmarked {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        BookmarkRibbonShape()
                            .fill(Self.crimson)
                            .frame(width: 18, height: 52)
                            .shadow(color: .black.opacity(0.25), radius: 3, x: -1, y: 2)
                            .padding(.trailing, 22)
                            .offset(y: yOffset)
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct BookmarkRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notchDepth = rect.width * 0.42
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notchDepth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
