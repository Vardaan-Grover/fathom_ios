import Combine
import Foundation

/// Emoji sticker pairs shown on collection folders. A shelf gets a stable
/// default pair from its ID; user overrides persist in UserDefaults.
class StickerStore: ObservableObject {
    static let shared = StickerStore()

    @Published var overrides: [String: String] = [:]
    private let key = "fathom.home.classic.stickers"

    static let allPairs: [(String, String)] = [
        // Travel / Places
        ("🇯🇵", "⛩️"), ("🇫🇷", "🗼"), ("🇳🇱", "🌷"), ("🇬🇧", "🎡"),
        ("🇮🇹", "🍕"), ("🇺🇸", "🗽"), ("🇰🇷", "🏯"), ("🇪🇬", "🐪"),
        ("🇨🇦", "🍁"), ("🇦🇺", "🦘"), ("🇧🇷", "🦜"), ("🇲🇽", "🌮"),
        ("🏝️", "🥥"), ("🏕️", "🔥"), ("🏔️", "🏂"), ("🏜️", "🌵"),
        ("🏰", "🛡️"), ("🎢", "🎡"), ("🚂", "🛤️"), ("✈️", "☁️"),

        // Hobbies / Arts
        ("📷", "🎞️"), ("🎨", "🖼️"), ("🎸", "🎶"), ("🎭", "🎟️"),
        ("🕹️", "👾"), ("♟️", "🎲"), ("🧵", "🧶"), ("🩰", "🦢"),
        ("🎤", "🎧"), ("🎬", "🍿"), ("🖍️", "📝"), ("🛹", "🧢"),
        ("📚", "🔖"), ("🖋️", "📜"), ("🔭", "🌌"), ("🔬", "🧬"),

        // Cozy / Vibe
        ("☕", "📚"), ("🌙", "✨"), ("🌿", "🪴"), ("🕯️", "📖"),
        ("🌧️", "🌂"), ("🍵", "🫖"), ("🧸", "🎀"), ("🧦", "🔥"),
        ("🛁", "🧼"), ("🛌", "💤"), ("🧶", "🐈"), ("📻", "🎵"),
        ("🍷", "🧀"), ("📻", "📼"), ("🔮", "🦋"), ("🧿", "🪬"),

        // Food / Drink
        ("🍕", "🍷"), ("🍔", "🍟"), ("🍣", "🥢"), ("🥐", "☕"),
        ("🥞", "🍯"), ("🥑", "🍞"), ("🌶️", "🌮"), ("🍜", "🥟"),
        ("🍓", "🍰"), ("🍦", "🍭"), ("🍺", "🥨"), ("🍾", "🥂"),
        ("🍉", "☀️"), ("🥥", "🍹"), ("🍩", "🥛"), ("🍒", "🍫"),

        // Nature / Animals
        ("❄️", "⛷️"), ("🏖️", "🍹"), ("🐶", "🦴"), ("🐱", "🧶"),
        ("🦊", "🍂"), ("🐸", "🍄"), ("🦉", "🌙"), ("🐝", "🌻"),
        ("🐢", "🌊"), ("🦕", "🌋"), ("🦋", "🌸"), ("🦦", "🐚"),
        ("🐼", "🎋"), ("🐧", "🧊"), ("🦄", "🌈"), ("🐉", "🔥"),

        // Random / Fun
        ("🚀", "👽"), ("🛸", "🌌"), ("👻", "🎃"), ("🤡", "🎈"),
        ("🤖", "⚙️"), ("🤠", "🌵"), ("👑", "💎"), ("🎯", "🏆"),
        ("💣", "💥"), ("🪄", "🐰"), ("🕰️", "⏳"), ("🗝️", "🚪"),
        ("💌", "💝"), ("💸", "💳"), ("💡", "🧠"), ("🧸", "🎈"),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        {
            overrides = dict
        }
    }

    func shuffle(for categoryID: UUID) {
        let current = overrides[categoryID.uuidString]
        var nextPair = StickerStore.allPairs.randomElement()!
        while "\(nextPair.0),\(nextPair.1)" == current {
            nextPair = StickerStore.allPairs.randomElement()!
        }

        overrides[categoryID.uuidString] = "\(nextPair.0),\(nextPair.1)"
        save()
    }

    func setStickers(_ s1: String, _ s2: String, for categoryID: UUID) {
        overrides[categoryID.uuidString] = "\(s1),\(s2)"
        save()
    }

    func stickers(for categoryID: UUID) -> (String, String)? {
        if let val = overrides[categoryID.uuidString] {
            let parts = val.split(separator: ",")
            if parts.count == 2 {
                return (String(parts[0]), String(parts[1]))
            }
        }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
