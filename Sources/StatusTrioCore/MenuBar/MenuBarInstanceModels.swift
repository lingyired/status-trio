import Foundation

// Menu-bar custom instances: persisted, display-only configuration models.
// These types are intentionally free of AppKit so they stay testable and
// Codable. Rendering/interaction live in the sibling files.

struct ColorValue: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

enum LineColor: Codable, Equatable, Sendable {
    case inheritSource
    case fixed(ColorValue)
}

enum LineAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

enum MenuBarIconSource: Codable, Equatable, Sendable {
    case sfSymbol(String)
    case emoji(String)
    case asset(String)
}

struct MenuBarIconSpec: Codable, Equatable, Sendable {
    var source: MenuBarIconSource
    /// Only meaningful for SF Symbols and template assets; emoji ignore it.
    var tint: Bool

    init(source: MenuBarIconSource, tint: Bool = true) {
        self.source = source
        self.tint = tint
    }
}

/// The built-in monitoring metrics a menu-bar line may show.
/// Version 1 covers the product list; Wi-Fi is a text metric (connected state).
enum MenuBarMetricID: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpuUsage
    case cpuTemperature
    case gpuUsage
    case gpuTemperature
    case memoryUsage
    case diskReadSpeed
    case diskWriteSpeed
    case networkDownload
    case networkUpload
    case fanRPM
    case batteryLevel
    case wifiConnectionStatus
    case outputVolume
    case screenBrightness

    var id: String { rawValue }
}

enum MenuBarLineSegment: Equatable, Sendable {
    case text(String)
    case metric(MenuBarMetricID)
}

extension MenuBarLineSegment: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case metric
    }

    private enum Kind: String, Codable {
        case text
        case metric
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .metric:
            let raw = try container.decode(String.self, forKey: .metric)
            guard let metric = MenuBarMetricID(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .metric, in: container,
                    debugDescription: "Unknown menu-bar metric: \(raw)"
                )
            }
            self = .metric(metric)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .metric(let metric):
            try container.encode(Kind.metric, forKey: .type)
            try container.encode(metric.rawValue, forKey: .metric)
        }
    }
}

/// A single line of a menu-bar instance: an ordered list of text/metric
/// segments plus line-level styling.
struct MenuBarLine: Equatable, Sendable {
    var segments: [MenuBarLineSegment]
    var icon: MenuBarIconSpec?
    var color: LineColor
    var isBold: Bool
    var fontSize: Double?
    var usesMonospacedDigits: Bool
    var alignment: LineAlignment

    init(
        segments: [MenuBarLineSegment] = [],
        icon: MenuBarIconSpec? = nil,
        color: LineColor = .inheritSource,
        isBold: Bool = false,
        fontSize: Double? = nil,
        usesMonospacedDigits: Bool = true,
        alignment: LineAlignment = .leading
    ) {
        self.segments = segments
        self.icon = icon
        self.color = color
        self.isBold = isBold
        self.fontSize = fontSize
        self.usesMonospacedDigits = usesMonospacedDigits
        self.alignment = alignment
    }

    /// True when the line would render nothing.
    var isEmpty: Bool {
        segments.allSatisfy { segment in
            if case .text(let text) = segment { return text.isEmpty }
            return false
        } && icon == nil
    }
}

extension MenuBarLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case segments, icon, color, isBold, fontSize, usesMonospacedDigits, alignment
    }

    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wrapped = try container.decodeIfPresent([Failable<MenuBarLineSegment>].self, forKey: .segments) ?? []
        self.segments = wrapped.compactMap(\.value)
        self.icon = try container.decodeIfPresent(MenuBarIconSpec.self, forKey: .icon)
        self.color = try container.decodeIfPresent(LineColor.self, forKey: .color) ?? .inheritSource
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        self.usesMonospacedDigits = try container.decodeIfPresent(Bool.self, forKey: .usesMonospacedDigits) ?? true
        self.alignment = try container.decodeIfPresent(LineAlignment.self, forKey: .alignment) ?? .leading
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
        try container.encode(isBold, forKey: .isBold)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
        try container.encode(usesMonospacedDigits, forKey: .usesMonospacedDigits)
        try container.encode(alignment, forKey: .alignment)
    }
}

/// System Settings panes a click may open. Wi-Fi uses its own extension route
/// first, matching the project's System Settings routing rule.
enum SystemSettingsPane: String, Codable, CaseIterable, Sendable {
    case wifi
    case bluetooth
    case battery
    case sound
    case network
}

/// What a left-click or hover on an instance does.
enum InstanceActivation: Codable, Equatable, Sendable {
    case none
    case sameAsMainIcon
    case panel(String) // StatusPanelRoute raw value
    case openAppSettings
    case openActivityMonitor
    case openSystemSettings(SystemSettingsPane)
}

/// What a right-click on an instance does (disable is always appended).
enum InstanceRightClick: Codable, Equatable, Sendable {
    case sameAsMainIcon
    case quickAction(String) // MenuBarRightClickOutcome identifier
}

struct MenuBarInstance: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var top: MenuBarLine?
    var bottom: MenuBarLine?
    var leadingIcon: MenuBarIconSpec?
    var innerPadding: Double
    var outerMargin: Double
    var clickAction: InstanceActivation
    var hoverAction: InstanceActivation
    var rightClick: InstanceRightClick

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        top: MenuBarLine? = nil,
        bottom: MenuBarLine? = nil,
        leadingIcon: MenuBarIconSpec? = nil,
        innerPadding: Double = 0,
        outerMargin: Double = 4,
        clickAction: InstanceActivation = .panel("summary"),
        hoverAction: InstanceActivation = .none,
        rightClick: InstanceRightClick = .sameAsMainIcon
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.top = top
        self.bottom = bottom
        self.leadingIcon = leadingIcon
        self.innerPadding = innerPadding
        self.outerMargin = outerMargin
        self.clickAction = clickAction
        self.hoverAction = hoverAction
        self.rightClick = rightClick
    }

    /// Default instance used by presets/tests: top "CPU 45%", no bottom line.
    static func `default`() -> MenuBarInstance {
        MenuBarInstance(
            top: MenuBarLine(segments: [.text("CPU "), .metric(.cpuUsage)])
        )
    }

    var hasVisibleContent: Bool {
        [top, bottom].contains { line in
            guard let line else { return false }
            return !line.isEmpty
        }
    }

    var allMetrics: Set<MenuBarMetricID> {
        Set([top, bottom].compactMap { $0 }.flatMap { line in
            line.segments.compactMap { segment -> MenuBarMetricID? in
                if case .metric(let metric) = segment { return metric }
                return nil
            }
        })
    }

    /// Metrics on enabled instances only (drives sampling demand).
    var demandedMetrics: Set<MenuBarMetricID> {
        isEnabled && hasVisibleContent ? allMetrics : []
    }
}

extension MenuBarInstance: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, top, bottom, leadingIcon
        case innerPadding, outerMargin, clickAction, hoverAction, rightClick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.top = try container.decodeIfPresent(MenuBarLine.self, forKey: .top)
        self.bottom = try container.decodeIfPresent(MenuBarLine.self, forKey: .bottom)
        self.leadingIcon = try container.decodeIfPresent(MenuBarIconSpec.self, forKey: .leadingIcon)
        self.innerPadding = try container.decodeIfPresent(Double.self, forKey: .innerPadding) ?? 0
        self.outerMargin = try container.decodeIfPresent(Double.self, forKey: .outerMargin) ?? 4
        self.clickAction = try container.decodeIfPresent(InstanceActivation.self, forKey: .clickAction) ?? .panel("summary")
        self.hoverAction = try container.decodeIfPresent(InstanceActivation.self, forKey: .hoverAction) ?? .none
        self.rightClick = try container.decodeIfPresent(InstanceRightClick.self, forKey: .rightClick) ?? .sameAsMainIcon
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(top, forKey: .top)
        try container.encodeIfPresent(bottom, forKey: .bottom)
        try container.encodeIfPresent(leadingIcon, forKey: .leadingIcon)
        try container.encode(innerPadding, forKey: .innerPadding)
        try container.encode(outerMargin, forKey: .outerMargin)
        try container.encode(clickAction, forKey: .clickAction)
        try container.encode(hoverAction, forKey: .hoverAction)
        try container.encode(rightClick, forKey: .rightClick)
    }
}

struct MenuBarInstancesConfiguration: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var instances: [MenuBarInstance]

    init(schemaVersion: Int = 1, instances: [MenuBarInstance] = []) {
        self.schemaVersion = schemaVersion
        self.instances = instances
    }

    static let empty = MenuBarInstancesConfiguration()

    /// Normalizes a configuration to the shipped limits. Never throws; drops or
    /// clamps invalid parts and returns human-readable warnings instead.
    func validated(limit: Int = 20) -> (config: MenuBarInstancesConfiguration, warnings: [String]) {
        var warnings: [String] = []
        var seen = Set<UUID>()
        var kept: [MenuBarInstance] = []

        for var instance in instances {
            guard seen.insert(instance.id).inserted else {
                warnings.append("Dropped duplicate instance id \(instance.id.uuidString).")
                continue
            }
            instance.innerPadding = instance.innerPadding.clamped(to: 0...24)
            instance.outerMargin = instance.outerMargin.clamped(to: 0...24)
            instance.top = instance.top.map { Self.normalize(line: $0, warnings: &warnings) }
            instance.bottom = instance.bottom.map { Self.normalize(line: $0, warnings: &warnings) }
            if !instance.hasVisibleContent {
                instance.isEnabled = false
            }
            kept.append(instance)
        }

        if kept.count > limit {
            warnings.append("Too many menu-bar instances (\(kept.count)); kept the first \(limit).")
            kept = Array(kept.prefix(limit))
        }
        return (MenuBarInstancesConfiguration(schemaVersion: max(1, schemaVersion), instances: kept), warnings)
    }

    private static func normalize(line: MenuBarLine, warnings: inout [String]) -> MenuBarLine {
        var line = line
        var segments: [MenuBarLineSegment] = []
        for segment in line.segments.prefix(32) {
            switch segment {
            case .text(var text):
                if text.count > 64 { text = String(text.prefix(64)) }
                segments.append(.text(text))
            case .metric(let metric):
                if MenuBarMetricID.allCases.contains(metric) {
                    segments.append(.metric(metric))
                } else {
                    warnings.append("Dropped unsupported metric \(metric.rawValue).")
                }
            }
        }
        if line.segments.count > 32 {
            warnings.append("Line truncated to 32 segments.")
        }
        line.segments = segments
        return line
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        isFinite ? min(range.upperBound, max(range.lowerBound, self)) : range.lowerBound
    }
}
