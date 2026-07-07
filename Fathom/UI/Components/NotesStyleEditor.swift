import SwiftUI
import UIKit

/// A text editor built the way Apple Notes works: a single scrollable `UITextView`
/// that *owns* its scrolling, with arbitrary SwiftUI header content (e.g. a cover +
/// photo) hosted **inside** the text view's scroll so it scrolls away with the text.
///
/// Because the `UITextView` is the only scroll owner, caret-following while typing is
/// handled entirely by UIKit's native, system-tested behavior — there is no manual
/// `scrollRectToVisible`/`setContentOffset` and therefore nothing competing with
/// SwiftUI for the scroll position (the source of the previous glitching).
struct NotesStyleEditor<Header: View>: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var configuration: Configuration
    /// Changes only when header-affecting state changes (NOT when `text` changes), so
    /// typing never rebuilds or re-measures the header — which would perturb the text
    /// view's native caret scrolling and cause per-keystroke jumping.
    var headerID: AnyHashable
    @ViewBuilder var header: () -> Header

    struct Configuration {
        var font: UIFont
        var textColor: UIColor
        var tintColor: UIColor
        var placeholder: String = ""
        var placeholderColor: UIColor = .placeholderText
        var textHorizontalPadding: CGFloat = 16
        var textTopPadding: CGFloat = 8
        /// Extra bottom clearance (added to `contentInset.bottom`) so the caret/last
        /// line can sit above a floating bottom bar that overlays the editor.
        var bottomInset: CGFloat = 0
    }

    func makeUIView(context: Context) -> HeaderTextView {
        let tv = HeaderTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = configuration.font
        tv.textColor = configuration.textColor
        tv.tintColor = configuration.tintColor
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(
            top: configuration.textTopPadding,
            left: configuration.textHorizontalPadding,
            bottom: 8,
            right: configuration.textHorizontalPadding
        )
        tv.contentInsetAdjustmentBehavior = .never
        tv.contentInset.bottom = configuration.bottomInset

        // Hosted SwiftUI header, added as a scrolling subview.
        let host = UIHostingController(rootView: AnyView(header()))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        context.coordinator.hostingController = host
        tv.hostingController = host
        tv.addSubview(host.view)

        // Placeholder shown over the text area when empty.
        let placeholder = UILabel()
        placeholder.text = configuration.placeholder
        placeholder.font = configuration.font
        placeholder.textColor = configuration.placeholderColor
        placeholder.numberOfLines = 0
        tv.placeholderLabel = placeholder
        tv.addSubview(placeholder)

        context.coordinator.textView = tv
        context.coordinator.lastHeaderID = headerID
        tv.text = text
        placeholder.isHidden = !text.isEmpty
        tv.markHeaderDirty()
        return tv
    }

    func updateUIView(_ tv: HeaderTextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            tv.text = text
            tv.placeholderLabel?.isHidden = !text.isEmpty
        }
        if tv.font != configuration.font { tv.font = configuration.font }
        tv.textColor = configuration.textColor
        tv.tintColor = configuration.tintColor
        // NB: contentInset.bottom is owned by the keyboard handlers, not set here, so
        // a re-render while the keyboard is up doesn't clobber the keyboard overlap.

        // Only refresh/re-measure the header when header-affecting state changed.
        // Crucially, this is skipped on plain text edits, so typing doesn't disturb
        // the scroll position.
        if context.coordinator.lastHeaderID != headerID {
            context.coordinator.lastHeaderID = headerID
            context.coordinator.hostingController?.rootView = AnyView(header())
            tv.markHeaderDirty()
        }

        // Bridge focus only on a real mismatch (no per-keystroke no-op dispatch).
        if isFocused != tv.isFirstResponder {
            let wantsFocus = isFocused
            DispatchQueue.main.async {
                if wantsFocus, !tv.isFirstResponder {
                    tv.becomeFirstResponder()
                } else if !wantsFocus, tv.isFirstResponder {
                    tv.resignFirstResponder()
                }
            }
        }
    }

    /// Pin the editor to the size SwiftUI proposes, independent of its text content.
    /// (Prevents any content-driven frame changes from feeding back into layout.)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HeaderTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width,
               height: proposal.height ?? uiView.bounds.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NotesStyleEditor
        weak var textView: HeaderTextView?
        var hostingController: UIHostingController<AnyView>?
        var lastHeaderID: AnyHashable?

        init(_ parent: NotesStyleEditor) {
            self.parent = parent
            super.init()
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            nc.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            (tv as? HeaderTextView)?.placeholderLabel?.isHidden = !tv.text.isEmpty
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        // MARK: Keyboard insets
        //
        // The text view owns its scroll and we disable SwiftUI's keyboard avoidance
        // (`.ignoresSafeArea(.keyboard)` at the call site), so we set the bottom inset
        // ourselves. These notifications fire on show/hide/rotate — NOT per keystroke —
        // so there's no per-character layout churn.

        @objc private func keyboardWillChange(_ note: Notification) {
            guard let tv = textView, tv.isFirstResponder, let window = tv.window,
                  let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }

            let kbInWindow = window.convert(endFrame, from: nil)
            let tvInWindow = tv.convert(tv.bounds, to: window)
            let overlap = max(0, tvInWindow.maxY - kbInWindow.minY)

            tv.contentInset.bottom = overlap + parent.configuration.bottomInset
            tv.verticalScrollIndicatorInsets.bottom = overlap
            // One scroll so the caret clears the freshly-shown keyboard.
            tv.scrollRangeToVisible(tv.selectedRange)
        }

        @objc private func keyboardWillHide(_ note: Notification) {
            guard let tv = textView else { return }
            tv.contentInset.bottom = parent.configuration.bottomInset
            tv.verticalScrollIndicatorInsets.bottom = 0
        }
    }
}

/// `UITextView` subclass that lays out a hosted header subview in the reserved top
/// inset and keeps a placeholder positioned at the start of the text.
final class HeaderTextView: UITextView {
    var hostingController: UIHostingController<AnyView>?
    var placeholderLabel: UILabel?

    private var headerDirty = true
    private var lastLayoutWidth: CGFloat = -1

    /// Flag that the hosted header may have changed size (content or width), so it
    /// gets re-measured on the next layout pass instead of on every scroll tick.
    func markHeaderDirty() {
        headerDirty = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }

        if headerDirty || width != lastLayoutWidth {
            lastLayoutWidth = width
            headerDirty = false

            if let host = hostingController {
                let fitting = host.sizeThatFits(
                    in: CGSize(width: width, height: .greatestFiniteMagnitude)
                )
                let headerHeight = ceil(fitting.height)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
                // Reserve space so text starts below the header.
                if textContainerInset.top != headerHeight {
                    textContainerInset.top = headerHeight
                }
            }

            if let ph = placeholderLabel {
                let x = textContainerInset.left
                let y = textContainerInset.top
                let maxW = max(0, width - textContainerInset.left - textContainerInset.right)
                let size = ph.sizeThatFits(CGSize(width: maxW, height: .greatestFiniteMagnitude))
                ph.frame = CGRect(x: x, y: y, width: maxW, height: ceil(size.height))
            }
        }
    }
}
