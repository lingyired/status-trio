import XCTest
@testable import StatusTrioCore

final class CapabilityRoutingTests: XCTestCase {

    // MARK: - Fixtures

    private func helper(
        protocolVersion: Int = 1,
        advertised: Set<DistributionCapabilityID> = [],
        services: [HelperService: HelperRuntimeStatus.ServiceState] = [:],
        teamID: String = "TEAM123456"
    ) -> HelperRuntimeStatus {
        HelperRuntimeStatus(
            installation: .installed(
                .init(
                    marketingVersion: "1.0.0",
                    protocolVersion: protocolVersion,
                    teamID: teamID,
                    advertisedCapabilities: advertised,
                    services: services
                )
            )
        )
    }

    private func catalog(
        _ id: DistributionCapabilityID,
        _ sourceClass: CapabilitySourceClass,
        service: HelperService? = nil,
        minProtocol: Int = 1
    ) -> CapabilityCatalog {
        var svc: [DistributionCapabilityID: HelperService] = [:]
        if let service { svc[id] = service }
        return CapabilityCatalog(
            sourceClass: [id: sourceClass],
            helperService: svc,
            minProtocolVersion: [id: minProtocol]
        )
    }

    private func ctx(
        _ channel: DistributionChannel,
        helper: HelperRuntimeStatus = .notInstalled
    ) -> CapabilityResolutionContext {
        CapabilityResolutionContext(channel: channel, helper: helper)
    }

    // MARK: - allowedTiers

    func testAllowedTiersByChannel() {
        XCTAssertEqual(
            CapabilityRouter.allowedTiers(for: .ddc, channel: .direct, sourceClass: .directPrivate),
            [.native, .externalHelper]
        )
        XCTAssertEqual(
            CapabilityRouter.allowedTiers(for: .ddc, channel: .appStore, sourceClass: .directPrivate),
            [.externalHelper]
        )
        XCTAssertEqual(
            CapabilityRouter.allowedTiers(for: .bluetoothBatteryLevels, channel: .appStore, sourceClass: .sharedPublic),
            [.native, .externalHelper]
        )
        XCTAssertEqual(
            CapabilityRouter.allowedTiers(for: .sensorsSMC, channel: .appStore, sourceClass: .unclassified),
            [.externalHelper]
        )
    }

    // MARK: - Direct never degraded (native wins regardless of helper)

    func testDirectPrivateCapabilityUsesNativeEvenWithoutHelper() {
        let r = CapabilityRouter.resolve(
            .chargeToFullNow,
            context: ctx(.direct),
            catalog: catalog(.chargeToFullNow, .directPrivate, service: .charge)
        )
        XCTAssertEqual(r.tier, .native)
        XCTAssertEqual(r.availability, .nativeAvailable)
        XCTAssertTrue(r.availability.isActionable)
    }

    func testDirectSharedCapabilityUsesNative() {
        let r = CapabilityRouter.resolve(
            .bluetoothBatteryLevels,
            context: ctx(.direct),
            catalog: catalog(.bluetoothBatteryLevels, .sharedPublic)
        )
        XCTAssertEqual(r.tier, .native)
        XCTAssertEqual(r.availability, .nativeAvailable)
    }

    // MARK: - App Store helper precedence chain

    func testAppStorePrivateWithoutHelperIsHelperNotInstalled() {
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay)
        )
        XCTAssertEqual(r.tier, .externalHelper)
        XCTAssertEqual(r.availability, .helperNotInstalled)
        XCTAssertEqual(r.primaryAction, .openEnhancerInstallGuide)
        XCTAssertEqual(r.severity, .needsAction)
    }

    func testAppStoreHelperProtocolTooLowIsUpdateRequired() {
        let h = helper(protocolVersion: 1, advertised: [.ddc], services: [.audioDisplay: .ready])
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore, helper: h),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay, minProtocol: 2)
        )
        XCTAssertEqual(r.availability, .helperUpdateRequired)
        XCTAssertEqual(r.primaryAction, .requestHelperUpdate)
    }

    func testAppStoreHelperNotAdvertisingIsNotVerified() {
        let h = helper(protocolVersion: 2, advertised: [], services: [.audioDisplay: .ready])
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore, helper: h),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay, minProtocol: 2)
        )
        XCTAssertEqual(r.availability, .notVerified)
        XCTAssertEqual(r.primaryAction, .learnMoreUnsupported)
    }

    func testAppStoreHelperMissingAuthorization() {
        let h = helper(
            protocolVersion: 2,
            advertised: [.ddc],
            services: [.audioDisplay: .missingAuthorization(reason: "screen recording")]
        )
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore, helper: h),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay, minProtocol: 2)
        )
        XCTAssertEqual(r.availability, .helperMissingAuthorization)
        XCTAssertEqual(r.primaryAction, .openEnhancerComponentCheck)
    }

    func testAppStoreHelperReadyIsProvided() {
        let h = helper(protocolVersion: 2, advertised: [.ddc], services: [.audioDisplay: .ready])
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore, helper: h),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay, minProtocol: 2)
        )
        XCTAssertEqual(r.tier, .externalHelper)
        XCTAssertEqual(r.availability, .helperProvided)
        XCTAssertTrue(r.availability.isActionable)
        XCTAssertEqual(r.primaryAction, .perform)
    }

    func testAppStoreHelperFailedIsTemporarilyUnavailable() {
        let h = helper(
            protocolVersion: 2,
            advertised: [.ddc],
            services: [.audioDisplay: .failed(reason: "display busy")]
        )
        let r = CapabilityRouter.resolve(
            .ddc,
            context: ctx(.appStore, helper: h),
            catalog: catalog(.ddc, .directPrivate, service: .audioDisplay, minProtocol: 2)
        )
        XCTAssertEqual(r.availability, .temporarilyUnavailable(reason: "display busy"))
        XCTAssertEqual(r.primaryAction, .retry)
    }

    // MARK: - Shared public capability on App Store uses native route

    func testAppStoreSharedPublicUsesNative() {
        let r = CapabilityRouter.resolve(
            .bluetoothBatteryLevels,
            context: ctx(.appStore),
            catalog: catalog(.bluetoothBatteryLevels, .sharedPublic)
        )
        XCTAssertEqual(r.tier, .native)
        XCTAssertEqual(r.availability, .nativeAvailable)
    }

    // MARK: - Unclassified defaults to helper-only / safe

    func testUnclassifiedAppStoreWithoutHelperIsNotNative() {
        let r = CapabilityRouter.resolve(
            .sensorsSMC,
            context: ctx(.appStore),
            catalog: catalog(.sensorsSMC, .unclassified, service: .sensor)
        )
        XCTAssertEqual(r.tier, .externalHelper)
        XCTAssertEqual(r.availability, .helperNotInstalled)
    }

    func testUnclassifiedNotHelperServableIsUnsupported() {
        let r = CapabilityRouter.resolve(
            .sensorsSMC,
            context: ctx(.appStore),
            catalog: catalog(.sensorsSMC, .unclassified, service: nil)
        )
        XCTAssertEqual(r.tier, .unavailable)
        XCTAssertEqual(r.availability, .unsupported(reason: "no-provider"))
    }

    // MARK: - Hard gate is terminal

    func testHardGateShortCircuits() {
        let cat = CapabilityCatalog(
            sourceClass: [.sensorsSMC: .directPrivate],
            helperService: [.sensorsSMC: .sensor],
            hardGate: { _, _ in .unsupported(reason: "intel-mac") }
        )
        let r = CapabilityRouter.resolve(.sensorsSMC, context: ctx(.direct), catalog: cat)
        XCTAssertEqual(r.tier, .unavailable)
        XCTAssertEqual(r.availability, .unsupported(reason: "intel-mac"))
        XCTAssertEqual(r.severity, .blocked)
    }

    // MARK: - Action / severity matrix

    func testActionAndSeverityMatrix() {
        let cases: [(CapabilityAvailability, CapabilityPrimaryAction, CapabilitySeverity)] = [
            (.nativeAvailable, .perform, .normal),
            (.helperProvided, .perform, .normal),
            (.helperNotInstalled, .openEnhancerInstallGuide, .needsAction),
            (.helperUpdateRequired, .requestHelperUpdate, .needsAction),
            (.helperMissingAuthorization, .openEnhancerComponentCheck, .needsAction),
            (.permissionDenied(reason: "x"), .openSystemPrivacyPane, .needsAction),
            (.temporarilyUnavailable(reason: "x"), .retry, .info),
            (.notVerified, .learnMoreUnsupported, .info),
            (.unsupported(reason: "x"), .learnMoreUnsupported, .blocked),
        ]
        for (availability, action, severity) in cases {
            let r = CapabilityResolution(capability: .ddc, tier: .unavailable, availability: availability)
            XCTAssertEqual(r.primaryAction, action, "action for \(availability)")
            XCTAssertEqual(r.severity, severity, "severity for \(availability)")
        }
    }

    func testActionableOnlyForNativeAndHelperProvided() {
        XCTAssertTrue(CapabilityAvailability.nativeAvailable.isActionable)
        XCTAssertTrue(CapabilityAvailability.helperProvided.isActionable)
        for state: CapabilityAvailability in [
            .helperNotInstalled, .helperUpdateRequired, .helperMissingAuthorization,
            .unsupported(reason: "x"), .temporarilyUnavailable(reason: "x"),
            .permissionDenied(reason: "x"), .notVerified
        ] {
            XCTAssertFalse(state.isActionable, "\(state) must not be actionable")
        }
    }
}
