import SwiftUI

struct BookDetailHeroView: View {
    @Binding var config: ScrollHeroEffectConfig
    var book: HomeBook
    var progress: CGFloat
    var namespace: Namespace.ID
    var onReadTap: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        scrollContent
    }

    // MARK: - Overlay Buttons
    private var overlayButtons: some View {
        HStack {
            Button {
                withAnimation(.interpolatingSpring(duration: 0.3)) {
                    config.expandDetailView = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundColor(theme.colors.primary)
            }
            Spacer()
            let shareText = "\(book.title) by \(book.author)"
            ShareLink(
                item: shareText
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundColor(theme.colors.primary)
            }
        }
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.top, 12)
    }

    // MARK: - Scroll Content
    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            coverHero
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            overlayButtons
                .opacity(opacity)
                .padding(.top, 8)
        }

        // ScrollView(.vertical, showsIndicators: false) {
        //     VStack(spacing: 0) {

        //         // 🟢 TOP SECTION (Theme Background)
        //         VStack(spacing: 0) {
        //             coverHero
        //             upperSection
        //             statsRow
        //         }
        //         .frame(maxWidth: .infinity)
        //         .background(theme.colors.background)

        //         // ⚪️ BOTTOM SECTION (System Background)
        //         VStack {
        //             overviewSection
        //             if !viewModel.otherBooksByAuthor.isEmpty {
        //                 authorBooksSection
        //             }
        //         }
        //         .frame(maxWidth: .infinity)
        //         .padding(.bottom, 48)
        //         .background {
        //             Color(.systemBackground)
        //                 .padding(.bottom, -1000)
        //         }
        //     }
        // }
    }

    // MARK: - Cover Hero
    private var coverHero: some View {
        VStack {
            BookCoverView(book: book, width: 190, height: 280)
                .clipShape(.rect(cornerRadius: 4))
                .matchedGeometryEffect(id: book.id.uuidString, in: namespace)

            VStack(spacing: 12) {
                Text(book.author)
                    .font(.title2.bold())

                Text("lorem ipsum details here...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }
            .compositingGroup()
            .opacity(opacity)
        }
        .padding(.top, 48)
    }

    // MARK: - Upper Section
    private var upperSection: some View {
        VStack {
            Text(book.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(theme.colors.primary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            Text(book.author)
                .font(theme.typography.body)
                .fontWeight(.medium)
                .tracking(0.05)
                .foregroundColor(theme.colors.secondary)
                .padding(.bottom, 10)

            // aiStatusChip

            // ctaButton
        }
        .padding(.top, 8)
        .padding(.horizontal, theme.layout.horizontalPadding)
        .padding(.bottom, 20)
    }

    /// Custom Buttom bar
    // @ViewBuilder
    // func BottomBar() -> some View {
    //     HStack(spacing: 10) {
    //         Button {
    //         } label: {
    //             Text("Favorite")
    //             .padding(.vertical, 5)
    //             .frame(maxWidth: .infinity)
    //         }
    //         .tint(.red)

    //         Button {
    //             onReadTap()
    //         } label: {
    //             Text("Read")
    //                 .padding(.vertical, 5)
    //                 .frame(maxWidth: .infinity)
    //         }
    //         .tint(.blue)
    //     }
    //     .font(.callout)
    //     .buttonStyle(.borderedProminent)
    //     .buttonBorderShape(.capsule)
    //     .padding(.horizontal, 15)
    //     .padding(.vertical, 10)
    //     .overlay(alignment: .top) {
    //         Divider()
    //     }
    // }

    /// Let's Convert the progress to opacity to only show after specific limit
    var opacity: CGFloat {
        return progress > 0.7 ? min((progress - 0.7) * 3.4, 1) : 0
    }
}
