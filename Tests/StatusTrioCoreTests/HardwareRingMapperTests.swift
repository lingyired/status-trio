import XCTest
@testable import StatusTrioCore

final class HardwareRingMapperTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Helpers

    private func sample(
        _ value: Double?,
        unit: HardwareMetricUnit,
        availability: HardwareMetricAvailability = .measured,
        sampledAt: Date? = nil,
        maximum: Double? = nil
    ) -> HardwareMetricSample {
        HardwareMetricSample(
            value: value,
            unit: unit,
            sampledAt: sampledAt ?? now,
            source: .smc,
            availability: availability,
            metadata: .init(maximum: maximum)
        )
    }

    private func snapshot(_ samples: [HardwareMetricID: HardwareMetricSample], fanCount: Int? = nil) -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples = samples
        snapshot.fanCount = fanCount
        return snapshot
    }

    private let green = HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage)
    private let blue = HardwareRingColorConfiguration.recommendedBaseColor(for: .gpuUsage)

    // MARK: - Single ring

    func testSingleRingMapsProgressAndBaseColor() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .normal], now: now)
        XCTAssertEqual(state.layout, .standard)
        XCTAssertEqual(state.segments.count, 1)
        XCTAssertEqual(state.segments[0].progress, 0.45, accuracy: 0.0001)
        XCTAssertEqual(state.segments[0].color, .custom(green))
    }

    func testStatusModeWarningAndCriticalRecolorWholeArc() {
        let snap = snapshot([.cpuUsage: sample(96, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))

        let warning = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                  levels: [.cpuUsage: .warning], now: now)
        XCTAssertEqual(warning.segments[0].color, .custom(HardwareRingColorConfiguration.warningColor))

        let critical = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                   levels: [.cpuUsage: .critical], now: now)
        XCTAssertEqual(critical.segments[0].color, .custom(HardwareRingColorConfiguration.criticalColor))
    }

    func testFixedModeIgnoresLevel() {
        let snap = snapshot([.cpuUsage: sample(99, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: false))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .critical], now: now)
        XCTAssertEqual(state.segments[0].color, .custom(green))
    }

    func testMonochromeUsesPrimaryRole() {
        let snap = snapshot([.cpuUsage: sample(99, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: true, thresholdColors: false))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .critical], now: now)
        XCTAssertEqual(state.segments[0].color, .primary)
    }

    func testUnavailableSampleShowsInactiveTrack() {
        let snap = snapshot([.cpuUsage: sample(nil, unit: .percent, availability: .temporarilyUnavailable)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .normal], now: now)
        XCTAssertEqual(state.segments.count, 1)
        XCTAssertEqual(state.segments[0].progress, 0)
        XCTAssertEqual(state.segments[0].color, .inactive)
    }

    func testStaleSampleIsNotShownAsLive() {
        let old = now.addingTimeInterval(-60)
        let snap = snapshot([.cpuUsage: sample(80, unit: .percent, sampledAt: old)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .normal], now: now)
        XCTAssertEqual(state.segments[0].progress, 0)
        XCTAssertEqual(state.segments[0].color, .inactive)
    }

    // MARK: - Temperature & fan ranges

    func testTemperatureUsesConfiguredRange() {
        let snap = snapshot([.cpuTemperature: sample(65, unit: .celsius)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuTemperature)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        // default 30...100 -> (65-30)/70 == 0.5
        XCTAssertEqual(state.segments[0].progress, 0.5, accuracy: 0.0001)
    }

    func testFanUsesTrustedMaximum() {
        let snap = snapshot([.fanRPM(index: 0): sample(3000, unit: .rpm, maximum: 6000)], fanCount: 1)
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .fan)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        XCTAssertEqual(state.segments[0].progress, 0.5, accuracy: 0.0001)
    }

    func testFanWithoutTrustedMaximumShowsTrackOnly() {
        let snap = snapshot([.fanRPM(index: 0): sample(3000, unit: .rpm, maximum: nil)], fanCount: 1)
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .fan)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        XCTAssertEqual(state.segments[0].progress, 0)
        XCTAssertEqual(state.segments[0].color, .inactive)
    }

    // MARK: - Dual ring

    func testDualRingIndependentSegments() {
        let snap = snapshot([
            .cpuUsage: sample(80, unit: .percent),
            .gpuUsage: sample(30, unit: .percent)
        ])
        let config = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage,
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            levels: [.cpuUsage: .warning, .gpuUsage: .normal], now: now
        )
        XCTAssertEqual(state.layout, .leftRight)
        XCTAssertEqual(state.segments.count, 2)
        let left = state.segments.first { $0.position == .left }
        let right = state.segments.first { $0.position == .right }
        XCTAssertEqual(left?.progress ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(left?.color, .custom(HardwareRingColorConfiguration.warningColor))
        XCTAssertEqual(right?.progress ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(right?.color, .custom(blue))
    }

    func testDualRingOneSideUnavailableOtherStillRenders() {
        let snap = snapshot([
            .cpuUsage: sample(nil, unit: .percent, availability: .unsupported),
            .gpuUsage: sample(50, unit: .percent)
        ])
        let config = HardwareRingConfiguration(layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        XCTAssertEqual(state.segments.count, 2)
        XCTAssertEqual(state.segments.first { $0.position == .left }?.color, .inactive)
        XCTAssertEqual(state.segments.first { $0.position == .right }?.progress ?? -1, 0.5, accuracy: 0.0001)
    }

    func testMetricColorOverrideFeedsSegment() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        let custom = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config,
                                                levels: [.cpuUsage: .normal],
                                                metricColors: [.cpuUsage: custom], now: now)
        XCTAssertEqual(state.segments[0].color, .custom(custom))
    }

    // MARK: - Top marker

    func testAutomaticTopMarkerForSingleUsesMetricGlyph() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage, topContent: .automatic)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        guard case let .symbol(symbol)? = state.accessory,
              case let .symbol(name, _, _) = symbol.source else {
            return XCTFail("expected symbol accessory")
        }
        XCTAssertEqual(name, HardwareRingMapper.topMarkerSymbol(for: .cpuUsage))
    }

    func testAutomaticTopMarkerForDualUsesGenericGlyph() {
        let snap = snapshot([
            .cpuUsage: sample(45, unit: .percent),
            .gpuUsage: sample(30, unit: .percent)
        ])
        let config = HardwareRingConfiguration(layout: .dual, primaryMetric: .cpuUsage,
                                               secondaryMetric: .gpuUsage, topContent: .automatic)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        guard case let .symbol(symbol)? = state.accessory,
              case let .symbol(name, _, _) = symbol.source else {
            return XCTFail("expected symbol accessory")
        }
        XCTAssertEqual(name, HardwareRingMapper.genericMonitorSymbol)
    }

    func testTopValueShowsFormattedMetric() {
        let snap = snapshot([.cpuUsage: sample(45.4, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               topContent: .value(.cpuUsage))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        guard case let .text(text)? = state.accessory else {
            return XCTFail("expected text accessory")
        }
        XCTAssertEqual(text.text, "45")
        XCTAssertEqual(text.scale, HardwareRingMapper.topValueTextScale(for: .percent))
        XCTAssertEqual(state.gap, .value)
    }

    func testTopTemperatureValueShowsDegree() {
        let snap = snapshot([.cpuTemperature: sample(55, unit: .celsius)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuTemperature,
                                               topContent: .value(.cpuTemperature))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        guard case let .text(text)? = state.accessory else {
            return XCTFail("expected text accessory")
        }
        XCTAssertEqual(text.text, "55°")
    }

    func testHiddenTopMarker() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage, topContent: .hidden)
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        XCTAssertNil(state.accessory)
        XCTAssertEqual(state.gap, .closed)
    }

    func testTopValueShowsPlaceholderWhenMetricUnavailable() {
        // Geometry is configuration-driven: an unavailable value keeps the gap
        // and shows a placeholder rather than collapsing the ring.
        let snap = snapshot([.cpuUsage: sample(nil, unit: .percent, availability: .temporarilyUnavailable)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               topContent: .value(.cpuUsage))
        let state = HardwareRingMapper.resolve(snapshot: snap, configuration: config, now: now)
        guard case let .text(text)? = state.accessory else { return XCTFail("placeholder expected") }
        XCTAssertEqual(text.text, "--")
        XCTAssertEqual(state.gap, .value)
    }

    func testTopMarkerScaleMultipliesSymbolAndValueScale() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let symbolConfig = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                                     topContent: .automatic, topMarkerScale: 1.5)
        let symbolState = HardwareRingMapper.resolve(snapshot: snap, configuration: symbolConfig, now: now)
        guard case let .symbol(symbol)? = symbolState.accessory else { return XCTFail("expected symbol") }
        XCTAssertEqual(symbol.scale, HardwareRingMapper.singleTopSymbolScale * 1.5, accuracy: 0.0001)

        let valueConfig = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                                    topContent: .value(.cpuUsage), topMarkerScale: 1.5)
        let valueState = HardwareRingMapper.resolve(snapshot: snap, configuration: valueConfig, now: now)
        guard case let .text(text)? = valueState.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.scale, HardwareRingMapper.topValueTextScale(for: .percent) * 1.5, accuracy: 0.0001)
    }

    // MARK: - Top-marker-only metrics (volume / Wi-Fi signal)

    private func auxiliarySample(_ value: Double?, availability: HardwareMetricAvailability = .measured) -> HardwareMetricSample {
        HardwareMetricSample(value: value, unit: .percent, sampledAt: now, source: .mach, availability: availability)
    }

    func testTopValueShowsVolumeFromAuxiliarySample() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .value(.volume),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.volume: auxiliarySample(37)], now: now
        )
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.text, "37")
        XCTAssertEqual(text.color, .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .volume)))
        XCTAssertEqual(state.gap, .value)
    }

    func testTopValueShowsWiFiSignalFromAuxiliarySample() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .value(.wifiSignal),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.wifiSignal: auxiliarySample(80)], now: now
        )
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.text, "80")
        XCTAssertEqual(text.color, .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .wifiSignal)))
    }

    func testBatteryLevelArcUsesBatteryStatusColorAndIgnoresMetricOverride() {
        let snap = snapshot([.cpuUsage: sample(20, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .batteryLevel, topContent: .hidden,
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            metricColors: [.batteryLevel: IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)],
            auxiliarySamples: [.batteryLevel: auxiliarySample(10)],
            batteryArcColor: .critical, now: now
        )
        XCTAssertEqual(state.segments.count, 1)
        XCTAssertEqual(state.segments[0].progress, 0.10, accuracy: 0.0001)
        XCTAssertEqual(state.segments[0].color, .critical)
    }

    func testBatteryLevelArcStaysPrimaryWhenMonochrome() {
        let snap = snapshot([.cpuUsage: sample(20, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .batteryLevel, topContent: .hidden,
            color: HardwareRingColorConfiguration(monochrome: true, thresholdColors: false)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.batteryLevel: auxiliarySample(10)],
            batteryArcColor: .critical, now: now
        )
        XCTAssertEqual(state.segments[0].color, .primary)
    }

    func testTopVolumeUsesCustomSharedColor() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .value(.volume),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let custom = IconRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            metricColors: [.volume: custom],
            auxiliarySamples: [.volume: auxiliarySample(50)], now: now
        )
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.color, .custom(custom))
    }

    func testTopVolumeMonochromeKeepsPrimaryColor() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .value(.volume),
            color: HardwareRingColorConfiguration(monochrome: true, thresholdColors: false)
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.volume: auxiliarySample(50)], now: now
        )
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.color, .primary)
    }

    func testTopVolumePlaceholderWhenUnavailable() {
        let snap = snapshot([.cpuUsage: sample(45, unit: .percent)])
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                               topContent: .value(.volume))
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.volume: auxiliarySample(nil, availability: .temporarilyUnavailable)],
            now: now
        )
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.text, "--")
    }

    // MARK: - Status-snapshot metrics as ring arcs

    func testVolumeArcUsesAuxiliarySampleAndBaseColor() {
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .volume,
                                               color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: config,
            levels: [.volume: .critical],
            auxiliarySamples: [.volume: auxiliarySample(60)], now: now
        )
        XCTAssertEqual(state.segments.count, 1)
        XCTAssertEqual(state.segments[0].progress, 0.6, accuracy: 0.0001)
        // Threshold levels never recolour a status-snapshot reading.
        XCTAssertEqual(state.segments[0].color,
                       .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .volume)))
    }

    func testWiFiSignalArcUsesAuxiliarySample() {
        let config = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .wifiSignal,
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let snap = snapshot([.cpuUsage: sample(20, unit: .percent)])
        let state = HardwareRingMapper.resolve(
            snapshot: snap, configuration: config,
            auxiliarySamples: [.wifiSignal: auxiliarySample(80)], now: now
        )
        let right = state.segments.first { $0.position == .right }
        XCTAssertEqual(right?.progress ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(right?.color, .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .wifiSignal)))
    }

    func testVolumeArcUnavailableKeepsTrackOnly() {
        let config = HardwareRingConfiguration(layout: .single, primaryMetric: .volume)
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: config,
            auxiliarySamples: [.volume: auxiliarySample(nil, availability: .temporarilyUnavailable)], now: now
        )
        XCTAssertEqual(state.segments[0].progress, 0)
        XCTAssertEqual(state.segments[0].color, .inactive)
    }

    // MARK: - Battery top markers

    private func battery(
        percent: Int = 62,
        charging: Bool = false,
        charged: Bool = false,
        connected: Bool = false,
        present: Bool = true
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percent,
            isPresent: present,
            isCharging: charging,
            isCharged: charged,
            isLowPowerMode: false,
            isConnectedToPower: connected
        )
    }

    private func singleRing(topContent: HardwareRingTopContent) -> HardwareRingConfiguration {
        HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage, topContent: topContent)
    }

    func testBatteryPercentageTopMarkerShowsLevelNumber() {
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([.cpuUsage: sample(45, unit: .percent)]),
            configuration: singleRing(topContent: .batteryPercentage),
            battery: battery(percent: 62), now: now
        )
        guard case let .text(text)? = state.accessory else {
            return XCTFail("expected text accessory")
        }
        XCTAssertEqual(text.text, "62")
        XCTAssertEqual(text.scale, HardwareRingMapper.topValueTextScale(for: .percent))
        XCTAssertEqual(state.gap, .value)
    }

    func testBatteryPercentageTopMarkerHidesOnBatteryLessMac() {
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .batteryPercentage),
            battery: battery(percent: 100, present: false), now: now
        )
        XCTAssertNil(state.accessory)
        XCTAssertEqual(state.gap, .closed)
    }

    func testChargingIndicatorShowsBoltWhileCharging() {
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: battery(percent: 40, charging: true, connected: true), now: now
        )
        guard case let .symbol(symbol)? = state.accessory else {
            return XCTFail("expected symbol accessory")
        }
        XCTAssertEqual(symbol.source, .primitive(.bolt))
        XCTAssertEqual(state.gap, .indicator)
    }

    func testChargingIndicatorShowsPlugWhenFull() {
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: battery(percent: 100, charged: true, connected: true), now: now
        )
        guard case let .symbol(symbol)? = state.accessory else {
            return XCTFail("expected symbol accessory")
        }
        XCTAssertEqual(symbol.source, .primitive(.plug))
    }

    func testChargingIndicatorShowsLevelNumberOnBattery() {
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: battery(percent: 37), now: now
        )
        guard case let .text(text)? = state.accessory else {
            return XCTFail("expected text accessory")
        }
        XCTAssertEqual(text.text, "37")
    }

    func testChargingIndicatorFollowsConfiguredChargingMarker() {
        let charging = battery(percent: 40, charging: true, connected: true)
        let plugState = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: charging, batteryOptions: BatteryIconOptions(chargingMarker: .plug), now: now
        )
        guard case let .symbol(plugSymbol)? = plugState.accessory else {
            return XCTFail("expected plug accessory")
        }
        XCTAssertEqual(plugSymbol.source, .primitive(.plug))

        let hiddenState = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: charging, batteryOptions: BatteryIconOptions(chargingMarker: .hidden), now: now
        )
        XCTAssertNil(hiddenState.accessory)
        XCTAssertEqual(hiddenState.gap, .closed)
    }

    func testChargingIndicatorFollowsConfiguredNoBatteryMarker() {
        let hidden = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: battery(percent: 100, present: false),
            batteryOptions: BatteryIconOptions(noBatteryMarker: .hidden), now: now
        )
        XCTAssertNil(hidden.accessory)

        let bolt = HardwareRingMapper.resolve(
            snapshot: snapshot([:]), configuration: singleRing(topContent: .chargingIndicator),
            battery: battery(percent: 100, present: false),
            batteryOptions: BatteryIconOptions(noBatteryMarker: .bolt), now: now
        )
        guard case let .symbol(symbol)? = bolt.accessory else {
            return XCTFail("expected bolt accessory")
        }
        XCTAssertEqual(symbol.source, .primitive(.bolt))
    }

    func testChargingIndicatorDualLayoutUsesPrimitiveBolt() {
        let config = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage,
            topContent: .chargingIndicator
        )
        let state = HardwareRingMapper.resolve(
            snapshot: snapshot([
                .cpuUsage: sample(20, unit: .percent),
                .gpuUsage: sample(30, unit: .percent),
            ]),
            configuration: config,
            battery: battery(percent: 40, charging: true, connected: true), now: now
        )
        XCTAssertEqual(state.layout, .leftRight)
        guard case let .symbol(symbol)? = state.accessory else {
            return XCTFail("expected symbol accessory")
        }
        XCTAssertEqual(symbol.source, .primitive(.bolt))
    }
}

