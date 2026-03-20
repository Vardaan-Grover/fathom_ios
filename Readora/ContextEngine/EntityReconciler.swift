import Foundation
import GRDB

// A helper to decode the aliases from JSON stored in the DB
extension NarrativeEntity {
    var aliases: [String] {
        guard let data = aliasesJSON.data(using: .utf8),
        let arr = try?  JSONDecoder().decode([String].self, from: data) else { return [] }

        return arr
    }

    /// All known names for this entity - canonical name + all aliases lowercased
    var knownNamesLower: Set<String> {
        var names = Set<String>()
        names.insert(canonicalName.lowercased())
        for alias in aliases {
            names.insert(alias.lowercased())
        }
        return names
    }
}

actor EntityReconciler {
    /// Checks if two entities refer to the same real-world entity.
    /// They overlap if any of their known names (aliases + canonical) match.
    static func overlaps(_ a: NarrativeEntity, _ b: NarrativeEntity) -> Bool {
        return !a.knownNamesLower.isDisjoint(with: b.knownNamesLower)
    }

    /// Groups a flat list of entities into clusters of duplicates.
    /// Each inner array is a group of entities that all refer to the same thing.
    static func group(_ entities: [NarrativeEntity]) -> [[NarrativeEntity]] {
        var groups: [[NarrativeEntity]] = []

        for entity in entities {
            // Find the first existing group that this entity overlaps with
            if let index = groups.firstIndex(where: {group in 
                group.contains(where: {overlaps($0, entity)})
            }) {
                // Add to the group
                groups[index].append(entity)
            } else {
                // No match found - start a new group
                groups.append([entity])
            }
        }

        return groups
    }

    ///  Given a group of duplicate entities, picks the best canonical entity,
    /// merges all aliases together and returns:
    /// - the winning entity (with merged aliases and updated importanceScore)
    /// - the UUIDs of the losers to delete from the DB
    static func mergeGroup(_ group: [NarrativeEntity]) -> (winner: NarrativeEntity, losers: [UUID]) {
        guard !group.isEmpty else { fatalError("merge called with empty group") }

        // Pick the entity with the longest canonical name as the "winner"
        // eg: "Elizabeth Bennet" wins over "Elizabeth" or "Lizzy"
        var winner = group.max(by: { $0.canonicalName.count < $1.canonicalName.count })!
        let losers = group.filter { $0.id != winner.id }.map {
            $0.id
        }

        // Merge all aliases from the duplicates into one unique set
        var mergedAliases = Set<String>()
        for entity in group {
            for alias in entity.aliases {
                mergedAliases.insert(alias)
            }
        }

        // Don't include the canonical name itself as an alias
        mergedAliases.remove(winner.canonicalName)

        // Encode merged aliases back to JSON for storage
        let aliasesData = (try?
        JSONEncoder().encode(Array(mergedAliases))) ?? Data()
        winner.aliasesJSON = String(data: aliasesData, encoding: .utf8) ?? "[]"

        // Importance score = total mention count across ALL duplicates in this group
        winner.importanceScore = group.reduce(0) {
            $0 + $1.importanceScore
        }

        return (winner: winner, losers: losers)
    }
}