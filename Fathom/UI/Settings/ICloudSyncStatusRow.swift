import SwiftUI

// MARK: - ICloudSyncStatusRow
//
// Live status of the CloudKit sync engine. Re-checks availability on
// appear. No-op visually if iCloud isn't available (Personal Team etc).

struct ICloudSyncStatusRow: View {
    @State private var isAvailable: Bool = ICloudFileStore.shared.isAvailable

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isAvailable ? "icloud.fill" : "icloud.slash")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isAvailable ? Color(.systemBlue) : Color(.systemOrange))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    (isAvailable ? Color(.systemBlue) : Color(.systemOrange)).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Sync")
                Text(isAvailable ? "Active" : "Unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            }
        }
        .onAppear { isAvailable = ICloudFileStore.shared.isAvailable }
    }
}
