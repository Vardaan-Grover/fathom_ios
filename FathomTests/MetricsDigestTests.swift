import Foundation
import Testing

@testable import Fathom

/// `MetricsDigest` decodes MetricKit's JSON by key name, and every field is
/// optional so that a section the OS omitted is not an error. That leniency is
/// correct, but it means a wrong key name reads as zero rather than throwing —
/// and for a digest whose whole purpose is counting jetsam kills, a silent zero
/// is indistinguishable from "no crashes."
///
/// So these tests exist to pin the key names against a payload shaped like the
/// real thing. `metrickit_payload.json` mirrors Apple's documented
/// `MXMetricPayload.jsonRepresentation()` output — including its quirks:
/// measurements are locale-formatted strings ("412,336 kB"), not numbers, and
/// counters that were zero for the period are omitted entirely rather than
/// serialised as 0.
@Suite struct MetricsDigestTests {

    // MARK: - Helpers

    private static func loadFixturePayload() throws -> Data {
        final class Token {}
        let url = try #require(
            Bundle(for: Token.self).url(forResource: "metrickit_payload", withExtension: "json"),
            "metrickit_payload.json missing from test bundle"
        )
        return try Data(contentsOf: url)
    }

    private static func record(
        _ json: Data,
        kind: MetricsRecord.Kind = .metric
    ) -> MetricsRecord {
        MetricsRecord(
            kind: kind,
            receivedAt: Date(),
            appVersion: "1.0",
            buildNumber: "1",
            payload: json
        )
    }

    private static func record(
        json: String,
        kind: MetricsRecord.Kind = .metric
    ) -> MetricsRecord {
        record(Data(json.utf8), kind: kind)
    }

    // MARK: - Real payload shape

    @Test func extractsCountersFromRealPayloadShape() throws {
        let digest = MetricsDigest.summarize([Self.record(try Self.loadFixturePayload())])

        #expect(digest.payloadCount == 1)
        #expect(digest.foregroundMemoryKills == 3)
        #expect(digest.backgroundMemoryKills == 2)
        #expect(digest.watchdogKills == 1)
    }

    /// The regression this suite was written for. MetricKit serialises
    /// measurements through the current locale, so the value arrives with
    /// grouping separators — "412,336 kB" on en_US. `Double("412,336")` is nil,
    /// which meant peak memory silently read 0 for every genuine payload while
    /// hand-written test values like "412336 kB" parsed fine.
    @Test func parsesLocaleFormattedPeakMemory() throws {
        let digest = MetricsDigest.summarize([Self.record(try Self.loadFixturePayload())])

        // 412,336 kB, and MetricKit's kB is decimal (1000), not 1024.
        #expect(digest.peakMemoryBytes == 412_336_000)
    }

    @Test(arguments: [
        ("21874 kB", UInt64(21_874_000)),
        ("21,874 kB", UInt64(21_874_000)),
        ("1,234,567 kB", UInt64(1_234_567_000)),
        ("512 bytes", UInt64(512)),
        ("2 MB", UInt64(2_000_000)),
        ("3 GB", UInt64(3_000_000_000)),
    ])
    func parsesMeasurementStrings(input: String, expected: UInt64) {
        let json = """
        {"memoryMetrics": {"peakMemoryUsage": "\(input)"}}
        """
        let digest = MetricsDigest.summarize([Self.record(json: json)])
        #expect(digest.peakMemoryBytes == expected)
    }

    @Test(arguments: ["", "not a measurement", "kB", "12 furlongs"])
    func unparseableMeasurementsReadZeroRatherThanThrow(input: String) {
        let json = """
        {"memoryMetrics": {"peakMemoryUsage": "\(input)"}}
        """
        let digest = MetricsDigest.summarize([Self.record(json: json)])
        #expect(digest.peakMemoryBytes == 0)
    }

    // MARK: - Omitted sections

    /// MetricKit ships `"foregroundExitData": {}` when nothing of note happened
    /// in the foreground — the keys are absent, not zero.
    @Test func handlesEmptyExitData() {
        let json = """
        {"applicationExitMetrics": {"foregroundExitData": {}, \
        "backgroundExitData": {"cumulativeMemoryPressureExitCount": 1}}}
        """
        let digest = MetricsDigest.summarize([Self.record(json: json)])

        #expect(digest.payloadCount == 1)
        #expect(digest.foregroundMemoryKills == 0)
        #expect(digest.backgroundMemoryKills == 0)
        #expect(digest.watchdogKills == 0)
    }

    @Test func handlesPayloadWithNoRelevantSections() {
        let digest = MetricsDigest.summarize([Self.record(json: #"{"appVersion": "1.0"}"#)])

        #expect(digest.payloadCount == 1)
        #expect(digest.foregroundMemoryKills == 0)
        #expect(digest.peakMemoryBytes == 0)
    }

    @Test func skipsUndecodablePayloadWithoutCountingIt() {
        let digest = MetricsDigest.summarize([Self.record(json: "this is not json")])
        #expect(digest.payloadCount == 0)
    }

    // MARK: - Aggregation

    /// Counters sum across payloads; peak memory is a high-water mark and must
    /// take the max rather than accumulate.
    @Test func aggregatesCountersAndTakesMaxPeakMemory() {
        let first = """
        {"memoryMetrics": {"peakMemoryUsage": "300,000 kB"}, \
        "applicationExitMetrics": {"foregroundExitData": \
        {"cumulativeMemoryResourceLimitExitCount": 2, "cumulativeAppWatchdogExitCount": 1}}}
        """
        let second = """
        {"memoryMetrics": {"peakMemoryUsage": "100,000 kB"}, \
        "applicationExitMetrics": {"foregroundExitData": \
        {"cumulativeMemoryResourceLimitExitCount": 5, "cumulativeAppWatchdogExitCount": 3}}}
        """
        let digest = MetricsDigest.summarize([
            Self.record(json: first), Self.record(json: second),
        ])

        #expect(digest.payloadCount == 2)
        #expect(digest.foregroundMemoryKills == 7)
        #expect(digest.watchdogKills == 4)
        #expect(digest.peakMemoryBytes == 300_000_000)
    }

    /// Diagnostic payloads carry call stacks rather than counters, so the
    /// digest must ignore them — including for `payloadCount`, which labels the
    /// metric payloads the numbers were drawn from.
    @Test func ignoresDiagnosticRecords() throws {
        let payload = try Self.loadFixturePayload()
        let digest = MetricsDigest.summarize([
            Self.record(payload, kind: .diagnostic),
            Self.record(payload, kind: .metric),
        ])

        #expect(digest.payloadCount == 1)
        #expect(digest.foregroundMemoryKills == 3)
    }

    @Test func emptyInputProducesZeroedDigest() {
        let digest = MetricsDigest.summarize([])

        #expect(digest.payloadCount == 0)
        #expect(digest.foregroundMemoryKills == 0)
        #expect(digest.backgroundMemoryKills == 0)
        #expect(digest.watchdogKills == 0)
        #expect(digest.peakMemoryBytes == 0)
    }
}
