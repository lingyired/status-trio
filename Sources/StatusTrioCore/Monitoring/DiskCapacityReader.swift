import DiskArbitration
import Foundation

/// Reads capacity for the system volume and enumerates every mounted local
/// volume for the disk detail page, using the same `FileManager` volume keys as
/// the summary's `DiskCapacitySample`. Cheap enough to read only while the
/// detail page is visible; no polling is added.
enum DiskCapacityReader {
    static func read(at date: Date = Date()) -> DiskCapacityReading? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedFormatDescriptionKey
        ]), let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        let free = resolvedFreeBytes(importantUsage: values.volumeAvailableCapacityForImportantUsage,
                                     plainAvailable: values.volumeAvailableCapacity,
                                     totalBytes: UInt64(total))
        let totalBytes = UInt64(total)
        let used = totalBytes > free ? totalBytes - free : 0
        return DiskCapacityReading(totalBytes: totalBytes,
                                   freeBytes: free,
                                   usedBytes: used,
                                   fileSystem: values.volumeLocalizedFormatDescription,
                                   sampledAt: date)
    }

    /// Every mounted local volume, startup volume first, then the rest sorted by
    /// name. Network volumes are skipped by product decision, and any volume
    /// whose capacity cannot be read is omitted rather than shown as zero.
    static func readVolumes() -> [DiskVolumeReading] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        let keySet = Set(keys)
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var entries: [(reading: DiskVolumeReading, apfsContainer: String?)] = []
        var seenPaths = Set<String>()
        let session = DASessionCreate(kCFAllocatorDefault)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            // Skip network volumes (default product decision) and anything the
            // system does not consider a local disk.
            if values.volumeIsLocal == false { continue }
            guard let total = values.volumeTotalCapacity, total > 0 else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard seenPaths.insert(path).inserted else { continue }
            // Mounted disk images (DMG installers, sparse bundles) are virtual
            // volumes, not real disks; skip them. We cannot use "read-only" as a
            // proxy because a real external NTFS/exFAT disk also mounts read-only.
            if let session, isDiskImage(path: path, session: session) { continue }
            let totalBytes = UInt64(total)
            let free = resolvedFreeBytes(importantUsage: values.volumeAvailableCapacityForImportantUsage,
                                         plainAvailable: values.volumeAvailableCapacity,
                                         totalBytes: totalBytes)
            let reading = DiskVolumeReading(
                name: values.volumeName ?? url.lastPathComponent,
                mountPath: path,
                totalBytes: totalBytes,
                freeBytes: free,
                fileSystem: values.volumeLocalizedFormatDescription,
                isExternal: values.volumeIsInternal == false,
                isReadOnly: values.volumeIsReadOnly ?? false
            )
            entries.append((reading, apfsContainerID(for: path)))
        }

        let sorted = entries.sorted { lhs, rhs in
            let l = lhs.reading, r = rhs.reading
            if l.mountPath == "/" { return r.mountPath != "/" }
            if r.mountPath == "/" { return false }
            if l.isExternal != r.isExternal { return !l.isExternal }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }

        // Several APFS volumes in one container share a single capacity pool
        // (e.g. the startup "Macintosh HD" and another volume on the same
        // internal disk). List only the container's representative volume so the
        // same physical disk is not shown twice; partitions of non-APFS disks
        // keep their own independent capacity and are all listed.
        var seenContainers = Set<String>()
        var readings: [DiskVolumeReading] = []
        for entry in sorted {
            if let container = entry.apfsContainer,
               !seenContainers.insert(container).inserted { continue }
            readings.append(entry.reading)
        }
        return readings
    }

    /// External volumes only (USB/Thunderbolt), for the SSD ring's external
    /// total and the Settings picker. Already container-deduped by `readVolumes`.
    static func externalVolumes() -> [DiskVolumeReading] {
        readVolumes().filter { $0.isExternal }
    }

    /// Whether a mounted volume is a disk image (DMG / sparse bundle) rather
    /// than a physical disk. DiskArbitration reports these as a virtual
    /// interface with the model "Disk Image" and the media name "disk image".
    static func isDiskImage(path: String) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return false }
        return isDiskImage(path: path, session: session)
    }

    private static func isDiskImage(path: String, session: DASession) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else {
            return false
        }
        let model = description[kDADiskDescriptionDeviceModelKey as String] as? String
        let protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let mediaName = description[kDADiskDescriptionMediaNameKey as String] as? String
        return model == "Disk Image"
            || protocolName == "Virtual Interface"
            || mediaName == "disk image"
    }

    /// The APFS container identifier (e.g. `disk3`) shared by every volume of
    /// that container, or `nil` for non-APFS volumes. Derived from the mount's
    /// `/dev/diskNsM` device name and its file-system type via `statfs`.
    static func apfsContainerID(for path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        let fileSystemType = withUnsafePointer(to: &stats.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        guard fileSystemType == "apfs" else { return nil }
        let device = withUnsafePointer(to: &stats.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let name = (device as NSString).lastPathComponent
        guard let range = name.range(of: "^disk[0-9]+", options: .regularExpression) else { return nil }
        return String(name[range])
    }

    /// `volumeAvailableCapacityForImportantUsage` reports `0` (not `nil`) on a
    /// read-only NTFS/exFAT mount, so it must only be trusted when positive;
    /// otherwise fall back to `volumeAvailableCapacity` (which is correct for
    /// those volumes), and finally to zero. Clamped to the total.
    static func resolvedFreeBytes(importantUsage: Int64?,
                                  plainAvailable: Int?,
                                  totalBytes: UInt64) -> UInt64 {
        let important = UInt64(max(0, importantUsage ?? 0))
        let plain = UInt64(max(0, plainAvailable ?? 0))
        let best = important > 0 ? important : plain
        return min(best, totalBytes)
    }
}
