import SwiftUI

struct HighlightsListView: View {
    let bookID: UUID
    var onSelect: (String) -> Void

    @State private var highlights: [Highlight] = []
    @State private var selectedColor: HighlightColor? = nil
    @Environment(\.dismiss) private var dismiss

    private var presentColors: [HighlightColor] {
        HighlightColor.allCases.filter { c in highlights.contains { $0.color == c } }
    }

    private var filtered: [Highlight] {
        guard let color = selectedColor else { return highlights }
        return highlights.filter { $0.color == color }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.4)
            if !highlights.isEmpty {
                colorFilterBar
                    .transition(.opacity)
            }
            if filtered.isEmpty {
                emptyState
            } else {
                highlightsList
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedColor)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .onAppear { loadHighlights() }
        .onReceive(
            NotificationCenter.default.publisher(for: HighlightStore.didChangeNotification)
        ) { notification in
            guard let changedID = notification.object as? UUID, changedID == bookID else { return }
            loadHighlights()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Highlights")
                    .font(.system(size: 22, weight: .bold))
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filtered.count)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var countLabel: String {
        let n = filtered.count
        return "\(n) \(n == 1 ? "highlight" : "highlights")"
    }

    // MARK: - Color Filter Bar

    private var colorFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HighlightColorChip(label: "All", color: nil, isSelected: selectedColor == nil) {
                    selectedColor = nil
                }
                ForEach(presentColors, id: \.self) { color in
                    HighlightColorChip(
                        label: color.rawValue.capitalized,
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Highlights List

    private var highlightsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { highlight in
                    HighlightCard(highlight: highlight) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(highlight.locatorJSON)
                        dismiss()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HighlightStore.shared.delete(id: highlight.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        selectedColor != nil
                            ? selectedColor!.displayColor.opacity(0.12)
                            : Color.accentColor.opacity(0.1)
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "highlighter")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(
                        selectedColor != nil
                            ? selectedColor!.displayColor
                            : Color.accentColor
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text(selectedColor == nil ? "No Highlights Yet" : "No \(selectedColor!.rawValue.capitalized) Highlights")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 24)
                Text(
                    selectedColor == nil
                        ? "Select text while reading to\nhighlight your first passage."
                        : "Try a different color filter."
                )
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - Data

    private func loadHighlights() {
        highlights = HighlightStore.shared.highlights(forBookID: bookID)
        if let color = selectedColor, !highlights.contains(where: { $0.color == color }) {
            selectedColor = nil
        }
    }
}

// MARK: - Color Filter Chip

private struct HighlightColorChip: View {
    let label: String
    let color: HighlightColor?
    let isSelected: Bool
    let action: () -> Void

    private var chipAccent: Color { color?.displayColor ?? Color.accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 10, height: 10)
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? chipAccent.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? chipAccent.opacity(0.5) : Color(.opaqueSeparator).opacity(0.7),
                                lineWidth: 1
                            )
                    )
            )
        }
        .foregroundStyle(isSelected ? chipAccent : Color.secondary)
        .buttonStyle(SpringPressStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - Highlight Card

private struct HighlightCard: View {
    let highlight: Highlight
    let onTap: () -> Void

    private var meta: LocatorMeta? {
        guard let data = highlight.locatorJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocatorMeta.self, from: data)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(highlight.color.displayColor)
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        if let chapter = meta?.title, !chapter.isEmpty {
                            Text(chapter)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let position = meta?.locations?.position {
                            let hasPrecedingChapter = meta?.title?.isEmpty == false
                            Text((hasPrecedingChapter ? " · " : "") + "p. \(position)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(highlight.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 13)
                    .padding(.bottom, 9)
                    .padding(.trailing, 14)

                    Text(highlight.text)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                }
                .padding(.leading, 12)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(highlight.color.displayColor.opacity(0.06))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(highlight.color.displayColor.opacity(0.25), lineWidth: 1)
                )
            )
        }
        .buttonStyle(SpringPressStyle())
    }
}

// MARK: - Locator JSON Decoding

private struct LocatorMeta: Decodable {
    let title: String?
    let locations: Locations?

    struct Locations: Decodable {
        let position: Int?
        let totalProgression: Double?
    }
}
