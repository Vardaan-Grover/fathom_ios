import SwiftUI

extension Font {
    /// The garden's handwritten voice — used only for the doodle's name.
    static func reenie(_ size: CGFloat) -> Font { .custom("Reenie Beanie", size: size) }
}

/// The read-only night a tap on the garden opens. The date sits centered up
/// top, the doodle you earned glows beneath it, named in serif ("you spotted a
/// comet"), with the minutes you read and the book(s) that time came from. No
/// text entry — the doodles are the record.
struct DayDetailSheet: View {
    let date: Date
    /// 1-based day of year, so the doodle matches exactly what the grid drew.
    let dayOfYear: Int
    let activity: DailyActivity?
    let books: [UUID: Book]
    let ink: Color

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private var duration: TimeInterval { activity?.duration ?? 0 }
    private var tier: DoodleTier { DoodleTier.tier(for: duration) }
    /// Settled only once the day is complete — today's doodle is still being
    /// spotted ("forms today, settles tomorrow").
    private var settled: Bool { date < Calendar.current.startOfDay(for: Date()) }
    /// You read today, but the doodle hasn't settled yet.
    private var isForming: Bool { !settled && duration > 0 }

    private var doodleName: String? {
        guard settled else { return nil }
        return DoodleCatalog.assetName(forDayOfYear: dayOfYear, duration: duration)
    }

    private var rankedBooks: [(book: Book, minutes: Int)] {
        guard let activity else { return [] }
        return activity.bookDurations
            .sorted { $0.value > $1.value }
            .compactMap { id, secs in books[id].map { ($0, max(1, Int(secs / 60))) } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundColor(theme.colors.secondary)
                    .padding(.top, 22)

                doodle
                    .padding(.top, 18)

                headline
                    .padding(.top, 6)

                if duration > 0 {
                    minutesPill.padding(.top, 16)
                }

                if !rankedBooks.isEmpty {
                    booksSection.padding(.top, 30)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .topTrailing) {
            // Only a settled doodle is worth sharing.
            if let doodleName {
                Button { presentShare(doodleName) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(ink.opacity(colorScheme == .dark ? 0.16 : 0.08)))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 18)
            }
        }
        .background(sheetBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showShare) {
            DoodleSharePreviewSheet(
                doodleName: doodleName ?? "",
                phrase: doodleName.map { DoodleCatalog.phrase(for: $0) } ?? "",
                date: date,
                name: UserProfileStore.shared.load().displayName ?? "",
                book: rankedBooks.first?.book,
                theme: ShareCardTheme.resolved(
                    background: theme.colors.background, ink: ink,
                    primary: theme.colors.primary, secondary: theme.colors.secondary,
                    scheme: colorScheme)
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { appeared = true }
        }
    }

    @State private var showShare = false
    private func presentShare(_ name: String) { showShare = true }

    // MARK: Doodle (no frame — just a soft glow behind it)

    @ViewBuilder private var doodle: some View {
        ZStack {
            if doodleName != nil {
                // A pure RadialGradient is highly optimized in CoreAnimation.
                // Removed the expensive and redundant .blur modifier for performance.
                RadialGradient(
                    colors: [ink.opacity(colorScheme == .dark ? 0.3 : 0.12), .clear],
                    center: .center, startRadius: 2, endRadius: 120
                )
                .frame(width: 240, height: 210)
            }

            if let doodleName {
                Image(doodleName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ink)
                    .frame(height: 120)
                    // Apply drawingGroup on the image itself, caching the image and its shadows.
                    // This allows CoreAnimation to perform scale transformations on a static texture.
                    .shadow(color: ink.opacity(colorScheme == .dark ? 0.38 : 0.12), radius: 7)
                    .shadow(color: ink.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 13)
                    .padding(24) // Give the shadows enough room so they don't get clipped by drawingGroup
                    .drawingGroup()
                    .padding(-24) // Negate the padding to keep original layout bounds
            } else if isForming {
                // Today: still being spotted — a doodle-style dashed ring.
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                    .foregroundColor(ink.opacity(0.5))
                    .frame(width: 78, height: 78)
            } else {
                Circle().fill(ink.opacity(0.3)).frame(width: 14, height: 14)
            }
        }
        .frame(height: 150)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Headline

    @ViewBuilder private var headline: some View {
        if let doodleName {
            VStack(spacing: 0) {
                Text("you spotted")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(theme.colors.secondary)
                Text(DoodleCatalog.phrase(for: doodleName))
                    .font(.reenie(46))
                    .foregroundColor(theme.colors.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if isForming {
            VStack(spacing: 0) {
                Text("being spotted")
                    .font(.reenie(46))
                    .foregroundColor(theme.colors.primary)
                Text("tonight's doodle settles tomorrow")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(theme.colors.secondary)
                    .padding(.top, 2)
            }
        } else {
            Text("a quiet night")
                .font(.reenie(46))
                .foregroundColor(theme.colors.primary)
        }
    }

    // MARK: Minutes

    private var minutesPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(minutesText)
                .font(.system(size: 13, weight: .semibold, design: .serif))
        }
        .foregroundColor(ink)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(ink.opacity(colorScheme == .dark ? 0.18 : 0.10))
                .overlay(Capsule().stroke(ink.opacity(0.18), lineWidth: 1))
        )
    }

    // MARK: Books

    private var booksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rankedBooks.count > 1 ? "What you read" : "From the pages of")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(theme.colors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(rankedBooks.enumerated()), id: \.offset) { index, entry in
                    if index > 0 {
                        Divider()
                            .overlay(ink.opacity(0.08))
                            .padding(.leading, 70)
                    }
                    bookRow(entry.book, minutes: entry.minutes, major: index == 0)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ink.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 6)
            )
        }
    }

    private func bookRow(_ book: Book, minutes: Int, major: Bool) -> some View {
        HStack(spacing: 16) {
            bookCover(book)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(theme.colors.primary)
                    .lineLimit(2)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundColor(theme.colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            // Stacked, editorial minutes readout.
            VStack(alignment: .trailing, spacing: -2) {
                Text("\(minutes)")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(ink)
                Text(minutes == 1 ? "min" : "mins")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(theme.colors.secondary)
            }
        }
        .padding(16)
    }

    /// A book cover with a little dimension — a spine shadow down the binding
    /// edge and a hint of page edges on the fore-edge, so it reads as an object
    /// rather than a flat thumbnail.
    private func bookCover(_ book: Book) -> some View {
        cover(for: book)
            .frame(width: 44, height: 64)
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [.black.opacity(0.28), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 5)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, x: 1, y: 5)
    }

    @ViewBuilder private func cover(for book: Book) -> some View {
        if let url = book.coverURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    coverPlaceholder(book)
                }
            }
        } else {
            coverPlaceholder(book)
        }
    }

    private func coverPlaceholder(_ book: Book) -> some View {
        ZStack {
            LinearGradient(colors: [ink.opacity(0.85), ink.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(book.title.prefix(1))
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(.white.opacity(0.92))
        }
    }

    // MARK: Styling

    private var sheetBackground: some View {
        ZStack(alignment: .top) {
            theme.colors.background
            LinearGradient(
                colors: [ink.opacity(colorScheme == .dark ? 0.12 : 0.05), .clear],
                startPoint: .top, endPoint: .center
            )
        }
    }

    private var minutesText: String {
        let total = Int(duration / 60)
        if total >= 60 {
            let h = total / 60, m = total % 60
            return m == 0 ? "\(h) hr read" : "\(h) hr \(m) min read"
        }
        return "\(max(1, total)) min read"
    }
}
