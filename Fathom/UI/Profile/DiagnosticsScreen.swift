import SwiftUI

// MARK: - DiagnosticsScreen

/// Reads back what `DiskMetricsSink` has captured and hands it to the share
/// sheet.
///
/// Reached by tapping the Version row in About seven times — deliberately not
/// a visible row. It has to exist in release builds so a TestFlight tester can
/// be walked to it over email, but a "Diagnostics" entry sitting in Profile
/// would be noise for everyone else.
///
/// Note the numbers here can legitimately read zero for the first 24 hours of
/// a fresh install: MetricKit delivers at most once a day, on launch or
/// foreground.
struct DiagnosticsScreen: View {
    @State private var digest: MetricsDigest?
    @State private var recordCount = 0
    @State private var exportURL: URL?
    @State private var preparing = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                heroRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if let digest {
                Section {
                    DiagnosticStatRow(
                        symbol: "memorychip.fill", color: Color(.systemRed),
                        label: "Foreground memory kills",
                        value: "\(digest.foregroundMemoryKills)"
                    )
                    DiagnosticStatRow(
                        symbol: "moon.fill", color: Color(.systemOrange),
                        label: "Background memory kills",
                        value: "\(digest.backgroundMemoryKills)"
                    )
                    DiagnosticStatRow(
                        symbol: "exclamationmark.triangle.fill", color: .yellow,
                        label: "Watchdog kills",
                        value: "\(digest.watchdogKills)"
                    )
                    DiagnosticStatRow(
                        symbol: "gauge.high", color: Color(.systemTeal),
                        label: "Peak memory",
                        value: formattedPeak(digest.peakMemoryBytes)
                    )
                } header: {
                    SectionHeader("Observed")
                } footer: {
                    Text("Aggregated across \(digest.payloadCount) daily "
                         + "\(digest.payloadCount == 1 ? "payload" : "payloads"). "
                         + "Foreground memory kills are the jetsam counter — the "
                         + "signal Xcode Organizer's crash reports cannot show.")
                }
            }

            Section {
                Button {
                    Task { await prepareAndShare() }
                } label: {
                    HStack {
                        Spacer()
                        if preparing {
                            ProgressView().tint(.white)
                        } else {
                            Label("Export & Share", systemImage: "square.and.arrow.up.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .disabled(preparing || recordCount == 0)
                .listRowBackground(recordCount == 0 ? Color(.systemGray4) : Color.accentColor)
                .foregroundStyle(Color.white)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if recordCount == 0 {
                    Text("Nothing captured yet. MetricKit delivers at most once "
                         + "every 24 hours, shortly after a launch.")
                } else {
                    Text("\(recordCount) stored \(recordCount == 1 ? "payload" : "payloads"). "
                         + "Creates a JSON file you can send to the developer. "
                         + "Nothing is uploaded automatically.")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .sheet(item: Binding(
            get: { exportURL.map(DiagnosticsFileURL.init) },
            set: { exportURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .task { await load() }
    }

    // MARK: - Hero

    private var heroRow: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemPurple).opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "waveform.path.ecg")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(.systemPurple))
                    .font(.system(size: 34))
            }
            Text("Device diagnostics")
                .font(.system(size: 17, weight: .semibold))
            Text("Memory and stability reports collected by iOS. Stored on this "
                 + "device only, and never sent anywhere unless you share them.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Data

    private func load() async {
        let records = await DiskMetricsSink.shared.storedRecords()
        recordCount = records.count
        digest = MetricsDigest.summarize(records)
    }

    private func prepareAndShare() async {
        preparing = true
        defer { preparing = false }
        error = nil
        guard let url = await DiskMetricsSink.shared.exportArchive() else {
            error = "Nothing to export yet."
            return
        }
        exportURL = url
    }

    private func formattedPeak(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

// MARK: - Supporting views

/// Local copy: `ExportDataScreen`'s `StatRow` is file-private, and this one
/// carries a wrapping multi-line label rather than a short noun.
private struct DiagnosticStatRow: View {
    let symbol: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct DiagnosticsFileURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
