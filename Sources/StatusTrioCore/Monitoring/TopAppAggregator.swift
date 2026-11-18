import Foundation

/// Groups process samples by application before ranking, then takes the top N.
///
/// Grouping happens before the cut: an application with several helpers that
/// are individually outside the visible cut can still be the busiest application.
enum TopAppAggregator {
    static func rows(metric: TopAppMetric,
                     samples: [ProcessUsageSample],
                     applications: [ProcessApplication],
                     limit: Int = 8) -> [TopAppRow] {
        guard limit > 0 else { return [] }

        var accumulated: [TopAppIdentity: AccumulatedRow] = [:]
        for sample in samples {
            guard sample.value.isFinite, sample.value >= 0 else { continue }
            let upload = max(0, sample.upload ?? 0)
            if metric == .network {
                guard sample.value > 0 || upload > 0 else { continue }
            } else {
                guard sample.value > 0 else { continue }
            }

            let resolution = ProcessAppResolver.resolve(sample.metadata, applications: applications)
            var row = accumulated[resolution.identity] ?? AccumulatedRow(
                name: resolution.name,
                applicationPath: resolution.applicationPath,
                value: 0,
                upload: 0
            )
            row.value += sample.value
            row.upload += upload
            if let path = resolution.applicationPath {
                row.applicationPath = path
                row.name = resolution.name
            }
            accumulated[resolution.identity] = row
        }

        let ranked = accumulated.map { identity, row in
            (identity: identity, row: row)
        }.sorted { left, right in
            if metric == .network {
                let leftBusiest = max(left.row.value, left.row.upload)
                let rightBusiest = max(right.row.value, right.row.upload)
                if leftBusiest != rightBusiest { return leftBusiest > rightBusiest }
                let leftQuieter = min(left.row.value, left.row.upload)
                let rightQuieter = min(right.row.value, right.row.upload)
                if leftQuieter != rightQuieter { return leftQuieter > rightQuieter }
            } else if left.row.value != right.row.value {
                return left.row.value > right.row.value
            }
            return left.identity.stableKey < right.identity.stableKey
        }

        return ranked.prefix(limit).map { entry in
            TopAppRow(
                id: entry.identity,
                name: entry.row.name,
                applicationPath: entry.row.applicationPath,
                value: entry.row.value,
                upload: metric == .network ? entry.row.upload : nil
            )
        }
    }

    private struct AccumulatedRow {
        var name: String
        var applicationPath: String?
        var value: Double
        var upload: Double
    }
}
