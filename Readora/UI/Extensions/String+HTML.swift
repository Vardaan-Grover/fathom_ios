import SwiftUI
import UIKit

extension String {
    func asHTMLAttributedString() -> AttributedString {
        // Ensure paragraphs are visibly separated and line breaks are double-spaced
        let processedText =
            self
            .replacingOccurrences(of: "<br>", with: "<br><br>", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "<br><br>", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "<br><br>", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "</p><br>", options: .caseInsensitive)

        // Appending a default system font family so that NSAttributedString doesn't fallback to Times.
        let styledHTML = """
            <style>
                body { font-family: '-apple-system', 'San Francisco', 'Helvetica Neue', Helvetica, sans-serif; font-size: 16px; }
                strong, b { font-weight: 500; }
            </style>
            <body>\(processedText)</body>
            """

        guard let data = styledHTML.data(using: .utf8) else {
            return AttributedString(self)
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        if let nsAttrString = try? NSMutableAttributedString(
            data: data, options: options, documentAttributes: nil)
        {
            // Remove foreground color to allow SwiftUI's .foregroundColor() to take effect natively
            nsAttrString.removeAttribute(
                .foregroundColor, range: NSRange(location: 0, length: nsAttrString.length))

            // Trim trailing newlines
            let str = nsAttrString.mutableString
            while str.hasSuffix("\n") {
                str.deleteCharacters(in: NSRange(location: str.length - 1, length: 1))
            }

            if let attrString = try? AttributedString(nsAttrString, including: \.uiKit) {
                return attrString
            }
        }
        return AttributedString(self)
    }
}
