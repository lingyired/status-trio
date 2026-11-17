// Collection strategy adapted from Stats (MIT License):
// https://github.com/exelban/stats

import Foundation

struct NetworkProcessCounter: Equatable, Sendable {
    let metadata: ProcessMetadata
    let received: UInt64
    let sent: UInt64
}

/// Turns cumulative per-PID network counters into bytes/second and groups them
/// by process identity. A PID whose start time changed is a different process.
struct NetworkAppUsageTracker: Sendable {
    private struct Baseline: Sendable {
        let identity: ProcessIdentity
        let received: UInt64
        let sent: UInt64
    }

    private var baselines: [Int32: Baseline] = [:]
    private var timestamp: UInt64?

    mutating func reset() {
        baselines.removeAll()
        timestamp = nil
    }

    /// Returns nil when this sample only establishes a baseline. `elapsed` is
    /// the real monotonic interval, never an assumed one-second tick.
    mutating func sample(_ counters: [NetworkProcessCounter],
                         at uptimeNanoseconds: UInt64) -> [ProcessUsageSample]? {
        let previous = baselines
        let previousTimestamp = timestamp

        var next: [Int32: Baseline] = [:]
        for counter in counters {
            guard counter.metadata.identity.isStable else { continue }
            next[counter.metadata.identity.pid] = Baseline(
                identity: counter.metadata.identity,
                received: counter.received,
                sent: counter.sent
            )
        }
        baselines = next
        timestamp = uptimeNanoseconds

        guard let previousTimestamp,
              uptimeNanoseconds > previousTimestamp else {
            return nil
        }
        let elapsedNanoseconds = uptimeNanoseconds - previousTimestamp
        // A sleep, a stalled window, or a debugger pause makes the average over
        // the gap meaningless; reprime rather than showing a spike.
        guard elapsedNanoseconds <= 3_000_000_000 else { return nil }

        var samples: [ProcessUsageSample] = []
        for counter in counters {
            guard counter.metadata.identity.isStable,
                  let baseline = previous[counter.metadata.identity.pid],
                  baseline.identity == counter.metadata.identity,
                  counter.received >= baseline.received,
                  counter.sent >= baseline.sent else { continue }
            let seconds = Double(elapsedNanoseconds) / 1_000_000_000
            guard seconds > 0 else { continue }
            let download = Double(counter.received - baseline.received) / seconds
            let upload = Double(counter.sent - baseline.sent) / seconds
            samples.append(ProcessUsageSample(metadata: counter.metadata,
                                              value: download,
                                              upload: upload))
        }
        return samples
    }
}

struct RawNetworkProcessRow: Equatable, Sendable {
    let pid: Int32
    let name: String
    let received: UInt64
    let sent: UInt64
}

enum TopAppNetworkParser {
    static func parse(_ data: Data) -> Result<[RawNetworkProcessRow], TopAppReadError> {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { $0.contains("bytes_in") && $0.contains("bytes_out") }) else {
            return .failure(.malformedOutput)
        }
        let header = csvFields(lines[headerIndex])
        guard let receivedColumn = header.firstIndex(of: "bytes_in"),
              let sentColumn = header.firstIndex(of: "bytes_out") else {
            return .failure(.malformedOutput)
        }

        var rows: [RawNetworkProcessRow] = []
        for line in lines[(headerIndex + 1)...] {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let fields = csvFields(line)
            guard fields.count > max(receivedColumn, sentColumn) else { continue }
            let process = fields[0]
            guard let dot = process.lastIndex(of: "."),
                  let pid = Int32(process[process.index(after: dot)...]) else { continue }
            let name = String(process[..<dot])
            guard !name.isEmpty,
                  let received = UInt64(fields[receivedColumn].trimmingCharacters(in: .whitespaces)),
                  let sent = UInt64(fields[sentColumn].trimmingCharacters(in: .whitespaces)) else { continue }
            rows.append(RawNetworkProcessRow(pid: pid, name: name, received: received, sent: sent))
        }
        return .success(rows)
    }

    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if insideQuotes {
                if character == "\"" {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = next
                    } else {
                        insideQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                insideQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}

struct TopAppNetworkReader: Sendable {
    let executor: any TopAppCommandExecuting
    let metadataReader: any ProcessMetadataReading

    init(executor: any TopAppCommandExecuting = SystemTopAppCommandExecutor(),
         metadataReader: any ProcessMetadataReading = SystemProcessMetadataReader()) {
        self.executor = executor
        self.metadataReader = metadataReader
    }

    func read() async -> Result<[NetworkProcessCounter], TopAppReadError> {
        let result = await executor.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/nettop"),
            arguments: ["-P", "-L", "1", "-n", "-J", "bytes_in,bytes_out"]
        )
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            switch TopAppNetworkParser.parse(data) {
            case .failure(let error):
                return .failure(error)
            case .success(let rows):
                let counters = rows.compactMap { row -> NetworkProcessCounter? in
                    guard let metadata = metadataReader.metadata(for: row.pid, fallbackName: row.name) else {
                        return nil
                    }
                    return NetworkProcessCounter(metadata: metadata, received: row.received, sent: row.sent)
                }
                return .success(counters)
            }
        }
    }
}
