import PhotosUI
import SwiftUI

struct BookDetailsStep: View {

    let bookID: UUID
    @Binding var title: String
    @Binding var author: String
    @Binding var coverImageData: Data?
    @Binding var isCoverChanged: Bool
    let isEditing: Bool
    let onNext: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focusedField: Field?
    @Environment(\.appTheme) private var theme

    private enum Field: Hashable { case title, author }

    private var anyFieldFocused: Bool { focusedField != nil }
    private var isTitleEmpty: Bool { title.allSatisfy(\.isWhitespace) }

    // Base cover size: ~72% of screen width, portrait ratio.
    // Sized large so the cover is the dominant visual when keyboard is hidden.
    private let baseWidth  = UIScreen.main.bounds.width * 0.72
    private var baseHeight: CGFloat { baseWidth * 1.4 }

    private var colorPair: (cover: Color, text: Color) {
        HomeViewModel.coverColorPair(for: bookID)
    }

    // MARK: - Body

    var body: some View {
        // Cover section fills all the space above the field inset.
        ZStack(alignment: .center) {
            coverArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        // Fields are pinned above the keyboard at all times via safeAreaInset.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                fieldsSection
                    .padding(.horizontal, 24)
                    .background(theme.colors.background)
            }
        }
        .navigationTitle(isEditing ? "Edit Book" : "Add Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Next") { onNext() }
                    .fontWeight(.semibold)
                    .disabled(isTitleEmpty)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { coverImageData = data }
                isCoverChanged = true
            }
        }
    }

    // MARK: - Cover area (fills above the field inset)

    private var coverArea: some View {
        GeometryReader { proxy in
            let availableHeight = proxy.size.height
            // Reserve ~90 points for the buttons and padding.
            let maxCoverHeight = max(10, availableHeight - 90)
            let computedScale = min(1.0, maxCoverHeight / baseHeight)
            
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                // Cover is a photo picker so tapping anywhere on it opens the library.
                PhotosPicker(selection: $photoItem, matching: .images) {
                    coverPreview(scale: computedScale)
                }
                .buttonStyle(.plain)

                coverButtons

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: - Cover preview

    private func coverPreview(scale: CGFloat) -> some View {
        let displayWidth = baseWidth * scale
        let displayHeight = baseHeight * scale
        
        return ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                // Background layer
                Group {
                    if let data = coverImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: baseWidth, height: baseHeight)
                            .clipped()
                    } else {
                        colorPair.cover
                            .frame(width: baseWidth, height: baseHeight)
                    }
                }

                // Spine shading — mirrors BookCoverView
                LinearGradient(
                    colors: [.black.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 10, height: baseHeight)

                // Title + author overlay — only when there is no cover image
                if coverImageData == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.isEmpty ? "Title" : title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(colorPair.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)

                        Spacer()

                        if !author.isEmpty {
                            Text(author)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(colorPair.text.opacity(0.70))
                                .lineLimit(2)
                        }
                    }
                    .padding(14)
                    .frame(width: baseWidth, height: baseHeight, alignment: .topLeading)
                }
            }
            .frame(width: baseWidth, height: baseHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)

            // Camera badge — makes the tap target visually obvious
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, Color(.systemGray3))
                .offset(x: 8, y: 8)
        }
        .drawingGroup() // Rasterize the complex view (shadows/gradients) for O(1) scaling performance
        .scaleEffect(scale)
        .frame(width: displayWidth, height: displayHeight)
        .padding(.bottom, 8)
        .padding(.trailing, 8)
    }

    // MARK: - Cover action buttons

    private var coverButtons: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    coverImageData == nil ? "Add cover" : "Change cover",
                    systemImage: "photo"
                )
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color(.systemFill), in: Capsule())
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            if coverImageData != nil {
                Button("Remove") {
                    withAnimation(.easeInOut(duration: 0.2)) { coverImageData = nil }
                    isCoverChanged = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coverImageData == nil)
    }

    // MARK: - Fields section (lives inside safeAreaInset)

    private var fieldsSection: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.body)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .author }
                .padding(.vertical, 14)

            Divider()

            TextField("Author", text: $author)
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondary)
                .focused($focusedField, equals: .author)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .padding(.vertical, 14)

            Divider()
        }
    }
}

// MARK: - Preview

#Preview("Import – no cover") {
    NavigationStack {
        BookDetailsStep(
            bookID: UUID(),
            title: .constant("The Design of Everyday Things"),
            author: .constant("Don Norman"),
            coverImageData: .constant(nil),
            isCoverChanged: .constant(false),
            isEditing: false,
            onNext: {}
        )
    }
}

#Preview("Edit") {
    NavigationStack {
        BookDetailsStep(
            bookID: UUID(),
            title: .constant("Dune"),
            author: .constant("Frank Herbert"),
            coverImageData: .constant(nil),
            isCoverChanged: .constant(false),
            isEditing: true,
            onNext: {}
        )
    }
}
