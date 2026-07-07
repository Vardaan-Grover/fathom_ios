import SwiftUI
import UIKit

/// A `UITextView`-backed editor that grows to fit its content (no internal scroll)
/// and asks its *enclosing* scroll view to keep the caret visible while typing.
///
/// This lets it live inside a SwiftUI `ScrollView` together with header content
/// (e.g. a cover + photo) so everything scrolls as one and the header scrolls away
/// naturally — true "Apple Notes" behavior — while the caret stays on screen.
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var font: UIFont
    var textColor: UIColor
    var tintColor: UIColor
    /// Extra space kept below the caret when scrolling it into view, so it clears
    /// the keyboard and any floating bottom bar.
    var caretBottomInset: CGFloat = 100

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        tv.isScrollEnabled = false          // grow to fit -> the outer ScrollView scrolls
        tv.backgroundColor = .clear
        tv.font = font
        tv.textColor = textColor
        tv.tintColor = tintColor
        // Report full content height to SwiftUI rather than compressing.
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.defaultLow, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        if tv.font != font { tv.font = font }
        tv.textColor = textColor
        tv.tintColor = tintColor

        // Bridge external focus changes to first-responder state. Only dispatch when
        // there's an actual mismatch, so we don't enqueue a no-op block per keystroke.
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: GrowingTextEditor
        weak var textView: UITextView?
        private var dismissTap: UITapGestureRecognizer?
        private var pendingScroll: DispatchWorkItem?
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            scrollCaretToVisible(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            scrollCaretToVisible(tv)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
            installDismissTapIfNeeded(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        // MARK: Tap-outside-to-dismiss

        /// Add a tap recognizer to the enclosing scroll view so tapping anywhere that
        /// isn't the text view dismisses the keyboard. `cancelsTouchesInView = false`
        /// and simultaneous recognition keep scrolling, buttons, and caret placement
        /// fully intact.
        private func installDismissTapIfNeeded(_ tv: UITextView) {
            guard dismissTap == nil, let scrollView = enclosingScrollView(tv) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(tap)
            dismissTap = tap
        }

        @objc private func handleDismissTap() {
            textView?.resignFirstResponder()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            // Ignore taps that land on the text view itself (let it place the caret).
            guard let tv = textView, let touched = touch.view else { return true }
            return !touched.isDescendant(of: tv)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Keep the caret visible within the enclosing scroll view (the one backing the
        /// surrounding SwiftUI `ScrollView`). Coalesced to a single adjustment per
        /// runloop, with all geometry read *after* layout settles, so rapid edits
        /// (e.g. holding return) don't fight SwiftUI's relayout or act on stale/bogus
        /// caret rects.
        private func scrollCaretToVisible(_ tv: UITextView) {
            // Collapse the didChange + didChangeSelection pair (and any burst) into one.
            pendingScroll?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv, tv.isFirstResponder,
                      let range = tv.selectedTextRange,
                      let scrollView = self.enclosingScrollView(tv) else { return }

                let caret = tv.caretRect(for: range.end)
                // Reject the transient bogus rects UITextView can emit mid-mutation.
                guard caret.minY.isFinite, caret.height.isFinite,
                      caret.height > 0, abs(caret.minY) < 1_000_000 else { return }

                let caretInScroll = tv.convert(caret, to: scrollView)
                let topInset = scrollView.adjustedContentInset.top
                let bottomInset = scrollView.adjustedContentInset.bottom
                let viewportHeight = scrollView.bounds.height
                let margin = self.parent.caretBottomInset

                let visibleTop = scrollView.contentOffset.y + topInset
                let visibleBottom = scrollView.contentOffset.y + viewportHeight - bottomInset

                var newY = scrollView.contentOffset.y
                if caretInScroll.maxY + margin > visibleBottom {
                    // Caret dropped below the comfortable zone: scroll down just enough.
                    newY = caretInScroll.maxY + margin - (viewportHeight - bottomInset)
                } else if caretInScroll.minY < visibleTop {
                    // Caret rose above the visible area: scroll up just enough.
                    newY = caretInScroll.minY - topInset
                } else {
                    return // Already comfortably visible — don't fight SwiftUI.
                }

                // Clamp to the scroll view's valid offset range.
                let maxY = max(-topInset, scrollView.contentSize.height + bottomInset - viewportHeight)
                newY = min(max(newY, -topInset), maxY)

                if abs(newY - scrollView.contentOffset.y) > 0.5 {
                    scrollView.setContentOffset(
                        CGPoint(x: scrollView.contentOffset.x, y: newY),
                        animated: false
                    )
                }
            }
            pendingScroll = work
            // Defer so SwiftUI's relayout from the edit (taller content) settles first.
            DispatchQueue.main.async(execute: work)
        }

        private func enclosingScrollView(_ view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let v = current {
                if let scroll = v as? UIScrollView { return scroll }
                current = v.superview
            }
            return nil
        }
    }
}

extension UIFont {
    /// Mirrors SwiftUI's `.system(size:weight:design: .serif)` (New York).
    static func serif(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}
