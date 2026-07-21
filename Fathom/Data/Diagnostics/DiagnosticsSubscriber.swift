import Foundation
import MetricKit

/// Receives MetricKit payloads and hands them to a `MetricsSink`.
///
/// MetricKit delivers at most once per 24 hours, shortly after a launch or
/// foreground — it is a daily digest, not a live feed. Nothing here polls or
/// wakes the app; registration is the entire cost.
///
/// The payload worth caring about is `MXAppExitMetric`: its
/// `cumulativeMemoryResourceLimitExitCount` is the jetsam counter, which is
/// the only field-visible signal for the reader's memory-pressure kills.
/// See `MetricsDigest` for the readable summary.
///
/// Note: the simulator never delivers real payloads. Use Xcode's
/// Debug ▸ Simulate MetricKit Payloads to exercise this path.
final class DiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber {

    /// Retained for the process lifetime. `MXMetricManager` holds subscribers
    /// weakly, so a subscriber that goes out of scope stops receiving payloads
    /// with no error and no crash — the failure mode is silence weeks later.
    private static var shared: DiagnosticsSubscriber?

    private let sink: MetricsSink

    private init(sink: MetricsSink) {
        self.sink = sink
        super.init()
    }

    // MARK: - Registration

    /// Registers for MetricKit delivery. Safe to call more than once.
    static func start(sink: MetricsSink = DiskMetricsSink.shared) {
        guard shared == nil else { return }
        let subscriber = DiagnosticsSubscriber(sink: sink)
        shared = subscriber
        MXMetricManager.shared.add(subscriber)

        // MetricKit retains up to 7 days of payloads that were generated
        // before this build ever registered. Draining them here means the
        // first run after shipping this has history instead of an empty
        // directory for 24 hours.
        subscriber.ingestPastPayloads()
    }

    private func ingestPastPayloads() {
        let manager = MXMetricManager.shared
        let metrics = manager.pastPayloads
        let diagnostics = manager.pastDiagnosticPayloads
        Task { [sink] in
            for payload in metrics {
                await sink.receive(Self.record(kind: .metric, json: payload.jsonRepresentation()))
            }
            for payload in diagnostics {
                await sink.receive(Self.record(kind: .diagnostic, json: payload.jsonRepresentation()))
            }
        }
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        let records = payloads.map {
            Self.record(kind: .metric, json: $0.jsonRepresentation())
        }
        Task { [sink] in
            for record in records { await sink.receive(record) }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let records = payloads.map {
            Self.record(kind: .diagnostic, json: $0.jsonRepresentation())
        }
        Task { [sink] in
            for record in records { await sink.receive(record) }
        }
    }

    // MARK: - Private

    private static func record(kind: MetricsRecord.Kind, json: Data) -> MetricsRecord {
        let info = Bundle.main.infoDictionary
        return MetricsRecord(
            kind: kind,
            receivedAt: Date(),
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
            payload: json
        )
    }
}
