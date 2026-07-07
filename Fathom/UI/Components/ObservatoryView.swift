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

    /// Cap the live states to 30fps — the sweep/pulse are slow, so the display's
    /// full (up to 120Hz) refresh would just burn energy for no visible gain.
    private let frameInterval = 1.0 / 30.0

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

    /// The dependency-free composition — the fallback (and current look) until the
    /// Lottie assets are added.
    private var nativeGlyph: some View {
        ZStack {
            // The lens.
            Circle()
                .fill(ink.opacity(colorScheme == .dark ? 0.16 : 0.08))
                .overlay(Circle().stroke(ink.opacity(0.18), lineWidth: 1))

            // Live decoration only for the state that needs it — `.idle` draws
            // nothing animated, so the home screen does zero continuous work.
            if !reduceMotion {
                switch phase {
                case .pending:  pendingPulse
                case .spotting: radarSweep
                case .idle:     EmptyView()
                }
            }

            // The core: a little telescope, dim at rest, lit while active.
            Image("Telescope")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ink)
                .frame(width: 22, height: 22)
                .opacity(phase == .idle ? 0.45 : 1)

            // Pending badge — a tiny "new" spark in the corner.
            if phase == .pending {
                Circle()
                    .fill(ink)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 17, y: -17)
            }
        }
    }

    /// A radar sweep rotating around the lens (spotting). Frame-capped TimelineView
    /// instead of a forever-running implicit animation.
    private var radarSweep: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let cycle = 2.4
            let angle = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle) / cycle * 360
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    AngularGradient(colors: [ink.opacity(0), ink.opacity(0.7)], center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(angle))
                .padding(3)
        }
    }

    /// A soft halo radiating outward (pending). Same frame-capped clock.
    private var pendingPulse: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let cycle = 1.6
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle) / cycle
            Circle()
                .stroke(ink.opacity(0.5), lineWidth: 2)
                .scaleEffect(0.9 + 0.45 * t)
                .opacity(0.7 * (1 - t))
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .idle:     return "Memory Garden"
        case .spotting: return "Spotting tonight's doodle. Open Memory Garden."
        case .pending:  return "A new doodle is waiting. Open Memory Garden."
        }
    }
}
