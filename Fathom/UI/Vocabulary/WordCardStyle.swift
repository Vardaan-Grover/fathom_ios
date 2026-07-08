import SwiftUI

// MARK: - Accent Palette

private let wordAccentPalette: [Color] = [
    Color(hex: "B8720A"),  // Burnt Amber
    Color(hex: "2A5E40"),  // Forest Green
    Color(hex: "922840"),  // Deep Rose
    Color(hex: "1C3E6E"),  // Oxford Navy
    Color(hex: "7A3E18"),  // Terracotta
    Color(hex: "4A2472"),  // Deep Violet
    Color(hex: "1A5C6E"),  // Teal
    Color(hex: "6E2A18"),  // Brick Red
    Color(hex: "2E4E1E"),  // Olive
    Color(hex: "8A3A70"),  // Plum
    Color(hex: "1A4A3A"),  // Dark Jade
    Color(hex: "5A3E10"),  // Dark Caramel
    Color(hex: "2A3A6E"),  // Indigo
    Color(hex: "6E4A1A"),  // Saddle Brown
    Color(hex: "3A1A5A"),  // Midnight Purple
    Color(hex: "1E5248"),  // Deep Teal
    Color(hex: "7A2030"),  // Burgundy
    Color(hex: "1E3E28"),  // Dark Emerald
]

// Fallback used by detail/share views where display-order context isn't available
func wordAccentColor(for word: SavedWord) -> Color {
    wordAccentPalette[StableHash.index(of: word.word, count: wordAccentPalette.count)]
}

// Assigns colors in display order, preventing runs of identical colors within a 3-wide window.
func assignMasonryColors(to words: [SavedWord]) -> [UUID: Color] {
    var result: [UUID: Color] = [:]
    var recentSlots: [Int] = []
    for word in words {
        let preferred = StableHash.index(of: word.word, count: wordAccentPalette.count)
        var slot = preferred
        var tries = 0
        while recentSlots.suffix(3).contains(slot) && tries < wordAccentPalette.count {
            slot = (slot + 1) % wordAccentPalette.count
            tries += 1
        }
        result[word.id] = wordAccentPalette[slot]
        recentSlots.append(slot)
    }
    return result
}

// MARK: - Definition Snippets

// Snippets require decoding the word's dictionary JSON blob, and the masonry
// layout asks for one per word per render pass — cache them. Keyed by
// id + modifiedAt so an edited word gets a fresh snippet.
private let definitionSnippetCache = NSCache<NSString, NSString>()

func firstDefinitionSnippet(for word: SavedWord) -> String {
    let key = "\(word.id.uuidString)-\(word.modifiedAt.timeIntervalSince1970)" as NSString
    if let cached = definitionSnippetCache.object(forKey: key) {
        return cached as String
    }

    let snippet: String
    if let data = word.fullDictionaryJSON,
        let entry = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data),
        let def = entry.entries.first?.senses.first?.definition
    {
        snippet = def.count > 120 ? String(def.prefix(120)) + "…" : def
    } else if let ctx = word.contextSentence {
        snippet = ctx.count > 120 ? String(ctx.prefix(120)) + "…" : ctx
    } else {
        snippet = ""
    }

    definitionSnippetCache.setObject(snippet as NSString, forKey: key)
    return snippet
}

// MARK: - Masonry Layout

func estimatedCardHeight(for word: SavedWord) -> CGFloat {
    let snippet = firstDefinitionSnippet(for: word)
    let charsPerLine: CGFloat = 26
    let snippetLines = max(1, CGFloat(snippet.count) / charsPerLine)
    let wordLines = max(1, CGFloat(word.word.count) / 13)
    let base: CGFloat = 76
    return min(220, base + snippetLines * 18 + wordLines * 22)
}

func masonryColumns(from words: [SavedWord]) -> (left: [SavedWord], right: [SavedWord]) {
    var left: [SavedWord] = []
    var right: [SavedWord] = []
    var leftH: CGFloat = 0
    var rightH: CGFloat = 0
    for word in words {
        let h = estimatedCardHeight(for: word)
        if leftH <= rightH {
            left.append(word)
            leftH += h + 12
        } else {
            right.append(word)
            rightH += h + 12
        }
    }
    return (left, right)
}
