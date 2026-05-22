import PhotosUI
import SwiftUI

/// Container for the multi-step book import / edit flow.
///
/// Import: Step 1 (details + cover) → Step 2 (AI companion)
/// Edit:   Step 1 only — trailing "Save" button confirms immediately.
struct BookImportFlow: View {

    let initial: BookCustomization
    let isEditing: Bool
    let onConfirm: (BookCustomization) -> Void
    let onCancel: () -> Void

    // Shared mutable state across steps
    @State private var title: String
    @State private var author: String
    @State private var coverImageData: Data?
    @State private var isCoverChanged: Bool
    @State private var enableAI: Bool

    @State private var navigateToAI = false
    @State private var didConfirm = false

    @Environment(\.dismiss) private var dismiss

    init(
        initial: BookCustomization,
        isEditing: Bool = false,
        onConfirm: @escaping (BookCustomization) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.isEditing = isEditing
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: initial.title)
        _author = State(initialValue: initial.author)
        _coverImageData = State(initialValue: initial.coverImageData)
        _isCoverChanged = State(initialValue: initial.isCoverChanged)
        _enableAI = State(initialValue: initial.enableAI)
    }

    var body: some View {
        NavigationStack {
            BookDetailsStep(
                bookID: initial.id,
                title: $title,
                author: $author,
                coverImageData: $coverImageData,
                isCoverChanged: $isCoverChanged,
                isEditing: isEditing,
                onNext: handleNext
            )
            .navigationDestination(isPresented: $navigateToAI) {
                BookAIStep(enableAI: $enableAI) {
                    didConfirm = true
                    commitAndDismiss()
                }
            }
        }
        .onDisappear {
            if !didConfirm { onCancel() }
        }
    }

    // MARK: - Actions

    private func handleNext() {
        if isEditing {
            didConfirm = true
            commitAndDismiss()
        } else {
            navigateToAI = true
        }
    }

    private func commitAndDismiss() {
        var result = initial
        result.title = title.trimmingCharacters(in: .whitespaces)
        result.author = author.trimmingCharacters(in: .whitespaces)
        result.coverImageData = coverImageData
        result.enableAI = enableAI
        result.isCoverChanged = isCoverChanged
        onConfirm(result)
        dismiss()
    }
}
