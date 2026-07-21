import SwiftUI

// MARK: - EmojiAvatarPickerSheet
//
// Sheet that lets the user pick an emoji and a background color for their
// profile avatar. The emoji comes from `EmojiGridPicker` — a first-party grid
// rather than the system emoji keyboard, which needed a Required Reason API
// Fathom cannot justify (see EmojiGridPicker for the details).

struct EmojiAvatarPickerSheet: View {
    let initialEmoji: String?
    let initialColorHex: String
    let initials: String
    var onSave: (_ emoji: String?, _ colorHex: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var workingEmoji: String = ""
    @State private var workingColorHex: String = ""
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            // Deliberately a VStack, not a ScrollView: the emoji grid scrolls
            // internally, and nesting two vertical scrollers makes the gesture
            // ambiguous. Header and footer stay put; only the grid moves.
            VStack(spacing: 16) {
                avatarPreview
                    .padding(.top, 12)

                Text(workingEmoji.isEmpty
                     ? "Pick an emoji, or just choose a color."
                     : "Tap another emoji to change it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                EmojiGridPicker(selection: $workingEmoji)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)

                VStack(spacing: 12) {
                    colorGrid

                    if !workingEmoji.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            workingEmoji = ""
                        } label: {
                            Label("Remove Emoji", systemImage: "xmark.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Edit Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(
                            workingEmoji.isEmpty ? nil : workingEmoji,
                            workingColorHex
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // Large only — the grid needs the height, and .medium left it a sliver.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            workingEmoji = initialEmoji ?? ""
            workingColorHex = initialColorHex
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: workingEmoji)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: workingColorHex)
    }

    // MARK: - Avatar preview

    private var avatarPreview: some View {
        AvatarView(
            emoji: workingEmoji.isEmpty ? nil : workingEmoji,
            initials: initials,
            colorHex: workingColorHex,
            diameter: 108
        )
    }

    // MARK: - Color grid

    private var colorGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarColors.palette, id: \.self) { hex in
                ColorSwatch(
                    hex: hex,
                    isSelected: workingColorHex.caseInsensitiveCompare(hex) == .orderedSame
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    workingColorHex = hex
                }
            }
        }
    }
}

// MARK: - ColorSwatch

private struct ColorSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: hex).opacity(0.85), Color(hex: hex)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 44)

                Circle()
                    .strokeBorder(
                        isSelected ? Color.primary : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2.5 : 1
                    )
                    .frame(height: 44)
                    .padding(2)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
            .scaleEffect(isSelected ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
