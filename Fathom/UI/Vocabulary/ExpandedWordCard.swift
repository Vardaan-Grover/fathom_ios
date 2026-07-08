import SwiftUI

struct ExpandedWordCard: View {
    let word: SavedWord
    let accentColor: Color
    let entry: DictionaryWordEntry?
    let sourceFrame: CGRect
    let isExpanded: Bool
    let contentVisible: Bool
    let hasPrev: Bool
    let hasNext: Bool
    let onDismiss: () -> Void
    let onNavigatePrev: () -> Void
    let onNavigateNext: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onJumpToBook: () -> Void

    @Environment(\.appTheme) var theme
    @State private var definitionPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var activeDragAxis: DragAxis? = nil
    @State private var navDirection: Edge? = nil

    private enum DragAxis { case horizontal, vertical }

    private static let headerHeight: CGFloat = 152
    private static let actionsHeight: CGFloat = 58

    private var entries: [DictionaryEntry] { entry?.entries ?? [] }
    private var phoneticText: String? { entries.first?.pronunciations?.compactMap(\.text).first }
    private var canJump: Bool { word.bookID != nil && word.locatorJSON != nil }

    private var contentTransition: AnyTransition {
        guard let dir = navDirection else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: dir).combined(with: .opacity),
            removal: .move(edge: dir == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { screen in
            let target = targetFrame(in: screen.size)

            ZStack {
                cardShell
                    .frame(
                        width: isExpanded ? target.width : sourceFrame.width,
                        height: isExpanded ? target.height : sourceFrame.height
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: isExpanded ? 26 : 16, style: .continuous)
                    )
                    .shadow(
                        color: .black.opacity(isExpanded ? 0.26 : 0),
                        radius: isExpanded ? 44 : 0,
                        y: isExpanded ? 18 : 0
                    )
                    .position(
                        x: isExpanded ? target.midX : sourceFrame.midX,
                        y: isExpanded ? target.midY : sourceFrame.midY
                    )
                    .offset(x: horizontalDragOffset, y: dragOffset)
                    .gesture(combinedDragGesture)
            }
        }
        .ignoresSafeArea()
        .onChange(of: contentVisible) { _, visible in
            if !visible { navDirection = nil }
        }
    }

    // MARK: - Combined Drag Gesture

    private var combinedDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if activeDragAxis == nil, max(abs(dx), abs(dy)) > 14 {
                    activeDragAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                }
                switch activeDragAxis {
                case .horizontal:
                    let atEnd = (dx < 0 && !hasNext) || (dx > 0 && !hasPrev)
                    horizontalDragOffset = atEnd ? dx * 0.12 : dx * 0.72
                case .vertical:
                    if dy > 0 { dragOffset = dy * 0.42 }
                case nil: break
                }
            }
            .onEnded { value in
                defer { activeDragAxis = nil }
                switch activeDragAxis {
                case .horizontal:
                    let dx = value.translation.width
                    let vx = value.velocity.width
                    withAnimation(.spring(duration: 0.38, bounce: 0.15)) {
                        horizontalDragOffset = 0
                    }
                    if (dx < -60 || vx < -400) && hasNext {
                        navDirection = .trailing
                        onNavigateNext()
                    } else if (dx > 60 || vx > 400) && hasPrev {
                        navDirection = .leading
                        onNavigatePrev()
                    }
                case .vertical:
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                        // Release the rubber-band with the same spring as the card collapse so
                        // both offset → 0 and position → sourceFrame settle at the same time.
                        withAnimation(.spring(duration: 0.38, bounce: 0.08)) { dragOffset = 0 }
                        onDismiss()
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dragOffset = 0 }
                    }
                case nil: break
                }
            }
    }

    // MARK: - Shell

    private var cardShell: some View {
        ZStack(alignment: .top) {
            if contentVisible {
                VStack(spacing: 0) {
                    accentColor.frame(height: Self.headerHeight)
                    theme.colors.background
                }
            } else {
                accentColor
            }

            LinearGradient(
                colors: [.white.opacity(0.28), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.6, y: 0.6)
            )
            .frame(maxWidth: .infinity, maxHeight: contentVisible ? Self.headerHeight : .infinity)

            if contentVisible {
                VStack(spacing: 0) {
                    headerSection.frame(height: Self.headerHeight)

                    Rectangle()
                        .fill(theme.colors.separator.opacity(0.4))
                        .frame(height: 0.5)

                    definitionsArea

                    Rectangle()
                        .fill(theme.colors.separator.opacity(0.4))
                        .frame(height: 0.5)

                    actionsRow.frame(height: Self.actionsHeight)
                }
                .id(word.id)
                .transition(contentTransition)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            Text("\u{201C}")
                .font(.system(size: 128, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.07))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -4, y: -12)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
                .padding(.trailing, 16)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 7) {
                    Text(word.word)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach(
                            word.partsOfSpeech.components(separatedBy: ", ").prefix(3),
                            id: \.self
                        ) { pos in
                            Text(pos.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill(.white.opacity(0.24)))
                        }
                        if let phonetic = phoneticText {
                            Text(phonetic)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.58))
                                .italic()
                        }
                        Spacer(minLength: 0)
                        Button {
                            PronunciationService.shared.speak(word.word)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }

                    if let title = word.bookTitle {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill").font(.system(size: 10))
                            Text(title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Definitions

    @ViewBuilder
    private var definitionsArea: some View {
        if entries.isEmpty {
            noDefinitionView
        } else if entries.count == 1 {
            singleEntryView(entries[0])
        } else {
            pagedEntriesView
        }
    }

    private var noDefinitionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.secondary)
            Text("No definition available")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.colors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func singleEntryView(_ dictEntry: DictionaryEntry) -> some View {
        ScrollView(showsIndicators: false) {
            entryContent(dictEntry, showHeader: false)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var pagedEntriesView: some View {
        VStack(spacing: 0) {
            GeometryReader { available in
                TabView(selection: $definitionPage) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, dictEntry in
                        entryContent(dictEntry, showHeader: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading
                            )
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: available.size.width, height: available.size.height)
            }

            HStack(spacing: 5) {
                ForEach(entries.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == definitionPage ? accentColor : theme.colors.separator)
                        .frame(width: index == definitionPage ? 18 : 6, height: 6)
                        .animation(.spring(duration: 0.3, bounce: 0.25), value: definitionPage)
                }
            }
            .frame(height: 28)
        }
    }

    private func entryContent(_ dictEntry: DictionaryEntry, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(dictEntry.partOfSpeech.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accentColor.opacity(0.10)))
                    if let phonetic = dictEntry.pronunciations?.compactMap(\.text).first {
                        Text(phonetic)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.secondary)
                            .italic()
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(dictEntry.senses.prefix(3).enumerated()), id: \.offset) {
                    index, sense in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(accentColor.opacity(0.7))
                            .frame(width: 18, alignment: .leading)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sense.definition)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.primary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            if let example = sense.examples?.first {
                                Text("\u{201C}\(example)\u{201D}")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.colors.secondary)
                                    .italic()
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if dictEntry.senses.count > 3 {
                Text("+ \(dictEntry.senses.count - 3) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.secondary.opacity(0.65))
                    .padding(.leading, 27)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 10) {
            if canJump {
                Button(action: onJumpToBook) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Jump to Book")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(accentColor))
                }
                .buttonStyle(SpringPressStyle())
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.colors.surface))
            }
            .buttonStyle(SpringPressStyle())

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.colors.surface))
            }
            .buttonStyle(SpringPressStyle())

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.72))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.red.opacity(0.08)))
            }
            .buttonStyle(SpringPressStyle())
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Geometry

    private func targetFrame(in size: CGSize) -> CGRect {
        let width = size.width - 48
        let height = min(size.height * 0.64, 510)
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2 - 18,
            width: width,
            height: height
        )
    }
}
