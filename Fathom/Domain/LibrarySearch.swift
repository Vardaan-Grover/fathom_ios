import Foundation

/// Translates what the user typed into an FTS5 MATCH expression.
///
/// Kept free of GRDB and UIKit so the query grammar — the part that is easy to
/// get subtly wrong and impossible to eyeball — can be unit tested directly.
enum LibrarySearch {

    /// Column weights for `bm25()`. A hit in the title should always outrank a
    /// hit in a long description, which bm25 would otherwise favour whenever
    /// the description happened to repeat the term.
    static let titleWeight = 10.0
    static let authorWeight = 5.0
    static let descriptionWeight = 1.0

    /// Builds the MATCH expression for `query`, or nil when there is nothing
    /// searchable in it.
    ///
    /// Every token is prefix-matched and combined with implicit AND, so "clear
    /// atom" finds *Atomic Habits* by James Clear — tokens may match different
    /// columns, and the user is mid-word on the last one by definition.
    ///
    /// Returns nil rather than an empty string for an empty or punctuation-only
    /// query: FTS5 treats "" as a syntax error, and callers should skip the
    /// index entirely and show the full library instead.
    static func matchExpression(for query: String) -> String? {
        let tokens = self.tokens(in: query)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// Splits `query` into FTS-safe tokens.
    ///
    /// Anything that isn't alphanumeric becomes a separator. This is a
    /// deliberate superset of FTS5's own quoting rules: rather than escaping
    /// the operators (`"`, `*`, `^`, `:`, `-`, `NEAR`, parentheses) we discard
    /// characters that can't survive inside a quoted string, which makes it
    /// impossible for typed punctuation to be parsed as query syntax. A
    /// trailing `*` is then appended by the caller, outside the quotes, where
    /// it does mean "prefix".
    ///
    /// Diacritics are deliberately left alone — the index is tokenized with
    /// `remove_diacritics 2`, so FTS5 folds both sides of the comparison.
    static func tokens(in query: String) -> [String] {
        query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
