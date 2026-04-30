import PhotosUI
import SwiftUI

struct BookCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: BookCustomization
    var onConfirm: (BookCustomization) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var author: String
    @State private var description: String
    @State private var coverImageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var didConfirm = false

    init(
        initial: BookCustomization,
        onConfirm: @escaping (BookCustomization) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: initial.title)
        _author = State(initialValue: initial.author)
        _description = State(initialValue: initial.description)
        _coverImageData = State(initialValue: initial.coverImageData)
    }

    private var isTitleEmpty: Bool { title.allSatisfy(\.isWhitespace) }

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            addButton
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    coverImageData = data
                }
            }
        }
        .onDisappear {
            if !didConfirm { onCancel() }
        }
    }

    // MARK: - Scroll content
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Add to Library")
                    .font(.title2.bold())
                    .padding(.top, 4)

                coverPicker

                fieldSection(label: "Title") {
                    TextField("Book title", text: $title)
                        .customFieldStyle()
                }

                fieldSection(label: "Author") {
                    TextField("Author name", text: $author)
                        .customFieldStyle()
                }

                fieldSection(label: "Description") {
                    descriptionEditor
                }
            }
            .padding(24)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Cover picker

    private var coverPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                coverPreview
                    .frame(width: 110, height: 154)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 1, y: 3)

                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white, Color(.systemGray))
                    .offset(x: 8, y: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let data = coverImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Color(.systemFill)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Description editor

    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text("No description")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 13)
            }
            TextEditor(text: $description)
                .scrollContentBackground(.hidden)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 90, maxHeight: 180)
        }
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            didConfirm = true
            var result = initial
            result.title = title.trimmingCharacters(in: .whitespaces)
            result.author = author.trimmingCharacters(in: .whitespaces)
            result.description = description.trimmingCharacters(in: .whitespaces)
            result.coverImageData = coverImageData
            onConfirm(result)
            dismiss()
        } label: {
            Label("Add to Library", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isTitleEmpty ? Color(.systemFill) : Color.accentColor)
                .foregroundStyle(isTitleEmpty ? Color.secondary : Color.white)
                .clipShape(Capsule())
        }
        .disabled(isTitleEmpty)
        .animation(.easeInOut(duration: 0.15), value: isTitleEmpty)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private extension View {
    func customFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}
