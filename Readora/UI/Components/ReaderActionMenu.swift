import SwiftUI

struct ReaderActionMenu: View {
    @Binding var isPresented: Bool
    @Binding var settings: ReaderSettings
    var onOpenSettings: () -> Void

    private var fg: Color { settings.colorTheme.foregroundColor }
    private var bg: Color { settings.colorTheme.backgroundColor }

    var body: some View {
        ReaderActionButton(
            animation: .smooth(duration: 0.3, extraBounce: 0),
            isPresented: $isPresented
        ) {
            menuContent
        } background: {
            Capsule()
                .fill(bg)
                .shadow(color: .gray.opacity(0.5), radius: 1)
        }
        .padding(.trailing, 15)
        .padding(.bottom, 0)
    }

    @ViewBuilder
    private var menuContent: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                CustomButton(
                    title: "Search",
                    symbol: "magnifyingglass",
                    isPresented: $isPresented,
                    foregroundColor: fg,
                    backgroundColor: bg
                ) {
                    isPresented = false
                }
                .frame(width: 250, height: 45)

                CustomButton(
                    title: "Themes & Settings",
                    symbol: "textformat.size",
                    isPresented: $isPresented,
                    foregroundColor: fg,
                    backgroundColor: bg
                ) {
                    isPresented = false
                    onOpenSettings()
                }
                .frame(width: 250, height: 45)

                HStack(spacing: 10) {
                    CustomSectionButton(
                        symbol: "textformat.size.smaller",
                        isPresented: $isPresented,
                        foregroundColor: fg, backgroundColor: bg
                    ) {
                        settings.fontSize = max(0.5, settings.fontSize - 0.1)
                    }
                    CustomSectionButton(
                        symbol: "textformat.size.larger",
                        isPresented: $isPresented,
                        foregroundColor: fg, backgroundColor: bg
                    ) {
                        settings.fontSize = min(2.5, settings.fontSize + 0.1)
                    }
                    CustomSectionButton(
                        symbol: "circle.lefthalf.filled",
                        isPresented: $isPresented,
                        foregroundColor: fg, backgroundColor: bg
                    ) {
                        settings.colorTheme = settings.colorTheme.next()
                    }
                    CustomSectionButton(
                        symbol: "bookmark",
                        isPresented: $isPresented,
                        foregroundColor: fg, backgroundColor: bg
                    )
                }
                .font(.title3)
                .fontWeight(.medium)
                .frame(width: 250, height: 50)
            }
        }
    }
}
