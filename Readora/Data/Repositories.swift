import Foundation

protocol CategoryRepository {
    func listCategories() async -> [BookCategory]
    func addCategory(_ category: BookCategory) async
    func updateCategory(id: UUID, name: String, colorHex: String) async
    func deleteCategory(id: UUID) async
}

final actor InMemoryCategoryRepository: CategoryRepository {
    private var categories: [BookCategory] = []

    func listCategories() async -> [BookCategory] { categories }
    func addCategory(_ category: BookCategory) async { categories.append(category) }
    func updateCategory(id: UUID, name: String, colorHex: String) async {
        guard let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].name = name
        categories[idx].shelfColorHex = colorHex
    }
    func deleteCategory(id: UUID) async {
        categories.removeAll { $0.id == id }
    }
}

protocol BookRepository {
    func listBooks() async -> [Book]
    func addBook(_ book: Book) async
    func deleteBook(_ book: Book) async
}

final actor InMemoryBookRepository: BookRepository {
    private var books: [Book] = [
        Book(id: UUID(), title: "Demo Book", author: "Demo Author", format: .epub, localFilename: nil)
    ]

    func listBooks() async -> [Book] {
        books
    }

    func addBook(_ book: Book) async { books.append(book) }
    
    func deleteBook(_ book: Book) async {
        books.removeAll { $0.id == book.id }
    }
}

final actor JSONBookRepository: BookRepository {
    private var books: [Book] = []
    private let saveURL: URL

    init() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)

        saveURL = appSupport.appendingPathComponent("books.json")

        // Load existing books from disk if the file exists
        if let data = try? Data(contentsOf: saveURL),
            let decoded = try? JSONDecoder().decode([Book].self, from: data)
        {
            books = decoded
        }
    }

    func listBooks() async -> [Book] {
        books
    }

    func addBook(_ book: Book) async {
        books.append(book)
        save()
    }
    
    func deleteBook(_ book: Book) async {
        books.removeAll { $0.id == book.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else {return}
        try? data.write(to: saveURL, options: .atomic)
    }
}
