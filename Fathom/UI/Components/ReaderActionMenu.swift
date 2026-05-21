import ReadiumShared
import SwiftUI

struct ReaderActionMenu: View {
    @Binding var isPresented: Bool
    @Binding var settings: ReaderSettings
    @Binding var isScrubbing: Bool
    @Binding var scrubTargetProgression: Double
    var currentProgression: Double
    var positions: [Locator] = []
    var tableOfContents: [ReadiumShared.Link] = []
    var aiEnabled: Bool = true
    var ingestionReady: Bool = true
    var hasBackendBookID: Bool = true
    var isCurrentPageBookmarked: Bool = false
    var onOpenSettings: () -> Void
    var onOpenAIChats: () -> Void = {}
    var onOpenTOC: () -> Void = {}
    var onOpenSearch: () -> Void = {}
    var onOpenNotes: () -> Void = {}
    var onOpenHighlights: () -> Void = {}
    var onOpenBookmarks: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onScrubReleased: (Double) -> Void = { _ in }

    private var fg: Color { settings.colorTheme.foregroundColor }
    private var bg: Color { settings.colorTheme.backgroundColor }

    /// Slightly-lightened background for button surfaces on dark themes,
    /// so buttons read as elevated above the reader canvas.
    private var elevatedBg: Color {
        guard settings.colorTheme.isDark else { return bg }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(bg).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(UIColor(red: min(r + 0.10, 1), green: min(g + 0.10, 1), blue: min(b + 0.10, 1), alpha: a))
    }

    var body: some View {
        ReaderActionButton(
            animation: .smooth(duration: 0.3, extraBounce: 0),
            isPresented: $isPresented
        ) {
            menuContent
        } background: {
            Capsule()
                .fill(bg)
                .shadow(
                    color: settings.colorTheme.isDark ? .black.opacity(0.55) : .black.opacity(0.2),
                    radius: settings.colorTheme.isDark ? 10 : 4,
                    y: 2
                )
        }
        .padding(.trailing, 15)
        .padding(.bottom, 0)
    }

    @ViewBuilder
    private var menuContent: some View {
        menuButtonsContainer
            // Overlay on the container (no transforms applied here, so coordinates are reliable).
            // frame(height: 0, alignment: .bottom) reports zero height to layout so the menu never
            // resizes, but the popover content renders upward past the frame boundary — above the menu.
            .overlay(alignment: .top) {
                if isScrubbing {
                    ScrubPreviewPopover(
                        progression: scrubTargetProgression,
                        positions: positions,
                        tableOfContents: tableOfContents,
                        foregroundColor: fg,
                        backgroundColor: bg
                    )
                    .frame(width: 250)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 0, alignment: .bottom)
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isScrubbing)
    }

    @ViewBuilder
    private var menuButtonsContainer: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) {
                menuButtons
            }
        } else {
            menuButtons
                .shadow(
                    color: .black.opacity(settings.colorTheme.isDark ? 0.55 : 0.12),
                    radius: 18,
                    y: 6
                )
        }
    }

    @ViewBuilder
    private var menuButtons: some View {
        VStack(spacing: 10) {
            ContentsScrubberButton(
                isScrubbing: $isScrubbing,
                scrubTargetProgression: $scrubTargetProgression,
                currentProgression: currentProgression,
                isPresented: $isPresented,
                foregroundColor: fg,
                backgroundColor: elevatedBg,
                onTapTOC: {
                    isPresented = false
                    onOpenTOC()
                },
                onScrubReleased: onScrubReleased
            )
            .frame(width: 250, height: 45)

            CustomButton(
                title: "Search",
                symbol: "magnifyingglass",
                isPresented: $isPresented,
                foregroundColor: fg,
                backgroundColor: elevatedBg
            ) {
                isPresented = false
                onOpenSearch()
            }
            .frame(width: 250, height: 45)

            CustomButton(
                title: "Bookmarks",
                symbol: "bookmark.fill",
                isPresented: $isPresented,
                foregroundColor: fg,
                backgroundColor: elevatedBg
            ) {
                isPresented = false
                onOpenBookmarks()
            }
            .frame(width: 250, height: 45)

            CustomButton(
                title: "Themes & Settings",
                symbol: "textformat.size",
                isPresented: $isPresented,
                foregroundColor: fg,
                backgroundColor: elevatedBg
            ) {
                isPresented = false
                onOpenSettings()
            }
            .frame(width: 250, height: 45)

            HStack(spacing: 10) {
                if hasBackendBookID {
                    CustomSectionButton(
                        symbol: "sparkles",
                        isPresented: $isPresented,
                        foregroundColor: fg, backgroundColor: elevatedBg
                    ) {
                        isPresented = false
                        onOpenAIChats()
                    }
                    .opacity(aiEnabled ? 1.0 : 0.35)
                }
                CustomSectionButton(
                    symbol: "highlighter",
                    isPresented: $isPresented,
                    foregroundColor: fg, backgroundColor: elevatedBg
                ) {
                    isPresented = false
                    onOpenHighlights()
                }
                CustomSectionButton(
                    symbol: "note.text",
                    isPresented: $isPresented,
                    foregroundColor: fg, backgroundColor: elevatedBg
                ) {
                    isPresented = false
                    onOpenNotes()
                }
                CustomSectionButton(
                    symbol: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                    isPresented: $isPresented,
                    foregroundColor: isCurrentPageBookmarked
                        ? Color(red: 0.78, green: 0.08, blue: 0.15) : fg,
                    backgroundColor: elevatedBg
                ) {
                    isPresented = false
                    onBookmark()
                }
            }
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 250, height: 50)
        }
    }
}

struct ContentsScrubberButton: View {
    @Binding var isScrubbing: Bool
    @Binding var scrubTargetProgression: Double
    var currentProgression: Double
    @Binding var isPresented: Bool
    var foregroundColor: Color = .primary
    var backgroundColor: Color = Color(.systemBackground)
    var onTapTOC: () -> Void
    var onScrubReleased: (Double) -> Void

    @State private var pendingProgression: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let activeProgression =
                isScrubbing ? scrubTargetProgression : (pendingProgression ?? currentProgression)

            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(backgroundColor)

                // Filled progress track (darker/inverted style)
                Rectangle()
                    .fill(foregroundColor.opacity(0.15))
                    .frame(width: max(0, w * activeProgression))

                // Foreground content
                HStack(spacing: 10) {
                    Text("Table of Contents")
                    Spacer()
                    Image(systemName: "list.bullet")
                }
                .padding(.horizontal, 20)
                .foregroundStyle(foregroundColor)
            }
            .clipShape(.capsule)
            .contentShape(.capsule)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                            // Use haptic on start
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }

                        let pct = Double(value.location.x / w)
                        scrubTargetProgression = max(0.0, min(1.0, pct))
                    }
                    .onEnded { _ in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()

                        let finalProgression = scrubTargetProgression
                        pendingProgression = finalProgression
                        isScrubbing = false
                        onScrubReleased(finalProgression)
                    }
            )
            .onTapGesture {
                onTapTOC()
            }
        }
        .opacity(isPresented ? 1 : 0)
        .onChange(of: currentProgression) { _, _ in
            pendingProgression = nil
        }
    }
}
