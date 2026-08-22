import SwiftUI

/// A small cloud glyph in the library header while records are moving.
///
/// It replaced a pill at the foot of the screen. The pill carried a live count,
/// which is genuinely more informative — but it also occupied a whole row to
/// say something that is usually over in a second, and the count only really
/// earns its space on a first sync, where `SyncSetupScreen` still shows it.
///
/// **Transient on purpose.** The finished state holds for a moment and then
/// goes away, rather than leaving a permanent green tick in the header. An
/// always-on "everything is fine" badge is chrome that never tells you
/// anything: Files and Photos both show their cloud glyph during activity and
/// hide it the rest of the time. It is status, not a control — there is nothing
/// to tap, because there is nothing a tap should do that the app is not already
/// doing by itself.
struct SyncStatusIndicator: View {

    @ObservedObject private var activity = SyncActivity.shared

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var spin = false

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
                glyph
                    .frame(width: 26, height: 26)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .animation(.spring(duration: 0.34, bounce: 0.12), value: isVisible)
        .animation(.spring(duration: 0.34, bounce: 0.12), value: activity.phase)
    }

    @ViewBuilder
    private var glyph: some View {
        switch activity.phase {
        case .settled:
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 17, weight: .medium))
                // Green reads as "done" everywhere in iOS, and this is the one
                // moment the header is allowed a colour that is not the app's.
                .foregroundStyle(.white, .green)

        default:
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.secondary)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                }
                .onDisappear { spin = false }
        }
    }

    private var accessibilityLabel: String {
        switch activity.phase {
        case .settled: "Library up to date"
        default:       "Syncing \(activity.received) items"
        }
    }
}

// MARK: - Preview

#Preview {
    SyncStatusIndicator()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.default.colors.background)
}
