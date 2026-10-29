import CoreBluetooth
import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothLEBatteryAdvertisementTests {
    private let batteryService = CBUUID(string: "180F")

    /// Apple's company identifier and a Continuity message type, as the radio
    /// delivers them: identifier first, then the message length.
    private func appleManufacturerData(messageType: UInt8) -> Data {
        Data([0x4C, 0x00, messageType, 0x01, 0x02])
    }

    @Test func advertisesTheBatteryServiceItselfIsEnoughToBeACandidate() {
        #expect(BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: [batteryService],
            manufacturerData: nil,
            name: nil,
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
    }

    @Test func batteryServiceMatchIgnoresCaseAndOtherServices() {
        #expect(BluetoothLEBatteryAdvertisement.advertisesBatteryService(
            [CBUUID(string: "180a"), CBUUID(string: "180f")],
            batteryService: batteryService
        ))
        #expect(!BluetoothLEBatteryAdvertisement.advertisesBatteryService(
            [CBUUID(string: "180A"), CBUUID(string: "1805")],
            batteryService: batteryService
        ))
    }

    @Test func missingServiceListIsNotABatteryAdvertisement() {
        #expect(!BluetoothLEBatteryAdvertisement.advertisesBatteryService(
            nil,
            batteryService: batteryService
        ))
    }

    /// An iPhone does not advertise the Battery Service, so the Continuity
    /// payload plus a name the system knows is the whole signal.
    @Test func knownAppleMobileDeviceIsACandidateWithoutTheBatteryService() {
        for messageType: UInt8 in [0x10, 0x0C] {
            #expect(BluetoothLEBatteryAdvertisement.isCandidate(
                serviceUUIDs: nil,
                manufacturerData: appleManufacturerData(messageType: messageType),
                name: "Ling's iPhone",
                batteryService: batteryService,
            allowsAppleMobileDevices: true,
                knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
            ))
        }
    }

    /// A stranger's phone broadcasts the same payload, and the prompt it would
    /// raise shows its own name — "iPhone", not the user's name for it. The
    /// missing name is what keeps the route on this Mac's own devices.
    @Test func unnamedAppleBroadcastsAreNotCandidates() {
        for name: String? in [nil, "", "   ", "\n"] {
            #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
                serviceUUIDs: nil,
                manufacturerData: appleManufacturerData(messageType: 0x10),
                name: name,
                batteryService: batteryService,
            allowsAppleMobileDevices: true,
                knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
            ))
        }
    }

    /// The service route does not need a name: a keyboard or a mouse reaches the
    /// scanner with whatever the advertisement carried.
    @Test func unnamedBatteryServiceDeviceStaysACandidate() {
        #expect(BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: [batteryService],
            manufacturerData: nil,
            name: nil,
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
    }

    /// AirPods send their own Continuity message types, and their battery is
    /// read by the paired-device path rather than this scanner.
    @Test func applePayloadWithAnotherMessageTypeIsNotACandidate() {
        for messageType: UInt8 in [0x07, 0x12, 0x01, 0x0D] {
            #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
                serviceUUIDs: nil,
                manufacturerData: appleManufacturerData(messageType: messageType),
                name: "AirPods",
                batteryService: batteryService,
            allowsAppleMobileDevices: true,
                knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
            ))
        }
    }

    @Test func anotherVendorsPayloadIsNotACandidate() {
        #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: nil,
            manufacturerData: Data([0x06, 0x00, 0x10]),
            name: "Some Sensor",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
    }

    @Test func appleContinuityRequiresTheCompleteCompanyIdentifier() {
        #expect(!BluetoothLEBatteryAdvertisement.isAppleMobileDevice(
            manufacturerData: Data([0x4C, 0x01, 0x10, 0x01])
        ))
    }

    /// A payload that carries no message type — or no payload at all — cannot
    /// be read past its end.
    @Test func shortManufacturerDataIsNotReadPastItsEnd() {
        for payload: Data? in [nil, Data(), Data([0x4C]), Data([0x4C, 0x00])] {
            #expect(!BluetoothLEBatteryAdvertisement.isAppleMobileDevice(manufacturerData: payload))
            #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
                serviceUUIDs: nil,
                manufacturerData: payload,
                name: "Ling's iPhone",
                batteryService: batteryService,
            allowsAppleMobileDevices: true,
                knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
            ))
        }
    }

    /// A sliced `Data` keeps the offsets of the buffer it came from, so the
    /// offsets have to come from `startIndex` rather than being written as 0..2.
    @Test func readsASlicedPayloadFromItsOwnStartIndex() {
        let framed = Data([0xFF, 0xFF]) + appleManufacturerData(messageType: 0x10)
        let slice = framed.dropFirst(2)

        #expect(slice.startIndex == 2)
        #expect(BluetoothLEBatteryAdvertisement.isAppleMobileDevice(manufacturerData: slice))
    }

    /// The Apple-device feature gates the Continuity
    /// route with it. A device that advertises the Battery Service is still a
    /// candidate — it answers without asking the user anything.
    @Test func appleMobileRouteRequiresTheAppleDeviceFeature() {
        let phone = appleManufacturerData(messageType: 0x10)
        #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: nil,
            manufacturerData: phone,
            name: "Ling's iPhone",
            batteryService: batteryService,
            allowsAppleMobileDevices: false,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
        #expect(BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: [batteryService],
            manufacturerData: nil,
            name: "MX Keys",
            batteryService: batteryService,
            allowsAppleMobileDevices: false,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
    }

    /// The system list is the identity gate: a phone broadcasting the payload
    /// under a name this Mac has no record of — including a stranger's default
    /// "iPhone" — is not opened.
    @Test func phoneNotInTheSystemListIsNotACandidate() {
        #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: nil,
            manufacturerData: appleManufacturerData(messageType: 0x10),
            name: "iPhone",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone"]
        ))
    }

    @Test func systemListMatchFoldsCaseAndSurroundingWhitespace() {
        #expect(BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: nil,
            manufacturerData: appleManufacturerData(messageType: 0x0C),
            name: "  ling's IPHONE ",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone"]
        ))
        #expect(BluetoothLEBatteryAdvertisement.matchesKnownAppleMobileName(
            nil,
            knownNames: ["Ling's iPhone"]
        ) == false)
    }

    /// With no system record to match, no phone is read — the master alone is
    /// not enough. A keyboard that advertises the Battery Service still is.
    @Test func emptySystemListReadsNoPhonesButKeepsTheServiceRoute() {
        #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: nil,
            manufacturerData: appleManufacturerData(messageType: 0x10),
            name: "Ling's iPhone",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: []
        ))
        #expect(BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: [batteryService],
            manufacturerData: nil,
            name: "MX Keys",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: []
        ))
    }

    @Test func deviceInformationAloneIsNotACandidate() {
        #expect(!BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: [CBUUID(string: "180A")],
            manufacturerData: nil,
            name: "MX Keys",
            batteryService: batteryService,
            allowsAppleMobileDevices: true,
            knownAppleMobileNames: ["Ling's iPhone", "AirPods"]
        ))
    }
}
