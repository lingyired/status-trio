import Testing
@testable import StatusTrioCore

struct AppleBluetoothAudioDiagnosticsTests {
    @Test("Bluetooth diagnostics keep unknown Apple audio metadata only")
    func bluetoothDiagnosticFilteringAndFields() throws {
        let record = try #require(AppleBluetoothAudioDiagnosticRecord.bluetooth(
            name: "My Earbuds",
            address: "AA:BB:CC:DD:EE:FF",
            kind: .audio,
            vendorID: 0x004C,
            productID: 0x2042,
            majorType: "Audio",
            minorType: "Headphones"
        ))

        #expect(record.source == .bluetooth)
        #expect(record.name == "My Earbuds")
        #expect(record.address == "AA:BB:CC:DD:EE:FF")
        #expect(record.vendorID == 0x004C)
        #expect(record.productID == 0x2042)
        #expect(record.majorType == "Audio")
        #expect(record.minorType == "Headphones")
        #expect(record.modelUID == nil)
        #expect(record.deviceUID == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.bluetooth(
            name: "Unknown device",
            address: "AA:BB:CC:DD:EE:FF",
            kind: .audio,
            vendorID: 0x004C,
            productID: 0,
            majorType: nil,
            minorType: nil
        ) == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.bluetooth(
            name: "Known AirPods",
            address: "AA:BB:CC:DD:EE:FF",
            kind: .audio,
            vendorID: 0x004C,
            productID: 0x2030,
            majorType: nil,
            minorType: nil
        ) == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.bluetooth(
            name: "Unknown device",
            address: "AA:BB:CC:DD:EE:FF",
            kind: .audio,
            vendorID: 0x1234,
            productID: 0x2042,
            majorType: nil,
            minorType: nil
        ) == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.bluetooth(
            name: "Unknown device",
            address: "AA:BB:CC:DD:EE:FF",
            kind: .peripheral(.keyboard),
            vendorID: 0x004C,
            productID: 0x2042,
            majorType: nil,
            minorType: nil
        ) == nil)
    }

    @Test("CoreAudio diagnostics use only a Bluetooth model UID")
    func coreAudioDiagnosticFieldsAndTransportFilter() throws {
        let record = try #require(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "My Earbuds",
            transport: .bluetooth,
            modelUID: "2042 4c"
        ))

        #expect(record.source == .coreAudio)
        #expect(record.name == "My Earbuds")
        #expect(record.address == nil)
        #expect(record.vendorID == 0x004C)
        #expect(record.productID == 0x2042)
        #expect(record.majorType == nil)
        #expect(record.minorType == nil)
        #expect(record.modelUID == "2042 4c")
        #expect(record.deviceUID == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "Unknown headphones",
            transport: .bluetooth,
            modelUID: "0 4c"
        ) == nil)
        #expect(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "USB headphones",
            transport: .usb,
            modelUID: "2042 4c"
        ) == nil)
    }

    @Test("Diagnostic reporters deduplicate and evict the oldest fingerprint")
    func deduplicationAndFIFOEviction() throws {
        let reporter = AppleBluetoothAudioDiagnosticReporter()
        let first = try record(productID: 0x3000)
        #expect(reporter.report(first))
        #expect(!reporter.report(first))
        #expect(reporter.retainedFingerprintCount == 1)

        for productID in 0x3001...0x3080 {
            #expect(reporter.report(try record(productID: productID)))
        }

        #expect(reporter.retainedFingerprintCount == AppleBluetoothAudioDiagnosticReporter.capacity)
        #expect(reporter.report(first), "the first entry was evicted when the FIFO reached capacity")
        #expect(reporter.retainedFingerprintCount == AppleBluetoothAudioDiagnosticReporter.capacity)
    }

    @Test("CoreAudio device UIDs distinguish devices with the same model UID")
    func coreAudioDeviceIdentityDoesNotCollapseSameModel() throws {
        let reporter = AppleBluetoothAudioDiagnosticReporter()
        let first = try #require(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "My Earbuds",
            transport: .bluetooth,
            modelUID: "2042 4c",
            deviceUID: "output-uid-1"
        ))
        let second = try #require(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "My Earbuds",
            transport: .bluetooth,
            modelUID: "2042 4c",
            deviceUID: "output-uid-2"
        ))

        #expect(reporter.report(first))
        #expect(reporter.report(second))
        #expect(reporter.retainedFingerprintCount == 2)
    }

    private func record(productID: Int) throws -> AppleBluetoothAudioDiagnosticRecord {
        try #require(AppleBluetoothAudioDiagnosticRecord.coreAudio(
            name: "Fixture \(productID)",
            transport: .bluetooth,
            modelUID: "\(String(productID, radix: 16)) 4c"
        ))
    }
}
