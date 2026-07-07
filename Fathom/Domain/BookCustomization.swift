import Foundation

struct BookCustomization: Identifiable {
    let id: UUID

    // User-editable — stored locally only
    var title: String
    var author: String
    var description: String
    var coverImageData: Data?

    // Original EPUB metadata — sent to the backend verbatim
    let originalTitle: String
    let originalAuthor: String?
    let originalLanguage: String?
    
    // AI Choice
    var enableAI: Bool = false

    // Set to true when the user explicitly picks a new cover image (edit mode only)
    var isCoverChanged: Bool = false

    // Location of the source EPUB on disk — used in edit mode to re-extract the
    // original embedded cover so the user can revert back to it.
    var epubURL: URL? = nil

    // Shelves the user chose to add this book to during import.
    var selectedCategoryIDs: Set<UUID> = []
}
