import SwiftUI

struct ReaderActionButton<Actions: View, Background: View>: View {
    var innerScaling: CGFloat = 1
    var minimisedButtonSize: CGSize = .init(width: 50, height: 50)
    var animation: Animation? = .spring(response: 0.5, dampingFraction: 0.7)

    @Binding var isPresented: Bool

    @ViewBuilder var actions: Actions
    @ViewBuilder var background: Background

    var body: some View {
        actions
        /// Disabling interaction when minimised
        .allowsHitTesting(isPresented)
        .contentShape(.rect)
        .compositingGroup()
        /// Scaling the actions to fit into the button using the visual effect modifier
        .visualEffect({ [innerScaling, minimisedButtonSize, isPresented] content, proxy in 
            let maxValue = max(proxy.size.width, proxy.size.height)
            let minButtonValue = min(minimisedButtonSize.width, minimisedButtonSize.height)
            let fitScale = minButtonValue / maxValue
            let modifiedInnerScale = 0.55 * innerScaling

            return content
            .scaleEffect(isPresented ? 1 : modifiedInnerScale)
            .scaleEffect(isPresented ? 1 : fitScale)
        })
        /// Acts like a button tap to expand actions
        .overlay {
            if !isPresented {
                Capsule()
                .foregroundStyle(.clear)
                .frame(width: minimisedButtonSize.width, height: minimisedButtonSize.height)
                .contentShape(.capsule)
                .onTapGesture {
                    isPresented = true
                }
                .transition(.identity)
            }
        }
        .background {
            background
            .frame(
                width: isPresented ? nil : minimisedButtonSize.width, 
                height: isPresented ? nil : minimisedButtonSize.height
            )
            .compositingGroup()
            /// Fading out with blur
            .opacity(isPresented ? 0 : 1)
            .blur(radius: isPresented ? 30 : 0)
        }
        .fixedSize()
        .frame(
            width: isPresented ? nil : minimisedButtonSize.width, 
            height: isPresented ? nil : minimisedButtonSize.height
        )
        .animation(animation, value: isPresented)

    }
}

/// Custom Buttons
struct CustomButton: View {
    var title: String
    var symbol: String
    @Binding var isPresented: Bool
    var foregroundColor: Color = .primary
    var backgroundColor: Color = Color(.systemBackground)
    var action: () -> () = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Spacer()
                Image(systemName: symbol)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColor)
            .opacity(isPresented ? 1 : 0)
            .background {
                ZStack {
                    Rectangle()
                        .fill(foregroundColor)
                        .opacity(isPresented ? 0 : 1)

                    Rectangle()
                        .fill(backgroundColor)
                        .opacity(isPresented ? 1 : 0)
                }
                .clipShape(.capsule)
            }
        }
    }
}

struct CustomSectionButton: View {
    var symbol: String
    @Binding var isPresented: Bool
    var foregroundColor: Color = .primary
    var backgroundColor: Color = Color(.systemBackground)
    var action: () -> () = {}
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColor)
            .opacity(isPresented ? 1 : 0)
            .background {
                ZStack {
                    Rectangle()
                        .fill(foregroundColor)
                        .opacity(isPresented ? 0 : 1)

                    Rectangle()
                        .fill(backgroundColor)
                        .opacity(isPresented ? 1 : 0)
                }
                .clipShape(.capsule)
            }
        }
    }
}