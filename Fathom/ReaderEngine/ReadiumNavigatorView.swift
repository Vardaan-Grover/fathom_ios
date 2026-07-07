import Combine
import SwiftUI

#if os(iOS)
    import UIKit
    import ReadiumShared
    import ReadiumNavigator
    import ReadiumAdapterGCDWebServer

    @MainActor
    final class NavigatorCommands: ObservableObject {
        var goLeft: (@MainActor () async -> Void)?
        var goRight: (@MainActor () async -> Void)?
        var goToLocatorJSON: (@MainActor (String) async -> Void)?
        var onTap: (@MainActor (CGPoint, CGSize) -> Void)?
        var onExplain: (@MainActor (String, String) -> Void)?
        var onAddNote: (@MainActor (String, String) -> Void)?
        var onEditNote: (@MainActor (UUID, String, String) -> Void)?
        var onDefine: (@MainActor (String, String, String?) -> Void)?
        var onTranslate: (@MainActor (String) -> Void)?
        var onSearchText: (@MainActor (String) -> Void)?
        var applySearchHighlight: (@MainActor (String) -> Void)?
    }

    final class ReaderContainerViewController: UIViewController,
        UIEditMenuInteractionDelegate,
        UIPopoverPresentationControllerDelegate
    {
        var onExplain: ((String, String) -> Void)?
        var onAddNote: ((String, String) -> Void)?
        var onEditNote: ((UUID, String, String) -> Void)?
        var onDefine: ((String, String, String?) -> Void)?
        var onTranslate: ((String) -> Void)?
        var onSearchText: ((String) -> Void)?
        var bookID: UUID = UUID()
        var aiEnabled: Bool = true
        private(set) var pendingNoteID: UUID?
        private(set) var pendingHighlightID: UUID?
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
        func showMenuForSelection(text: String, locatorJSON: String, contextSentence: String?, at frame: CGRect) {
            guard let navView = navigator?.view else { return }

            // Store BEFORE presenting — the delegate is called synchronously inside presentEditMenu
            pendingText = text
            pendingLocatorJSON = locatorJSON
            pendingContextSentence = contextSentence
            pendingIsSingleWord = text.split(whereSeparator: \.isWhitespace).count == 1
            pendingNoteID = nil  // fresh selection: not a note tap

            // Convert to self.view coordinates and store for targetRectFor delegate.
            // The menu's width tracks this rect's width, so widen narrow (e.g. single-word)
            // selections to a minimum so the segmented buttons aren't cramped.
            var rect = navView.convert(frame, to: view)
            let minWidth: CGFloat = 280
            if rect.width < minWidth {
                rect.origin.x -= (minWidth - rect.width) / 2
                rect.size.width = minWidth
            }
            lastSelectionRect = rect
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
        private var pendingContextSentence: String? = nil
        private var pendingIsSingleWord: Bool = false
        private var lastSelectionRect: CGRect = .zero

        // UIEditMenuInteractionDelegate — builds the menu items
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {

            let isTappingDecoration = pendingNoteID != nil || pendingHighlightID != nil

            // "Highlight" behavior:
            // - fresh selection    → add a new highlight (color picker)
            // - note tap           → change the note's highlight color
            // - highlight tap      → change color or remove via HighlightMenuView
            let highlightAction = UIAction(
                title: "Highlight", image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                guard let self else { return }
                if let noteID = pendingNoteID {
                    let currentColor = NoteStore.shared
                        .notes(forBookID: bookID)
                        .first(where: { $0.id == noteID })?.highlightColor ?? .indigo
                    showNoteColorPicker(for: noteID, currentColor: currentColor)
                } else if let highlightID = pendingHighlightID {
                    showExistingHighlightColorPicker(for: highlightID)
                } else {
                    navigator?.clearSelection()
                    showColorPicker(text: pendingText, locatorJSON: pendingLocatorJSON)
                }
            }

            // "Add Note" ↔ "Edit Note" depending on context
            let noteAction: UIAction
            if let noteID = pendingNoteID {
                noteAction = UIAction(
                    title: "Edit Note", image: UIImage(systemName: "square.and.pencil")
                ) { [weak self] _ in
                    guard let self else { return }
                    let capturedID = noteID
                    let text = pendingText
                    let locatorJSON = pendingLocatorJSON
                    pendingNoteID = nil
                    onEditNote?(capturedID, text, locatorJSON)
                }
            } else {
                noteAction = UIAction(
                    title: "Add Note", image: UIImage(systemName: "square.and.pencil")
                ) { [weak self] _ in
                    guard let self else { return }
                    let text = pendingText
                    let locatorJSON = pendingLocatorJSON
                    // If adding a note on top of a standalone highlight, remove the
                    // highlight — the note decoration replaces it visually.
                    if let highlightID = pendingHighlightID {
                        HighlightStore.shared.delete(id: highlightID)
                        applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
                        pendingHighlightID = nil
                    } else {
                        navigator?.clearSelection()
                    }
                    onAddNote?(text, locatorJSON)
                }
            }

            // Lead action: Define for single words. "Ask AI" for phrases is
            // hidden from the UI for now (kept here in case it's re-enabled).
            let leadAction: UIAction?
            if pendingIsSingleWord {
                leadAction = UIAction(
                    title: "Define", image: UIImage(systemName: "character.book.closed")
                ) { [weak self] _ in
                    guard let self else { return }
                    let term = pendingText
                    let locatorJSON = pendingLocatorJSON
                    if !isTappingDecoration { navigator?.clearSelection() }
                    pendingNoteID = nil
                    pendingHighlightID = nil
                    onDefine?(term, locatorJSON, pendingContextSentence)
                }
            } else {
                leadAction = nil
                // let askAIAction = UIAction(
                //     title: "Ask AI", image: UIImage(systemName: "sparkles")
                // ) { [weak self] _ in
                //     guard let self else { return }
                //     let text = pendingText
                //     let locatorJSON = pendingLocatorJSON
                //     if !isTappingDecoration { navigator?.clearSelection() }
                //     pendingNoteID = nil
                //     pendingHighlightID = nil
                //     onExplain?(text, locatorJSON)
                // }
            }

            // Copy, Search, Share, Translate
            let copyAction = UIAction(
                title: "Copy", image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = pendingText
                navigator?.clearSelection()
            }

            let searchAction = UIAction(
                title: "Search", image: UIImage(systemName: "doc.text.magnifyingglass")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                navigator?.clearSelection()
                onSearchText?(text)
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

            let translateAction = UIAction(
                title: "Translate", image: UIImage(systemName: "translate")
            ) { [weak self] _ in
                guard let self else { return }
                let text = pendingText
                navigator?.clearSelection()
                onTranslate?(text)
            }

            // Primary group: top 3 actions shown immediately as a segmented row.
            // Single word  → Define, Highlight, Add Note
            // Multi word   → Highlight, Add Note, Copy
            let primaryActions: [UIAction]
            if let leadAction {
                primaryActions = [leadAction, highlightAction, noteAction]
            } else {
                primaryActions = [highlightAction, noteAction, copyAction]
            }
            let primaryGroup = UIMenu(
                options: .displayInline,
                children: primaryActions)
            primaryGroup.preferredElementSize = .medium

            // Secondary group: remaining actions appear behind the > chevron
            var secondaryActions: [UIAction] = []
            if leadAction != nil {
                secondaryActions.append(copyAction)
            }
            secondaryActions.append(contentsOf: [searchAction, translateAction,shareAction])

            let secondaryGroup = UIMenu(
                options: .displayInline,
                children: secondaryActions)

            // System actions (Look Up, etc.) — filter out Copy and Translate since we supply our own
            let systemActions = suggestedActions.filter { element in
                guard let action = element as? UIAction else { return true }
                return action.title != "Copy" && action.title != "Translate"
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
                let locator = try? Locator(jsonString: locatorJSON)
            {
                // Vibrant purple that is distinct from the standard highlight colors
                let aiTint = UIColor(red: 0.48, green: 0.53, blue: 0.94, alpha: 1.0)
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

        func applyTemporarySearchHighlight(locatorJSON: String) {
            guard let navigator, let locator = try? Locator(jsonString: locatorJSON) else { return }
            let yellow = UIColor.systemYellow.withAlphaComponent(0.55)
            navigator.apply(
                decorations: [Decoration(id: "search_result", locator: locator, style: .highlight(tint: yellow))],
                in: "search_result"
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                self?.navigator?.apply(decorations: [], in: "search_result")
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

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHighlightsDidChange(_:)),
                name: HighlightStore.didChangeNotification,
                object: nil
            )
        }

        @objc private func handleHighlightsDidChange(_ notification: Notification) {
            guard let changedBookID = notification.object as? UUID,
                  changedBookID == bookID
            else { return }
            applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
        }

        func applyNoteHighlights(_ notes: [Note]) {
            guard let navigator = navigator else { return }

            // Background highlight using the note's chosen color
            let highlights: [Decoration] = notes.compactMap { note in
                guard let locator = try? Locator(jsonString: note.locatorJSON) else { return nil }
                return Decoration(
                    id: note.id.uuidString,
                    locator: locator,
                    style: .highlight(tint: note.highlightColor.uiColor)
                )
            }
            navigator.apply(decorations: highlights, in: "note_highlights")

            // Underline tinted to match each note's highlight color
            let underlines: [Decoration] = notes.compactMap { note in
                guard let locator = try? Locator(jsonString: note.locatorJSON) else { return nil }
                return Decoration(
                    id: "\(note.id.uuidString)_ul",
                    locator: locator,
                    style: .underline(tint: note.highlightColor.uiColor)
                )
            }
            navigator.apply(decorations: underlines, in: "note_underlines")
        }

        func setupNoteInteractions() {
            guard let navigator = navigator else { return }
            navigator.observeDecorationInteractions(inGroup: "note_highlights") { [weak self] event in
                guard let self, let noteID = UUID(uuidString: event.decoration.id) else { return }
                showNoteMenu(for: noteID, at: event.point)
            }

            // Observe NoteStore writes and reapply decorations immediately on the main thread.
            // This bypasses SwiftUI's updateUIViewController timing entirely.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleNotesDidChange(_:)),
                name: NoteStore.didChangeNotification,
                object: nil
            )
        }

        @objc private func handleNotesDidChange(_ notification: Notification) {
            guard let changedBookID = notification.object as? UUID,
                  changedBookID == bookID
            else { return }
            applyNoteHighlights(NoteStore.shared.notes(forBookID: bookID))
        }

        private func showNoteMenu(for noteID: UUID, at navigatorPoint: CGPoint?) {
            guard let note = NoteStore.shared.notes(forBookID: bookID).first(where: { $0.id == noteID })
            else { return }

            pendingText = note.selectedText
            pendingLocatorJSON = note.locatorJSON
            pendingIsSingleWord = note.selectedText.split(whereSeparator: \.isWhitespace).count == 1
            pendingNoteID = noteID

            if let pt = navigatorPoint, let navView = navigator?.view {
                let converted = navView.convert(pt, to: view)
                lastSelectionRect = CGRect(x: converted.x, y: converted.y, width: 1, height: 1)
            }

            presentMenu()
        }

        private func showNoteColorPicker(for noteID: UUID, currentColor: HighlightColor) {
            let content = NoteHighlightColorPickerView(
                currentColor: currentColor,
                onSelect: { [weak self] color in
                    guard let self else { return }
                    NoteStore.shared.updateHighlightColor(id: noteID, color: color)
                    applyNoteHighlights(NoteStore.shared.notes(forBookID: bookID))
                }
            )

            let host = UIHostingController(rootView: content)
            host.modalPresentationStyle = .popover
            // 5 circles × 34pt + 4 gaps × 14pt + 2 × 12pt padding
            host.preferredContentSize = CGSize(width: 258, height: 58)

            if let popover = host.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = lastSelectionRect
                popover.permittedArrowDirections = [.up, .down]
                popover.delegate = self
            }

            present(host, animated: true)
        }

        private func showHighlightMenu(for highlightID: UUID, at navigatorPoint: CGPoint?) {
            guard let highlight = HighlightStore.shared.highlights(forBookID: bookID)
                .first(where: { $0.id == highlightID })
            else { return }

            pendingText = highlight.text
            pendingLocatorJSON = highlight.locatorJSON
            pendingIsSingleWord = highlight.text.split(whereSeparator: \.isWhitespace).count == 1
            pendingHighlightID = highlightID
            pendingNoteID = nil

            if let pt = navigatorPoint, let navView = navigator?.view {
                let converted = navView.convert(pt, to: view)
                lastSelectionRect = CGRect(x: converted.x, y: converted.y, width: 1, height: 1)
            }

            presentMenu()
        }

        private func showExistingHighlightColorPicker(for highlightID: UUID) {
            let content = HighlightMenuView(
                onChangeColor: { [weak self] color in
                    guard let self else { return }
                    HighlightStore.shared.updateColor(id: highlightID, color: color)
                    applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
                    pendingHighlightID = nil
                },
                onRemove: { [weak self] in
                    guard let self else { return }
                    HighlightStore.shared.delete(id: highlightID)
                    applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
                    pendingHighlightID = nil
                }
            )

            let host = UIHostingController(rootView: content)
            host.modalPresentationStyle = .popover
            host.preferredContentSize = CGSize(width: 256, height: 56)

            if let popover = host.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = lastSelectionRect
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
        var onPositionsLoaded: ([Locator]) -> Void = { _ in }
        var commands: NavigatorCommands? = nil
        var settings: ReaderSettings = ReaderSettings()
        var bookID: UUID = UUID()
        var aiQueryLocatorJSON: String? = nil
        var aiEnabled: Bool = true
        var notesVersion: Int = 0

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
                let safe =
                    navigator.view.window?.safeAreaInsets
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

                let before = selection.locator.text.before ?? ""
                let after = selection.locator.text.after ?? ""
                let contextSentence = (before + text + after).trimmingCharacters(in: .whitespacesAndNewlines)

                container?.showMenuForSelection(
                    text: text,
                    locatorJSON: locatorJSON,
                    contextSentence: contextSentence.isEmpty ? nil : contextSentence,
                    at: frame
                )

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
                let config = EPUBNavigatorViewController.Configuration(
                    // Readium spawns one WKWebView (backed by a separate WebKit.WebContent
                    // process) per preloaded position. The defaults (2 before / 6 after) keep
                    // ~8 web views warm, which dominates the app's memory coalition and makes
                    // it a prime jetsam target under system-wide memory pressure. Trim to the
                    // immediate neighbours — enough for smooth page turns, far less resident RAM.
                    preloadPreviousPositionCount: 1,
                    preloadNextPositionCount: 2,
                    decorationTemplates: HTMLDecorationTemplate.defaultTemplates(
                        lineWeight: 2,
                        cornerRadius: 5,
                        alpha: 0.55,
                        experimentalPositioning: true
                    )
                )
                navigator = try EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    config: config,
                    httpServer: ReadiumStack.shared.httpServer
                )
            } catch {
                AppLogger.logError(tag: "ReadiumNavigatorView", error)
                return UIViewController()
            }
            AppLogger.log(
                tag: "ReadiumNavigatorView", "Successfully initialized EPUBNavigatorViewController."
            )
            navigator.delegate = context.coordinator

            commands?.goLeft = { @MainActor [weak navigator] in
                guard let navigator = navigator else { return }
                await navigator.goLeft(options: NavigatorGoOptions.animated)
            }
            commands?.goRight = { @MainActor [weak navigator] in
                guard let navigator = navigator else { return }
                await navigator.goRight(options: NavigatorGoOptions.animated)
            }
            commands?.goToLocatorJSON = { @MainActor [weak navigator] json in
                guard let navigator = navigator else { return }
                guard let locator = try? Locator(jsonString: json) else { return }
                await navigator.go(to: locator)
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
            container.onEditNote = { [commands] noteID, text, locatorJSON in
                commands?.onEditNote?(noteID, text, locatorJSON)
            }
            container.onDefine = { [commands] text, locatorJSON, contextSentence in
                commands?.onDefine?(text, locatorJSON, contextSentence)
            }
            container.onTranslate = { [commands] text in
                commands?.onTranslate?(text)
            }
            container.onSearchText = { [commands] text in
                commands?.onSearchText?(text)
            }

            commands?.applySearchHighlight = { [weak container] locatorJSON in
                container?.applyTemporarySearchHighlight(locatorJSON: locatorJSON)
            }

            container.applyHighlights(HighlightStore.shared.highlights(forBookID: bookID))
            container.applyNoteHighlights(NoteStore.shared.notes(forBookID: bookID))
            container.setupHighlightInteractions()
            container.setupNoteInteractions()

            context.coordinator.container = container

            let pub = publication
            let positionsCallback = onPositionsLoaded
            Task {
                if case .success(let positions) = await pub.positions() {
                    await MainActor.run { positionsCallback(positions) }
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
            container.applyNoteHighlights(NoteStore.shared.notes(forBookID: bookID))
        }
    }
#endif
