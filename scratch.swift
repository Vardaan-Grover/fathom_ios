import Foundation

struct Book: Codable {
    var title: String
    var contentHash: String? = nil
}

let b = Book(title: "Test", contentHash: "hash123")
let data = try! JSONEncoder().encode(b)
print(String(data: data, encoding: .utf8)!)
