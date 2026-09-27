import SwiftUI

// MARK: - ICloudSyncStatusRow
//
// What sync is actually doing, in one row. It used to say "Active" with a
// green tick whenever the iCloud Drive container resolved — including while
// every CloudKit save was failing because iCloud storage was full.

struct ICloudSyncStatusRow: View {
    @ObservedObject private var activity = SyncActivity.shared
    @State private var filesAvailable: Bool = ICloudFileStore.shared.isAvailable

    private enum Status {
        case upToDate(Date?)
        case syncing
        case attention(String)
        case off(String)
    }

    private var status: Status {
        switch activity.problem {
        case .noAccount:
            return .off("Sign in to iCloud in Settings to sync")
        case .accountUnavailable:
            return .off("iCloud is unavailable for this account")
        case .quotaExceeded:
            return .attention("iCloud storage is full — changes are waiting on this device")
        case .failing(let reason):
            return .attention(reason)
        case nil:
            break
        }
        if activity.phase == .gathering { return .syncing }
        return .upToDate(activity.lastSyncedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Sync")
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .onAppear { filesAvailable = ICloudFileStore.shared.isAvailable }
    }

    private var symbol: String {
        switch status {
        case .upToDate: return "checkmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
        case .attention: return "exclamationmark.icloud.fill"
        case .off: return "icloud.slash"
        }
    }

    private var tint: Color {
        switch status {
        case .upToDate, .syncing: return Color(.systemBlue)
        case .attention, .off: return Color(.systemOrange)
        }
    }

    private var detail: String {
        switch status {
        case .upToDate(let date):
            var text = date.map { "Up to date · \(Self.relative.localizedString(for: $0, relativeTo: Date()))" }
                ?? "Waiting for the first sync"
            if !filesAvailable {
                // Records sync over CloudKit regardless; book files need
                // iCloud Drive to reach other devices.
                text += "\nTurn on iCloud Drive for Fathom to sync book files"
            }
            return text
        case .syncing:
            return "Syncing…"
        case .attention(let message), .off(let message):
            return message
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
