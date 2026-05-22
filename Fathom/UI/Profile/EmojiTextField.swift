import SwiftUI
import UIKit

// MARK: - EmojiTextField (UIKit)
//
// A UITextField subclass that forces the emoji keyboard to appear when
// focused. There is no public SwiftUI API for this — overriding
// `textInputMode` is the standard workaround.

final class EmojiTextFieldUIKit: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes
        where mode.primaryLanguage == "emoji" {
            return mode
        }
        return super.textInputMode
    }
}

// MARK: - SwiftUI wrapper

struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    /// Bump this value to re-focus the field (re-opens the keyboard).
    var focusTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> EmojiTextFieldUIKit {
        let tf = EmojiTextFieldUIKit()
        tf.delegate = context.coordinator
        tf.textAlignment = .center
        tf.tintColor = .clear
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        tf.text = text
        DispatchQueue.main.async { tf.becomeFirstResponder() }
        return tf
    }

    func updateUIView(_ uiView: EmojiTextFieldUIKit, context: Context) {
        if uiView.text != text { uiView.text = text }

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                if uiView.window != nil { uiView.becomeFirstResponder() }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var lastFocusTrigger: Int = 0

        init(text: Binding<String>) {
            self._text = text
        }

        // Replace existing content with the most recent emoji so the user
        // always sees a single character avatar.
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                text = ""
                textField.text = ""
                return false
            }
            if let lastChar = string.last {
                let single = String(lastChar)
                text = single
                textField.text = single
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
