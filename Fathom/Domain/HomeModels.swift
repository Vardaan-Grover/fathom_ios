import SwiftUI

struct HomeBook: Identifiable {
    let id: UUID
    let title: String
    let author: String
    let coverColor: Color?
    let textColor: Color?
    let coverFilename: String?
    var categoryIDs: Set<UUID> = []
}

extension HomeBook: Equatable {
    static func == (lhs: HomeBook, rhs: HomeBook) -> Bool { lhs.id == rhs.id }
}

struct HomeCategory: Identifiable {
    let id: UUID
    let name: String
    var books: [HomeBook]
    let shelfColor: Color
    let shelfColorHex: String
}
