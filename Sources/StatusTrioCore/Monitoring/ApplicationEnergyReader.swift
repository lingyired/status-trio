import Darwin
import Foundation

struct ApplicationEnergyReader: Sendable {
    /// Same-user processes only. Permission failures and exited processes are
    /// omitted; never launch powermetrics, ask for root, or read process content.
    func read(applications: [EnergyApplication]) -> ApplicationEnergySnapshot {
        let readAt = ProcessInfo.processInfo.systemUptime
        guard !applications.isEmpty else { return ApplicationEnergySnapshot(readAt: readAt, processes: []) }
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard bytes > 0 else { return ApplicationEnergySnapshot(readAt: readAt, processes: []) }
        let capacity = min(Int(bytes) / MemoryLayout<pid_t>.stride + 64, 16_384)
        var pids = [pid_t](repeating: 0, count: capacity)
        let returned = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        var processes: [ProcessEnergySample] = []
        for pid in pids.prefix(max(0, min(Int(returned) / MemoryLayout<pid_t>.stride, capacity))) where pid > 0 {
            // PROC_PIDPATHINFO_MAXSIZE is a C expression macro not imported by
            // Swift; the SDK defines it as 4 * MAXPATHLEN (4096 bytes).
            var path = [CChar](repeating: 0, count: 4_096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let app = Self.application(for: executable, applications: applications) else { continue }
            var usage = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            if status == 0 {
                processes.append(ProcessEnergySample(pid: pid, startedAt: usage.ri_proc_start_abstime,
                    app: app, cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
                    energyNanojoules: usage.ri_energy_nj > 0 ? usage.ri_energy_nj : nil))
            } else {
                // Older macOS kernels may not implement flavor 6. Flavor 4
                // supplies CPU time, explicitly presented as an activity proxy.
                var fallback = rusage_info_v4()
                let result = withUnsafeMutablePointer(to: &fallback) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                    }
                }
                if result == 0 {
                    processes.append(ProcessEnergySample(pid: pid, startedAt: fallback.ri_proc_start_abstime,
                        app: app, cpuNanoseconds: fallback.ri_user_time &+ fallback.ri_system_time,
                        energyNanojoules: nil))
                }
            }
        }
        return ApplicationEnergySnapshot(readAt: readAt, processes: processes)
    }

    static func application(for executable: String, applications: [EnergyApplication]) -> EnergyApplication? {
        // Outer app bundles own nested helper bundles. A slash prevents an app
        // path from accidentally matching a similarly named sibling bundle.
        applications.filter { executable.hasPrefix($0.id + "/") }
            .min { $0.id.count < $1.id.count }
    }
}
