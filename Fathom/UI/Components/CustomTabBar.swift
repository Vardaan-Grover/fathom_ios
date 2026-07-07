import SwiftUI

struct CustomTabBar<TabItemView: View>: UIViewRepresentable {
    var size: CGSize
    var activeTint: Color = .blue
    var barTint: Color = .gray.opacity(0.15)

    @Binding var activeTab: CustomTab
    @ViewBuilder var tabItemView: (CustomTab) -> TabItemView

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let items = CustomTab.allCases.map(\.rawValue)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = activeTab.index

        for (index, tab) in CustomTab.allCases.enumerated() {
            let renderer = ImageRenderer(content: tabItemView(tab))
            renderer.scale = 2

            let image = renderer.uiImage
            control.setImage(image, forSegmentAt: index)
        }

        DispatchQueue.main.async {
            for subview in control.subviews {
                if subview is UIImageView && subview != control.subviews.last {
                    /// It's a hack to remove the default background of UISegmentedControl
                    subview.alpha = 0
                }
            }
        }

        control.selectedSegmentTintColor = UIColor(barTint)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(activeTint)
        ], for: .selected)

        control.addTarget(context.coordinator, action: #selector(Coordinator.tabSelected(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        if uiView.selectedSegmentIndex != activeTab.index {
            uiView.selectedSegmentIndex = activeTab.index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        return size
    }

    class Coordinator: NSObject {
        var parent: CustomTabBar
        init(parent: CustomTabBar) {
            self.parent = parent
        }

        @objc func tabSelected(_ control: UISegmentedControl) {
            parent.activeTab = CustomTab.allCases[control.selectedSegmentIndex]
        }
    }
}

#Preview {
    let container = AppContainer.shared
    let homeVM = HomeViewModel(bookRepository: container.bookRepo, categoryRepository: container.categoryRepo)
    let libraryVM = LibraryViewModel(
        bookRepo: container.bookRepo,
        readerService: container.readerService,
        contextEngine: container.contextEngine,
        aiClient: container.aiClient,
        preprocessingCoordinator: container.preprocessingCoordinator
    )
    RootView(homeViewModel: homeVM, libraryViewModel: libraryVM, bookRepository: container.bookRepo, vocabularyRepo: container.vocabularyRepo)
        .task { await homeVM.load() }
}