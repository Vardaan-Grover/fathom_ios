import Foundation
import ReadiumShared

struct TOCEntry {
    let link: ReadiumShared.Link
    let depth: Int
    let breadcrumbTitle: String
}

/// Resolves the chapter title for a total-progression value by matching TOC
/// entries against the positions list (by href, then by filename) and picking
/// the last chapter marker at or before that progression. Returns nil when the
/// TOC is empty or no entry could be matched, so callers can fall back to the
/// locator's own title.
func tocChapterTitle(
    atTotalProgression progression: Double,
    positions: [Locator],
    tableOfContents: [ReadiumShared.Link]
) -> String? {
    guard !tableOfContents.isEmpty else { return nil }

    var markers: [(prog: Double, title: String)] = []
    for entry in flattenedTOCEntries(tableOfContents) {
        guard !entry.breadcrumbTitle.isEmpty else { continue }
        let linkHref = "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
        let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

        let match =
            positions.first(where: { "\($0.href)" == linkHref })
            ?? positions.first(where: {
                let fn = "\($0.href)".split(separator: "/").last.map(String.init) ?? ""
                return !linkFilename.isEmpty && fn == linkFilename
            })

        if let pos = match, let prog = pos.locations.totalProgression {
            markers.append((prog: prog, title: entry.breadcrumbTitle))
        }
    }

    guard !markers.isEmpty else { return nil }
    markers.sort { $0.prog < $1.prog }

    return markers.last(where: { $0.prog <= progression })?.title ?? markers.first?.title
}

func flattenedTOCEntries(
    _ links: [ReadiumShared.Link],
    depth: Int = 0,
    parentBreadcrumb: String? = nil
) -> [TOCEntry] {
    var entries: [TOCEntry] = []
    for link in links {
        let title = link.title ?? ""
        let crumb: String
        if let parent = parentBreadcrumb, !parent.isEmpty, !title.isEmpty {
            crumb = "\(parent) › \(title)"
        } else {
            crumb = title
        }
        entries.append(TOCEntry(link: link, depth: depth, breadcrumbTitle: crumb))
        if !link.children.isEmpty {
            entries += flattenedTOCEntries(link.children, depth: depth + 1, parentBreadcrumb: crumb)
        }
    }
    return entries
}
