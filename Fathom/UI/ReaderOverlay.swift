import SwiftUI

struct ReaderOverlay: View {
    let bookTitle: String
    let currentPage: Int
    let totalPages: Int
    let isActive: Bool
    let foregroundColor: Color
    let isScrolling: Bool
    let onDismiss: () -> Void

    private var textColor: Color { foregroundColor }

    private var pageLabel: String {
        guard currentPage > 0 else { return "" }
        return isActive && totalPages > 0
            ? "\(currentPage) of \(totalPages)"
            : "Page \(currentPage)"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var topBar: some View {
        ZStack {
            Text(bookTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(textColor.opacity(isActive ? 0.9 : 0.4))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, isScrolling ? 14 : 0)
                .padding(.vertical, isScrolling ? 6 : 0)
                .background(
                    Group {
                        if isScrolling {
                            Capsule()
                                .glassEffect(.regular)
                        }
                    }
                )
                .padding(.horizontal, 65)
                .frame(maxWidth: .infinity)
                .opacity(isScrolling && !isActive ? 0 : 1)

            if isActive {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(textColor)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .background(
                        Group {
                            if isScrolling {
                                Circle()
                                    .glassEffect(.regular)
                            }
                        }
                    )
                    Spacer()
                }
                .opacity(isScrolling && !isActive ? 0 : 1)
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        ZStack {
            if !pageLabel.isEmpty {
                Text(pageLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor.opacity(isActive ? 0.9 : 0.4))
                    .padding(.horizontal, isScrolling ? 14 : 0)
                    .padding(.vertical, isScrolling ? 6 : 10)
                    .background(
                        Group {
                            if isScrolling {
                                Capsule()
                                    .glassEffect(.regular)
                            }
                        }
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, isScrolling ? 20 : 0)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isScrolling && !isActive ? 0 : 1)
    }
}
