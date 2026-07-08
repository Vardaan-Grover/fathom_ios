import ReadiumShared
import SwiftUI

// MARK: - Locator Parsing

struct ParsedBookmarkLocator {
    let id: UUID
    let href: String
    let inChapterProg: Double
    let totalProg: Double
}

/// Parse bookmark locators once; called only when the bookmarks array changes.
func parseBookmarkLocators(_ bookmarks: [Bookmark]) -> [ParsedBookmarkLocator] {
    bookmarks.compactMap { b in
        guard let loc = try? Locator(jsonString: b.locatorJSON) else { return nil }
        return ParsedBookmarkLocator(
            id: b.id,
            href: "\(loc.href)",
            inChapterProg: loc.locations.progression ?? 0,
            totalProg: b.progression
        )
    }
}

/// Returns true if any parsed bookmark falls on the current rendered page.
///
/// Paginated mode: uses the positions array to determine the exact in-chapter
/// progression range for the current page, then checks if any bookmark's
/// in-chapter progression falls within that range. Self-corrects after font-size
/// changes because both the stored progression and the current positions list
/// use the same (pageIndex / totalPages) formula.
///
/// Scroll mode: matches by same chapter + in-chapter progression within 5%.
func bookmarkOnCurrentPage(
    parsedLocators: [ParsedBookmarkLocator],
    currentLocator: Locator?,
    currentProgression: Double,
    positions: [Locator],
    isScrolling: Bool
) -> Bool {
    guard !parsedLocators.isEmpty else { return false }

    guard let current = currentLocator else {
        // No locator yet — tight totalProgression fallback
        return parsedLocators.contains { abs($0.totalProg - currentProgression) <= 0.003 }
    }

    let currentHref = "\(current.href)"

    if isScrolling {
        // Scroll mode: same chapter + in-chapter progression within 5%
        let currentProg = current.locations.progression ?? currentProgression
        return parsedLocators.contains { b in
            b.href == currentHref && abs(b.inChapterProg - currentProg) <= 0.05
        }
    }

    // Paginated mode: range check using current positions list
    let resourcePositions = positions.filter { "\($0.href)" == currentHref }
    guard !resourcePositions.isEmpty,
          let idx = resourcePositions.firstIndex(where: {
              $0.locations.position == current.locations.position
          }) else {
        // Positions not yet loaded or page not found — tight fallback
        return parsedLocators.contains { abs($0.totalProg - currentProgression) <= 0.003 }
    }

    let rangeStart = resourcePositions[idx].locations.progression ?? 0.0
    let rangeEnd = idx + 1 < resourcePositions.count
        ? (resourcePositions[idx + 1].locations.progression ?? 1.0)
        : 1.0

    return parsedLocators.contains { b in
        b.href == currentHref &&
        b.inChapterProg >= rangeStart &&
        b.inChapterProg < rangeEnd
    }
}

// MARK: - Visual Overlay

struct BookmarkVisualOverlay: View {
    let bookmarks: [Bookmark]
    let parsedLocators: [ParsedBookmarkLocator]
    let positions: [Locator]
    let currentLocator: Locator?
    let currentProgression: Double
    let isScrolling: Bool
    let isShowingBars: Bool

    private static let crimson = Color(red: 0.78, green: 0.08, blue: 0.15)

    private var isBookmarked: Bool {
        bookmarkOnCurrentPage(
            parsedLocators: parsedLocators,
            currentLocator: currentLocator,
            currentProgression: currentProgression,
            positions: positions,
            isScrolling: isScrolling
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let yOffset = isShowingBars ? topInset : 0.0

            Group {
                if isScrolling {
                    scrollContent(proxy: proxy, yOffset: yOffset)
                } else {
                    paginatedContent(yOffset: yOffset)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isBookmarked)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func paginatedContent(yOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                if isBookmarked {
                    cornerRibbon(yOffset: yOffset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func scrollContent(proxy: GeometryProxy, yOffset: CGFloat) -> some View {
        ZStack {
            // Side-rail mini markers at proportional positions along right edge
            ForEach(bookmarks) { bookmark in
                BookmarkRibbonShape()
                    .fill(Self.crimson.opacity(0.65))
                    .frame(width: 10, height: 20)
                    .position(
                        x: proxy.size.width - 6,
                        y: max(10, proxy.size.height * bookmark.progression)
                    )
            }

            // Full corner ribbon when near a bookmark
            if isBookmarked {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        cornerRibbon(yOffset: yOffset)
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func cornerRibbon(yOffset: CGFloat) -> some View {
        BookmarkRibbonShape()
            .fill(Self.crimson)
            .frame(width: 18, height: 52)
            .shadow(color: .black.opacity(0.25), radius: 3, x: -1, y: 2)
            .padding(.trailing, 22)
            .offset(y: yOffset)
    }
}

struct BookmarkRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notchDepth = rect.width * 0.42
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notchDepth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
