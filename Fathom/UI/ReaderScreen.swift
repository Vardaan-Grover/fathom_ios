import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI

struct ReaderScreen: View {
    let bookFileURL: URL
    let bookTitle: String
    let bookID: UUID
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

    // Vocabulary State
    @State private var definedWord: String?
    @State private var definedLocatorJSON: String?

    @State private var isActionButtonPresented = false
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var positions: [Locator] = []
    @State private var currentProgression: Double = 0.0
    @State private var currentLocator: Locator?
    @StateObject private var navigationHistory = ReaderNavigationHistory()
    @State private var isScrubbing: Bool = false
    @State private var scrubTargetProgression: Double = 0.0
    @StateObject private var loader = PublicationLoader()
    @State private var tableOfContents: [ReadiumShared.Link] = []
    @State private var aiSelectedText: String?
    @State private var aiSelectedLocatorJSON: String?

    @Environment(\.dismiss) private var dismiss

    private var aiReady: Bool { aiEnabled && ingestionStatus == .completed }

    // Current chapter title derived from the table of contents and positions.
    // Mirrors the logic used in the scrub preview so the shown chapter matches
    // what the TOC and scrub preview display.
    private var chapterTitle: String? {
        // Prefer TOC-derived titles when available so the UI matches TableOfContentsSheet
        guard !tableOfContents.isEmpty else { return currentLocator?.title }

        let prog = currentLocator?.locations.totalProgression ?? currentProgression

        var markers: [(prog: Double, title: String)] = []
        for link in tableOfContents {
            guard let title = link.title, !title.isEmpty else { continue }
            let linkHref = "\(link.href)".components(separatedBy: "#").first ?? "\(link.href)"
            let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

            let match =
                positions.first(where: { "\($0.href)" == linkHref })
                ?? positions.first(where: {
                    let fn = "\($0.href)".split(separator: "/").last.map(String.init) ?? ""
                    return !linkFilename.isEmpty && fn == linkFilename
                })

            if let pos = match, let p = pos.locations.totalProgression {
                markers.append((prog: p, title: title))
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
                ReadiumNavigatorView(
                    publication: publication,
                    initialLocation: ReadingStateStore.shared.loadLocator(forBookID: bookID),
                    onLocationChange: { locator in
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
                    },
                    onPositionsLoaded: { loadedPositions in
                        positions = loadedPositions
                        totalPages = loadedPositions.count
                    },
                    commands: commands,
                    settings: settings,
                    bookID: bookID,
                    aiQueryLocatorJSON: aiSelectedText != nil ? aiSelectedLocatorJSON : nil,
                    aiEnabled: aiEnabled && backendBookID != nil
                )
                .ignoresSafeArea()
                .task {
                    if let links = try? await publication.tableOfContents().get() {
                        self.tableOfContents = links
                    }
                }
                .onAppear {
                    commands.onExplain = { text, locatorJSON in
                        guard aiEnabled && backendBookID != nil else { return }
                        if ingestionStatus == .completed {
                            aiSelectedLocatorJSON = locatorJSON
                            aiSelectedText = text
                        } else {
                            isShowingAIProcessingAlert = true
                        }
                    }
                    commands.onDefine = { text, locatorJSON in
                        definedLocatorJSON = locatorJSON
                        definedWord = text
                    }
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
                }
                .overlay {
                    ZStack {
                        // Main Bottom Trailing controls
                        ZStack(alignment: .bottomTrailing) {
                            Rectangle()
                                .fill(
                                    settings.colorTheme.dimColor.opacity(
                                        isActionButtonPresented ? 1 : 0)
                                )
                                .blur(radius: 20)
                                .ignoresSafeArea()
                                .allowsHitTesting(isActionButtonPresented)
                                .onTapGesture { isActionButtonPresented = false }
                                .animation(
                                    .smooth(duration: 0.5, extraBounce: 0),
                                    value: isActionButtonPresented)

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
                                onScrubReleased: { targetProgression in
                                    handleScrubReleased(progression: targetProgression)
                                }
                            )
                            .opacity(isShowingBars ? 1 : 0)
                            .allowsHitTesting(isShowingBars)
                        }

                    }
                }
                .sheet(
                    isPresented: $isShowingTOC,
                    onDismiss: {
                        guard let json = pendingTOCLocatorJSON else { return }
                        pendingTOCLocatorJSON = nil
                        if let currentLocator = currentLocator {
                            navigationHistory.push(currentLocator)
                        }
                        Task { @MainActor in await commands.goToLocatorJSON?(json) }
                    }
                ) {
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
                    }
                }
            )
        ) {
            if let word = definedWord {
                VocabularySheetView(
                    viewModel: VocabularySheetViewModel(
                        word: word,
                        bookID: bookID,
                        chapter: chapterTitle,
                        pageNumber: currentPage > 0 ? currentPage : nil,
                        locatorJSON: definedLocatorJSON,
                        repository: VocabularyRepositorySQLite(
                            dbQueue: DatabaseManager.shared.dbQueue)
                    )
                )
            }
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

        // Use only the top-level TOC entries — the same set that TableOfContentsSheet
        // displays — so the shown title always matches what the reader sees in the TOC.
        guard !tableOfContents.isEmpty else { return projectedLocator?.title }

        // For each TOC entry find the totalProgression of the first position whose
        // spine item matches. Falling back to filename-only comparison handles the
        // common case where position hrefs and TOC hrefs have different base paths.
        var markers: [(prog: Double, title: String)] = []
        for link in tableOfContents {
            guard let title = link.title, !title.isEmpty else { continue }
            let linkHref = "\(link.href)".components(separatedBy: "#").first ?? "\(link.href)"
            let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

            let match =
                positions.first(where: { "\($0.href)" == linkHref })
                ?? positions.first(where: {
                    let fn = "\($0.href)".split(separator: "/").last.map(String.init) ?? ""
                    return !linkFilename.isEmpty && fn == linkFilename
                })

            if let pos = match, let prog = pos.locations.totalProgression {
                markers.append((prog: prog, title: title))
            }
        }

        guard !markers.isEmpty else { return projectedLocator?.title }
        markers.sort { $0.prog < $1.prog }

        // The current chapter is the last one whose start progression ≤ scrub position.
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
