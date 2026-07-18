import ReadiumShared
import XCTest

@testable import Fathom

final class BookPositionIndexTests: XCTestCase {
    // MARK: - Fixtures

    private func position(
        href: String,
        page: Int,
        totalProgression: Double,
        progression: Double = 0
    ) -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            title: nil,
            locations: Locator.Locations(
                progression: progression,
                totalProgression: totalProgression,
                position: page
            )
        )
    }

    /// Three chapters, four positions each, evenly spread across the book.
    private func makePositions() -> [Locator] {
        var positions: [Locator] = []
        let hrefs = ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml", "OEBPS/ch3.xhtml"]
        var page = 1
        for (chapterIndex, href) in hrefs.enumerated() {
            for pageInChapter in 0..<4 {
                positions.append(
                    position(
                        href: href,
                        page: page,
                        totalProgression: Double(page - 1) / 12.0,
                        progression: Double(pageInChapter) / 4.0
                    )
                )
                page += 1
            }
        }
        return positions
    }

    private func makeTOC() -> [ReadiumShared.Link] {
        [
            Link(href: "OEBPS/ch1.xhtml", title: "One"),
            Link(
                href: "OEBPS/ch2.xhtml",
                title: "Two",
                children: [Link(href: "OEBPS/ch2.xhtml#s1", title: "Two A")]
            ),
            Link(href: "OEBPS/ch3.xhtml", title: "Three"),
        ]
    }

    /// The pre-index behaviour, kept as the oracle the fast path must match.
    private func referenceChapterTitle(
        atTotalProgression progression: Double,
        positions: [Locator],
        tableOfContents: [ReadiumShared.Link]
    ) -> String? {
        guard !tableOfContents.isEmpty else { return nil }

        var markers: [(prog: Double, title: String)] = []
        for entry in flattenedTOCEntries(tableOfContents) {
            guard !entry.breadcrumbTitle.isEmpty else { continue }
            let linkHref =
                "\(entry.link.href)".components(separatedBy: "#").first ?? "\(entry.link.href)"
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

    // MARK: - Chapter titles

    func testChapterTitleMatchesReferenceAcrossTheBook() {
        let positions = makePositions()
        let toc = makeTOC()
        let index = BookPositionIndex(positions: positions, tableOfContents: toc)

        for step in 0...200 {
            let progression = Double(step) / 200.0
            XCTAssertEqual(
                index.chapterTitle(atTotalProgression: progression),
                referenceChapterTitle(
                    atTotalProgression: progression,
                    positions: positions,
                    tableOfContents: toc
                ),
                "mismatch at progression \(progression)"
            )
        }
    }

    func testChapterTitleAtBoundaries() {
        let index = BookPositionIndex(positions: makePositions(), tableOfContents: makeTOC())

        // Chapter one covers pages 1-4, i.e. progression 0 up to (not incl.) 4/12.
        XCTAssertEqual(index.chapterTitle(atTotalProgression: 0), "One")
        XCTAssertEqual(index.chapterTitle(atTotalProgression: 3.0 / 12.0), "One")

        // Chapter two covers pages 5-8. Its nested entry strips the fragment and
        // so anchors to the same page; the deepest breadcrumb wins the tie.
        XCTAssertEqual(index.chapterTitle(atTotalProgression: 4.0 / 12.0), "Two › Two A")
        XCTAssertEqual(index.chapterTitle(atTotalProgression: 7.0 / 12.0), "Two › Two A")

        XCTAssertEqual(index.chapterTitle(atTotalProgression: 8.0 / 12.0), "Three")
        XCTAssertEqual(index.chapterTitle(atTotalProgression: 1), "Three")
    }

    func testChapterTitleBeforeFirstMarkerFallsBackToFirstChapter() {
        let positions = [
            position(href: "OEBPS/ch1.xhtml", page: 1, totalProgression: 0.25),
            position(href: "OEBPS/ch2.xhtml", page: 2, totalProgression: 0.75),
        ]
        let index = BookPositionIndex(positions: positions, tableOfContents: makeTOC())

        XCTAssertEqual(index.chapterTitle(atTotalProgression: 0.0), "One")
    }

    func testChapterTitleMatchesTOCByFilenameWhenFullHrefDiffers() {
        let positions = [
            position(href: "text/ch1.xhtml", page: 1, totalProgression: 0.0),
            position(href: "text/ch2.xhtml", page: 2, totalProgression: 0.5),
        ]
        let index = BookPositionIndex(positions: positions, tableOfContents: makeTOC())

        XCTAssertEqual(index.chapterTitle(atTotalProgression: 0.6), "Two › Two A")
    }

    func testChapterTitleIsNilWithoutTOC() {
        let index = BookPositionIndex(positions: makePositions(), tableOfContents: [])

        XCTAssertNil(index.chapterTitle(atTotalProgression: 0.5))
    }

    func testEmptyIndexHasNoChapterOrLocator() {
        XCTAssertNil(BookPositionIndex.empty.chapterTitle(atTotalProgression: 0.5))
        XCTAssertNil(BookPositionIndex.empty.locator(atTotalProgression: 0.5))
        XCTAssertTrue(BookPositionIndex.empty.positions(forHref: "OEBPS/ch1.xhtml").isEmpty)
    }

    // MARK: - Positions by href

    func testPositionsForHrefReturnsResourcePagesInOrder() {
        let index = BookPositionIndex(positions: makePositions(), tableOfContents: makeTOC())

        let chapter2 = index.positions(forHref: "OEBPS/ch2.xhtml")
        XCTAssertEqual(chapter2.map { $0.locations.position }, [5, 6, 7, 8])
        XCTAssertTrue(index.positions(forHref: "OEBPS/missing.xhtml").isEmpty)
    }

    // MARK: - Projected locator

    func testLocatorAtProgressionMatchesScrubberProjection() {
        let positions = makePositions()
        let index = BookPositionIndex(positions: positions, tableOfContents: makeTOC())

        for step in 0...100 {
            let progression = Double(step) / 100.0
            let expectedIndex = max(
                0,
                min(Int(progression * Double(positions.count - 1)), positions.count - 1)
            )
            XCTAssertEqual(
                index.locator(atTotalProgression: progression)?.locations.position,
                positions[expectedIndex].locations.position
            )
        }
    }
}
