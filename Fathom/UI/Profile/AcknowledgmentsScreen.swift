import SwiftUI

// MARK: - AcknowledgmentsScreen

struct AcknowledgmentsScreen: View {
    private struct Item: Identifiable {
        let name: String
        let blurb: String
        let url: URL?
        let license: String
        var id: String { name }
    }

    private let items: [Item] = [
        Item(name: "Readium",
             blurb: "EPUB reading engine — navigation, layout, and styling.",
             url: URL(string: "https://github.com/readium/swift-toolkit"),
             license: "BSD-3-Clause"),
        Item(name: "GRDB",
             blurb: "SQLite toolkit powering the local library and annotations.",
             url: URL(string: "https://github.com/groue/GRDB.swift"),
             license: "MIT"),
        Item(name: "Supabase",
             blurb: "Authentication via magic-link sign in.",
             url: URL(string: "https://github.com/supabase/supabase-swift"),
             license: "MIT"),
        Item(name: "ReadiumAdapterGCDWebServer",
             blurb: "Local web server for serving EPUB resources to the reader.",
             url: URL(string: "https://github.com/readium/swift-toolkit"),
             license: "BSD-3-Clause"),
        Item(name: "Minizip",
             blurb: "ZIP decompression used by the EPUB pipeline.",
             url: URL(string: "https://github.com/zlib-ng/minizip-ng"),
             license: "Zlib"),
    ]

    var body: some View {
        List {
            Section {
                Text("Fathom stands on the shoulders of the open-source community. Thanks to the maintainers of these projects.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(items) { item in
                    if let url = item.url {
                        Link(destination: url) { row(item) }
                    } else {
                        row(item)
                    }
                }
            }
        }
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(item.license)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(.tertiarySystemFill))
                    )
            }
            Text(item.blurb)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
