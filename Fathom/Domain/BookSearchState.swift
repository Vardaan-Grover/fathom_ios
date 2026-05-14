import Combine
import Foundation
import ReadiumShared
import SwiftUI

struct SearchResultItem: Identifiable {
    let id: UUID
    let locatorJSON: String
    let textBefore: String
    let textMatch: String
    let textAfter: String
}

struct SearchChapterGroup: Identifiable {
    let id: String
    var chapterTitle: String
    var results: [SearchResultItem]
    var isExpanded: Bool = true
}

@MainActor
final class BookSearchState: ObservableObject {
    @Published var query: String = ""
    @Published var groups: [SearchChapterGroup] = []
    @Published var isSearching: Bool = false
    @Published var wholeWord: Bool = false
    @Published var diacriticsInsensitive: Bool = false

    var publication: Publication?
    var tableOfContents: [ReadiumShared.Link] = []

    private var debounceTask: Task<Void, Never>?
    private var iteratorTask: Task<Void, Never>?

    var totalCount: Int { groups.reduce(0) { $0 + $1.results.count } }

    func scheduleSearch() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            iteratorTask?.cancel()
            iteratorTask = nil
            groups = []
            isSearching = false
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch()
        }
    }

    func toggleExpanded(groupID: String) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            groups[idx].isExpanded.toggle()
        }
    }

    // MARK: - Private

    private func performSearch() async {
        guard let publication else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        iteratorTask?.cancel()
        iteratorTask = nil
        groups = []
        isSearching = true

        // diacriticSensitive must always be explicit — the algorithm defaults to insensitive when nil.
        // wholeWord is unsupported by BasicStringSearchAlgorithm, so we filter post-hoc instead.
        let options = SearchOptions(
            caseSensitive: false,
            diacriticSensitive: diacriticsInsensitive ? false : true
        )

        let searchResult = await publication.search(query: trimmed, options: options)
        guard case .success(let iterator) = searchResult else {
            isSearching = false
            return
        }

        iteratorTask = Task { [weak self] in
            defer { iterator.close() }
            guard let self else { return }
            while !Task.isCancelled {
                let next = await iterator.next()
                switch next {
                case .success(let collection):
                    guard let collection else {
                        await MainActor.run { self.isSearching = false }
                        return
                    }
                    await MainActor.run { self.appendResults(from: collection) }
                case .failure:
                    await MainActor.run { self.isSearching = false }
                    return
                }
            }
            await MainActor.run { self.isSearching = false }
        }
    }

    private func appendResults(from collection: LocatorCollection) {
        for locator in collection.locators {
            guard let highlight = locator.text.highlight, !highlight.isEmpty else { continue }
            guard let jsonString = locator.jsonString else { continue }

            if wholeWord && !isWholeWordMatch(
                before: locator.text.before ?? "",
                after: locator.text.after ?? ""
            ) { continue }

            let hrefString = "\(locator.href)"
            let item = SearchResultItem(
                id: UUID(),
                locatorJSON: jsonString,
                textBefore: locator.text.before ?? "",
                textMatch: highlight,
                textAfter: locator.text.after ?? ""
            )

            if let idx = groups.firstIndex(where: { $0.id == hrefString }) {
                groups[idx].results.append(item)
            } else {
                let title = resolveChapterTitle(for: locator, hrefString: hrefString)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    groups.append(SearchChapterGroup(
                        id: hrefString,
                        chapterTitle: title,
                        results: [item]
                    ))
                }
            }
        }
    }

    private func isWholeWordMatch(before: String, after: String) -> Bool {
        let beforeOK = before.isEmpty || !(before.last!.isLetter || before.last!.isNumber)
        let afterOK = after.isEmpty || !(after.first!.isLetter || after.first!.isNumber)
        return beforeOK && afterOK
    }

    private var flatTOC: [TOCEntry] { flattenedTOCEntries(tableOfContents) }

    private func resolveChapterTitle(for locator: Locator, hrefString: String) -> String {
        let hrefPath = hrefString.components(separatedBy: "#").first ?? hrefString
        let hrefFilename = hrefPath.split(separator: "/").last.map(String.init) ?? hrefPath

        // Prefer TOC breadcrumb — gives "Part 1 › I" style full path instead of bare leaf title
        for entry in flatTOC.reversed() {
            guard !entry.breadcrumbTitle.isEmpty else { continue }
            let linkHref = "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
            let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref
            if linkHref == hrefPath || (!linkFilename.isEmpty && linkFilename == hrefFilename) {
                return entry.breadcrumbTitle
            }
        }

        if let title = locator.title, !title.isEmpty { return title }

        if let pub = publication {
            if let idx = pub.readingOrder.firstIndex(where: {
                let roHref = "\($0.href)".components(separatedBy: "#").first ?? "\($0.href)"
                let roFilename = roHref.split(separator: "/").last.map(String.init) ?? roHref
                return roHref == hrefPath || (!roFilename.isEmpty && roFilename == hrefFilename)
            }) {
                return "Part \(idx + 1)"
            }
        }

        return "Chapter"
    }
}
