import Foundation
import ReadiumShared

/// Precomputed lookups over a publication's positions list, built once when the
/// positions and table of contents load.
///
/// The scrubber and bookmark overlay resolve a chapter title and a bookmark hit
/// on every drag frame. Doing that straight off the positions array costs a scan
/// per lookup — and, for the chapter title, a scan per TOC entry — which a book
/// with tens of thousands of positions cannot absorb at touch rate. Here those
/// become a binary search and a dictionary hit.
struct BookPositionIndex {
    let positions: [Locator]

    private let chapterMarkers: [ChapterMarker]
    private let positionsByHref: [String: [Locator]]
    private let identity: UUID

    private struct ChapterMarker {
        let totalProgression: Double
        let title: String
        /// Position in the flattened TOC, used to break progression ties.
        let order: Int
    }

    static let empty = BookPositionIndex()

    private init() {
        positions = []
        chapterMarkers = []
        positionsByHref = [:]
        identity = UUID()
    }

    init(positions: [Locator], tableOfContents: [ReadiumShared.Link]) {
        self.positions = positions
        self.identity = UUID()

        var byHref: [String: [Locator]] = [:]
        for position in positions {
            byHref["\(position.href)", default: []].append(position)
        }
        self.positionsByHref = byHref

        // Reversed so the earliest position for a filename ends up as the final
        // write, matching the first-match semantics of the TOC lookup below.
        var firstPositionByFilename: [String: Locator] = [:]
        for position in positions.reversed() {
            let filename = "\(position.href)".split(separator: "/").last.map(String.init) ?? ""
            guard !filename.isEmpty else { continue }
            firstPositionByFilename[filename] = position
        }

        var markers: [ChapterMarker] = []
        if !tableOfContents.isEmpty {
            for entry in flattenedTOCEntries(tableOfContents) {
                guard !entry.breadcrumbTitle.isEmpty else { continue }
                let linkHref = "\(entry.link.href)".components(separatedBy: "#").first
                    ?? "\(entry.link.href)"
                let linkFilename = linkHref.split(separator: "/").last.map(String.init) ?? linkHref

                let match = byHref[linkHref]?.first
                    ?? (linkFilename.isEmpty ? nil : firstPositionByFilename[linkFilename])

                if let progression = match?.locations.totalProgression {
                    markers.append(
                        ChapterMarker(
                            totalProgression: progression,
                            title: entry.breadcrumbTitle,
                            order: markers.count
                        )
                    )
                }
            }
            // A nested entry anchors to the same position as its parent, because
            // the fragment is stripped when matching. Sorting on TOC order as a
            // tiebreak keeps the deepest breadcrumb winning, rather than leaving
            // it to an unstable sort.
            markers.sort {
                $0.totalProgression == $1.totalProgression
                    ? $0.order < $1.order
                    : $0.totalProgression < $1.totalProgression
            }
        }
        self.chapterMarkers = markers
    }

    /// The title of the last chapter starting at or before `progression`, or the
    /// first chapter's title when `progression` precedes every marker. Returns
    /// nil when the TOC is empty or no entry matched, so callers can fall back to
    /// the locator's own title.
    func chapterTitle(atTotalProgression progression: Double) -> String? {
        guard !chapterMarkers.isEmpty else { return nil }

        // Lower-bound search for the first marker starting after `progression`.
        var low = 0
        var high = chapterMarkers.count
        while low < high {
            let mid = low + (high - low) / 2
            if chapterMarkers[mid].totalProgression <= progression {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low > 0 ? chapterMarkers[low - 1].title : chapterMarkers.first?.title
    }

    /// The positions belonging to one resource, in reading order.
    func positions(forHref href: String) -> [Locator] {
        positionsByHref[href] ?? []
    }

    /// The position the scrubber projects for a total-progression value.
    func locator(atTotalProgression progression: Double) -> Locator? {
        guard !positions.isEmpty else { return nil }
        let index = max(0, min(Int(progression * Double(positions.count - 1)), positions.count - 1))
        return positions[index]
    }
}

extension BookPositionIndex: Equatable {
    /// Compared by build identity: an index is rebuilt only when its inputs
    /// change, and this keeps SwiftUI's view diffing off the positions array.
    static func == (lhs: BookPositionIndex, rhs: BookPositionIndex) -> Bool {
        lhs.identity == rhs.identity
    }
}
