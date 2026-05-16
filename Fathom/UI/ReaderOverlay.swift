import ReadiumShared
import SwiftUI

struct ReaderOverlay: View {
    let bookTitle: String
    let currentPage: Int
    let totalPages: Int
    let isActive: Bool
    let foregroundColor: Color
    let backgroundColor: Color
    let isScrolling: Bool
    let onDismiss: () -> Void
    var lastUndoJSON: String? = nil
    var onUndo: () -> Void = {}

    private var textColor: Color { foregroundColor }

    private var pageLabel: String {
        guard currentPage > 0 else { return "" }
        return isActive && totalPages > 0
            ? "\(currentPage) of \(totalPages)"
            : "Page \(currentPage)"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var topBar: some View {
        // Side elements take their natural size; title claims whatever space remains.
        // An invisible placeholder (same width as the back button) fills the trailing
        // slot when the undo button is absent, keeping the title visually centred.
        // The back button uses opacity rather than conditional inclusion so the
        // layout — and therefore the title position — stays stable when bars toggle.
        HStack(spacing: 8) {

            // Leading: back button (always in layout, invisible when bars hidden)
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .background(Group { if isScrolling {
                if #available(iOS 26, *) { Circle().glassEffect(.regular) }
                else { Circle().fill(.ultraThinMaterial) }
            } })
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)

            // Centre: title, takes all remaining space
            Text(bookTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(textColor.opacity(isActive ? 0.9 : 0.4))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, isScrolling ? 14 : 0)
                .padding(.vertical, isScrolling ? 6 : 0)
                .background(Group { if isScrolling {
                    if #available(iOS 26, *) { Capsule().glassEffect(.regular) }
                    else { Capsule().fill(.ultraThinMaterial) }
                } })
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(isScrolling && !isActive ? 0 : 1)

            // Trailing: undo button when available, otherwise an invisible
            // placeholder matching the back button width to keep the title centred.
            if isActive, let undoJSON = lastUndoJSON {
                UndoJumpButton(
                    lastLocatorJSON: undoJSON,
                    foregroundColor: foregroundColor,
                    backgroundColor: backgroundColor,
                    onUndo: onUndo
                )
                .transition(.scale.combined(with: .opacity))
                .fixedSize()
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: lastUndoJSON)
    }

    private var bottomBar: some View {
        ZStack {
            if !pageLabel.isEmpty {
                Text(pageLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor.opacity(isActive ? 0.9 : 0.4))
                    .padding(.horizontal, isScrolling ? 14 : 0)
                    .padding(.vertical, isScrolling ? 6 : 10)
                    .background(
                        Group {
                            if isScrolling {
                                if #available(iOS 26, *) {
                                    Capsule().glassEffect(.regular)
                                } else {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                            }
                        }
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, isScrolling ? 20 : 0)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isScrolling && !isActive ? 0 : 1)
    }
}

struct UndoJumpButton: View {
    let lastLocatorJSON: String
    let foregroundColor: Color
    let backgroundColor: Color
    let onUndo: () -> Void

    private var locator: Locator? {
        try? Locator(jsonString: lastLocatorJSON)
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onUndo()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .bold))

                if let loc = locator, let page = loc.locations.position {
                    Text("\(page)")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
