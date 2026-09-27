import SwiftUI
import UIKit

@main
struct FathomApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService = AuthService()
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var themeManager = ThemeManager()

    private let bookRepository: BookRepository
    private let vocabularyRepo: VocabularyRepository

    init() {
        #if DEBUG
        // Started here rather than from the launch bootstrap so it is running
        // before the first main-thread work happens — and so it can capture the
        // main thread's port synchronously. Capturing it from a background
        // thread means queueing behind whatever block we are trying to sample,
        // which is why the first block of a launch used to report no stack.
        MainThreadWatchdog.start()
        SyncActivity.startPreviewIfRequested()
        #endif

        // Sync comes up at process launch rather than from a view: CKSyncEngine
        // only hears pushes once it exists, and a push can launch the app in
        // the background with no scene — and so no view `.task` — at all.
        // Idempotent, so extra windows and re-created scenes cannot start it
        // twice.
        Task.detached(priority: .userInitiated) { await SyncBootstrap.start() }

        let container = AppContainer.shared
        bookRepository = container.bookRepo
        vocabularyRepo = container.vocabularyRepo
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            bookRepository: container.bookRepo,
            categoryRepository: container.categoryRepo
        ))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(
            bookRepo: container.bookRepo,
            preprocessingCoordinator: container.preprocessingCoordinator
        ))
    }

    var body: some Scene {
        WindowGroup {
            ToastRootView {
                AuthFlowView(
                    homeViewModel: homeViewModel,
                    libraryViewModel: libraryViewModel,
                    bookRepository: bookRepository,
                    vocabularyRepo: vocabularyRepo
                )
                .environmentObject(authService)
                .environmentObject(themeManager)
                .task {
                    if FeatureFlags.accountsEnabled {
                        await authService.startListening()
                    }
                }
                // MetricKit delivers at most once a day; registering is the
                // whole cost. Payloads stay on device — see DiskMetricsSink.
                .task { DiagnosticsSubscriber.start() }
                .task { await homeViewModel.load() }
                .onOpenURL { url in
                    if url.isFileURL && url.pathExtension.lowercased() == "epub" {
                        libraryViewModel.handleIncomingEPUB(url)
                    } else if FeatureFlags.accountsEnabled {
                        Task { try? await authService.handleDeepLink(url) }
                    }
                }
                .themed(with: themeManager)
                // Pull remote changes whenever the app comes to the foreground.
                // SyncEngine guards internally if not started (no iCloud/paid account).
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await SyncEngine.shared.fetchChangesIfNeeded() }
                    } else {
                        // Positions and settings are disk-written on a debounce;
                        // force the pending writes out before we can be killed,
                        // then push them while the system still lets us run.
                        let positions = ReadingStateStore.shared.flush()
                        let settingsChanged = ReaderSettingsStore.shared.flush()
                        SuspensionSync.push(positions: positions, settingsChanged: settingsChanged)
                    }
                }
            }
        }
    }
}

/// Sends pending changes inside a background task when the app leaves the
/// foreground, so the last reading session reaches iCloud before suspension
/// rather than at the next launch.
@MainActor
private enum SuspensionSync {

    /// Holds the task identifier for both the expiration handler and the
    /// completion, which may race.
    private final class TaskBox {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    static func push(positions: Set<UUID>, settingsChanged: Bool) {
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "Fathom iCloud sync") {
            box.end()
        }
        Task {
            await SyncEngine.shared.sendBeforeSuspension(positions: positions,
                                                         settingsChanged: settingsChanged)
            box.end()
        }
    }
}
