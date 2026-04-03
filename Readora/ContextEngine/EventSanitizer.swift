import Foundation

struct EventSanitizer {

    /// Cleans raw LLM-extracted events by applying deterministic validation rules.
    /// - Parameters:
    ///   - events: Raw events from the LLM
    ///   - paragraphsByIndex: Lookup of all paragraph texts, keyed by absoluteIndex
    ///   - mainIndices: The set of absoluteIndex values that are "main" paragraphs in this chunk
    ///                  (i.e., NOT part of the prefix). Events must only reference these.
    static func sanitize(
        events: [ExtractedEvent],
        paragraphsByIndex: [Int: NarrativeParagraph],
        mainIndices: Set<Int>
    ) -> [ExtractedEvent] {

        return events.filter { event in

            // Rule 1: Range must be logically valid
            guard event.startParagraph <= event.endParagraph else {
                print(
                    "   ⚠️ Dropped event (inverted range): \(event.startParagraph)-\(event.endParagraph)"
                )
                return false
            }

            // Rule 2: Both paragraph indices must exist in the book
            guard paragraphsByIndex[event.startParagraph] != nil,
                paragraphsByIndex[event.endParagraph] != nil
            else {
                print(
                    "   ⚠️ Dropped event (unknown paragraph index): \(event.startParagraph)-\(event.endParagraph)"
                )
                return false
            }

            // Rule 3: Must only reference main paragraphs, not prefix
            guard mainIndices.contains(event.startParagraph),
                mainIndices.contains(event.endParagraph)
            else {
                print(
                    "   ⚠️ Dropped event (references prefix paragraph): \(event.startParagraph)-\(event.endParagraph)"
                )
                return false
            }

            // Rule 4: Summary must not be empty
            guard !event.summary.trimmingCharacters(in: .whitespaces).isEmpty else {
                print("   ⚠️ Dropped event (empty summary)")
                return false
            }

            return true
        }
    }
}
