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
    @State private var settings: ReaderSettings = ReaderSettingsStore.shared.load()
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
                        initialLocation: ReadingStateStore.shared.loadLocator(forBookID: bookID),
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
            }
            .sheet(isPresented: $isShowingSettings) {
                ReaderSettingsView(settings: $settings)
                    .presentationDetents([.medium])
                    .onChange(of: settings) { _, newSettings in
                        ReaderSettingsStore.shared.save(newSettings)
                    }
            }
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
