import SwiftUI

#if os(iOS)
    import UIKit
    import ReadiumShared
    import ReadiumNavigator
    import ReadiumAdapterGCDWebServer

    final class NavigatorCommands {
        var goLeft: (() async -> Void)?
        var goRight: (() async -> Void)?
        var onTap: ((CGPoint, CGSize) -> Void)?
        var onExplain: ((String, String) -> Void)?
        var onAddNote: ((String, String) -> Void)?
    }

    final class ReaderContainerViewController: UIViewController, UIEditMenuInteractionDelegate {
        var onExplain: ((String, String) -> Void)?
        var onAddNote: ((String, String) -> Void)?
        var bookID: UUID = UUID()
        private(set) var navigator: EPUBNavigatorViewController?
        private var editMenuInteraction: UIEditMenuInteraction?

        func embed(_ nav: EPUBNavigatorViewController) {
            navigator = nav
            addChild(nav)
            view.addSubview(nav.view)
            nav.view.frame = view.bounds
            nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            nav.didMove(toParent: self)

            let interaction = UIEditMenuInteraction(delegate: self)
            nav.view.addInteraction(interaction)
            editMenuInteraction = interaction
        }

        // Called by Coordinator when text is selected
        func showMenuForSelection(text: String, locatorJSON: String, at frame: CGRect) {
            // Convert the selection frame from navigator view coords to our view coords
            guard let navView = navigator?.view else { return }
            let converted = navView.convert(frame, to: view)
            let config = UIEditMenuConfiguration(
                identifier: nil, sourcePoint: CGPoint(x: converted.midX, y: converted.minY - 70))
            editMenuInteraction?.presentEditMenu(with: config)

            // Store for use in action callbacks
            pendingText = text
            pendingLocatorJSON = locatorJSON
        }

        private var pendingText: String = ""
        private var pendingLocatorJSON: String = ""

        // UIEditMenuInteractionDelegate — builds the menu items
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {

            // — Reader actions group —
            let highlightAction = UIAction(
                title: "Highlight", image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                guard let self else { return }
                navigator?.clearSelection()
                showColorPicker(text: pendingText, locatorJSON: pendingLocatorJSON)
            }

            let addNoteAction = UIAction(
                title: "Add Note", image: UIImage(systemName: "note.text.badge.plus")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                let locatorJSON = pendingLocatorJSON
                navigator?.clearSelection()
                onAddNote?(text, locatorJSON)
            }

            let explainAction = UIAction(
                title: "Ask AI", image: UIImage(systemName: "sparkles")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                let locatorJSON = pendingLocatorJSON
                navigator?.clearSelection()
                onExplain?(text, locatorJSON)
            }

            let readerGroup = UIMenu(
                options: .displayInline,
                children: [highlightAction, addNoteAction, explainAction])

            // — Utility actions group —
            let copyAction = UIAction(
                title: "Copy", image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = pendingText
                navigator?.clearSelection()
            }

            let shareAction = UIAction(
                title: "Share", image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                navigator?.clearSelection()
                let activityVC = UIActivityViewController(
                    activityItems: [text], applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = self.view
                    popover.sourceRect = CGRect(
                        x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                }
                present(activityVC, animated: true)
            }

            let utilityGroup = UIMenu(
                options: .displayInline,
                children: [copyAction, shareAction])

            // — System actions (Translate, Look Up, etc.) — iOS provides these via suggestedActions.
            // Filter out Copy since we supply our own.
            let systemActions = suggestedActions.filter { element in
                guard let action = element as? UIAction else { return true }
                return action.title != "Copy"
            }

            return UIMenu(children: [readerGroup, utilityGroup] + systemActions)
        }

        private func showColorPicker(text: String, locatorJSON: String) {
            // Check for duplicate
            let existing = HighlightStore.shared.highlights(forBookID: bookID)
            if existing.contains(where: { $0.locatorJSON == locatorJSON }) { return }

            let view = HighlightColorPickerView { [weak self] color in
                guard let self else { return }
                let highlight = Highlight(
                    id: UUID(),
                    bookID: bookID,
                    locatorJSON: locatorJSON,
                    text: text,
                    createdAt: Date(),
                    color: color,
                )
                HighlightStore.shared.add(highlight)
                applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
            }
            let host = UIHostingController(rootView: view)
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.custom { _ in 200 }]
                sheet.prefersGrabberVisible = true
            }
            present(host, animated: true)
        }

        func applyHighlights(_ highlights: [Highlight]) {
            guard let navigator = navigator else { return }
            let decorations: [Decoration] = highlights.compactMap { highlight in
                guard let locator = try? Locator(jsonString: highlight.locatorJSON) else {
                    return nil
                }
                return Decoration(
                    id: highlight.id.uuidString,
                    locator: locator,
                    style: .highlight(tint: highlight.color.uiColor)
                )
            }
            navigator.apply(decorations: decorations, in: "highlights")
        }

        func setupHighlightInteractions() {
            guard let navigator = navigator else { return }
            navigator.observeDecorationInteractions(inGroup: "highlights") { [weak self] event in
                guard let self, let highlightID = UUID(uuidString: event.decoration.id) else {
                    return
                }
                showHighlightMenu(for: highlightID)
            }
        }

        private func showHighlightMenu(for highlightID: UUID) {
            let view = HighlightMenuView(
                onChangeColor: { [weak self] color in
                    guard let self else { return }
                    HighlightStore.shared.updateColor(id: highlightID, color: color)
                    applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
                },
                onRemove: { [weak self] in
                    guard let self else { return }
                    HighlightStore.shared.delete(id: highlightID)
                    applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
                }
            )
            let host = UIHostingController(rootView: view)
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.custom { _ in 260 }]
                sheet.prefersGrabberVisible = false
            }
            present(host, animated: true)
        }
    }

    struct ReadiumNavigatorView: UIViewControllerRepresentable {
        let publication: Publication
        var initialLocation: Locator?
        var onLocationChange: (Locator) -> Void = { _ in }
        var onPositionsLoaded: (Int) -> Void = { _ in }
        var commands: NavigatorCommands? = nil
        var settings: ReaderSettings = ReaderSettings()
        var bookID: UUID = UUID()

        class Coordinator: NSObject, EPUBNavigatorDelegate, UIGestureRecognizerDelegate {
            var onLocationChange: (Locator) -> Void
            var commands: NavigatorCommands?

            weak var container: ReaderContainerViewController?

            init(onLocationChange: @escaping (Locator) -> Void, commands: NavigatorCommands?) {
                self.onLocationChange = onLocationChange
                self.commands = commands
            }

            func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
                onLocationChange(locator)
            }

            func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
                let safe = navigator.view.window?.safeAreaInsets
                    ?? UIEdgeInsets(top: 50, left: 0, bottom: 34, right: 0)
                // top: safe area + active overlay bar (56pt) + gap
                // bottom: safe area + page-label bar (33pt) + gap
                return UIEdgeInsets(top: safe.top + 56, left: 0, bottom: safe.bottom + 45, right: 0)
            }

            func navigator(
                _ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection
            ) -> Bool {
                guard
                    let locatorJSON = selection.locator.jsonString,
                    let text = selection.locator.text.highlight,
                    !text.isEmpty,
                    let frame = selection.frame
                else { return false }

                container?.showMenuForSelection(text: text, locatorJSON: locatorJSON, at: frame)

                return false
            }

            func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
                print("Navigation error: \(error)")
            }

            @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
                if container?.navigator?.currentSelection != nil { return }
                guard let view = recognizer.view else { return }
                let point = recognizer.location(in: view)
                let size = view.bounds.size
                commands?.onTap?(point, size)
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool {
                return true
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldReceive touch: UITouch
            ) -> Bool {
                guard let view = gestureRecognizer.view else { return true }
                let point = touch.location(in: view)
                let safeTop = view.window?.safeAreaInsets.top ?? 44
                let safeBottom = view.window?.safeAreaInsets.bottom ?? 34
                // Block the gesture in the overlay bar zones so SwiftUI buttons there handle taps
                if point.y < safeTop + 72 { return false }
                if point.y > view.bounds.height - safeBottom - 52 { return false }
                return true
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onLocationChange: onLocationChange, commands: commands)
        }

        func makeUIViewController(context: Context) -> UIViewController {
            guard
                let navigator = try? EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    // config: config,
                    httpServer: GCDHTTPServer(assetRetriever: ReadiumStack.shared.assetRetriever),
                )
            else {
                return UIViewController()  // fallback
            }
            navigator.delegate = context.coordinator

            commands?.goLeft = { [weak navigator] in
                await navigator?.goLeft(options: NavigatorGoOptions.animated)
            }
            commands?.goRight = { [weak navigator] in
                await navigator?.goRight(options: NavigatorGoOptions.animated)
            }

            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = context.coordinator
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            navigator.view.addGestureRecognizer(tap)

            let container = ReaderContainerViewController()
            container.embed(navigator)

            container.bookID = bookID

            container.onExplain = { [commands] text, locatorJSON in
                commands?.onExplain?(text, locatorJSON)
            }
            container.onAddNote = { [commands] text, locatorJSON in
                commands?.onAddNote?(text, locatorJSON)
            }

            container.applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
            container.setupHighlightInteractions()

            context.coordinator.container = container

            let pub = publication
            let positionsCallback = onPositionsLoaded
            Task {
                if case .success(let positions) = await pub.positions() {
                    await MainActor.run { positionsCallback(positions.count) }
                }
            }

            return container
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            guard let container = uiViewController as? ReaderContainerViewController,
                let navigator = container.navigator
            else { return }

            let bg = ReadiumNavigator.Color(hex: settings.colorTheme.backgroundHex)
            let fg = ReadiumNavigator.Color(hex: settings.colorTheme.foregroundHex)

            let fontFamily: ReadiumNavigator.FontFamily? = settings.font.cssFamily
                .map { ReadiumNavigator.FontFamily(rawValue: $0) }

            let preferences = EPUBPreferences(
                backgroundColor: bg,
                fontFamily: fontFamily,
                fontSize: settings.fontSize,
                fontWeight: settings.boldText ? 1.75 : nil,
                lineHeight: settings.lineHeight,
                pageMargins: settings.margin,
                publisherStyles: settings.font == .original ? nil : false,
                scroll: settings.layout == .scrolling,
                textAlign: settings.justifyText ? .justify : .start,
                textColor: fg
            )

            Task {
                await navigator.submitPreferences(preferences)
            }
        }
    }
#endif
