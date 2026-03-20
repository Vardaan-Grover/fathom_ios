import Foundation

protocol ReaderService {
    func openSamplePassage(for book: Book) async -> Passage
}

struct DefaultReaderService: ReaderService {
    func openSamplePassage(for book: Book) async -> Passage {
        // Placeholder passage (until EPUB/PDF selection extraction is implemented)
        return Passage(
                    id: UUID(),
                    bookID: book.id,
                    chapterTitle: "Chapter 1",
                    selectedText: "…a phrase whose meaning is unclear…",
                    beforeText: "The character hesitated at the door, remembering the promise.",
                    afterText: "And yet, they stepped forward as if compelled."
                )
    }
}
