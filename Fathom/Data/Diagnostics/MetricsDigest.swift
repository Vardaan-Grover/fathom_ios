import Foundation

/// A readable summary of the fields we actually act on, pulled out of stored
/// `MXMetricPayload` JSON.
///
/// Deliberately narrow. MetricKit's payload is large and its shape shifts
/// between OS releases, so this decodes only the exit counters and peak
/// memory — the fields behind the reader's jetsam question — and treats every
/// one of them as optional. A key Apple renames turns into a zero here, never
/// a thrown error; the verbatim payload is still on disk for anything this
/// summary doesn't cover.
struct MetricsDigest {

    /// Foreground kills for exceeding the memory limit — the jetsam counter.
    /// This is the number to watch when changing Readium preload counts.
    var foregroundMemoryKills = 0
    /// Background kills for the same reason. Usually benign: the OS reclaiming
    /// a suspended app is normal, and only a sharp rise is interesting.
    var backgroundMemoryKills = 0
    /// Foreground watchdog terminations — the main thread blocked long enough
    /// for the OS to kill the app.
    var watchdogKills = 0
    /// Highest resident footprint MetricKit observed, in bytes.
    var peakMemoryBytes: UInt64 = 0
    /// How many payloads contributed to these totals.
    var payloadCount = 0

    /// Aggregates every stored metric payload. Diagnostics are skipped — they
    /// carry call stacks rather than counters and are meant to be read raw.
    static func summarize(_ records: [MetricsRecord]) -> MetricsDigest {
        var digest = MetricsDigest()
        for record in records where record.kind == .metric {
            guard let payload = try? JSONDecoder().decode(
                RawMetricPayload.self, from: record.payload
            ) else { continue }

            digest.payloadCount += 1
            let exits = payload.applicationExitMetrics
            digest.foregroundMemoryKills +=
                exits?.foregroundExitData?.cumulativeMemoryResourceLimitExitCount ?? 0
            digest.backgroundMemoryKills +=
                exits?.backgroundExitData?.cumulativeMemoryResourceLimitExitCount ?? 0
            digest.watchdogKills +=
                exits?.foregroundExitData?.cumulativeAppWatchdogExitCount ?? 0
            digest.peakMemoryBytes = max(
                digest.peakMemoryBytes,
                payload.memoryMetrics?.peakMemoryUsageBytes ?? 0
            )
        }
        return digest
    }
}

// MARK: - Lenient payload decoding

/// The slice of `MXMetricPayload`'s JSON this file reads. Every field is
/// optional: MetricKit omits whole sections when a device produced no data for
/// them, which is the common case rather than an error.
private struct RawMetricPayload: Decodable {
    let applicationExitMetrics: ExitMetrics?
    let memoryMetrics: MemoryMetrics?

    struct ExitMetrics: Decodable {
        let foregroundExitData: ExitCounts?
        let backgroundExitData: ExitCounts?
    }

    struct ExitCounts: Decodable {
        let cumulativeMemoryResourceLimitExitCount: Int?
        let cumulativeAppWatchdogExitCount: Int?
    }

    struct MemoryMetrics: Decodable {
        /// MetricKit serialises measurements as strings with a unit suffix
        /// ("123456 kB"), not as numbers, so this cannot decode as `UInt64`.
        let peakMemoryUsage: String?

        var peakMemoryUsageBytes: UInt64 {
            Self.bytes(from: peakMemoryUsage)
        }

        /// Parses "<value> <unit>" into bytes. Returns 0 for anything
        /// unrecognised rather than guessing at a unit.
        static func bytes(from measurement: String?) -> UInt64 {
            guard let measurement else { return 0 }
            let parts = measurement.split(separator: " ")
            guard let value = Double(parts.first ?? "") else { return 0 }
            let unit = parts.count > 1 ? parts[1].lowercased() : "bytes"
            switch unit {
            case "bytes": return UInt64(value)
            case "kb": return UInt64(value * 1_000)
            case "mb": return UInt64(value * 1_000_000)
            case "gb": return UInt64(value * 1_000_000_000)
            default: return 0
            }
        }
    }
}
