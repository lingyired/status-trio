import Foundation

/// Pure ranking used by the top-application list. Every refresh re-sorts by the
/// current value so a row moves when its usage changes and a newly seen busy app
/// lands in the right place; the merge step only preserves/fills rows and never
/// freezes the order.
enum TopAppRanking {
    /// Rank rows by their current value, descending.
    ///
    /// - Non-network metrics rank by `value`.
    /// - Network rows rank by the busiest of download/upload, then by the quieter
    ///   direction, matching the values shown in the network columns.
    /// - Ties break on `id.stableKey` so equal values keep a stable order.
    static func sorted(_ rows: [TopAppRow], metric: TopAppMetric) -> [TopAppRow] {
        rows.sorted { left, right in
            if metric == .network {
                let leftBusiest = max(left.value, left.upload ?? 0)
                let rightBusiest = max(right.value, right.upload ?? 0)
                if leftBusiest != rightBusiest { return leftBusiest > rightBusiest }
                let leftQuieter = min(left.value, left.upload ?? 0)
                let rightQuieter = min(right.value, right.upload ?? 0)
                if leftQuieter != rightQuieter { return leftQuieter > rightQuieter }
            } else if left.value != right.value {
                return left.value > right.value
            }
            return left.id.stableKey < right.id.stableKey
        }
    }
}
