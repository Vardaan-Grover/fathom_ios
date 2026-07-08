import Combine
import SwiftUI

class StickerStore: ObservableObject {
  static let shared = StickerStore()

  @Published var overrides: [String: String] = [:]
  private let key = "fathom.home.classic.stickers"

  static let allPairs: [(String, String)] = [
    // Travel / Places
    ("🇯🇵", "⛩️"), ("🇫🇷", "🗼"), ("🇳🇱", "🌷"), ("🇬🇧", "🎡"),
    ("🇮🇹", "🍕"), ("🇺🇸", "🗽"), ("🇰🇷", "🏯"), ("🇪🇬", "🐪"),
    ("🇨🇦", "🍁"), ("🇦🇺", "🦘"), ("🇧🇷", "🦜"), ("🇲🇽", "🌮"),
    ("🏝️", "🥥"), ("🏕️", "🔥"), ("🏔️", "🏂"), ("🏜️", "🌵"),
    ("🏰", "🛡️"), ("🎢", "🎡"), ("🚂", "🛤️"), ("✈️", "☁️"),

    // Hobbies / Arts
    ("📷", "🎞️"), ("🎨", "🖼️"), ("🎸", "🎶"), ("🎭", "🎟️"),
    ("🕹️", "👾"), ("♟️", "🎲"), ("🧵", "🧶"), ("🩰", "🦢"),
    ("🎤", "🎧"), ("🎬", "🍿"), ("🖍️", "📝"), ("🛹", "🧢"),
    ("📚", "🔖"), ("🖋️", "📜"), ("🔭", "🌌"), ("🔬", "🧬"),

    // Cozy / Vibe
    ("☕", "📚"), ("🌙", "✨"), ("🌿", "🪴"), ("🕯️", "📖"),
    ("🌧️", "🌂"), ("🍵", "🫖"), ("🧸", "🎀"), ("🧦", "🔥"),
    ("🛁", "🧼"), ("🛌", "💤"), ("🧶", "🐈"), ("📻", "🎵"),
    ("🍷", "🧀"), ("📻", "📼"), ("🔮", "🦋"), ("🧿", "🪬"),

    // Food / Drink
    ("🍕", "🍷"), ("🍔", "🍟"), ("🍣", "🥢"), ("🥐", "☕"),
    ("🥞", "🍯"), ("🥑", "🍞"), ("🌶️", "🌮"), ("🍜", "🥟"),
    ("🍓", "🍰"), ("🍦", "🍭"), ("🍺", "🥨"), ("🍾", "🥂"),
    ("🍉", "☀️"), ("🥥", "🍹"), ("🍩", "🥛"), ("🍒", "🍫"),

    // Nature / Animals
    ("❄️", "⛷️"), ("🏖️", "🍹"), ("🐶", "🦴"), ("🐱", "🧶"),
    ("🦊", "🍂"), ("🐸", "🍄"), ("🦉", "🌙"), ("🐝", "🌻"),
    ("🐢", "🌊"), ("🦕", "🌋"), ("🦋", "🌸"), ("🦦", "🐚"),
    ("🐼", "🎋"), ("🐧", "🧊"), ("🦄", "🌈"), ("🐉", "🔥"),

    // Random / Fun
    ("🚀", "👽"), ("🛸", "🌌"), ("👻", "🎃"), ("🤡", "🎈"),
    ("🤖", "⚙️"), ("🤠", "🌵"), ("👑", "💎"), ("🎯", "🏆"),
    ("💣", "💥"), ("🪄", "🐰"), ("🕰️", "⏳"), ("🗝️", "🚪"),
    ("💌", "💝"), ("💸", "💳"), ("💡", "🧠"), ("🧸", "🎈"),
  ]

  init() {
    if let data = UserDefaults.standard.data(forKey: key),
      let dict = try? JSONDecoder().decode([String: String].self, from: data)
    {
      overrides = dict
    }
  }

  func shuffle(for categoryID: UUID) {
    let current = overrides[categoryID.uuidString]
    var nextPair = StickerStore.allPairs.randomElement()!
    while "\(nextPair.0),\(nextPair.1)" == current {
      nextPair = StickerStore.allPairs.randomElement()!
    }

    overrides[categoryID.uuidString] = "\(nextPair.0),\(nextPair.1)"
    save()
  }

  func setStickers(_ s1: String, _ s2: String, for categoryID: UUID) {
    overrides[categoryID.uuidString] = "\(s1),\(s2)"
    save()
  }

  func stickers(for categoryID: UUID) -> (String, String)? {
    if let val = overrides[categoryID.uuidString] {
      let parts = val.split(separator: ",")
      if parts.count == 2 {
        return (String(parts[0]), String(parts[1]))
      }
    }
    return nil
  }

  private func save() {
    if let data = try? JSONEncoder().encode(overrides) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }
}

struct CollectionsListView: View {
  @ObservedObject var viewModel: HomeViewModel
  let bookRepository: BookRepository
  @Environment(\.appTheme) var theme

  @State private var editingCategory: HomeCategory? = nil
  @State private var categoryToDelete: HomeCategory? = nil
  @State private var stickerEditingCategory: HomeCategory? = nil
  @State private var removingCategoryIDs: Set<UUID> = []
  @State private var showReorderShelves = false

  var body: some View {
    let userCategories = viewModel.categories.filter { !$0.shelfColorHex.isEmpty }

    ScrollView {
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
        spacing: 24
      ) {
        ForEach(userCategories) { category in
          let isRemoving = removingCategoryIDs.contains(category.id)

          NavigationLink {
            CollectionDetailView(
              category: category, viewModel: viewModel, bookRepository: bookRepository)
          } label: {
            CollectionFolderCell(category: category)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button {
              stickerEditingCategory = category
            } label: {
              Label("Edit Stickers", systemImage: "face.smiling")
            }

            Divider()

            Button {
              editingCategory = category
            } label: {
              Label("Edit Shelf", systemImage: "pencil")
            }

            Button(role: .destructive) {
              categoryToDelete = category
            } label: {
              Label("Delete Shelf", systemImage: "trash")
            }
          }
          .scaleEffect(
            x: isRemoving ? 0.88 : 1,
            y: isRemoving ? 0.001 : 1,
            anchor: .center
          )
          .opacity(isRemoving ? 0 : 1)
          .allowsHitTesting(!isRemoving)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(
                with: .scale(scale: 0.94, anchor: .top)),
              removal: .identity
            ))
        }
      }
      .padding(.horizontal, theme.layout.horizontalPadding)
      .padding(.top, 32)
      .padding(.bottom, 72)
    }
    .background(theme.colors.background.ignoresSafeArea())
    .navigationTitle("Collections")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          if userCategories.count > 1 {
            showReorderShelves = true
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.primary.opacity(0.8))
            .frame(width: 32, height: 32)
        }
      }
    }
    .sheet(isPresented: $showReorderShelves) {
      ReorderShelvesSheet(shelves: userCategories) { newOrder in
        viewModel.applyShelfOrder(newOrder)
      }
    }
    .sheet(item: $stickerEditingCategory) { category in
      let initial =
        StickerStore.shared.stickers(for: category.id)
        ?? {
          let pairs = StickerStore.allPairs
          let index = StableHash.index(of: category.id, count: pairs.count)
          return pairs[index]
        }()

      FolderStickerEditSheet(
        category: category,
        initialStickers: initial
      ) { s1, s2 in
        StickerStore.shared.setStickers(s1, s2, for: category.id)
      }
      .presentationDetents([.height(500)])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $editingCategory) { category in
      NewShelfSheet(
        initialName: category.name,
        initialColorHex: category.shelfColorHex,
        isEditing: true
      ) { name, colorHex in
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
          viewModel.updateCategory(id: category.id, name: name, colorHex: colorHex)
        }
      }
      .padding(.top, 16)
      .presentationDetents([.height(380)])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $categoryToDelete) { category in
      VStack(spacing: 24) {
        VStack(spacing: 8) {
          Text("Delete \"\(category.name)\"?")
            .font(.title2.bold())
            .multilineTextAlignment(.center)

          Text("This will permanently remove the shelf. Books in it won't be deleted.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .padding(.horizontal)
        }
        .padding(.top, 10)

        HStack(spacing: 12) {
          Button(role: .cancel) {
            categoryToDelete = nil
          } label: {
            Text("Cancel")
              .font(.body.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(
                Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14)
              )
              .foregroundStyle(.primary)
          }
          Button(role: .destructive) {
            categoryToDelete = nil
            beginDeleteAnimation(for: category)
          } label: {
            Text("Delete Shelf")
              .font(.body.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(
                Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)
              )
              .foregroundStyle(.red)
          }
        }

      }
      .padding(.top, 36)
      .padding(.horizontal, 24)
      .presentationDetents([.height(216)])
      .presentationDragIndicator(.visible)
    }
  }

  private func beginDeleteAnimation(for category: HomeCategory) {
    _ = withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
      removingCategoryIDs.insert(category.id)
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 200_000_000)
      withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
        viewModel.deleteCategory(id: category.id)
      }
      removingCategoryIDs.remove(category.id)
    }
  }
}

private struct CollectionFolderCell: View {
  let category: HomeCategory
  @ObservedObject private var stickerStore = StickerStore.shared

  // Deterministic emoji pairs to mimic the sticker look
  private var stickers: (String, String) {
    if let overridden = stickerStore.stickers(for: category.id) {
      return overridden
    }
    let pairs = StickerStore.allPairs
    let index = StableHash.index(of: category.id, count: pairs.count)
    return pairs[index]
  }

  var body: some View {
    VStack(spacing: 12) {
      ZStack(alignment: .bottom) {
        // Back of the folder
        folderBack

        // Books peeking out
        peekingBooks
          .padding(.bottom, 16)

        // Front frosted glass flap
        folderFront
          .frame(height: 75)  // Lower half of the folder
      }
      .aspectRatio(1.2, contentMode: .fit)

      VStack(spacing: 6) {
        Text(category.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)

        Text("\(category.books.count) books")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Color.gray.opacity(0.12), in: Capsule())
      }
    }
  }

  private var folderBack: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height

      Path { path in
        let tabWidth = w * 0.45
        let tabHeight = h * 0.18
        let radius: CGFloat = 8

        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: tabWidth - radius, y: 0))
        path.addQuadCurve(
          to: CGPoint(x: tabWidth + radius, y: tabHeight), control: CGPoint(x: tabWidth, y: 0))

        path.addLine(to: CGPoint(x: w - radius, y: tabHeight))
        path.addQuadCurve(
          to: CGPoint(x: w, y: tabHeight + radius), control: CGPoint(x: w, y: tabHeight))

        path.addLine(to: CGPoint(x: w, y: h - radius))
        path.addQuadCurve(to: CGPoint(x: w - radius, y: h), control: CGPoint(x: w, y: h))

        path.addLine(to: CGPoint(x: radius, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - radius), control: CGPoint(x: 0, y: h))

        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
      }
      .fill(Color.gray.opacity(0.2))
    }
  }

  private var peekingBooks: some View {
    GeometryReader { geo in
      let w = geo.size.width * 0.38
      let h = w * 1.4

      ZStack {
        if category.books.count > 1 {
          bookThumbnail(for: category.books[1], width: w, height: h)
            .rotationEffect(.degrees(-15))
            .offset(x: -w * 0.5, y: h * 0.15)
        }

        if category.books.count > 2 {
          bookThumbnail(for: category.books[2], width: w, height: h)
            .rotationEffect(.degrees(18))
            .offset(x: w * 0.5, y: h * 0.2)
        }

        if category.books.count > 0 {
          bookThumbnail(for: category.books[0], width: w, height: h)
            .offset(y: -h * 0.05)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private func bookThumbnail(for book: HomeBook, width: CGFloat, height: CGFloat) -> some View {
    BookCoverView(book: book, width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .strokeBorder(Color.white, lineWidth: 2.5)
      )
      .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
  }

  private var folderFront: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height

      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(.ultraThinMaterial)

        RoundedRectangle(cornerRadius: 12)
          .fill(category.shelfColor.opacity(0.12))

        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)

        VStack(spacing: 2) {
          Spacer()
          Rectangle()
            .fill(Color.black.opacity(0.04))
            .frame(height: 1)
            .padding(.horizontal, 16)
          Rectangle()
            .fill(Color.white.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }

        let (s1, s2) = stickers

        Text(s1)
          .font(.system(size: 24))
          .background(Color.white.clipShape(Circle()).padding(-3))
          .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
          .rotationEffect(.degrees(-10))
          .position(x: w * 0.28, y: h * 0.4)

        Text(s2)
          .font(.system(size: 24))
          .background(Color.white.clipShape(Circle()).padding(-3))
          .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
          .rotationEffect(.degrees(14))
          .position(x: w * 0.72, y: h * 0.6)
      }
    }
  }
}

struct CollectionDetailView: View {
  let category: HomeCategory
  @ObservedObject var viewModel: HomeViewModel
  let bookRepository: BookRepository
  @Environment(\.appTheme) var theme

  @AppStorage("fathom.home.classic.showMetadata") private var showGridMetadata = false

  @State private var selectedBook: UUID? = nil
  @State private var readerBook: Book? = nil
  @State private var reorderingBooksCategory: HomeCategory? = nil

  var body: some View {
    let liveCategory = viewModel.categories.first(where: { $0.id == category.id }) ?? category

    ScrollView {
      let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
      LazyVGrid(columns: columns, spacing: 28) {
        ForEach(liveCategory.books) { book in
          bookCell(for: book)
        }
      }
      .padding(.horizontal, theme.layout.horizontalPadding)
      .padding(.top, 16)
      .padding(.bottom, 90)
    }
    .background(theme.colors.background.ignoresSafeArea())
    .navigationTitle(liveCategory.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          reorderingBooksCategory = liveCategory
        } label: {
          Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.primary.opacity(0.8))
            .frame(width: 32, height: 32)
        }
      }
    }
    .sheet(item: $reorderingBooksCategory) { category in
      let liveCategory = viewModel.categories.first(where: { $0.id == category.id }) ?? category
      ReorderBooksSheet(category: liveCategory) { newOrder in
        viewModel.applyBookOrder(in: liveCategory.id, newOrder: newOrder)
      }
    }
    .sheet(
      item: Binding(
        get: { selectedBook.map { SelectedBookWrapper(id: $0) } },
        set: { selectedBook = $0?.id }
      )
    ) { selection in
      BookDetailsScreen(
        bookID: selection.id,
        bookRepository: bookRepository,
        onStartReading: { book in
          selectedBook = nil
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            readerBook = book
          }
        }
      )
    }
    .fullScreenCover(item: $readerBook) { book in
      if let url = book.localURL {
        ReaderScreen(
          bookFileURL: url,
          bookTitle: book.title,
          bookID: book.id,
          book: book,
          bookRepository: bookRepository,
          backendBookID: book.backendBookID,
          aiEnabled: book.aiEnabled,
          ingestionStatus: book.preprocessingStatus,
          onEnableAI: {
            readerBook = nil
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 350_000_000)
              selectedBook = book.id
            }
          }
        )
      }
    }
  }

  @ViewBuilder
  private func bookCell(for book: HomeBook) -> some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = w * 1.5

      VStack(alignment: .leading, spacing: 8) {
        BookCoverView(
          book: book,
          width: w,
          height: h,
          userCategories: viewModel.categories.filter { !$0.shelfColorHex.isEmpty },
          onToggleCategory: { categoryID in
            withAnimation {
              viewModel.toggleBookInCategory(bookID: book.id, categoryID: categoryID)
            }
          },
          onCreateShelf: { name, colorHex in
            viewModel.createCategory(name: name, colorHex: colorHex)
          }
        )
        .onTapGesture {
          selectedBook = book.id
        }

        if showGridMetadata {
          VStack(alignment: .leading, spacing: 2) {
            Text(book.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(theme.colors.primary)
              .lineLimit(2)

            Text(book.author)
              .font(.system(size: 12, weight: .regular))
              .foregroundColor(theme.colors.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal, 4)
        }
      }
    }
    .aspectRatio(showGridMetadata ? 0.55 : 0.66, contentMode: .fit)
  }
}
private struct SelectedBookWrapper: Identifiable {
  let id: UUID
}
