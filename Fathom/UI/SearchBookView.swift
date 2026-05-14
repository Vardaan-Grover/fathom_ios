import SwiftUI

struct SearchBookView: View {
    @ObservedObject var state: BookSearchState
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    private enum ContentState: Equatable {
        case idle, searching, noResults, results
    }

    private var contentState: ContentState {
        let q = state.query.trimmingCharacters(in: .whitespaces)
        if q.count < 3 { return .idle }
        if state.groups.isEmpty && state.isSearching { return .searching }
        if state.groups.isEmpty && !state.isSearching { return .noResults }
        return .results
    }

    var body: some View {
        VStack(spacing: 0) {
            searchArea
            Divider().opacity(0.4)
            ZStack {
                switch contentState {
                case .idle:      emptyPrompt
                case .searching: searchingState
                case .noResults: noResultsState
                case .results:   resultsList
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: contentState)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .onTapGesture { isSearchFocused = false }
        .onAppear { isSearchFocused = true }
        .onChange(of: state.query) { _, _ in state.scheduleSearch() }
        .onChange(of: state.wholeWord) { _, _ in state.scheduleSearch() }
        .onChange(of: state.diacriticsInsensitive) { _, _ in state.scheduleSearch() }
    }

    // MARK: - Search Area

    private var searchArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroSearchField
            filterChips
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Hero Search Field

    private var heroSearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(state.query.isEmpty ? Color(.tertiaryLabel) : Color.accentColor)
                .animation(.spring(response: 0.25), value: state.query.isEmpty)

            TextField("Search this book…", text: $state.query)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .font(.system(size: 17))
                .onSubmit { isSearchFocused = false }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if !state.query.isEmpty {
                    if state.isSearching {
                        ProgressView()
                            .scaleEffect(0.75)
                            .transition(.scale.combined(with: .opacity))
                    } else if state.totalCount > 0 {
                        Text("\(state.totalCount)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if !state.query.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            state.query = ""
                        }
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: state.query.isEmpty)
            .animation(.spring(response: 0.3), value: state.isSearching)
            .animation(.spring(response: 0.3), value: state.totalCount)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(.opaqueSeparator).opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SearchOptionChip(
                    label: "Whole Word",
                    symbol: "textformat",
                    isActive: state.wholeWord
                ) { state.wholeWord.toggle() }

                SearchOptionChip(
                    label: "Ignore Accents",
                    symbol: "a.magnify",
                    isActive: state.diacriticsInsensitive
                ) { state.diacriticsInsensitive.toggle() }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text("Search This Book")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 24)
                Text("Type at least 3 characters to find\nevery occurrence across all chapters.")
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

    // MARK: - Searching State

    private var searchingState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(Color.accentColor)
            }
            VStack(spacing: 6) {
                Text("Searching")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 20)
                Text("\"\(state.query)\"")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results State

    private var noResultsState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 96, height: 96)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 8) {
                Text("No Results")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 24)
                Text("Nothing matched \"\(state.query)\".")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                if state.wholeWord || state.diacriticsInsensitive {
                    Button {
                        state.wholeWord = false
                        state.diacriticsInsensitive = false
                    } label: {
                        Text("Clear Filters")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.28), value: state.wholeWord || state.diacriticsInsensitive)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(state.groups) { group in
                    chapterSection(group: group)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Chapter Section

    @ViewBuilder
    private func chapterSection(group: SearchChapterGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            chapterHeader(group: group)

            VStack(spacing: 10) {
                ForEach(group.results) { item in
                    SearchResultCard(item: item) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(item.locatorJSON)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 18)
            .frame(maxHeight: group.isExpanded ? .infinity : 0, alignment: .top)
            .clipped()
            .opacity(group.isExpanded ? 1 : 0)
            // Override the spring from toggleExpanded — a spring on large heights
            // bounces through too many pixels and reads as a slam. Scale duration
            // with result count so longer sections feel proportional, not rushed.
            .animation(
                .easeInOut(duration: min(0.22 + Double(group.results.count) * 0.006, 0.42)),
                value: group.isExpanded
            )
        }
    }

    // MARK: - Chapter Header

    private func chapterHeader(group: SearchChapterGroup) -> some View {
        Button {
            state.toggleExpanded(groupID: group.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                breadcrumbText(group.chapterTitle)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(group.results.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(group.isExpanded ? .zero : .degrees(-90))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: group.isExpanded)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Renders "Part 1 › I" with the leaf segment emphasised
    private func breadcrumbText(_ title: String) -> Text {
        let separator = " › "
        let parts = title.components(separatedBy: separator)
        guard parts.count > 1, let last = parts.last else {
            return Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.label))
        }
        let prefix = parts.dropLast().joined(separator: separator) + " › "
        return Text(prefix)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.secondary)
        + Text(last)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(.label))
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let item: SearchResultItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Accent strip for visual rhythm and dark-mode legibility
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                snippet
                    .font(.system(size: 15, design: .serif))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(.opaqueSeparator).opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SpringPressStyle())
    }

    private var snippet: Text {
        Text(item.textBefore.trailingSnippet())
            .foregroundStyle(Color.secondary)
        + Text(item.textMatch)
            .bold()
            .foregroundStyle(Color.accentColor)
        + Text(item.textAfter.leadingSnippet())
            .foregroundStyle(Color.secondary)
    }
}

// MARK: - Search Option Chip

private struct SearchOptionChip: View {
    let label: String
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "checkmark" : symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .animation(.spring(response: 0.22), value: isActive)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isActive ? Color.accentColor.opacity(0.5) : Color(.opaqueSeparator).opacity(0.7),
                                lineWidth: 1
                            )
                    )
            )
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .buttonStyle(SpringPressStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isActive)
    }
}

// MARK: - String Snippet Helpers

private extension String {
    func trailingSnippet(maxLength: Int = 45) -> String {
        guard count > maxLength else { return self }
        return "…" + suffix(maxLength)
    }

    func leadingSnippet(maxLength: Int = 45) -> String {
        guard count > maxLength else { return self }
        return prefix(maxLength) + "…"
    }
}
