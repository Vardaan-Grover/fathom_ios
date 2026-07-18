import SwiftUI

struct BookDetailsScreen: View {
    @StateObject private var viewModel: BookDetailsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let onStartReading: (Book) -> Void

    @State private var isShowingCompletion = false

    init(bookID: UUID, bookRepository: BookRepository, onStartReading: @escaping (Book) -> Void) {
        _viewModel = StateObject(
            wrappedValue: BookDetailsViewModel(
                bookID: bookID,
                bookRepository: bookRepository
            ))
        self.onStartReading = onStartReading
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.colors.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }

            overlayButtons
        }
        .overlay(alignment: .bottom) {
            // ✅ Set this back to systemBackground to fill the bottom safe area
            Color(.systemBackground)
                .frame(height: 0)
                .ignoresSafeArea(edges: .bottom)
        }
        .task { await viewModel.load() }
        .fullScreenCover(isPresented: $isShowingCompletion) {
            if let book = viewModel.book {
                BookCompletionScreen(
                    book: book,
                    bookRepository: viewModel.bookRepository
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookCompletionDidSave)) { _ in
            Task { await viewModel.load() }
        }
    }

    // MARK: - Overlay Buttons

    private var overlayButtons: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundColor(theme.colors.primary)
            }
            Spacer()
            let shareText =
                viewModel.book.map { "\($0.title)\($0.author.map { " by \($0)" } ?? "")" } ?? ""
            ShareLink(
                item: shareText
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundColor(theme.colors.primary)
            }
            .opacity(viewModel.book == nil ? 0 : 1)
            .disabled(viewModel.book == nil)
        }
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.top, 12)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {

                // 🟢 TOP SECTION (Theme Background)
                VStack(spacing: 0) {
                    coverHero
                    upperSection
                    statsRow
                }
                .frame(maxWidth: .infinity)
                .background(theme.colors.background)

               // ⚪️ BOTTOM SECTION (System Background)
                VStack {
                    overviewSection
                    if !viewModel.otherBooksByAuthor.isEmpty {
                        authorBooksSection
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 48)
                .background {
                    Color(.systemBackground)
                        .padding(.bottom, -1000)
                }
            }
        }
    }

    // MARK: - Cover Hero

    private var coverHero: some View {
        Group {
            if let book = viewModel.book {
                largeCover(book: book)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .padding(.top, 36)
    }

    @ViewBuilder
    private func largeCover(book: Book) -> some View {
        let w: CGFloat = 190
        let h: CGFloat = 280

        ZStack(alignment: .topLeading) {
            if let filename = book.coverFilename,
                let url = BookFileStore.coverURL(for: filename),
                let uiImage = UIImage(contentsOfFile: url.path)
            {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                HomeViewModel.coverColor(for: book)
                    .frame(width: w, height: h)
            }

            LinearGradient(
                colors: [theme.colors.spineShadow, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 16)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: theme.layout.cornerRadiusSmall))
        .shadow(color: theme.colors.spineShadow, radius: 16, x: 4, y: 8)
    }

    // MARK: - Upper Section

    private var upperSection: some View {
        VStack {
            if let book = viewModel.book {
                Text(book.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(theme.colors.primary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                if let author = book.author {
                    Text(author)
                        .font(theme.typography.body)
                        .fontWeight(.medium)
                        .tracking(0.05)
                        .foregroundColor(theme.colors.secondary)
                        .padding(.bottom, 10)
                }
            }

            // AI status chip / "Enable AI Reading Companion" CTA is hidden
            // from the UI for now (kept in codebase).
            // aiStatusChip

            ctaButton
        }
        .padding(.top, 8)
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.bottom, 20)
    }

    // MARK: - AI Status Chip

    private var aiStatusChip: some View {
        let aiEnabled = viewModel.book?.aiEnabled ?? false
        let config = aiEnabled
            ? chipConfig(for: viewModel.book?.preprocessingStatus ?? .pending)
            : ChipConfig(label: "Basic Reading", icon: "doc.text", color: theme.colors.secondary)

        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                if aiEnabled && viewModel.book?.preprocessingStatus == .inProgress {
                    ProgressView(value: Double(viewModel.book?.aiAnalysisProgress ?? 0))
                        .progressViewStyle(.circular)
                        .frame(width: 12, height: 12)
                        .tint(config.color)
                } else {
                    Image(systemName: config.icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(config.label)
                    .font(theme.typography.subheadline)
            }
            .foregroundColor(config.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(config.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(config.color.opacity(0.3), lineWidth: 1))

            // "Enable AI" call-to-action for Tier 1 books, or "Try Again" on failure
            if !aiEnabled {
                enableAIButton
            } else if viewModel.book?.preprocessingStatus == .failed {
                retryAIButton
            }

            // Error banner
            if let errorMessage = viewModel.enableAIError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var retryAIButton: some View {
        Button {
            Task { await viewModel.enableAI() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isEnablingAI {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 14, height: 14)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(viewModel.isEnablingAI ? "Retrying…" : "Try Again")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Color(hex: "C0392B").opacity(viewModel.isEnablingAI ? 0.6 : 1),
                in: Capsule()
            )
        }
        .disabled(viewModel.isEnablingAI)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isEnablingAI)
    }

    private var enableAIButton: some View {
        Button {
            Task { await viewModel.enableAI() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isEnablingAI {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 14, height: 14)
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(viewModel.isEnablingAI ? "Enabling AI…" : "Enable AI Reading Companion")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                viewModel.isEnablingAI
                    ? Color.accentColor.opacity(0.6)
                    : Color.accentColor,
                in: Capsule()
            )
        }
        .disabled(viewModel.isEnablingAI)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isEnablingAI)
    }

    private struct ChipConfig {
        let label: String
        let icon: String
        let color: Color
    }

    private func chipConfig(for status: PreprocessingStatus) -> ChipConfig {
        switch status {
        case .completed:
            return ChipConfig(
                label: "AI Ready", icon: "checkmark.circle.fill", color: Color(hex: "2A6B3E"))
        case .inProgress:
            return ChipConfig(
                label: "AI Analysis in Progress…", icon: "arrow.triangle.2.circlepath",
                color: theme.colors.shelfAccent)
        case .pending:
            return ChipConfig(label: "AI Queued", icon: "clock", color: theme.colors.secondary)
        case .failed:
            return ChipConfig(
                label: "AI Analysis Failed", icon: "exclamationmark.triangle",
                color: Color(hex: "C0392B"))
        }
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        let hasProgress = (viewModel.totalProgression ?? 0) > 0.01
        let isFinished = viewModel.book?.finishedAt != nil
        let label = hasProgress ? "Continue Reading" : "Start Reading"

        return VStack(spacing: 10) {
            Button {
                if let book = viewModel.book {
                    dismiss()
                    onStartReading(book)
                }
            } label: {
                Text(label)
                    .font(theme.typography.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        theme.colors.shelfAccent,
                        in: RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge))
            }

            if !isFinished {
                Button {
                    isShowingCompletion = true
                } label: {
                    Text("Mark as Finished")
                        .font(theme.typography.subheadline)
                        .foregroundColor(theme.colors.shelfAccent)
                }
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: viewModel.pageCountText, label: "Pages", iconName: "text.page")
            Divider()
                .frame(height: 36)
                .background(theme.colors.separator)
            statCell(value: viewModel.readingTimeText, label: "Reading Time", iconName: "clock")
            Divider()
                .frame(height: 36)
                .background(theme.colors.separator)
            statCell(value: viewModel.progressText, label: "Progress", iconName: "circle.dashed")
        }
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    private func statCell(value: String, label: String, iconName: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.colors.secondary)
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(theme.colors.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.colors.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let book = viewModel.book, book.finishedAt != nil {
                BookCompletionPreviewCard(book: book) {
                    isShowingCompletion = true
                }
                .padding(.bottom, 24)
            }

            Text("Book Overview")
                .font(theme.typography.title)
                .foregroundColor(theme.colors.primary)
                .tracking(0.1)

            Spacer().frame(height: 10)

            if let description = viewModel.book?.description, !description.isEmpty {
                Text(description.asHTMLAttributedString())
                    .font(theme.typography.body)
                    .foregroundColor(theme.colors.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No description available.")
                    .font(theme.typography.body)
                    .foregroundColor(theme.colors.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.vertical, 24)
    }

    // MARK: - Author Books Section

    private var authorBooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Books by \(viewModel.book?.author ?? "This Author")")
                .font(theme.typography.title)
                .foregroundColor(theme.colors.primary)
                .padding(.horizontal, theme.layout.horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.otherBooksByAuthor) { homeBook in
                        BookCoverView(book: homeBook)
                    }
                }
                .padding(.horizontal, theme.layout.horizontalPadding)
                .padding(.vertical, 8)
            }
        }
        .padding(.top, theme.layout.sectionSpacing)
    }
}

#if DEBUG
    private final actor PreviewBookRepository: BookRepository {
        let mockBooks: [Book]

        init(mockBooks: [Book]) {
            self.mockBooks = mockBooks
        }

        func listBooks() async -> [Book] {
            return mockBooks
        }

        func searchBooks(query: String) async -> [Book] { [] }

        func addBook(_ book: Book) async {}
        func updateBook(_ book: Book) async {}
        func deleteBook(_ book: Book) async {}
        func touchLastReadAt(bookID: UUID) async {}
        func logReadingSession(for bookID: UUID, duration: TimeInterval) async {}
        func listReadingActivity(forYear year: Int) async -> [ReadingActivity] { [] }
        func insertMockReadingActivity(_ activity: ReadingActivity) async {}
        func deleteAllReadingActivity(forYear year: Int) async {}
    }

    #Preview {
        let mockBook = Book(
            id: UUID(),
            title: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            format: .epub,
            localFilename: nil,
            description:
                "A spectacularly evocative novel of 1920s America that paints a picture of the Jazz Age.",
            estimatedPageCount: 180,
            estimatedReadingTimeMinutes: 240
        )

        BookDetailsScreen(
            bookID: mockBook.id,
            bookRepository: PreviewBookRepository(mockBooks: [mockBook]),
            onStartReading: { _ in }
        )
    }
#endif
