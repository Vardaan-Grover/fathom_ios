import SwiftUI

/// A quiet line at the top of the library while records are arriving.
///
/// This is the everyday case — the first sync gets `SyncSetupScreen`, and every
/// sync after it gets this. It follows the rule Apple's own sync surfaces
/// follow: say nothing unless something is actually happening. A fetch that
/// finds no changes shows nothing at all, because `SyncActivity` waits for a
/// record to arrive before it counts as news.
///
/// It never takes touches — the library stays fully usable underneath while its
/// contents fill in.
struct SyncStatusBanner: View {

    @ObservedObject var activity: SyncActivity

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweep = false

    private var isVisible: Bool {
        switch activity.phase {
        case .gathering: activity.hasArrivals
        case .settled:   true
        case .idle:      false
        }
    }

    var body: some View {
        Group {
            if isVisible {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .animation(.easeInOut(duration: 0.3), value: activity.phase)
    }

    private var content: some View {
        HStack(spacing: 8) {
            mark

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.colors.primary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
        // Decoration, not a control. Without this it would sit over the top row
        // of shelves and quietly eat taps on them.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch activity.phase {
        case .settled: "Library up to date"
        default:       "Syncing \(activity.received) items"
        }
    }

    /// A small hand-drawn mark rather than a UIActivityIndicator: a spinner is
    /// the one piece of chrome that would look borrowed from another app.
    @ViewBuilder
    private var mark: some View {
        switch activity.phase {
        case .settled:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.colors.shelfAccent)
                .transition(.scale.combined(with: .opacity))
        default:
            Image("Spark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(theme.colors.shelfAccent)
                .opacity(sweep ? 1 : 0.35)
                .scaleEffect(sweep ? 1 : 0.82)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        sweep = true
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    SyncStatusBanner(activity: .shared)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.default.colors.background)
}
