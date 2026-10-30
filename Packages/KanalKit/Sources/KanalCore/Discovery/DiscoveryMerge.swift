import Foundation

/// Folds several ranked rows into one.
public enum DiscoveryMerge {

    /// Takes each row's best pick in turn, so no one service crowds the
    /// others out, and drops anything already taken.
    public static func roundRobin<Item, ID: Hashable>(
        _ rows: [[Item]], id: KeyPath<Item, ID>, limit: Int = 24
    ) -> [Item] {
        var merged: [Item] = []
        var seen = Set<ID>()
        let longest = rows.map(\.count).max() ?? 0
        for index in 0..<longest {
            for row in rows where index < row.count {
                let item = row[index]
                if seen.insert(item[keyPath: id]).inserted { merged.append(item) }
                if merged.count == limit { return merged }
            }
        }
        return merged
    }
}
