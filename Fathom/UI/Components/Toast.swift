import SwiftUI

struct ToastRootView<Content: View>: View {
    @ViewBuilder var content: Content

    /// View Properties
    @State private var activeToast: Toast?
    @State private var toastDismissWorkItem: DispatchWorkItem?

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Group {
                if let activeToast {
                    toastView(activeToast)
                }
            }
            .opacity(activeToast == nil ? 0 : 1)
        }
        .environment(\.showToast) { toast in 
            withAnimation(animation.logicallyComplete(after: 0.17), completionCriteria: .logicallyComplete) {
                /// Removing old toast to show the updated one
                if activeToast != nil {
                    activeToast = nil
                }

            } completion: {
                toastDismissWorkItem?.cancel()

                withAnimation(animation) {
                    activeToast = toast
                }

                toastDismissWorkItem = .init(block: dismiss)
                /// Limiting the minimum duration to 1 second to ensure the toast is visible enough for the user to read and interact with it if needed.
                let duration = max(toast.duration, 1)
                if let toastDismissWorkItem {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + duration, 
                        execute: toastDismissWorkItem
                    )
                }
            }
        }
        .environment(\.dismissToast) {
            dismiss()
        }
    }

    @ViewBuilder
    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 10) {
            if let symbol = toast.symbol {
                Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.primary)
                .transition(.identity)
            }

            Text(toast.title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle = toast.actionTitle, let action = toast.action {
                Button {
                    /// If true, then dismiss the toast!
                    if action() {
                        dismiss()
                    }
                } label: {
                    Text(actionTitle)
                    .foregroundStyle(toast.actionTint)
                }
                .transition(.identity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .clipShape(.capsule)
        .contentShape(.capsule)
        .capsuleGlassEffect()
        .padding(.horizontal, 15)
        /// placement offset
        .offset(y: toast.placementOffset)
        .gesture(DragGesture().onEnded{ value in 
                let endTranslation = value.translation.height
                if endTranslation > 30 {
                    dismiss()
                }
        })
        /// offset transition
        .transition(.offset(y: toast.transitionOffset))
    }

    private func dismiss() {
        withAnimation(animation) {
            activeToast = nil
        }

        toastDismissWorkItem?.cancel()
    }

    private let animation: Animation = .interpolatingSpring(duration: 0.35, bounce: 0, initialVelocity: 0)
}

struct Toast: Identifiable {
    private(set) var id: String = UUID().uuidString
    /// Toast Properties
    var title: String
    var duration: CGFloat
    var placementOffset: CGFloat
    var transitionOffset: CGFloat = 100
    var symbol: String? = nil
    var actionTitle: String? = nil
    var actionTint: Color = .accentColor
    var action: (() -> Bool)? = nil
}

extension EnvironmentValues {
    @Entry var showToast: (Toast) -> Void = { _ in }
    @Entry var dismissToast: () -> Void = {  }
}

private extension View {
    @ViewBuilder
    func capsuleGlassEffect() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

#Preview {

}
