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
    @State private var enableAI: Bool = false
    @State private var isAnimatingGradient: Bool = false
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
        _enableAI = State(initialValue: initial.enableAI)
    }

    private var isTitleEmpty: Bool { title.allSatisfy(\.isWhitespace) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    coverPicker
                }
                .listRowBackground(Color.clear)

                Section {
                    aiChoiceCard
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Book Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Description")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $description)
                            .frame(minHeight: 300, maxHeight: 300)
                    }
                }
            }
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button {
                        confirmAndDismiss()
                    } label: {
                        Label("Add to Library", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isTitleEmpty ? Color(.systemFill) : Color.accentColor)
                            .foregroundStyle(isTitleEmpty ? Color.secondary : Color.white)
                            .clipShape(Capsule())
                    }
                    .background {
                        Capsule()
                            .fill(isTitleEmpty ? Color(.systemFill) : Color.accentColor)
                            .blur(radius: 12)
                            .opacity(0.5)
                    }
                    .disabled(isTitleEmpty)
                    .animation(.easeInOut(duration: 0.15), value: isTitleEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.clear)
            }
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

    private func confirmAndDismiss() {
        didConfirm = true
        var result = initial
        result.title = title.trimmingCharacters(in: .whitespaces)
        result.author = author.trimmingCharacters(in: .whitespaces)
        result.description = description.trimmingCharacters(in: .whitespaces)
        result.coverImageData = coverImageData
        result.enableAI = enableAI
        onConfirm(result)
        dismiss()
    }

    // MARK: - Cover picker

    private var coverPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                coverPreview
                    .frame(width: 172, height: 220)
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

    // MARK: - AI Choice Card
    private var aiChoiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enableAI.animation(.easeInOut)) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(enableAI ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(enableAI ? .white : Color.accentColor)
                    }
                    Text("Enable AI Companion")
                        .font(.headline)
                        .foregroundStyle(enableAI ? .white : .primary)
                }
            }
            .tint(.accentColor)

            Text("The AI companion can answer your questions about characters, plot, and meaning as you read — without spoilers. Best for novels and literary fiction.")
                .font(.subheadline)
                .foregroundStyle(enableAI ? .white.opacity(0.9) : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(16)
        .background {
            ZStack {
                if enableAI {
                    if #available(iOS 18.0, *) {
                        MeshGradient(
                            width: 3,
                            height: 3,
                            points: [
                                .init(0, 0), .init(0.5, 0), .init(1, 0),
                                .init(0, 0.5), .init(isAnimatingGradient ? 0.2 : 0.8, isAnimatingGradient ? 0.7 : 0.3), .init(1, 0.5),
                                .init(0, 1), .init(0.5, 1), .init(1, 1)
                            ],
                            colors: [
                                .indigo, .purple, .blue,
                                .purple, .blue, .indigo,
                                .blue, .indigo, .purple
                            ]
                        )
                        .onAppear {
                            isAnimatingGradient = false
                            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                                isAnimatingGradient = true
                            }
                        }
                    } else {
                        LinearGradient(
                            colors: [Color.purple, Color.blue, Color.indigo, Color.purple],
                            startPoint: isAnimatingGradient ? .topLeading : .bottomTrailing,
                            endPoint: isAnimatingGradient ? .bottomTrailing : .topLeading
                        )
                        .onAppear {
                            // Reset and animate each time it appears
                            isAnimatingGradient = false
                            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: true)) {
                                isAnimatingGradient = true
                            }
                        }
                    }
                } else {
                    Color(.systemFill)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
