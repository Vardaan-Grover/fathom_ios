import SwiftUI

// MARK: - ProfileRow

struct ProfileRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

            Text(title)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .kerning(0.4)
            .textCase(.uppercase)
    }
}
