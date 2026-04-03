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
        let narrativeContext = await contextStore.buildPromptContext(
            bookID: passage.bookID,
            selectedText: passage.selectedText
        )

        var window = """
            [BEFORE]
            \(passage.beforeText)

            [SELECTED]
            \(passage.selectedText)

            [AFTER]
            \(passage.afterText)
            """

        if !narrativeContext.promptContext.isEmpty {
            window += "\n\n[NARRATIVE_CONTEXT]\n\(narrativeContext.promptContext)"
        }

        let readingPositionHint: String?
        if let paragraphID = narrativeContext.currentParagraphID {
            readingPositionHint = "paragraphID:\(paragraphID)"
        } else {
            readingPositionHint = nil
        }

        return ContextBundle(
            selectedText: passage.selectedText,
            localWindow: window,
            chapterTitle: passage.chapterTitle,
            readingPositionHint: readingPositionHint
        )
    }
}