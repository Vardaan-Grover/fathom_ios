import Foundation

protocol ContextEngine {
    func makeBundle(from passage: Passage) async -> ContextBundle
}

struct DefaultContextEngine: ContextEngine {
    private let contextStore: NarrativeContextStore

    init(contextStore: NarrativeContextStore = .shared) {
        self.contextStore = contextStore
    }

    func makeBundle(from passage: Passage) async -> ContextBundle {
        let window = """
            [BEFORE]
            \(passage.beforeText)

            [SELECTED]
            \(passage.selectedText)

            [AFTER]
            \(passage.afterText)
            """

        let absoluteIndex = await contextStore.getAbsoluteIndex(
            for: passage.bookID,
            selectedText: passage.selectedText
        )

        let readingPositionHint: String?
        if let idx = absoluteIndex {
            readingPositionHint = "absoluteIndex:\(idx)"
        } else {
            readingPositionHint = nil
        }

        return ContextBundle(
            bookID: passage.bookID,
            selectedText: passage.selectedText,
            localWindow: window,
            chapterTitle: passage.chapterTitle,
            readingPositionHint: readingPositionHint
        )
    }
}
