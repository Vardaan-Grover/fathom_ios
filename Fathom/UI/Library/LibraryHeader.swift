import SwiftUI

/// The shared header for the two library surfaces (HomeScreen and
/// ClassicLibraryView): observatory · serif title · optional menu · search.
///
/// Tapping search grows the capsule leftward into a full-width field, and the
/// title and observatory give up their space to it.
struct LibraryHeader<Menu: View>: View {

    let title: String
    @ObservedObject var search: LibrarySearchViewModel
    let bookRepository: BookRepository
    let observatoryRefresh: Int
    let onOpenGarden: () -> Void
    /// Extra trailing control (the classic view's sort menu). Hidden while searching.
    @ViewBuilder let menu: Menu

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool

    private let buttonSize: CGFloat = 46

    private var expandAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) { headerContent }
            } else {
                headerContent
            }
        }
        .onChange(of: search.isActive) { _, active in
            isFieldFocused = active
        }
        // Deliberately no onChange(of: isFieldFocused) closing the surface.
        // Scrolling the results dismisses the keyboard, which drops focus —
        // treating that as intent to close would tear the search down the
        // moment the user scrolled. Cancel is the only way out.
    }

    // MARK: - Layout
    //
    // One HStack for both states, and — critically — a single capsule view that
    // is never destroyed. It simply changes width, so the glass resizes as one
    // continuous piece of material. Swapping between two separate capsule views
    // and matching them with matchedGeometryEffect/glassEffectID looks janky by
    // comparison: the geometry has to be reconstructed across an insert/remove.
    private var headerContent: some View {
        HStack(spacing: 12) {
            if !search.isActive {
                ObservatoryView(bookRepository: bookRepository, refreshTrigger: observatoryRefresh) {
                    onOpenGarden()
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))

                Spacer(minLength: 4)

                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(theme.colors.primary)
                    .lineLimit(1)
                    // "Fathom" is 127.6pt at 34pt New York Bold; with two 46pt
                    // capsules and 20pt margins that leaves ~115pt of slack on a
                    // 375pt screen, so it fits uncompressed. minimumScaleFactor
                    // is insurance for the classic view's third capsule and for
                    // longer titles, not an expected state.
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                    .transition(.opacity)

                Spacer(minLength: 4)

                menu
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            searchCapsule

            if search.isActive {
                Button("Cancel") {
                    isFieldFocused = false
                    withAnimation(expandAnimation) { search.close() }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.colors.primary)
                .fixedSize()
                .transition(.opacity)
            }
        }
    }

    // MARK: - The capsule

    private var searchCapsule: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: search.isActive ? 17 : 19, weight: .semibold))
                .foregroundStyle(
                    search.isActive ? theme.colors.secondary : theme.colors.primary)

            if search.isActive {
                TextField("Search your library", text: $search.query)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.colors.primary)
                    .focused($isFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .transition(.opacity)

                if search.hasQuery {
                    Button {
                        search.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(theme.colors.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, search.isActive ? 15 : 0)
        .frame(height: buttonSize)
        .frame(maxWidth: search.isActive ? .infinity : buttonSize)
        .glassCapsule(interactive: true)
        .contentShape(.capsule)
        // Fires only when the tap isn't claimed by the field or clear button,
        // so this stays inert once expanded.
        .onTapGesture {
            guard !search.isActive else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(expandAnimation) { search.open() }
        }
        .accessibilityElement(children: search.isActive ? .contain : .ignore)
        .accessibilityLabel(search.isActive ? "" : "Search library")
        .accessibilityAddTraits(search.isActive ? [] : .isButton)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: search.hasQuery)
    }
}

// MARK: - Convenience

extension LibraryHeader where Menu == EmptyView {
    init(
        title: String,
        search: LibrarySearchViewModel,
        bookRepository: BookRepository,
        observatoryRefresh: Int,
        onOpenGarden: @escaping () -> Void
    ) {
        self.init(
            title: title,
            search: search,
            bookRepository: bookRepository,
            observatoryRefresh: observatoryRefresh,
            onOpenGarden: onOpenGarden,
            menu: { EmptyView() }
        )
    }
}
