import PhotosUI
import SwiftUI

/// Container for the multi-step book import / edit flow.
///
/// Import: Step 1 (details + cover) → Step 2 (AI companion)
/// Edit:   Step 1 only — trailing "Save" button confirms immediately.
struct BookImportFlow: View {

    let initial: BookCustomization
    let isEditing: Bool
    let categories: [HomeCategory]
    let onCreateShelf: (String, String) -> HomeCategory?
    let onConfirm: (BookCustomization) -> Void
    let onCancel: () -> Void

    // Shared mutable state across steps
    @State private var title: String
    @State private var author: String
    @State private var coverImageData: Data?
    @State private var isCoverChanged: Bool
    @State private var enableAI: Bool
    @State private var originalCoverImageData: Data?
    @State private var selectedCategoryIDs: Set<UUID>

    @State private var navigateToAI = false
    @State private var navigateToShelves = false
    @State private var didConfirm = false

    @Environment(\.dismiss) private var dismiss

    init(
        initial: BookCustomization,
        isEditing: Bool = false,
        categories: [HomeCategory] = [],
        onCreateShelf: @escaping (String, String) -> HomeCategory? = { _, _ in nil },
        onConfirm: @escaping (BookCustomization) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.isEditing = isEditing
        self.categories = categories
        self.onCreateShelf = onCreateShelf
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: initial.title)
        _author = State(initialValue: initial.author)
        _coverImageData = State(initialValue: initial.coverImageData)
        _isCoverChanged = State(initialValue: initial.isCoverChanged)
        _enableAI = State(initialValue: initial.enableAI)
        _selectedCategoryIDs = State(initialValue: initial.selectedCategoryIDs)
        // During import, the initial cover IS the EPUB's embedded cover —
        // capture it now so "Revert to original" works if the user removes it.
        // In edit mode this gets overwritten by re-extracting from the EPUB.
        _originalCoverImageData = State(initialValue: isEditing ? nil : initial.coverImageData)
    }

    var body: some View {
        NavigationStack {
            BookDetailsStep(
                bookID: initial.id,
                title: $title,
                author: $author,
                coverImageData: $coverImageData,
                isCoverChanged: $isCoverChanged,
                originalCoverImageData: originalCoverImageData,
                isEditing: isEditing,
                onNext: handleNext
            )
            .navigationDestination(isPresented: $navigateToShelves) {
                ChooseShelvesStep(
                    categories: categories,
                    selectedIDs: $selectedCategoryIDs,
                    onCreateShelf: onCreateShelf
                ) {
                    didConfirm = true
                    commitAndDismiss()
                }
            }
            // AI companion step is hidden from the UI for now (kept in codebase).
            // .navigationDestination(isPresented: $navigateToAI) {
            //     BookAIStep(enableAI: $enableAI) {
            //         didConfirm = true
            //         commitAndDismiss()
            //     }
            // }
        }
        .onDisappear {
            if !didConfirm { onCancel() }
        }
        .task {
            guard isEditing, let epubURL = initial.epubURL else { return }
            originalCoverImageData = try? await EPUBMetadataExtractor.extract(from: epubURL).coverImageData
        }
    }

    // MARK: - Actions

    private func handleNext() {
        // AI companion step is hidden from the UI for now; the shelves step
        // follows directly during import. `navigateToAI` is kept unused but
        // around for when the AI step is re-enabled.
        _ = navigateToAI
        if isEditing {
            didConfirm = true
            commitAndDismiss()
        } else {
            navigateToShelves = true
        }
    }

    private func commitAndDismiss() {
        var result = initial
        result.title = title.trimmingCharacters(in: .whitespaces)
        result.author = author.trimmingCharacters(in: .whitespaces)
        result.coverImageData = coverImageData
        result.enableAI = enableAI
        result.isCoverChanged = isCoverChanged
        result.selectedCategoryIDs = selectedCategoryIDs
        onConfirm(result)
        dismiss()
    }
}
