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
    @FocusState private var reflectionFocused: Bool

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    
    // Polaroid & Full Screen
    @State private var polaroidAngle: Double = 0
    @State private var isFullScreenImage = false
    @Namespace private var imageAnimation
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

        if let url = book.reflectionImageURL, let image = UIImage(contentsOfFile: url.path) {
            _attachedImage = State(initialValue: image)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.colors.background
                .ignoresSafeArea()
                .onTapGesture {
                    reflectionFocused = false
                }

            // Main scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Spacer for top bar
                    Color.clear.frame(height: 70)

                    if !reflectionFocused {
                        coverSection
                    }

                    if let img = attachedImage, !isFullScreenImage {
                        polaroidView(image: img)
                    }

                    reflectionSection
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 120) // Space for bottom pill
            }
            .contentShape(Rectangle()) // Allows tapping on empty space
            .onTapGesture {
                reflectionFocused = false
            }

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
            }
        }
        .opacity(screenAlpha)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                screenAlpha = 1
            }
            polaroidAngle = Double.random(in: -3...3)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
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
        .overlay(alignment: .trailing) {
            if !isEditing {
                Button("Skip") {
                    dismiss()
                }
                .font(theme.typography.subheadline)
                .foregroundColor(theme.colors.secondary)
                .padding(.trailing, theme.layout.horizontalPadding)
            }
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
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .matchedGeometryEffect(id: "hero_image", in: imageAnimation)
                // Fixed square-ish aspect ratio inside the polaroid
                .aspectRatio(1.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    // Delete button relative to the image
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
            // Straighten out rotation to prevent matchedGeometryEffect glitch
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                polaroidAngle = 0
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
                .matchedGeometryEffect(id: "hero_image", in: imageAnimation)
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

    // MARK: - Reflection

    private var reflectionSection: some View {
        ZStack(alignment: .topLeading) {
            if reflection.isEmpty && !reflectionFocused {
                Text("Start writing...")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundColor(theme.colors.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $reflection)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(theme.colors.primary)
                .focused($reflectionFocused)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .tint(theme.colors.shelfAccent)
        }
        .onTapGesture {
            reflectionFocused = true
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
                        // Add glow shadow
                        .shadow(color: color.opacity(0.6), radius: glowRadius)
                        .overlay(
                            // Add inner shadow/stroke for depth
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

            // Handle image save
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
                NotificationCenter.default.post(name: .bookCompletionDidSave, object: updated.id)
                dismiss()
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
    func addBook(_ book: Book) async {}
    func updateBook(_ book: Book) async {}
    func deleteBook(_ book: Book) async {}
    func touchLastReadAt(bookID: UUID) async {}
    func logReadingSession(for bookID: UUID, duration: TimeInterval) async {}
    func listReadingActivity(forYear year: Int) async -> [ReadingActivity] { [] }
    func insertMockReadingActivity(_ activity: ReadingActivity) async {}
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
