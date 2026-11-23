import Foundation

/// Reads capacity for the system volume for the disk detail page, using the same
/// FileManager volume keys as the summary's `DiskCapacitySample`. Cheap enough
/// to read only while the detail page is visible; no polling is added.
enum DiskCapacityReader {
    static func read(at date: Date = Date()) -> DiskCapacityReading? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedFormatDescriptionKey
        ]), let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        let totalBytes = UInt64(total)
        let used = totalBytes > free ? totalBytes - free : 0
        return DiskCapacityReading(totalBytes: totalBytes,
                                   freeBytes: free,
                                   usedBytes: used,
                                   fileSystem: values.volumeLocalizedFormatDescription,
                                   sampledAt: date)
    }
}
