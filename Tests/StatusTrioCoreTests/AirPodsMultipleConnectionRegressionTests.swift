import CoreAudio
import XCTest
@testable import StatusTrioCore

final class AirPodsMultipleConnectionRegressionTests: XCTestCase {
    private let connectedReport = Data("""
    {"SPBluetoothDataType":[{"device_connected":[{"Renamed Pro 2":{"device_address":"AA:BB:CC:DD:EE:FF","device_minorType":"Headphones","device_productID":"0x2014","device_vendorID":"0x004C"}},{"Renamed AirPods 4":{"device_address":"11:22:33:44:55:66","device_minorType":"Headphones","device_productID":"0x201b","device_vendorID":"0x004C"}}]}]}
    """.utf8)

    func testBothSystemReportedConnectionsRemainConnected() async throws {
        let report = connectedReport
        let worker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { report }, reportCache: BluetoothProfilerReportCache()
        )
        let result = await withCheckedContinuation { continuation in
            worker.read { continuation.resume(returning: $0) }
        }
        guard case .success(let devices) = result else { return XCTFail("Expected successful read") }
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices.allSatisfy(\.isConnected), "Both connections must follow the system report")
    }

    private struct Endpoints: CoreAudioBluetoothEndpointProviding {
        let values: [BluetoothListeningModeEndpoint]
        func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] { values }
    }

    @MainActor
    func testTwoConnectedAirPodsResolveIndependentlyOfDefaultOutputAndEndpointCount() throws {
        let devices = try XCTUnwrap(BluetoothPairedDeviceReader.parse(json: connectedReport))
        let endpoints = zip([AudioDeviceID(42), AudioDeviceID(43)], ["AABBCCDDEEFF", "112233445566"]).map { id, address in
            BluetoothListeningModeEndpoint(
                audioDeviceID: id,
                capability: BluetoothListeningModeCapability(
                    audioDeviceID: id, availableModes: [.noiseCancellation, .transparency, .adaptive],
                    currentMode: .noiseCancellation, canSet: true
                ),
                isDefaultOutput: id == 43, bluetoothAddress: address
            )
        }
        // The active pair can remain controllable whether the other connected
        // pair has its own HAL endpoint yet or not. Neither device is hidden.
        for available in [endpoints, Array(endpoints.prefix(1))] {
            let controller = BluetoothListeningModeController(
                hal: BluetoothListeningModeHAL(backend: FakeListeningModeBackend()),
                endpointProvider: Endpoints(values: available),
                listenerBackend: FakeListeningModeListenerBackend()
            )
            defer { controller.stop() }
            controller.refresh(devices: devices)
            XCTAssertEqual(controller.control(forEndpoint: 42)?.address, "AABBCCDDEEFF")
            XCTAssertEqual(controller.control(forEndpoint: 42)?.presentation.isControllable, true)
            if available.count == 2 {
                XCTAssertEqual(controller.control(forEndpoint: 43)?.address, "112233445566")
                XCTAssertEqual(controller.control(forEndpoint: 43)?.presentation.isControllable, true)
            } else {
                XCTAssertNil(controller.control(forEndpoint: 43))
            }
        }
    }

    func testUnknownHardwareDoesNotAdvertiseControls() {
        let unknown = AirPodsFeatureSupport(modelUID: "ffff 4c")
        XCTAssertNil(unknown.spatial, "Unknown hardware must not assert support")
        XCTAssertNil(unknown.conversation)
        XCTAssertEqual(AirPodsFeatureSupport(modelUID: "2014 4c").conversation, nil)
        XCTAssertEqual(AirPodsFeatureSupport(modelUID: "2013 4c").conversation, false)
    }

    @MainActor
    func testOtherGroupsStayReachableForListeningAndPreviewCombinations() {
        let listeningMode = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency, .adaptive],
            selectedMode: .noiseCancellation
        )
        for preview in [false, true] {
            for spatial in [false, true] {
                for conversation in [false, true] {
                    var state = PanelAudioDeviceRow(
                        key: .init(id: 42, uid: "AA-BB-CC-DD-EE-FF:output"),
                        name: "AirPods Pro 2",
                        symbol: .symbol(name: "airpodspro", variableValue: nil, fallback: nil),
                        selected: true, enabled: true, accessibilityLabel: "AirPods Pro 2"
                    )
                    state.listeningMode = listeningMode
                    state.isPreview = preview
                    state.supportsAirPodsSystemControls = true
                    state.airPodsSpatialSupported = spatial
                    state.airPodsConversationSupported = conversation
                    let view = OutputDeviceRow(state: state, onSelect: {}, onSelectListeningMode: { _ in })
                    XCTAssertEqual(view.showsExtraToggle, spatial && conversation, "Preview and real rows must disclose the same groups")
                    XCTAssertEqual(view.showsInlineExtraGroup, spatial != conversation, "One extra group must remain inline beside listening controls")
                    state.listeningMode = nil
                    let noListening = OutputDeviceRow(state: state, onSelect: {}, onSelectListeningMode: { _ in })
                    XCTAssertFalse(noListening.showsExtraToggle, "A missing listening row must never reserve an empty chevron row")
                    XCTAssertEqual(noListening.showsInlineExtraGroup, spatial || conversation)
                }
            }
        }
    }

    @MainActor
    func testMissingListeningControlsPromotesOtherGroupsInline() {
        XCTAssertFalse(OutputDeviceRow.disclosesExtraGroups(hasListeningMode: false, spatial: true, conversation: true))
        XCTAssertTrue(OutputDeviceRow.disclosesExtraGroups(hasListeningMode: true, spatial: true, conversation: true))
    }
}
