import SwiftUI
import UIKit

/// The home-screen observatory: a small, live celestial emblem in the top-right
/// that makes the Memory Garden an active part of the app. It scans for tonight's
/// doodle while you read, glows when one is waiting to be revealed, and is the
/// one-tap doorway into the garden.
struct ObservatoryView: View {
    let bookRepository: BookRepository
    /// Bumped by the host to re-evaluate state (e.g. after a reading session).
    var refreshTrigger: Int = 0
    var onTap: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: ObservatoryViewModel
    @State private var showReveal = false

    init(bookRepository: BookRepository, refreshTrigger: Int = 0, onTap: @escaping () -> Void) {
        self.bookRepository = bookRepository
        self.refreshTrigger = refreshTrigger
        self.onTap = onTap
        _viewModel = StateObject(wrappedValue: ObservatoryViewModel(repository: bookRepository))
    }

    /// The garden's deep-blue ink, matched here so the home emblem belongs to it.
    private var ink: Color {
        let base = Color(hex: "1530E6")
        return colorScheme == .dark ? base.adjusted(saturationScale: 1, brightnessDelta: 0.12) : base
    }

    private var phase: ObservatoryViewModel.Phase { viewModel.phase }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleTap()
        } label: {
            Group {
                // Prefer a recolored Lottie for this state once it's available;
                // otherwise the native composition (works today, no dependency).
                if let lottie = lottieName, LottieAsset.available(lottie), !reduceMotion {
                    LottieView(name: lottie, loop: .loop, isPlaying: true, tint: ink)
                } else {
                    nativeGlyph
                }
            }
            .frame(width: 46, height: 46)
            .shadow(color: ink.opacity(phase == .pending ? 0.5 : 0.18),
                    radius: phase == .pending ? 9 : 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .onAppear { Task { await viewModel.refresh() } }
        .onChange(of: refreshTrigger) { _, _ in
            Task { await viewModel.refresh() }
        }
        // Refresh the moment a reading session is committed — fixes the race where
        // the old refresh fired before the write landed.
        .onReceive(NotificationCenter.default.publisher(for: .fathomReadingSessionLogged)) { _ in
            Task { await viewModel.refresh() }
        }
        .fullScreenCover(isPresented: $showReveal, onDismiss: {
            Task { await viewModel.refresh() }   // pending clears now that it's seen
        }) {
            if let doodle = viewModel.pendingDoodle, let key = viewModel.pendingDayKey {
                // The reveal now happens *inside* the real garden, so the doodle
                // can fly into its actual month-grid cell.
                MemoryGardenView(
                    bookRepository: bookRepository,
                    revealRequest: RevealRequest(
                        doodleName: doodle,
                        date: Self.dayFormatter.date(from: key) ?? Date(),
                        tierTitle: DoodleTier.tier(for: viewModel.pendingDuration).title
                    )
                )
            }
        }
    }

    /// Pending → run the reveal ceremony (and mark the day seen now, so it counts
    /// as revealed even if the ceremony is swiped away). Otherwise just open the
    /// garden.
    private func handleTap() {
        if viewModel.phase == .pending, viewModel.pendingDoodle != nil {
            if let key = viewModel.pendingDayKey {
                UserDefaults.standard.set(key, forKey: ObservatoryViewModel.lastRevealedKey)
            }
            showReveal = true
        } else {
            onTap()
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The Lottie animation file for each state (drop these JSONs into the app to
    /// light them up). Idle stays native/static — no animation needed.
    private var lottieName: String? {
        switch phase {
        case .idle:     return nil
        case .spotting: return "observatory_spotting"
        case .pending:  return "observatory_pending"
        }
    }

    /// The dependency-free celestial emblem — the fallback (and current look)
    /// until the Lottie assets are added.
    private var nativeGlyph: some View {
        ObservatoryGlyph(phase: phase, ink: ink, reduceMotion: reduceMotion)
    }

    private var accessibilityText: String {
        switch phase {
        case .idle:     return "Memory Garden"
        case .spotting: return "Spotting tonight's doodle. Open Memory Garden."
        case .pending:  return "A new doodle is waiting. Open Memory Garden."
        }
    }
}
