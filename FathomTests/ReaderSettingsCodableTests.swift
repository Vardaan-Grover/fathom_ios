import Foundation
import Testing

@testable import Fathom

/// `ReaderSettings` is persisted as JSON and CloudKit-synced across devices
/// running different app versions. `pageTurnStyle` must therefore be additive:
/// old payloads (without the key) must decode into the new struct, and new
/// payloads (with the key) must not break old decoders.
struct ReaderSettingsCodableTests {

    /// The struct shape shipped before page curl, used to stand in for an old
    /// app version decoding a new payload.
    private struct LegacyReaderSettings: Codable, Equatable {
        var fontSize: Double = 1.0
        var lineHeight: Double = 1.4
        var colorTheme: ReaderColorTheme = .paper
        var font: ReaderFont = .original
        var margin: Double = 1.5
        var justifyText: Bool = false
        var layout: ReadingLayout = .paginated
        var boldText: Bool = false
    }

    @Test func legacyPayloadDecodesIntoNewStruct() throws {
        let legacy = LegacyReaderSettings(fontSize: 1.3, colorTheme: .night, layout: .scrolling)
        let data = try JSONEncoder().encode(legacy)

        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)

        #expect(decoded.fontSize == 1.3)
        #expect(decoded.colorTheme == .night)
        #expect(decoded.layout == .scrolling)
        #expect(decoded.pageTurnStyle == nil)
        #expect(!decoded.isCurlEnabled)
    }

    @Test func newPayloadDecodesIntoLegacyStruct() throws {
        var settings = ReaderSettings()
        settings.pageTurnStyle = .curl
        let data = try JSONEncoder().encode(settings)

        // An old app version must not reset all reader settings to defaults
        // just because the payload carries the unknown pageTurnStyle key.
        let decoded = try JSONDecoder().decode(LegacyReaderSettings.self, from: data)

        #expect(decoded.fontSize == settings.fontSize)
        #expect(decoded.layout == .paginated)
    }

    @Test func curlRoundTrips() throws {
        var settings = ReaderSettings()
        settings.pageTurnStyle = .curl

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)

        #expect(decoded.pageTurnStyle == .curl)
        #expect(decoded.isCurlEnabled)
        #expect(decoded == settings)
    }

    @Test func curlRequiresPaginatedLayout() {
        var settings = ReaderSettings()
        settings.pageTurnStyle = .curl
        settings.layout = .scrolling

        #expect(!settings.isCurlEnabled)
    }
}
