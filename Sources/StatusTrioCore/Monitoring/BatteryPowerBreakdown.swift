import Foundation

/// The budget the Mac can split into measured branches.
///
/// The source is whichever rail is actually feeding the machine: the adapter
/// while it supplies power, otherwise the battery discharging into the load.
/// The last branch is always a residual rather than a sensor: whatever the
/// source delivers that the measured branches (battery charge, built-in
/// display, USB output) do not account for. That covers the SoC, DRAM, display
/// controllers and any other DC load the machine does not expose separately.
///
/// Only produced when the readings share one measurement window and the
/// residual stays physically plausible. A breakdown that cannot be computed
/// honestly is `nil`, and the panel keeps the legacy two-branch diagram instead
/// of inventing a branch.
struct BatteryPowerBreakdown: Equatable, Sendable {
    struct Component: Equatable, Sendable {
        let watts: Double
        let readAt: Date
    }

    /// Which rail the diagram starts from.
    enum Source: Equatable, Sendable {
        /// The adapter's DC input (`PDTR`).
        case adapter
        /// The battery discharging into the system load.
        case battery
    }

    let source: Source
    /// Adapter input watts, or battery discharge watts, depending on `source`.
    let sourceWatts: Double
    /// Built-in display backlight (`PDBR`). Nil when this Mac does not expose it.
    let display: Component?
    /// Power sourced to accessories over USB / Thunderbolt.
    let usb: Component?
    /// Everything else the source supplies: `source - charging - display - usb`.
    let system: Component
    let readAt: Date

    var components: [Component] { [display, usb, system].compactMap { $0 } }

    /// Residual tolerance: sensor rails are sampled by one overall refresh but
    /// the SMC updates each rail on its own cadence, so a rail can be one tick
    /// ahead of the source total. Small negatives are rounding, not a
    /// measurement that justifies a fake branch.
    static let residualTolerance = 0.75
    /// Below this the adapter is not really feeding the machine (a connected but
    /// idle charger still reads fractions of a watt), so the battery takes over
    /// as the source.
    static let adapterFloor = 5.0
    /// Below this the battery is not meaningfully discharging either.
    static let batteryFloor = 1.0

    static func resolve(
        adapterInput: SystemPowerSample?,
        charging: Double?,
        discharge: Double?,
        display: SystemPowerSample?,
        usb: USBOutputSample?,
        now: Date = Date()
    ) -> BatteryPowerBreakdown? {
        // The source total is the branch's own numerator, so an unknown source
        // has no budget to split.
        let adapterWatts = adapterInput.flatMap { $0.isFresh(at: now) ? $0.watts : nil }
        if let adapterWatts, adapterWatts >= adapterFloor {
            // Unknown charge is enough to make the residual wrong.
            guard let charging, charging.isFinite, charging >= 0 else { return nil }
            return make(source: .adapter, sourceWatts: adapterWatts, subtractCharging: charging,
                        display: display, usb: usb, now: now)
        }
        guard let discharge, discharge.isFinite, discharge >= batteryFloor else { return nil }
        return make(source: .battery, sourceWatts: discharge, subtractCharging: 0,
                    display: display, usb: usb, now: now)
    }

    private static func make(
        source: Source,
        sourceWatts: Double,
        subtractCharging: Double,
        display: SystemPowerSample?,
        usb: USBOutputSample?,
        now: Date
    ) -> BatteryPowerBreakdown? {
        if let display, !display.isFresh(at: now) { return nil }
        if let usb, !usb.isFresh(at: now) { return nil }

        let displayWatts = display?.watts ?? 0
        let usbWatts = usb?.watts ?? 0
        let residual = sourceWatts - subtractCharging - displayWatts - usbWatts
        if residual < -residualTolerance { return nil }
        return BatteryPowerBreakdown(
            source: source,
            sourceWatts: sourceWatts,
            display: display.map { Component(watts: $0.watts, readAt: $0.readAt) },
            usb: usb.map { Component(watts: $0.watts, readAt: $0.readAt) },
            system: Component(watts: max(0, residual), readAt: now),
            readAt: now
        )
    }
}
