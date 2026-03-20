import Foundation

protocol ContextEngine {
    func makeBundle(from passage: Passage) -> ContextBundle
}

struct DefaultContextEngine: ContextEngine {
    func makeBundle(from passage: Passage) -> ContextBundle {
        let window = """
            [BEFORE]
            \(passage.beforeText)

            [SELECTED]
            \(passage.selectedText)

            [AFTER]
            \(passage.afterText)
            """

        return ContextBundle(
            selectedText: passage.selectedText,
            localWindow: window,
            chapterTitle: passage.chapterTitle,
            readingPositionHint: nil
        )
    }
}