import CoreAudio
import XCTest

@testable import StatusTrioCore

/// The identity boundary (§6) held as a pure rule: exact-address match wins, a
/// sibling conflict fails closed, and only a wholly unambiguous single-device /
/// single-endpoint / default-output set is trusted without address evidence. These
/// are the cases where writing the wrong endpoint would commandeer a different
/// device, so the resolution — not just the parsing — is pinned here.
final class CoreAudioBluetoothDeviceMapperTests: XCTestCase {
    private let address = "AABBCCDDEEFF"

    private func capability(
        canSet: Bool = true,
        modes: [BluetoothListeningMode] = [.noiseCancellation, .transparency]
    ) -> BluetoothListeningModeCapability {
        BluetoothListeningModeCapability(
            audioDeviceID: 0,
            availableModes: modes,
            currentMode: .noiseCancellation,
            canSet: canSet
        )
    }

    private func endpoint(
        _ id: AudioDeviceID,
        address: String?,
        isDefault: Bool = true,
        capability: BluetoothListeningModeCapability? = nil
    ) -> BluetoothListeningModeEndpoint {
        BluetoothListeningModeEndpoint(
            audioDeviceID: id,
            capability: capability ?? self.capability(),
            isDefaultOutput: isDefault,
            bluetoothAddress: address
        )
    }

    func testConflictingTrustedAddressNeverFallsBackToDefaultOutput() {
        XCTAssertNil(BluetoothListeningModeEndpointMapper.endpointID(
            forNormalizedAddress: address,
            connectedEligibleAirPodsCount: 1,
            in: [endpoint(7, address: "112233445566")]
        ))
    }

    func testExactAddressMatchResolves() {
        let endpoints = [
            endpoint(7, address: address),
            endpoint(9, address: "112233445566")
        ]
        let resolved = BluetoothListeningModeEndpointMapper.endpointID(
            forNormalizedAddress: address,
            connectedEligibleAirPodsCount: 1,
            in: endpoints
        )
        XCTAssertEqual(resolved, 7)
    }

    func testAddressComparisonNormalizes() {
        // A device id the reader would normalize (colons/lowercase) must still match
        // an endpoint address stored the same way it came from the source.
        let endpoints = [endpoint(3, address: "aa:bb:cc:dd:ee:ff")]
        XCTAssertEqual(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: "AA:BB:CC:DD:EE:FF",
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            ),
            3
        )
    }

    func testSiblingEndpointsSharingAnAddressFailClosed() {
        // Two controllable endpoints for the same buds (input/output siblings) that
        // both carry the address: nothing distinguishes the writable one, so we write
        // none.
        let endpoints = [
            endpoint(5, address: address),
            endpoint(6, address: address)
        ]
        XCTAssertNil(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            )
        )
    }

    func testOnlyControllableSiblingsCountTowardConflict() {
        // A non-controllable sibling (only one mode, or not settable) is not a write
        // candidate, so it does not create ambiguity — the one controllable endpoint
        // resolves.
        let endpoints = [
            endpoint(5, address: address),
            endpoint(6, address: address, capability: capability(canSet: false))
        ]
        XCTAssertEqual(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            ),
            5
        )
    }

    func testNoAddressEvidenceUsesConservativeDefaultOutputFallback() {
        let endpoints = [endpoint(8, address: nil, isDefault: true)]
        XCTAssertEqual(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            ),
            8
        )
    }

    func testConservativeFallbackRejectedWhenNotDefaultOutput() {
        let endpoints = [endpoint(8, address: nil, isDefault: false)]
        XCTAssertNil(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            )
        )
    }

    func testConservativeFallbackRejectedWithMultipleAirPods() {
        // Two connected AirPods, one controllable endpoint, no address: which buds is
        // it? Ambiguous — fail closed even though the endpoint set alone looked safe.
        let endpoints = [endpoint(8, address: nil, isDefault: true)]
        XCTAssertNil(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 2,
                in: endpoints
            )
        )
    }

    func testConservativeFallbackRejectedWithMultipleEndpoints() {
        let endpoints = [
            endpoint(8, address: nil, isDefault: true),
            endpoint(9, address: nil, isDefault: false)
        ]
        XCTAssertNil(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: endpoints
            )
        )
    }

    func testEmptyEndpointSetResolvesNothing() {
        XCTAssertNil(
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: address,
                connectedEligibleAirPodsCount: 1,
                in: []
            )
        )
    }
}
