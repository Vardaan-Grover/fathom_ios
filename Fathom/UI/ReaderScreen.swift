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

    @State private var commands = NavigatorCommands()

    @State private var isShowingBars = true
    @State private var isShowingSettings = false
    @State private var isShowingAIChats = false
    @State private var isShowingAIProcessingAlert = false
    @State private var isShowingTOC = false
    @State private var pendingTOCLocator: ReadiumShared.Locator? = nil
    @State private var isActionButtonPresented = false
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @StateObject private var loader = PublicationLoader()
    @State private var aiSelectedText: String?
    @State private var aiSelectedLocatorJSON: String?

    @Environment(\.dismiss) private var dismiss

    private var aiReady: Bool { aiEnabled && ingestionStatus == .completed }

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
                        if let page = locator.locations.position {
                            currentPage = page
                        } else if let prog = locator.locations.totalProgression, totalPages > 0 {
                            currentPage = max(1, Int(prog * Double(totalPages)))
                        }
                    },
                    onPositionsLoaded: { count in
                        totalPages = count
                    },
                    commands: commands,
                    settings: settings,
                    bookID: bookID,
                    aiQueryLocatorJSON: aiSelectedText != nil ? aiSelectedLocatorJSON : nil,
                    aiEnabled: aiEnabled && backendBookID != nil
                )
                .ignoresSafeArea()
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
                            isScrolling: settings.layout == .scrolling,
                            onDismiss: { dismiss() }
                        )

                        ReaderActionMenu(
                            isPresented: $isActionButtonPresented,
                            settings: $settings,
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
                            onOpenTOC: { isShowingTOC = true }
                        )
                        .opacity(isShowingBars ? 1 : 0)
                        .allowsHitTesting(isShowingBars)
                    }
                }
                .sheet(isPresented: $isShowingTOC, onDismiss: {
                    guard let locator = pendingTOCLocator else { return }
                    pendingTOCLocator = nil
                    Task { @MainActor in await commands.goToLocator?(locator) }
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
                                pendingTOCLocator = Locator(
                                    href: roLink.url(),
                                    mediaType: mediaType,
                                    title: link.title ?? roLink.title,
                                    locations: Locator.Locations(
                                        fragments: fragment.map { [$0] } ?? [],
                                        progression: fragment == nil ? 0.0 : nil
                                    )
                                )
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
