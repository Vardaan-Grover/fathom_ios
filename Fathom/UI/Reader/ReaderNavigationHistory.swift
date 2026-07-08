import Combine
import ReadiumShared
import SwiftUI

/// Stack of locators the reader jumped away from (TOC, search, scrub…),
/// backing the Undo button in the reader overlay.
@MainActor
final class ReaderNavigationHistory: ObservableObject {
    @Published var history: [String] = []

    private let maxDepth = 20

    func push(_ locator: Locator) {
        guard let json = locator.jsonString else { return }
        if history.last != json {
            history.append(json)
            if history.count > maxDepth {
                history.removeFirst()
            }
        }
    }

    func pop() -> String? {
        guard !history.isEmpty else { return nil }
        return history.removeLast()
    }

    func clear() {
        history.removeAll()
    }
}
