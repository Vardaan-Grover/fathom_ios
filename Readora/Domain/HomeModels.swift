import SwiftUI

struct HomeBook: Identifiable {
    let id: UUID
    let title: String
    let author: String
    let coverColor: Color?
    let textColor: Color?
    let coverFilename: String?
}

struct HomeCategory: Identifiable {
    let id: UUID
    let name: String
    let books: [HomeBook]
    let shelfColor: Color
    let shelfColorHex: String
}
