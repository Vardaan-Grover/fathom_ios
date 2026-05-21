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
}
