import Foundation
import ReadiumShared

struct TOCEntry {
    let link: ReadiumShared.Link
    let depth: Int
    let breadcrumbTitle: String
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
