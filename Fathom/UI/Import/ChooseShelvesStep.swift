import SwiftUI

/// Import flow step — lets the user add the newly imported book to one or more
/// shelves, with the option to create a new shelf on the spot.
struct ChooseShelvesStep: View {
    let onCreateShelf: (String, String) -> HomeCategory?
    let onNext: () -> Void

    @Binding var selectedIDs: Set<UUID>
    @State private var categories: [HomeCategory]
    @State private var showNewShelfSheet = false

    init(
        categories: [HomeCategory],
        selectedIDs: Binding<Set<UUID>>,
        onCreateShelf: @escaping (String, String) -> HomeCategory?,
        onNext: @escaping () -> Void
    ) {
        _categories = State(initialValue: categories)
        _selectedIDs = selectedIDs
        self.onCreateShelf = onCreateShelf
        self.onNext = onNext
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                Text("Add to Shelves")
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: selectedIDs.count)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(categories) { category in
                        ShelfPill(
                            category: category,
                            isSelected: selectedIDs.contains(category.id)
                        ) {
                            if selectedIDs.contains(category.id) {
                                selectedIDs.remove(category.id)
                            } else {
                                selectedIDs.insert(category.id)
                            }
                        }
                        .equatable()
                    }

                    AddShelfPill { showNewShelfSheet = true }
                }
                .padding(20)
            }
        }
        .navigationTitle("Add to Shelves")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onNext() }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showNewShelfSheet) {
            NewShelfSheet { name, colorHex in
                guard let newCategory = onCreateShelf(name, colorHex) else { return }
                categories.append(newCategory)
                selectedIDs.insert(newCategory.id)
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
    }

    private var subtitle: String {
        switch selectedIDs.count {
        case 0: "Tap a shelf to add this book"
        case 1: "1 shelf selected"
        default: "\(selectedIDs.count) shelves selected"
        }
    }
}
