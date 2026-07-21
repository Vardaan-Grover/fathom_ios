import Foundation

// MARK: - MetricsRecord

/// One MetricKit payload, wrapped with the context needed to interpret it
/// later.
///
/// MetricKit's own JSON does not say which build produced it, and payloads can
/// sit on disk across app updates — without the version stamp a jetsam spike
/// can't be attributed to the release that caused it.
struct MetricsRecord: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// `MXMetricPayload` — the daily digest (memory, launch, hangs, exits).
        case metric
        /// `MXDiagnosticPayload` — crashes, hangs, CPU/disk exceptions, with
        /// call stacks.
        case diagnostic
    }

    let kind: Kind
    /// When Fathom received the payload, not the period it covers. The covered
    /// range lives inside `payload` (`timeStampBegin`/`timeStampEnd`).
    let receivedAt: Date
    let appVersion: String
    let buildNumber: String
    /// The raw `jsonRepresentation()` bytes, stored verbatim.
    ///
    /// Kept opaque on purpose: MetricKit adds fields between OS releases, and
    /// re-encoding through our own model would silently drop whatever Apple
    /// shipped that we don't know about yet.
    let payload: Data
}

// MARK: - MetricsSink

/// Where received payloads go.
///
/// The seam exists so a network sink can be added without touching the
/// MetricKit subscriber: today the only implementation is `DiskMetricsSink`,
/// and nothing about a Fathom install leaves the device.
protocol MetricsSink: Sendable {
    func receive(_ record: MetricsRecord) async
}

// MARK: - DiskMetricsSink

/// Persists records as individual JSON files under Application Support,
/// keeping only the most recent `retentionLimit`.
///
/// An actor rather than the lock-plus-queue pattern the other stores use:
/// those are written to on every page turn and have to stay cheap on the main
/// thread, whereas MetricKit delivers at most once per day, off the main
/// thread, so there is no contention to design around.
actor DiskMetricsSink: MetricsSink {

    static let shared = DiskMetricsSink()

    /// Roughly a month of daily payloads. Each is a few KB; diagnostics with
    /// call stacks can reach a few hundred KB, so this is bounded by count
    /// rather than left to grow.
    private static let retentionLimit = 30

    private let directory: URL

    private init() {
        directory = AppFiles.applicationSupportDirectory()
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    // MARK: - MetricsSink

    func receive(_ record: MetricsRecord) async {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: record), options: .atomic)
            pruneOldest()
        } catch {
            // A diagnostics store that crashes the app it is diagnosing would
            // be worse than useless — losing a payload is the correct failure.
            AppLogger.logError(tag: "Diagnostics", error)
        }
    }

    // MARK: - Reading back

    /// All stored records, newest first.
    func storedRecords() -> [MetricsRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return storedFiles()
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(MetricsRecord.self, from: $0) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// Writes every stored record into a single JSON array at a temporary URL,
    /// suitable for handing to the share sheet.
    ///
    /// Returns `nil` when nothing has been captured yet — on a fresh install
    /// that is the normal state for the first 24 hours.
    func exportArchive() -> URL? {
        let records = storedRecords()
        guard !records.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fathom-diagnostics.json")
        do {
            try encoder.encode(records).write(to: url, options: .atomic)
            return url
        } catch {
            AppLogger.logError(tag: "Diagnostics", error)
            return nil
        }
    }

    // MARK: - Private

    private func fileURL(for record: MetricsRecord) -> URL {
        // Timestamp-prefixed so a lexical sort is a chronological sort, and
        // suffixed so two payloads delivered in the same second don't collide.
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: record.receivedAt)
        return directory.appendingPathComponent(
            "\(stamp)-\(record.kind.rawValue)-\(UUID().uuidString.prefix(8)).json"
        )
    }

    /// Files in the diagnostics directory, newest first.
    private func storedFiles() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return (contents ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func pruneOldest() {
        let files = storedFiles()
        guard files.count > Self.retentionLimit else { return }
        for url in files.dropFirst(Self.retentionLimit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Filename formatting

private extension ISO8601DateFormatter {
    /// ISO8601 without the colons, which are legal in APFS filenames but are
    /// displayed as `/` in Finder and confuse anything shell-adjacent.
    static let filenameSafe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return formatter
    }()
}
