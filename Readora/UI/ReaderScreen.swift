import ReadiumNavigator
import ReadiumShared
import SwiftUI

struct ReaderScreen: View {
    let bookFileURL: URL
    let bookTitle: String
    let bookID: UUID

    private let commands = NavigatorCommands()

    @State private var isShowingBars = true
    @State private var isShowingSettings = false
    @State private var isActionButtonPresented = false
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @StateObject private var loader = PublicationLoader()

    @Environment(\.dismiss) private var dismiss

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

                    Button { dismiss() } label: {
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
                }
                .overlay {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                            .fill(settings.colorTheme.dimColor.opacity(isActionButtonPresented ? 1 : 0))
                            .blur(radius: 20)
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
                            onDismiss: { dismiss() }
                        )

                        ReaderActionMenu(
                            isPresented: $isActionButtonPresented,
                            settings: $settings,
                            onOpenSettings: { isShowingSettings = true }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsView(settings: $settings)
                .onChange(of: settings) { _, newSettings in
                    ReaderSettingsStore.shared.save(newSettings)
                }
        }
    }

}
