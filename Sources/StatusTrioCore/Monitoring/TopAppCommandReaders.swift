// Collection strategy adapted from Stats (MIT License):
// https://github.com/exelban/stats

import Darwin
import Foundation

/// One bounded command run for a top-application reader. Abstracted so parser
/// and ranking tests never launch a real ps/top/nettop.
protocol TopAppCommandExecuting: Sendable {
    func run(executableURL: URL, arguments: [String]) async -> Result<Data, TopAppReadError>
}

struct SystemTopAppCommandExecutor: TopAppCommandExecuting {
    static let outputLimit = 8_388_608
    static let timeout: Duration = .seconds(5)

    func run(executableURL: URL, arguments: [String]) async -> Result<Data, TopAppReadError> {
        let outcome = await BoundedProcessInvocation.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: Self.timeout,
            environment: ["LC_ALL": "C", "LANG": "C"],
            outputLimit: Self.outputLimit
        )
        switch outcome {
        case .exited(let data):
            return .success(data)
        case .timedOut:
            return .failure(.timedOut)
        case .cancelled:
            return .failure(.cancelled)
        case .failed:
            return .failure(.launchOrExit)
        case .outputTooLarge:
            return .failure(.outputTooLarge)
        }
    }
}

/// Reads the identity metadata needed to group a PID without reading what the
/// process is doing. Start time protects cumulative counters from PID reuse.
protocol ProcessMetadataReading: Sendable {
    func metadata(for pid: Int32, fallbackName: String) -> ProcessMetadata?
}

struct SystemProcessMetadataReader: ProcessMetadataReading {
    private typealias ResponsiblePIDFunction = @convention(c) (Int32) -> Int32

    private static let responsibleFunction: ResponsiblePIDFunction? = {
        guard let handle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    func metadata(for pid: Int32, fallbackName: String) -> ProcessMetadata? {
        guard pid > 0 else { return nil }
        let name = Self.name(for: pid) ?? fallbackName
        return ProcessMetadata(
            identity: ProcessIdentity(pid: pid, startedAt: Self.startTime(for: pid)),
            name: name.isEmpty ? fallbackName : name,
            executablePath: Self.executablePath(for: pid),
            responsiblePID: Self.responsiblePID(for: pid)
        )
    }

    static func startTime(for pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard read == Int32(size) else { return nil }
        let seconds = UInt64(info.pbi_start_tvsec)
        let microseconds = UInt64(info.pbi_start_tvusec)
        let value = seconds &* 1_000_000_000 &+ microseconds &* 1_000
        return value == 0 ? nil : value
    }

    static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func name(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func responsiblePID(for pid: Int32) -> Int32? {
        guard let function = responsibleFunction else { return nil }
        let value = function(pid)
        return value > 0 ? value : nil
    }
}

struct PSProcessRow: Equatable, Sendable {
    let pid: Int32
    let cpuPercent: Double
    let name: String
}

enum TopAppPSParser {
    static func parse(_ data: Data) -> Result<[PSProcessRow], TopAppReadError> {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { line in
            let upper = line.uppercased()
            return upper.contains("PID") && upper.contains("%CPU") && upper.contains("COMM")
        }) else {
            return .failure(.malformedOutput)
        }

        var rows: [PSProcessRow] = []
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let fields = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]) else { continue }
            let name = String(fields[2]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            rows.append(PSProcessRow(pid: pid, cpuPercent: cpu, name: name))
        }
        guard !rows.isEmpty else { return .failure(.malformedOutput) }
        return .success(rows)
    }
}

struct TopProcessRow: Equatable, Sendable {
    let pid: Int32
    let name: String
    let memoryBytes: Double
}

enum TopAppTopParser {
    static func parse(_ data: Data) -> Result<[TopProcessRow], TopAppReadError> {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { line in
            let upper = line.uppercased()
            return upper.contains("PID") && upper.contains("COMMAND") && upper.contains("MEM")
        }) else {
            return .failure(.malformedOutput)
        }

        var rows: [TopProcessRow] = []
        var sawDataLine = false
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            sawDataLine = true
            guard let row = parseRow(trimmed) else { continue }
            rows.append(row)
        }
        if sawDataLine && rows.isEmpty { return .failure(.malformedOutput) }
        return .success(rows)
    }

    private static func parseRow(_ line: String) -> TopProcessRow? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        let pidStart = index
        while index < characters.count, characters[index].isNumber { index += 1 }
        guard index > pidStart, let pid = Int32(String(characters[pidStart..<index])) else { return nil }
        guard index < characters.count, characters[index].isWhitespace else { return nil }
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        let commandStart = index
        var scan = characters.count - 1
        while scan >= commandStart, characters[scan].isWhitespace { scan -= 1 }
        guard scan >= commandStart else { return nil }
        let tokenEnd = scan + 1
        var tokenStart = scan
        while tokenStart >= commandStart, !characters[tokenStart].isWhitespace { tokenStart -= 1 }
        let memoryToken = String(characters[(tokenStart + 1)..<tokenEnd])
        guard let memory = memoryBytes(memoryToken) else { return nil }
        while tokenStart >= commandStart, characters[tokenStart].isWhitespace { tokenStart -= 1 }
        guard tokenStart >= commandStart else { return nil }
        let command = String(characters[commandStart...tokenStart]).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        return TopProcessRow(pid: pid, name: command, memoryBytes: memory)
    }

    static func memoryBytes(_ token: String) -> Double? {
        var text = token.trimmingCharacters(in: .whitespaces)
        while let last = text.last, last == "+" || last == "-" { text.removeLast() }
        guard !text.isEmpty else { return nil }
        let suffix = text.last?.uppercased() ?? ""
        let multiplier: Double
        switch suffix {
        case "B": multiplier = 1
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        case "P": multiplier = 1024 * 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        if ["B", "K", "M", "G", "T", "P"].contains(suffix) { text.removeLast() }
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value * multiplier
    }
}

struct TopAppCPUReader: Sendable {
    let executor: any TopAppCommandExecuting
    let metadataReader: any ProcessMetadataReading

    init(executor: any TopAppCommandExecuting = SystemTopAppCommandExecutor(),
         metadataReader: any ProcessMetadataReading = SystemProcessMetadataReader()) {
        self.executor = executor
        self.metadataReader = metadataReader
    }

    func read() async -> Result<[ProcessUsageSample], TopAppReadError> {
        let result = await executor.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-Aceo", "pid,pcpu,comm", "-r"]
        )
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            switch TopAppPSParser.parse(data) {
            case .failure(let error):
                return .failure(error)
            case .success(let rows):
                let samples = rows.compactMap { row -> ProcessUsageSample? in
                    guard let metadata = metadataReader.metadata(for: row.pid, fallbackName: row.name) else {
                        return nil
                    }
                    return ProcessUsageSample(metadata: metadata, value: row.cpuPercent)
                }
                return samples.isEmpty ? .failure(.malformedOutput) : .success(samples)
            }
        }
    }
}

struct TopAppMemoryReader: Sendable {
    let executor: any TopAppCommandExecuting
    let metadataReader: any ProcessMetadataReading

    init(executor: any TopAppCommandExecuting = SystemTopAppCommandExecutor(),
         metadataReader: any ProcessMetadataReading = SystemProcessMetadataReader()) {
        self.executor = executor
        self.metadataReader = metadataReader
    }

    func read() async -> Result<[ProcessUsageSample], TopAppReadError> {
        let result = await executor.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/top"),
            arguments: ["-l", "1", "-o", "mem", "-stats", "pid,command,mem"]
        )
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            switch TopAppTopParser.parse(data) {
            case .failure(let error):
                return .failure(error)
            case .success(let rows):
                let samples = rows.compactMap { row -> ProcessUsageSample? in
                    guard row.memoryBytes > 0,
                          let metadata = metadataReader.metadata(for: row.pid, fallbackName: row.name) else {
                        return nil
                    }
                    return ProcessUsageSample(metadata: metadata, value: row.memoryBytes)
                }
                return .success(samples)
            }
        }
    }
}
