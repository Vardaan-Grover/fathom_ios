import SwiftUI

#if os(iOS)
    import UIKit
    import ReadiumShared
    import ReadiumNavigator
    import ReadiumAdapterGCDWebServer

    final class NavigatorCommands {
        var goLeft: (() async -> Void)?
        var goRight: (() async -> Void)?
        var goToLocator: ((ReadiumShared.Locator) async -> Void)?
        var onTap: ((CGPoint, CGSize) -> Void)?
        var onExplain: ((String, String) -> Void)?
        var onAddNote: ((String, String) -> Void)?
    }

    final class ReaderContainerViewController: UIViewController,
        UIEditMenuInteractionDelegate,
        UIPopoverPresentationControllerDelegate
    {
        var onExplain: ((String, String) -> Void)?
        var onAddNote: ((String, String) -> Void)?
        var bookID: UUID = UUID()
        var aiEnabled: Bool = true
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
            guard let navView = navigator?.view else { return }

            // Store BEFORE presenting — the delegate is called synchronously inside presentEditMenu
            pendingText = text
            pendingLocatorJSON = locatorJSON
            pendingIsSingleWord = text.split(whereSeparator: \.isWhitespace).count == 1

            // Convert to self.view coordinates and store for targetRectFor delegate
            lastSelectionRect = navView.convert(frame, to: view)
            presentMenu()
        }

        // Re-presents the menu at the same position (e.g. when user taps on selected text)
        func reshowMenu() {
            guard !pendingText.isEmpty else { return }
            presentMenu()
        }

        private func presentMenu() {
            // sourcePoint is required by the API but placement is driven by targetRectFor below
            let config = UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: CGPoint(x: lastSelectionRect.midX, y: lastSelectionRect.midY))
            editMenuInteraction?.presentEditMenu(with: config)
        }

        // UIEditMenuInteractionDelegate — returns the selection rect so iOS places the menu
        // fully above or below the selected text without overlapping it.
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            targetRectFor configuration: UIEditMenuConfiguration
        ) -> CGRect {
            return lastSelectionRect
        }

        private var pendingText: String = ""
        private var pendingLocatorJSON: String = ""
        private var pendingIsSingleWord: Bool = false
        private var lastSelectionRect: CGRect = .zero

        // UIEditMenuInteractionDelegate — builds the menu items
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {

            let highlightAction = UIAction(
                title: "Highlight", image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                guard let self else { return }
                navigator?.clearSelection()
                showColorPicker(text: pendingText, locatorJSON: pendingLocatorJSON)
            }

            let addNoteAction = UIAction(
                title: "Add Note", image: UIImage(systemName: "square.and.pencil")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                let locatorJSON = pendingLocatorJSON
                navigator?.clearSelection()
                onAddNote?(text, locatorJSON)
            }

            // Lead action depends on selection length: Define for single words, Ask AI for phrases
            let leadAction: UIAction
            if pendingIsSingleWord {
                leadAction = UIAction(
                    title: "Define", image: UIImage(systemName: "character.book.closed")
                ) { [weak self] _ in
                    guard let self else { return }
                    let term = pendingText
                    navigator?.clearSelection()
                    guard UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
                    else { return }
                    present(UIReferenceLibraryViewController(term: term), animated: true)
                }
            } else {
                leadAction = UIAction(
                    title: "Ask AI", image: UIImage(systemName: "sparkles")
                ) { [weak self] _ in
                    guard let self else { return }
                    let text = pendingText
                    let locatorJSON = pendingLocatorJSON
                    navigator?.clearSelection()
                    onExplain?(text, locatorJSON)
                }
            }

            // Primary group: visible immediately in the pill
            let primaryGroup = UIMenu(
                options: .displayInline,
                children: [leadAction, highlightAction, addNoteAction])

            // Secondary group: Copy and Share appear behind the > chevron
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

            let secondaryGroup = UIMenu(
                options: .displayInline,
                children: [copyAction, shareAction])

            // System actions (Translate, Look Up, etc.) — filter out Copy since we supply our own
            let systemActions = suggestedActions.filter { element in
                guard let action = element as? UIAction else { return true }
                return action.title != "Copy"
            }

            return UIMenu(children: [primaryGroup, secondaryGroup] + systemActions)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            return .none
        }

        private func showColorPicker(text: String, locatorJSON: String) {
            let existing = HighlightStore.shared.highlights(forBookID: bookID)
            if existing.contains(where: { $0.locatorJSON == locatorJSON }) { return }

            let content = HighlightColorPickerView { [weak self] color in
                guard let self else { return }
                let highlight = Highlight(
                    id: UUID(),
                    bookID: bookID,
                    locatorJSON: locatorJSON,
                    text: text,
                    createdAt: Date(),
                    color: color
                )
                HighlightStore.shared.add(highlight)
                applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
            }

            let host = UIHostingController(rootView: content)
            host.modalPresentationStyle = .popover
            host.preferredContentSize = CGSize(width: 216, height: 60)

            if let popover = host.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = lastSelectionRect
                popover.permittedArrowDirections = [.up, .down]
                popover.delegate = self
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

        func applyAIQueryHighlight(locatorJSON: String?) {
            guard let navigator = navigator else { return }
            if let locatorJSON,
               let locator = try? Locator(jsonString: locatorJSON) {
                // Vibrant purple that is distinct from the standard highlight colors
                let aiTint = UIColor(red: 0.48, green: 0.53, blue: 0.94, alpha: 0.55)
                let decoration = Decoration(
                    id: "ai_query_highlight",
                    locator: locator,
                    style: .highlight(tint: aiTint)
                )
                navigator.apply(decorations: [decoration], in: "ai_query")
            } else {
                navigator.apply(decorations: [], in: "ai_query")
            }
        }

        func setupHighlightInteractions() {
            guard let navigator = navigator else { return }
            navigator.observeDecorationInteractions(inGroup: "highlights") { [weak self] event in
                guard let self, let highlightID = UUID(uuidString: event.decoration.id) else {
                    return
                }
                showHighlightMenu(for: highlightID, at: event.point)
            }
        }

        private func showHighlightMenu(for highlightID: UUID, at navigatorPoint: CGPoint?) {
            let content = HighlightMenuView(
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

            let host = UIHostingController(rootView: content)
            host.modalPresentationStyle = .popover
            host.preferredContentSize = CGSize(width: 256, height: 56)

            if let popover = host.popoverPresentationController {
                popover.sourceView = view
                let anchorPoint: CGPoint
                if let pt = navigatorPoint, let navView = navigator?.view {
                    anchorPoint = navView.convert(pt, to: view)
                } else {
                    anchorPoint = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                }
                popover.sourceRect = CGRect(x: anchorPoint.x, y: anchorPoint.y, width: 0, height: 0)
                popover.permittedArrowDirections = [.up, .down]
                popover.delegate = self
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
        var aiQueryLocatorJSON: String? = nil
        var aiEnabled: Bool = true

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
            let navigator: EPUBNavigatorViewController
            do {
                navigator = try EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    httpServer: ReadiumStack.shared.httpServer
                )
            } catch {
                AppLogger.logError(tag: "ReadiumNavigatorView", error)
                return UIViewController()
            }
            AppLogger.log(tag: "ReadiumNavigatorView", "Successfully initialized EPUBNavigatorViewController.")
            navigator.delegate = context.coordinator

            commands?.goLeft = { [weak navigator] in
                await navigator?.goLeft(options: NavigatorGoOptions.animated)
            }
            commands?.goRight = { [weak navigator] in
                await navigator?.goRight(options: NavigatorGoOptions.animated)
            }
            commands?.goToLocator = { [weak navigator] locator in
                await navigator?.go(to: locator)
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
            container.aiEnabled = aiEnabled

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

            container.applyAIQueryHighlight(locatorJSON: aiQueryLocatorJSON)
        }
    }
#endif
