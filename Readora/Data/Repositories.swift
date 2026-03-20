import Foundation

protocol BookRepository {
    func listBooks() async -> [Book]
    func addBook(_ book: Book) async
}

final actor InMemoryBookRepository: BookRepository {
    private var books: [Book] = [
        Book(id: UUID(), title: "Demo Book", author: "Demo Author", format: .epub, localFilename: nil)
    ]

    func listBooks() async -> [Book] {
        books
    }

    func addBook(_ book: Book) async { books.append(book) }
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

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else {return}
        try? data.write(to: saveURL, options: .atomic)
    }
}
