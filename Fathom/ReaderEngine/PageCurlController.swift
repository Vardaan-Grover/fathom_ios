import SwiftUI

#if os(iOS)
    import UIKit
    import WebKit
    import ReadiumShared
    import ReadiumNavigator

    /// A page shown inside the curl transition: either a live snapshot view of
    /// the current page, or a bitmap of the destination page rendered by
    /// WebKit. The background color doubles as the placeholder while the
    /// destination bitmap is in flight and as the tint behind the translucent
    /// curl backside, so it must always match the reader theme.
    @MainActor
    final class SnapshotPageViewController: UIViewController {
        private var snapshotView: UIView?
        private var overlayView: UIView?
        private let imageView = UIImageView()
        private var imageFrame: CGRect?

        var background: UIColor {
            didSet { view.backgroundColor = background }
        }

        init(background: UIColor) {
            self.background = background
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = background
            imageView.contentMode = .scaleToFill
            view.addSubview(imageView)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            imageView.frame = imageFrame ?? view.bounds
        }

        /// Full-bleed live snapshot of the on-screen page (current side).
        func setSnapshotView(_ snapshot: UIView) {
            loadViewIfNeeded()
            snapshotView?.removeFromSuperview()
            snapshotView = snapshot
            snapshot.frame = view.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(snapshot)
        }

        /// Destination bitmap. `frame` is the web view's frame in the reader's
        /// coordinate space — the web view is inset from the reader edges, so
        /// the theme background fills the margins.
        func setImage(_ image: UIImage, frame: CGRect) {
            loadViewIfNeeded()
            imageFrame = frame
            imageView.transform = .identity
            imageView.alpha = 1.0
            imageView.image = image
            imageView.frame = frame
            view.bringSubviewToFront(imageView)
            if let overlay = overlayView {
                view.bringSubviewToFront(overlay)
            }
        }

        func setFlippedSnapshotView(_ snapshot: UIView, alpha: CGFloat = 0.15) {
            loadViewIfNeeded()
            snapshotView?.removeFromSuperview()
            snapshotView = snapshot
            snapshot.frame = view.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.transform = CGAffineTransform(scaleX: -1, y: 1)
            snapshot.alpha = alpha
            view.addSubview(snapshot)
        }

        func setFlippedImage(_ image: UIImage, frame: CGRect, alpha: CGFloat = 0.15) {
            loadViewIfNeeded()
            imageFrame = frame
            imageView.image = image
            imageView.frame = frame
            imageView.transform = CGAffineTransform(scaleX: -1, y: 1)
            imageView.alpha = alpha
            view.bringSubviewToFront(imageView)
            if let overlay = overlayView {
                view.bringSubviewToFront(overlay)
            }
        }
        
        func setFlippedOverlay(_ overlay: UIView, alpha: CGFloat = 0.15) {
            loadViewIfNeeded()
            self.overlayView?.removeFromSuperview()
            self.overlayView = overlay
            overlay.frame = view.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.transform = CGAffineTransform(scaleX: -1, y: 1)
            overlay.alpha = alpha
            view.addSubview(overlay)
        }

        func setOverlay(_ overlay: UIView) {
            loadViewIfNeeded()
            self.overlayView?.removeFromSuperview()
            self.overlayView = overlay
            overlay.frame = view.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(overlay)
        }
    }

    /// Drives an Apple Books-style interactive page curl on top of a Readium
    /// `EPUBNavigatorViewController`.
    ///
    /// Readium renders a whole chapter as CSS columns inside one WKWebView, so
    /// individual pages never exist as separate views. The curl is therefore
    /// snapshot-driven: a hidden `UIPageViewController(.pageCurl)` overlay curls
    /// between a snapshot of the current page and a freshly rendered snapshot of
    /// the destination page, while the live navigator performs the real turn
    /// non-animated underneath. The overlay's pan recognizer is reattached to
    /// the host view (an Apple-documented pattern for the pageCurl style) so
    /// drags anywhere on the page start an interactive curl.
    @MainActor
    final class PageCurlController: NSObject {
        enum PhysicalDirection {
            case left, right

            var opposite: PhysicalDirection { self == .left ? .right : .left }
        }

        private enum State {
            /// Overlay hidden, live navigator fully interactive.
            case idle
            /// Pan began: current-page snapshot shown, direction not yet known.
            case tracking
            /// Gesture-driven curl in flight; hidden pre-turn commanded.
            case interactive(PhysicalDirection)
            /// Tap-driven curl animating via setViewControllers.
            case programmatic(PhysicalDirection)
            /// Reverting a cancelled pre-turn before hiding the overlay.
            case cancelling

            var isIdle: Bool { if case .idle = self { return true } else { return false } }
        }

        private let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )

        private weak var navigator: EPUBNavigatorViewController?
        private weak var hostViewController: UIViewController?
        private var panGesture: UIPanGestureRecognizer?

        /// Coordinator handshake: while suppressed, locationDidChange events are
        /// stashed instead of forwarded, so a cancellable pre-turn never leaks
        /// locator saves or page-label updates. `endSuppression(true)` flushes
        /// the stash, `endSuppression(false)` drops it.
        var beginSuppression: () -> Void = {}
        var endSuppression: (_ commit: Bool) -> Void = { _ in }

        var themeBackground: UIColor {
            didSet {
                currentPageVC?.background = themeBackground
                destinationPageVC?.background = themeBackground
                backPageVC?.background = themeBackground
            }
        }

        private var state: State = .idle
        private var pendingTurns: [PhysicalDirection] = []
        private var currentPageVC: SnapshotPageViewController?
        private var destinationPageVC: SnapshotPageViewController?
        private var backPageVC: SnapshotPageViewController?

        /// Direction of the single hidden pre-turn allowed per gesture.
        private var hiddenTurnDirection: PhysicalDirection?
        /// The in-flight pre-turn; its value is whether the navigator actually
        /// moved (and therefore needs a revert on cancel). Cancel paths await
        /// it so a quick release can never race the turn itself.
        private var hiddenTurnTask: Task<Bool, Never>?
        private var suppressionActive = false

        private var positionCount: Int?
        private var currentPosition: Int?
        private var lastTotalProgression: Double?
        private var isRTL = false

        // Both directions show the theme background until the destination
        // bitmap lands (~50ms). There is deliberately no snapshot cache: it
        // would need a destination position, and the only reliable source of
        // one arrives too late to prime a placeholder with. See
        // `captureDestinationSnapshot`.

        private(set) var isInstalled = false

        init(navigator: EPUBNavigatorViewController, host: UIViewController, themeBackground: UIColor) {
            self.navigator = navigator
            self.hostViewController = host
            self.themeBackground = themeBackground
            super.init()
        }

        // MARK: - Install / uninstall

        func install() {
            guard !isInstalled, let host = hostViewController, let navigator = navigator else { return }
            isInstalled = true

            isRTL = navigator.presentation.readingProgression == .rtl

            pageVC.dataSource = self
            pageVC.delegate = self
            pageVC.isDoubleSided = true
            pageVC.view.backgroundColor = .clear
            pageVC.view.isHidden = true

            // Set a placeholder view controller so the page view controller is never in
            // an empty state (0 VCs), which crashes with UIPageViewControllerSpineLocationMin.
            let placeholder = SnapshotPageViewController(background: themeBackground)
            pageVC.setViewControllers([placeholder], direction: .forward, animated: false)

            host.addChild(pageVC)
            host.view.addSubview(pageVC.view)
            pageVC.view.frame = host.view.bounds
            pageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pageVC.didMove(toParent: host)

            // Reattach the curl gestures to the host so drags anywhere on the
            // reader start an interactive curl even while the overlay is hidden.
            // The tap recognizer is disabled outright: the app's own tap zones
            // drive programmatic curls with their own exclusion rules.
            for recognizer in pageVC.gestureRecognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
                if let pan = recognizer as? UIPanGestureRecognizer {
                    pan.addTarget(self, action: #selector(handleCurlPan(_:)))
                    host.view.addGestureRecognizer(pan)
                    panGesture = pan
                } else {
                    recognizer.isEnabled = false
                }
            }

            navigator.arePageTurnGesturesEnabled = false

            let publication = navigator.publication
            Task { [weak self] in
                if case let .success(positions) = await publication.positions() {
                    self?.positionCount = positions.count
                }
            }
        }

        func uninstall() {
            guard isInstalled else { return }
            isInstalled = false

            abortForEnvironmentChange()

            if let pan = panGesture {
                pan.removeTarget(self, action: #selector(handleCurlPan(_:)))
                pan.view?.removeGestureRecognizer(pan)
            }
            panGesture = nil

            pageVC.willMove(toParent: nil)
            pageVC.view.removeFromSuperview()
            pageVC.removeFromParent()

            navigator?.arePageTurnGesturesEnabled = true
            releaseSnapshots()
        }

        /// Tracks the reading position for boundary checks. Called for every
        /// location change, including suppressed ones.
        func noteLocation(_ locator: Locator) {
            currentPosition = locator.locations.position
            lastTotalProgression = locator.locations.totalProgression
        }

        // MARK: - Programmatic turns (tap zones)

        func requestTurn(_ direction: PhysicalDirection) {
            guard isInstalled else { return }
            guard state.isIdle else {
                // Queue at most 2; an opposite-direction request expresses
                // "never mind" — clear instead of stacking a round trip.
                if pendingTurns.last == direction.opposite || pendingTurns.first == direction.opposite {
                    pendingTurns.removeAll()
                } else if pendingTurns.count < 2 {
                    pendingTurns.append(direction)
                }
                return
            }
            guard canTurn(direction), let navigator = navigator else { return }

            guard prepareOverlayShowingCurrentPage() else {
                // Snapshot failed (e.g. memory pressure): degrade to the slide.
                Task {
                    if direction == .right {
                        await navigator.goRight(options: NavigatorGoOptions.animated)
                    } else {
                        await navigator.goLeft(options: NavigatorGoOptions.animated)
                    }
                }
                return
            }

            state = .programmatic(direction)
            let destination = SnapshotPageViewController(background: themeBackground)
            destinationPageVC = destination
            let back = SnapshotPageViewController(background: themeBackground)
            backPageVC = back
            if direction == .right {
                if let backSnapshot = navigator.view.snapshotView(afterScreenUpdates: false) {
                    back.setFlippedSnapshotView(backSnapshot, alpha: 0.15)
                }
            }
            if let overlay = (hostViewController as? ReaderContainerViewController)?.overlaySnapshotView {
                back.setFlippedOverlay(overlay)
            }
            let turnTask = startHiddenTurn(direction, into: destination, backPage: direction == .left ? back : nil)

            Task { [weak self] in
                guard let self else { return }
                let moved = await turnTask.value
                guard moved, self.isInstalled, case .programmatic = self.state else {
                    self.endSuppressionIfActive(commit: false)
                    self.hideOverlayAndReset()
                    return
                }
                self.pageVC.setViewControllers(
                    [destination, back],
                    direction: direction == .right ? .forward : .reverse,
                    animated: true
                ) { [weak self] _ in
                    Task { @MainActor in self?.commit() }
                }
            }
        }

        /// Cancels any in-flight curl and restores a consistent live page.
        /// Used on rotation, backgrounding and uninstall — the snapshots are
        /// stale for the new environment anyway.
        func abortForEnvironmentChange() {
            guard !state.isIdle else { return }
            pendingTurns.removeAll()
            cancelPanGesture()

            if case .programmatic = state {
                // The animation's completion will commit normally; the turn was
                // an explicit tap, so keep it rather than yanking it back.
                return
            }

            // Interactive/tracking: revert any commanded pre-turn and reset.
            cancelAndRevert()
        }

        // MARK: - Gesture handling

        @objc private func handleCurlPan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                if !prepareGestureIfPossible(at: pan.location(in: pan.view)) {
                    cancelPanGesture()
                }
            case .ended, .cancelled, .failed:
                // If UIPVC started a transition, its delegate callbacks own the
                // rest. A dead drag (no transition) is torn down here, on the
                // next runloop so a same-moment willTransitionTo wins.
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .tracking = self.state else { return }
                    self.teardownDeadDrag()
                }
            default:
                break
            }
        }

        /// Idempotent per gesture: veto checks, then snapshot the current page
        /// and show the overlay. Callable from both the pan target and the
        /// dataSource (whichever fires first).
        private func prepareGestureIfPossible(at point: CGPoint?) -> Bool {
            switch state {
            case .tracking, .interactive:
                return true
            case .idle:
                break
            default:
                return false
            }

            guard let navigator = navigator, navigator.currentSelection == nil else { return false }

            // Same exclusion zones as the reader's tap recognizer: drags in the
            // overlay-bar areas belong to the SwiftUI chrome.
            if let point, let hostView = hostViewController?.view {
                let safe = hostView.window?.safeAreaInsets ?? UIEdgeInsets(top: 44, left: 0, bottom: 34, right: 0)
                if point.y < safe.top + 72 { return false }
                if point.y > hostView.bounds.height - safe.bottom - 52 { return false }
            }

            guard prepareOverlayShowingCurrentPage() else { return false }
            state = .tracking
            return true
        }

        /// Kicks off the hidden pre-turn, recording it for the cancel paths.
        private func startHiddenTurn(
            _ direction: PhysicalDirection,
            into destination: SnapshotPageViewController,
            backPage: SnapshotPageViewController?
        ) -> Task<Bool, Never> {
            hiddenTurnDirection = direction
            beginSuppression()
            suppressionActive = true
            let task = Task { [weak self] in
                await self?.performHiddenTurn(direction, into: destination, backPage: backPage) ?? false
            }
            hiddenTurnTask = task
            return task
        }

        private func endSuppressionIfActive(commit: Bool) {
            guard suppressionActive else { return }
            suppressionActive = false
            endSuppression(commit)
        }

        /// Snapshots the live page into the overlay's current side and unhides
        /// it — visually seamless because the snapshot is pixel-identical.
        private func prepareOverlayShowingCurrentPage() -> Bool {
            guard let navigator = navigator else { return false }
            // If we are already tracking, the overlay is up to date.
            guard state.isIdle else { return true }

            guard let snapshot = navigator.view.snapshotView(afterScreenUpdates: false) else { return false }

            let current: SnapshotPageViewController
            if let existing = pageVC.viewControllers?.first as? SnapshotPageViewController {
                current = existing
            } else {
                current = SnapshotPageViewController(background: themeBackground)
                pageVC.setViewControllers([current], direction: .forward, animated: false)
            }
            
            current.setSnapshotView(snapshot)
            if let container = hostViewController as? ReaderContainerViewController,
               let factory = container.overlayForLocator {
                let anyView = factory(navigator.currentLocation)
                let hosting = UIHostingController(rootView: anyView)
                hosting.view.backgroundColor = UIColor.clear
                current.addChild(hosting)
                current.setOverlay(hosting.view)
                hosting.didMove(toParent: current)
            }
            currentPageVC = current
            hostViewController?.view.bringSubviewToFront(pageVC.view)
            pageVC.view.isHidden = false
            return true
        }

        private func cancelPanGesture() {
            // Toggling isEnabled force-cancels an in-flight recognizer without
            // touching UIPVC's private gesture delegate.
            guard let pan = panGesture else { return }
            pan.isEnabled = false
            pan.isEnabled = true
        }

        // MARK: - Hidden pre-turn + destination snapshot

        /// Commands the live navigator (hidden behind the overlay) to actually
        /// turn, then renders the newly visible page into `destination`.
        /// Returns whether the navigator moved.
        private func performHiddenTurn(
            _ direction: PhysicalDirection,
            into destination: SnapshotPageViewController,
            backPage: SnapshotPageViewController?
        ) async -> Bool {
            guard let navigator = navigator else { return false }

            let moved: Bool
            if direction == .right {
                moved = await navigator.goRight(options: NavigatorGoOptions())
            } else {
                moved = await navigator.goLeft(options: NavigatorGoOptions())
            }
            guard moved else { return false }

            if let webView = navigator.visibleWebViewForSnapshot {
                await waitForWebKitPaint(webView)
            }
            await captureDestinationSnapshot(into: destination, backPage: backPage, retriesLeft: 2)
            return true
        }

        /// The page turn is a scroll-offset change in the UI process; WebKit's
        /// WebContent process repaints the newly exposed tiles asynchronously.
        /// Snapshotting before that repaint captures a half-blank, shifted
        /// frame. Neither step is directly observable, so: a short delay lets
        /// the new visible rect reach the web process, then two nested
        /// requestAnimationFrame ticks inside the page act as a paint barrier.
        private func waitForWebKitPaint(_ webView: WKWebView) async {
            try? await Task.sleep(nanoseconds: 32_000_000)
            _ = try? await webView.callAsyncJavaScript(
                "return await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true))));",
                arguments: [:],
                contentWorld: .defaultClient
            )
        }

        private func captureDestinationSnapshot(
            into destination: SnapshotPageViewController,
            backPage: SnapshotPageViewController?,
            retriesLeft: Int
        ) async {
            guard let navigator = navigator,
                  let webView = navigator.visibleWebViewForSnapshot
            else { return }

            let frame = webView.convert(webView.bounds, to: navigator.view)
            let image: UIImage?
            do {
                image = try await webView.takeSnapshot(configuration: nil)
            } catch {
                image = nil
            }

            if let image, !isSuspiciouslyBlank(image) {
                destination.setImage(image, frame: frame)
                backPage?.setFlippedImage(image, frame: frame, alpha: 0.15)

                let container = hostViewController as? ReaderContainerViewController
                if let factory = container?.overlayForLocator {
                    let anyView = factory(navigator.currentLocation)
                    // The destination page MUST render the UI for the new state.
                    let hosting = UIHostingController(rootView: anyView)
                    hosting.view.backgroundColor = UIColor.clear
                    destination.addChild(hosting)
                    destination.setOverlay(hosting.view)
                    hosting.didMove(toParent: destination)
                }
            } else if retriesLeft > 0 {
                // WebContent hadn't painted yet — wait out another paint cycle.
                await waitForWebKitPaint(webView)
                await captureDestinationSnapshot(into: destination, backPage: backPage, retriesLeft: retriesLeft - 1)
            }
            // On persistent failure the theme-background placeholder stays —
            // degraded but never a white flash.
        }

        /// A pure-white capture on a dark theme means WebKit returned an
        /// unpainted buffer. On light themes white is indistinguishable from
        /// real content, so only dark backgrounds are checked.
        private func isSuspiciouslyBlank(_ image: UIImage) -> Bool {
            // To detect an unpainted buffer (which may be solid white for light themes or solid black for dark themes),
            // we scale the image down to 10x10 and check if it's completely uniform (variance in color is almost zero).
            guard let cgImage = image.cgImage else { return false }
            let size = 10
            let bytesPerPixel = 4
            let bytesPerRow = size * bytesPerPixel
            var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            
            // Check if all pixels are exactly the same as the first pixel
            let r = pixels[0]
            let g = pixels[1]
            let b = pixels[2]
            
            for i in 1..<(size * size) {
                let offset = i * bytesPerPixel
                // Allow a tiny bit of compression/interpolation noise, but an unpainted buffer will be perfectly uniform.
                if abs(Int(pixels[offset]) - Int(r)) > 2 ||
                   abs(Int(pixels[offset+1]) - Int(g)) > 2 ||
                   abs(Int(pixels[offset+2]) - Int(b)) > 2 {
                    return false // Found varying pixels, so it has content (text/images)
                }
            }
            
            return true // Perfectly uniform -> suspiciously blank
        }

        // MARK: - Boundaries

        private func canTurn(_ direction: PhysicalDirection) -> Bool {
            let forward = (direction == .right) != isRTL
            if let position = currentPosition, let count = positionCount, count > 0 {
                return forward ? position < count : position > 1
            }
            if let progression = lastTotalProgression {
                return forward ? progression < 1.0 : progression > 0.0
            }
            return true
        }

        // MARK: - Completion paths

        private func commit() {
            endSuppressionIfActive(commit: true)
            hideOverlayAndReset()
            if !pendingTurns.isEmpty {
                let next = pendingTurns.removeFirst()
                requestTurn(next)
            }
        }

        /// Awaits the pre-turn, reverts it if the navigator moved, and only
        /// then hides the overlay — the wrong live page is never exposed
        /// because the overlay has settled back on the current-page snapshot.
        private func cancelAndRevert() {
            let turnTask = hiddenTurnTask
            let direction = hiddenTurnDirection
            state = .cancelling
            Task { [weak self] in
                guard let self else { return }
                let moved = await turnTask?.value ?? false
                if moved, let direction, let navigator = self.navigator {
                    if direction == .right {
                        _ = await navigator.goLeft(options: NavigatorGoOptions())
                    } else {
                        _ = await navigator.goRight(options: NavigatorGoOptions())
                    }
                }
                self.endSuppressionIfActive(commit: false)
                self.hideOverlayAndReset()
            }
        }

        private func teardownDeadDrag() {
            if hiddenTurnTask != nil {
                cancelAndRevert()
            } else {
                hideOverlayAndReset()
            }
        }

        private func hideOverlayAndReset() {
            pageVC.view.isHidden = true
            releaseSnapshots()
            hiddenTurnDirection = nil
            hiddenTurnTask = nil
            state = .idle
        }

        private func releaseSnapshots() {
            currentPageVC = nil
            destinationPageVC = nil
            backPageVC = nil
        }
    }

    // MARK: - UIPageViewControllerDataSource

    extension PageCurlController: UIPageViewControllerDataSource {
        // Double-sided page curl expects interleaved pages: turning one leaf
        // moves two positions — front of the current page, back of the leaf,
        // front of the destination. The first query for a direction returns
        // the leaf's back; the follow-up query (relative to that back page)
        // returns the destination front.

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            if viewController === backPageVC {
                return hiddenTurnDirection == .left ? destinationPageVC : nil
            }
            return startLeaf(for: .left)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            if viewController === backPageVC {
                return hiddenTurnDirection == .right ? destinationPageVC : nil
            }
            return startLeaf(for: .right)
        }

        private func startLeaf(for direction: PhysicalDirection) -> UIViewController? {
            guard isInstalled else { return nil }
            if case .cancelling = state { return nil }

            // Only one hidden pre-turn at a time: re-queries for the same
            // direction (including the programmatic transition asking for its
            // leaf's back) reuse it; the opposite is refused mid-turn.
            if let commanded = hiddenTurnDirection {
                return commanded == direction ? backPageVC : nil
            }

            guard prepareGestureIfPossible(at: panGesture?.location(in: panGesture?.view)) else { return nil }
            guard canTurn(direction) else { return nil }

            let destination = SnapshotPageViewController(background: themeBackground)
            destinationPageVC = destination
            let back = SnapshotPageViewController(background: themeBackground)
            backPageVC = back

            // Turning forward, the curling leaf is the current page, so its
            // backside is a mirror of what's on screen right now. Turning back,
            // the leaf is the destination, and its backside can only be filled
            // once that page has been captured — hence `backPage:` below.
            if direction == .right {
                if let backSnapshot = navigator?.view.snapshotView(afterScreenUpdates: false) {
                    back.setFlippedSnapshotView(backSnapshot, alpha: 0.15)
                }
            }
            
            if let container = hostViewController as? ReaderContainerViewController,
               let factory = container.overlayForLocator {
                let anyView = factory(navigator?.currentLocation)
                let hosting = UIHostingController(rootView: anyView)
                hosting.view.backgroundColor = UIColor.clear
                back.addChild(hosting)
                back.setFlippedOverlay(hosting.view)
                hosting.didMove(toParent: back)
            }
            let turnTask = startHiddenTurn(direction, into: destination, backPage: direction == .left ? back : nil)

            Task { [weak self] in
                let moved = await turnTask.value
                if !moved {
                    // Boundary race or navigator busy: abandon this gesture.
                    // Cancelling the pan tears the rest down via the normal
                    // dead-drag / cancel paths.
                    self?.cancelPanGesture()
                }
            }
            return back
        }
    }

    // MARK: - UIPageViewControllerDelegate

    extension PageCurlController: UIPageViewControllerDelegate {
        func pageViewController(
            _ pageViewController: UIPageViewController,
            spineLocationFor orientation: UIInterfaceOrientation
        ) -> UIPageViewController.SpineLocation {
            // Force single-page layout (.min) even on iPad or landscape to prevent
            // UIPageViewController from defaulting to .mid (which requires 2 VCs).
            pageViewController.isDoubleSided = true
            return .min
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            guard case .tracking = state,
                  let direction = hiddenTurnDirection,
                  pendingViewControllers.contains(where: {
                      $0 === destinationPageVC || $0 === backPageVC
                  })
            else { return }
            state = .interactive(direction)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard case .interactive = state else { return }
            if completed {
                // A flip moves a whole leaf, but guard against landing on the
                // back page: the navigator has already turned either way.
                if pageViewController.viewControllers?.first === backPageVC,
                   let destination = destinationPageVC {
                    pageViewController.setViewControllers([destination], direction: .forward, animated: false)
                }
                commit()
            } else {
                cancelAndRevert()
            }
        }
    }
#endif
