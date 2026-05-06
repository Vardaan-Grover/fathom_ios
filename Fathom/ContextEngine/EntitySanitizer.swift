import Foundation

actor EntitySanitizer {

    // MARK: - Constants

    /// Pronouns that should never be valid entity mentions.
    private static let pronouns: Set<String> = [
        "he", "she", "him", "her", "his", "hers",
        "they", "them", "their", "theirs", "it", "its"
    ]

    /// Minimum confidence score for a mention to be kept.
    private static let minimumConfidence: Double = 0.8

    /// Applies all 5 sanitization rules to the raw LLM output.
    /// - Parameters:
    ///   - entities: The raw array of entities returned by the LLM.
    ///   - paragraphsByIndex: A lookup dictionary mapping absoluteIndex → NarrativeParagraph,
    ///     used to verify that surface forms actually exist in the cited paragraph text.
    /// - Returns: A cleaned array of entities with invalid mentions removed.
    static func sanitize(
        entities: [ExtractedEntity],
        paragraphsByIndex: [Int: NarrativeParagraph]
    ) -> [ExtractedEntity] {

        // Process each entity independently
        var cleaned = entities.map { entity -> ExtractedEntity in

            // Per-entity deduplication set: tracks (absoluteIndex, surfaceForm) pairs
            // so the same mention isn't counted twice within the same entity.
            var seen = Set<String>()

            let cleanedMentions = entity.paragraphMentions.filter { mention in
                // Trim whitespace first — LLMs often add trailing spaces
                let trimmed = mention.surfaceForm.trimmingCharacters(in: .whitespaces)

                // Rule 1: Pronoun removal
                // Pronouns are never valid named entity mentions.
                guard !pronouns.contains(trimmed.lowercased()) else { return false }

                // Rule 2: Confidence filter
                // Drop anything below 0.7 — these are ambiguous or incorrect mappings.
                guard mention.confidence >= minimumConfidence else { return false }

                // Rule 3: Surface form must exist verbatim in the paragraph text
                // This is the ground truth check: if the exact string isn't there, the LLM hallucinated it.
                guard let paragraph = paragraphsByIndex[mention.absoluteIndex] else { return false }
                guard paragraph.text.contains(trimmed) else { return false }

                // Rule 4: Deduplication within this entity
                // Key = "paragraphIndex-surfaceForm", e.g. "42-Miss Bennet"
                let key = "\(mention.absoluteIndex)-\(trimmed)"
                guard seen.insert(key).inserted else { return false }

                return true
            }

            let cleanedAliases = entity.aliases.filter {
                !$0.hasSuffix("'s") && !$0.hasSuffix("\u{2019}s")
            }

            // Return a new entity with the cleaned mentions (and trimmed surface forms)
            return ExtractedEntity(
                name: entity.name,
                type: entity.type,
                aliases: cleanedAliases,
                paragraphMentions: cleanedMentions.map { mention in
                    ExtractedMention(
                        absoluteIndex: mention.absoluteIndex,
                        surfaceForm: mention.surfaceForm.trimmingCharacters(in: .whitespaces),
                        confidence: mention.confidence
                    )
                }
            )
        }

        // Rule 5: Entity purity check
        // After all of the above, if an entity has no valid mentions remaining, drop it entirely.
        // It was likely hallucinated or only referenced via pronouns.
        cleaned = cleaned.filter { !$0.paragraphMentions.isEmpty }

        return cleaned
    }

    /// Given a surface form and the text of its paragraph, finds all occurrences
    /// and returns their character offsets as (charStart, charEnd) pairs.
    ///
    /// We return ALL occurrences because the same name might appear several times
    /// in one paragraph, and we want to highlight each instance in the reader.
    ///
    /// We use NSRange (UTF-16 offsets) rather than Swift String.Index because
    /// NSAttributedString — which powers text rendering — uses UTF-16 internally.
    ///
    /// - Parameters:
    ///   - surfaceForm: The exact text to search for (e.g., "Miss Bennet").
    ///   - paragraphText: The full text of the paragraph.
    /// - Returns: An array of (charStart, charEnd) tuples, one per occurrence.
    static func resolveOffsets(
        for surfaceForm: String,
        in paragraphText: String
    ) -> [(charStart: Int, charEnd: Int)] {

        let trimmed = surfaceForm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var results: [(Int, Int)] = []
        var searchRange = paragraphText.startIndex..<paragraphText.endIndex

        // Walk through the string finding each occurrence of the surface form.
        // After each find, move the search start forward past that match
        // so we don't get stuck in an infinite loop on repeated text.
        while let range = paragraphText.range(of: trimmed, options: .literal, range: searchRange) {
            // Convert Swift String.Range → NSRange (UTF-16 offsets)
            let nsRange = NSRange(range, in: paragraphText)
            results.append((nsRange.location, nsRange.location + nsRange.length))

            // Advance the search window past this match
            searchRange = range.upperBound..<paragraphText.endIndex
        }

        return results
    }
}