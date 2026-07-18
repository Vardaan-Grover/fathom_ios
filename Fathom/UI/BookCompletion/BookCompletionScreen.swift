import SwiftUI
import PhotosUI

// MARK: - BookCompletionScreen
//
// Minimalist, premium reflection screen inspired by "One Year".

struct BookCompletionScreen: View {

    let book: Book
    let bookRepository: BookRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var rating: Int
    @State private var reflection: String
    @State private var screenAlpha: Double = 0
    @State private var reflectionFocused: Bool = false
    @State private var showDiscardAlert: Bool = false
    @State private var showShare: Bool = false

    private let originalRating: Int
    private let originalReflection: String
    private let hadOriginalImage: Bool

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    
    // Polaroid & Full Screen
    @State private var polaroidAngle: Double = 0
    @State private var isFullScreenImage = false
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var steadyStateZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var steadyStatePanOffset: CGSize = .zero

    private var isEditing: Bool { book.finishedAt != nil }
    private var finishedDate: Date { book.finishedAt ?? Date() }

    // Enhanced vibrant rating colors
    private let ratingColors: [Color] = [
        Color(hex: "FF6B6B"), // Vibrant Coral Red
        Color(hex: "FFB23F"), // Vibrant Orange
        Color(hex: "FFD93D"), // Vibrant Yellow
        Color(hex: "6BCB77"), // Vibrant Green
        Color(hex: "4D96FF")  // Vibrant Blue
    ]

    init(book: Book, bookRepository: BookRepository) {
        self.book = book
        self.bookRepository = bookRepository
        _rating = State(initialValue: book.rating ?? 0)
        _reflection = State(initialValue: book.reflection ?? "")

        originalRating = book.rating ?? 0
        originalReflection = book.reflection ?? ""
        hadOriginalImage = book.reflectionImageURL != nil

        if let url = book.reflectionImageURL, let image = UIImage(contentsOfFile: url.path) {
            _attachedImage = State(initialValue: image)
        }
    }

    private var hasUnsavedChanges: Bool {
        let trimmedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if rating != originalRating { return true }
        if trimmedReflection != originalReflection { return true }
        if selectedPhotoItem != nil { return true }
        if (attachedImage != nil) != hadOriginalImage { return true }
        return false
    }

    private func requestDismiss() {
        reflectionFocused = false
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            performDismiss()
        }
    }

    /// Resigns the keyboard first, then dismisses on the next runloop turn.
    /// Calling `dismiss()` while the text view is still first responder makes the
    /// `fullScreenCover` dismissal animation and the keyboard dismissal animation
    /// fight each other, which can leave the cover visually stuck.
    private func performDismiss() {
        reflectionFocused = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            dismiss()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.colors.background
                .ignoresSafeArea()
                .onTapGesture {
                    reflectionFocused = false
                }

            // Apple Notes-style editor: the UITextView owns its own scroll, with the
            // cover + photo hosted *inside* it as a header that scrolls away with the
            // text. Single scroll owner => native caret tracking, no scroll fighting.
            NotesStyleEditor(
                text: $reflection,
                isFocused: $reflectionFocused,
                configuration: .init(
                    font: .serif(ofSize: 18, weight: .regular),
                    textColor: UIColor(theme.colors.primary),
                    tintColor: UIColor(theme.colors.shelfAccent),
                    placeholder: "Start writing...",
                    placeholderColor: UIColor(theme.colors.secondary),
                    textHorizontalPadding: 32,
                    textTopPadding: 8,
                    bottomInset: 120 // clears the floating bottom pill
                ),
                headerID: AnyHashable([
                    AnyHashable(reflectionFocused),
                    AnyHashable(attachedImage.map { ObjectIdentifier($0).hashValue } ?? 0),
                    AnyHashable(polaroidAngle),
                    AnyHashable(colorScheme == .dark)
                ]),
                header: { reflectionHeader }
            )
            // The editor manages its own keyboard inset; keep SwiftUI's keyboard
            // avoidance out of the loop so it can't nudge the editor on each keystroke.
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Top Bar Overlay with proper Blur
            VStack(spacing: 0) {
                topBar
                    .padding(.bottom, 16)
                    .background {
                        theme.colors.background
                            .padding(.top, -100) // Ensure top edge doesn't thin out
                            .blur(radius: 20, opaque: false)
                            .ignoresSafeArea(edges: .top)
                    }
                Spacer()
            }

            // Bottom Bar Overlay
            VStack {
                Spacer()
                bottomPill
            }
            
            // Full Screen Image Overlay
            if let img = attachedImage, isFullScreenImage {
                fullScreenImageView(image: img)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .opacity(screenAlpha)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                screenAlpha = 1
            }
            polaroidAngle = Double.random(in: -3...3)
        }
        .alert("Discard changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                performDismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes will not be saved.")
        }
        .sheet(isPresented: $showShare) {
            BookSharePreviewSheet(
                book: book,
                bookRepository: bookRepository,
                rating: rating,
                finishedDate: finishedDate,
                name: UserProfileStore.shared.load().displayName ?? "",
                theme: ShareCardTheme.resolved(
                    background: theme.colors.background,
                    ink: .gardenInk(colorScheme),
                    primary: theme.colors.primary,
                    secondary: theme.colors.secondary,
                    scheme: colorScheme)
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.reflectionFocused = false
                        self.attachedImage = image
                        self.polaroidAngle = Double.random(in: -3...3)
                    }
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Spacer()
            
            Text(finishedDate, format: .dateTime.month(.abbreviated).day().year())
                .font(theme.typography.subheadline)
                .foregroundColor(theme.colors.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    theme.colors.surface,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(theme.colors.separator.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

            Spacer()
        }
        .overlay(alignment: .leading) {
            Button {
                requestDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.colors.primary)
                    .frame(width: 32, height: 32)
                    .background(theme.colors.surface, in: Circle())
                    .overlay(Circle().strokeBorder(theme.colors.separator.opacity(0.5), lineWidth: 1))
            }
            .padding(.leading, theme.layout.horizontalPadding)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 12) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.colors.primary)
                        .frame(width: 32, height: 32)
                        .background(theme.colors.surface, in: Circle())
                        .overlay(Circle().strokeBorder(theme.colors.separator.opacity(0.5), lineWidth: 1))
                }
                if !isEditing {
                    Button("Skip") { requestDismiss() }
                        .font(theme.typography.subheadline)
                        .foregroundColor(theme.colors.secondary)
                }
            }
            .padding(.trailing, theme.layout.horizontalPadding)
        }
        .padding(.top, 16)
    }

    // MARK: - Cover Section

    private var coverSection: some View {
        let w: CGFloat = 64
        let h: CGFloat = 96

        return ZStack(alignment: .topLeading) {
            if let filename = book.coverFilename,
               let url = BookFileStore.coverURL(for: filename),
               let img = UIImage(contentsOfFile: url.path)
            {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
            } else {
                let colorPair = HomeViewModel.coverColorPair(for: book.id)
                colorPair.cover
                    .frame(width: w, height: h)
                
                LinearGradient(
                    colors: [.black.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(colorPair.text)
                        .lineLimit(4)
                    Spacer(minLength: 0)
                    if let author = book.author {
                        Text(author)
                            .font(.system(size: 6, weight: .regular))
                            .foregroundColor(colorPair.text.opacity(0.70))
                            .lineLimit(2)
                    }
                }
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.layout.cornerRadiusSmall))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
    
    // MARK: - Polaroid Image
    private func polaroidView(image: UIImage) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1.0, contentMode: .fit)
                .overlay(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation {
                            attachedImage = nil
                            selectedPhotoItem = nil
                            isFullScreenImage = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .background(Circle().fill(.black.opacity(0.5)).padding(2))
                    }
                    .padding(8)
                }
                .padding([.top, .leading, .trailing], 12)
            
            // Bottom thick border of the polaroid
            Color.white
                .frame(height: 48)
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 6)
        .padding(.horizontal, 48)
        .rotationEffect(.degrees(polaroidAngle))
        .onTapGesture {
            reflectionFocused = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isFullScreenImage = true
            }
        }
    }
    
    // MARK: - Full Screen Image View
    
    private func clampedPanOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 1.0 else { return .zero }
        
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        
        let maxX = max(0, (screenW * scale - screenW) / 2.0)
        let maxY = max(0, (screenH * scale - screenH) / 2.0)
        
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }
    
    private func fullScreenImageView(image: UIImage) -> some View {
        let dragProgress = min(1.0, abs(dragOffset.height) / 200.0)
        let backgroundAlpha = 1.0 - Double(dragProgress)
        let scale = 1.0 - (dragProgress * 0.2)

        return ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(backgroundAlpha)
                
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * zoomScale)
                .offset(zoomScale > 1.0 ? clampedPanOffset(panOffset, scale: zoomScale) : dragOffset)
                .ignoresSafeArea()
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            // For MagnifyGesture in iOS 17+, the value is .magnification
                            // If using older iOS, it might be .scale. Assuming .magnification for iOS 17+
                            zoomScale = max(1.0, steadyStateZoomScale * value.magnification)
                            panOffset = clampedPanOffset(panOffset, scale: zoomScale)
                            steadyStatePanOffset = clampedPanOffset(steadyStatePanOffset, scale: zoomScale)
                        }
                        .onEnded { _ in
                            steadyStateZoomScale = zoomScale
                            // Snap back if zoomed out too much
                            if steadyStateZoomScale <= 1.0 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    zoomScale = 1.0
                                    steadyStateZoomScale = 1.0
                                    panOffset = .zero
                                    steadyStatePanOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if zoomScale <= 1.0 {
                                dragOffset = value.translation
                            } else {
                                let rawPan = CGSize(
                                    width: steadyStatePanOffset.width + value.translation.width,
                                    height: steadyStatePanOffset.height + value.translation.height
                                )
                                panOffset = clampedPanOffset(rawPan, scale: zoomScale)
                            }
                        }
                        .onEnded { value in
                            if zoomScale <= 1.0 {
                                let velocity = value.velocity.height
                                let translation = value.translation.height
                                
                                // Dismiss if dragged far enough or fast enough
                                if abs(translation) > 100 || abs(velocity) > 500 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isFullScreenImage = false
                                        dragOffset = .zero
                                        polaroidAngle = Double.random(in: -3...3) // re-tilt
                                    }
                                } else {
                                    // Snap back to center
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        dragOffset = .zero
                                    }
                                }
                            } else {
                                steadyStatePanOffset = panOffset
                            }
                        }
                )
        }
        .zIndex(100)
    }

    // MARK: - Reflection header (scrolls inside the editor)

    private var reflectionHeader: some View {
        VStack(spacing: 24) {
            // Spacer so the first line clears the top bar overlay.
            Color.clear.frame(height: 70)

            // Cover + photo are hidden while writing for a clean, distraction-free
            // surface (and so they're out of the text view's scroll content during
            // typing). They return when the editor loses focus.
            if !reflectionFocused {
                coverSection

                if let img = attachedImage {
                    polaroidView(image: img)
                }
            }
        }
        .padding(.bottom, reflectionFocused ? 4 : 24)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the non-text header area dismisses the keyboard. The polaroid's
            // own tap (zoom) takes precedence over this on the polaroid itself.
            reflectionFocused = false
        }
    }

    // MARK: - Bottom Pill

    private var bottomPill: some View {
        // Use a stark contrast background for the pill
        let pillBg = colorScheme == .dark ? Color(hex: "1C1C1E") : Color.white
        let pillBorder = theme.colors.separator.opacity(0.3)
        
        return HStack(spacing: 0) {
            // Photo picker button
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.primary)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 8)

            Spacer()

            // Glowing Rating dots
            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { i in
                    let color = ratingColors[i - 1]
                    let isSelected = i == rating
                    
                    let dotBg = isSelected ? color : color.opacity(0.15)
                    let glowRadius: CGFloat = isSelected ? 8 : 0

                    Circle()
                        .fill(dotBg)
                        .frame(width: 14, height: 14)
                        .scaleEffect(isSelected ? 1.4 : 1.0)
                        .shadow(color: color.opacity(0.6), radius: glowRadius)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(isSelected ? 1.0 : 0.0), lineWidth: 1)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: rating)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            rating = (rating == i) ? 0 : i
                        }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Done button
            Button {
                save()
            } label: {
                Text(isEditing ? "Save" : "Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.colors.shelfAccent, in: Capsule())
            }
            .padding(.trailing, 8)
        }
        .frame(height: 60)
        .background(
            pillBg,
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(pillBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Save

    private func save() {
        reflectionFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let trimmedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            var updated = book
            updated.rating = rating == 0 ? nil : rating
            updated.reflection = trimmedReflection.isEmpty ? nil : trimmedReflection
            updated.finishedAt = book.finishedAt ?? Date()

            if let img = attachedImage {
                if selectedPhotoItem != nil {
                    // New image selected, compress and save
                    if let data = img.jpegData(compressionQuality: 0.8) {
                        let filename = try? BookFileStore.saveReflectionImage(data)
                        updated.reflectionImageFilename = filename
                    }
                }
            } else {
                updated.reflectionImageFilename = nil
            }

            await bookRepository.updateBook(updated)

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    screenAlpha = 0
                }
            }

            try? await Task.sleep(nanoseconds: 200_000_000)

            await MainActor.run {
                dismiss()
            }

            // Post after dismiss so the parent's reload doesn't re-render the
            // presenting view while the cover is still animating away.
            try? await Task.sleep(nanoseconds: 50_000_000)

            await MainActor.run {
                NotificationCenter.default.post(name: .bookCompletionDidSave, object: updated.id)
            }
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let bookCompletionDidSave = Notification.Name("bookCompletionDidSave")
}

// MARK: - Preview

#if DEBUG
private final actor PreviewBookRepo: BookRepository {
    func listBooks() async -> [Book] { [] }
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
    let book = Book(
        id: UUID(),
        title: "Piranesi",
        author: "Susanna Clarke",
        format: .epub,
        localFilename: nil
    )
    BookCompletionScreen(book: book, bookRepository: PreviewBookRepo())
}
#endif
