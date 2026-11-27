import Foundation

// Menu-bar custom instances: persisted, display-only configuration models (v2).
// A line is now an ordered list of independent elements (metric / text / icon),
// each with a stable id so the editor can drag and reorder them. Legacy v1
// (`segments` + line `icon`) still decodes into elements.

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
    /// Paints with the system label colour, which follows the menu bar's
    /// light/dark appearance.
    case systemDefault
    /// Paints with the data source colour of each metric.
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

/// Explicit single/double line choice. Switching to single line keeps the other
/// line's elements so the user does not lose work.
enum MenuBarLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case singleLine
    case doubleLine

    var id: String { rawValue }
}

enum MenuBarElementContent: Equatable, Sendable {
    case metric(MenuBarMetricID)
    case text(String)
    case icon(MenuBarIconSpec)
}

struct MenuBarElement: Equatable, Identifiable, Sendable {
    var id: UUID
    var content: MenuBarElementContent

    init(id: UUID = UUID(), content: MenuBarElementContent) {
        self.id = id
        self.content = content
    }
}

extension MenuBarElementContent: Codable {
    private enum CodingKeys: String, CodingKey { case type, metric, text, icon }
    private enum Kind: String, Codable { case metric, text, icon }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .metric:
            let raw = try container.decode(String.self, forKey: .metric)
            guard let metric = MenuBarMetricID(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .metric, in: container,
                                                       debugDescription: "Unknown menu-bar metric: \(raw)")
            }
            self = .metric(metric)
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .icon:
            self = .icon(try container.decode(MenuBarIconSpec.self, forKey: .icon))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metric(let metric):
            try container.encode(Kind.metric, forKey: .type)
            try container.encode(metric.rawValue, forKey: .metric)
        case .text(let text):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .icon(let icon):
            try container.encode(Kind.icon, forKey: .type)
            try container.encode(icon, forKey: .icon)
        }
    }
}

extension MenuBarElement: Codable {
    private enum CodingKeys: String, CodingKey { case id, content }
}

/// A single line: an ordered list of elements plus line-level styling.
struct MenuBarLine: Equatable, Sendable {
    var elements: [MenuBarElement]
    /// Optional icon pinned to the row's leading edge. The row's elements stay
    /// in the trailing alignment slot, so a two-line item can show e.g. an up
    /// arrow with a right-aligned value on the first row and a down arrow with
    /// a right-aligned value on the second.
    var leadingIcon: MenuBarIconSpec?
    var color: LineColor
    var isBold: Bool
    var fontSize: Double?
    var usesMonospacedDigits: Bool
    var alignment: LineAlignment

    init(
        elements: [MenuBarElement] = [],
        leadingIcon: MenuBarIconSpec? = nil,
        color: LineColor = .systemDefault,
        isBold: Bool = false,
        fontSize: Double? = nil,
        usesMonospacedDigits: Bool = true,
        alignment: LineAlignment = .leading
    ) {
        self.elements = elements
        self.leadingIcon = leadingIcon
        self.color = color
        self.isBold = isBold
        self.fontSize = fontSize
        self.usesMonospacedDigits = usesMonospacedDigits
        self.alignment = alignment
    }

    var isEmpty: Bool {
        elements.allSatisfy { element in
            if case .text(let text) = element.content { return text.isEmpty }
            return false
        }
    }

    var metrics: [MenuBarMetricID] {
        elements.compactMap { element in
            if case .metric(let metric) = element.content { return metric }
            return nil
        }
    }
}

extension MenuBarLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case elements, leadingIcon, color, isBold, fontSize, usesMonospacedDigits, alignment
    }
    // Legacy v1 keys.
    private enum LegacyKeys: String, CodingKey {
        case segments, icon
    }

    private enum LegacySegmentKind: String, Codable { case text, metric }
    private struct LegacySegment: Decodable {
        let kind: LegacySegmentKind
        let text: String?
        let metric: String?
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(LegacySegmentKind.self, forKey: .type)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            metric = try container.decodeIfPresent(String.self, forKey: .metric)
        }
        enum CodingKeys: String, CodingKey { case type, text, metric }
    }
    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.leadingIcon = try container.decodeIfPresent(MenuBarIconSpec.self, forKey: .leadingIcon)
        self.color = try container.decodeIfPresent(LineColor.self, forKey: .color) ?? .systemDefault
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        self.usesMonospacedDigits = try container.decodeIfPresent(Bool.self, forKey: .usesMonospacedDigits) ?? true
        self.alignment = try container.decodeIfPresent(LineAlignment.self, forKey: .alignment) ?? .leading

        if container.contains(.elements) {
            let wrapped = (try? container.decodeIfPresent([Failable<MenuBarElement>].self, forKey: .elements)) ?? nil
            self.elements = (wrapped ?? []).compactMap(\.value)
        } else {
            // Legacy v1 migration.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            var migrated: [MenuBarElement] = []
            if let icon = try legacy.decodeIfPresent(MenuBarIconSpec.self, forKey: .icon) {
                migrated.append(MenuBarElement(content: .icon(icon)))
            }
            let wrapped = (try? legacy.decodeIfPresent([Failable<LegacySegment>].self, forKey: .segments)) ?? nil
            for item in wrapped ?? [] {
                guard let segment = item.value else { continue }
                switch segment.kind {
                case .text:
                    migrated.append(MenuBarElement(content: .text(segment.text ?? "")))
                case .metric:
                    if let raw = segment.metric, let metric = MenuBarMetricID(rawValue: raw) {
                        migrated.append(MenuBarElement(content: .metric(metric)))
                    }
                }
            }
            self.elements = migrated
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elements, forKey: .elements)
        try container.encodeIfPresent(leadingIcon, forKey: .leadingIcon)
        try container.encode(color, forKey: .color)
        try container.encode(isBold, forKey: .isBold)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
        try container.encode(usesMonospacedDigits, forKey: .usesMonospacedDigits)
        try container.encode(alignment, forKey: .alignment)
    }
}

/// Convenience shim kept for tests/callers that still describe a line as a
/// simple text/metric run. New code should use `MenuBarElement` directly.
enum MenuBarLineSegment: Equatable, Sendable {
    case text(String)
    case metric(MenuBarMetricID)
}

extension MenuBarLine {
    init(
        segments: [MenuBarLineSegment],
        color: LineColor = .systemDefault,
        isBold: Bool = false,
        fontSize: Double? = nil,
        usesMonospacedDigits: Bool = true,
        alignment: LineAlignment = .leading
    ) {
        self.init(
            elements: segments.map { segment in
                switch segment {
                case .text(let text): return MenuBarElement(content: .text(text))
                case .metric(let metric): return MenuBarElement(content: .metric(metric))
                }
            },
            color: color,
            isBold: isBold,
            fontSize: fontSize,
            usesMonospacedDigits: usesMonospacedDigits,
            alignment: alignment
        )
    }
}

enum SystemSettingsPane: String, Codable, CaseIterable, Sendable {
    case wifi, bluetooth, battery, sound, network
}

enum InstanceActivation: Codable, Equatable, Sendable {
    case none
    case sameAsMainIcon
    case panel(String)
    case openAppSettings
    case openActivityMonitor
    case openSystemSettings(SystemSettingsPane)
}

enum InstanceRightClick: Codable, Equatable, Sendable {
    case sameAsMainIcon
    case quickAction(String)
}

struct MenuBarInstance: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var layoutMode: MenuBarLayoutMode
    var top: MenuBarLine?
    var bottom: MenuBarLine?
    var leadingIcon: MenuBarIconSpec?
    var innerPadding: Double
    var outerMargin: Double
    var minimumWidth: Double?
    var clickAction: InstanceActivation
    var hoverAction: InstanceActivation
    var rightClick: InstanceRightClick

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        layoutMode: MenuBarLayoutMode = .doubleLine,
        top: MenuBarLine? = nil,
        bottom: MenuBarLine? = nil,
        leadingIcon: MenuBarIconSpec? = nil,
        innerPadding: Double = 0,
        outerMargin: Double = 4,
        minimumWidth: Double? = nil,
        clickAction: InstanceActivation = .panel("summary"),
        hoverAction: InstanceActivation = .none,
        rightClick: InstanceRightClick = .sameAsMainIcon
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.layoutMode = layoutMode
        self.top = top
        self.bottom = bottom
        self.leadingIcon = leadingIcon
        self.innerPadding = innerPadding
        self.outerMargin = outerMargin
        self.minimumWidth = minimumWidth
        self.clickAction = clickAction
        self.hoverAction = hoverAction
        self.rightClick = rightClick
    }

    static func `default`() -> MenuBarInstance {
        MenuBarInstance(
            layoutMode: .doubleLine,
            top: MenuBarLine(elements: [
                MenuBarElement(content: .text("CPU ")),
                MenuBarElement(content: .metric(.cpuUsage)),
            ])
        )
    }

    /// Lines actually rendered for the current layout mode.
    var renderedLines: [(slot: MenuBarLineSlot, line: MenuBarLine)] {
        switch layoutMode {
        case .singleLine:
            return top.map { [(.top, $0)] } ?? []
        case .doubleLine:
            return [top, bottom].compactMap { $0 }.enumerated().map { index, line in
                (index == 0 ? .top : .bottom, line)
            }
        }
    }

    var hasVisibleContent: Bool {
        renderedLines.contains { !$0.line.isEmpty }
    }

    var allMetrics: Set<MenuBarMetricID> {
        Set(renderedLines.flatMap { $0.line.metrics })
    }

    var demandedMetrics: Set<MenuBarMetricID> {
        isEnabled && hasVisibleContent ? allMetrics : []
    }
}

enum MenuBarLineSlot: String, Codable, Equatable, Sendable {
    case top
    case bottom
}

extension MenuBarInstance: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, layoutMode, top, bottom, leadingIcon
        case innerPadding, outerMargin, minimumWidth, clickAction, hoverAction, rightClick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.top = try container.decodeIfPresent(MenuBarLine.self, forKey: .top)
        self.bottom = try container.decodeIfPresent(MenuBarLine.self, forKey: .bottom)
        if let mode = try container.decodeIfPresent(MenuBarLayoutMode.self, forKey: .layoutMode) {
            self.layoutMode = mode
        } else {
            // v1 had no explicit mode; two non-nil lines meant two rows.
            self.layoutMode = self.bottom == nil ? .singleLine : .doubleLine
        }
        self.leadingIcon = try container.decodeIfPresent(MenuBarIconSpec.self, forKey: .leadingIcon)
        self.innerPadding = try container.decodeIfPresent(Double.self, forKey: .innerPadding) ?? 0
        self.outerMargin = try container.decodeIfPresent(Double.self, forKey: .outerMargin) ?? 4
        self.minimumWidth = try container.decodeIfPresent(Double.self, forKey: .minimumWidth)
        self.clickAction = try container.decodeIfPresent(InstanceActivation.self, forKey: .clickAction) ?? .panel("summary")
        self.hoverAction = try container.decodeIfPresent(InstanceActivation.self, forKey: .hoverAction) ?? .none
        self.rightClick = try container.decodeIfPresent(InstanceRightClick.self, forKey: .rightClick) ?? .sameAsMainIcon
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(layoutMode, forKey: .layoutMode)
        try container.encodeIfPresent(top, forKey: .top)
        try container.encodeIfPresent(bottom, forKey: .bottom)
        try container.encodeIfPresent(leadingIcon, forKey: .leadingIcon)
        try container.encode(innerPadding, forKey: .innerPadding)
        try container.encode(outerMargin, forKey: .outerMargin)
        try container.encodeIfPresent(minimumWidth, forKey: .minimumWidth)
        try container.encode(clickAction, forKey: .clickAction)
        try container.encode(hoverAction, forKey: .hoverAction)
        try container.encode(rightClick, forKey: .rightClick)
    }
}

struct MenuBarInstancesConfiguration: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var instances: [MenuBarInstance]

    init(schemaVersion: Int = 2, instances: [MenuBarInstance] = []) {
        self.schemaVersion = schemaVersion
        self.instances = instances
    }

    static let empty = MenuBarInstancesConfiguration()

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
            if let width = instance.minimumWidth {
                instance.minimumWidth = width.clamped(to: 20...400)
            }
            instance.top = instance.top.map { Self.normalize(line: $0, warnings: &warnings) }
            instance.bottom = instance.bottom.map { Self.normalize(line: $0, warnings: &warnings) }
            if instance.layoutMode == .singleLine && instance.top == nil {
                instance.top = instance.bottom
            }
            if !instance.hasVisibleContent { instance.isEnabled = false }
            kept.append(instance)
        }
        if kept.count > limit {
            warnings.append("Too many menu-bar instances (\(kept.count)); kept the first \(limit).")
            kept = Array(kept.prefix(limit))
        }
        return (MenuBarInstancesConfiguration(schemaVersion: max(2, schemaVersion), instances: kept), warnings)
    }

    private static func normalize(line: MenuBarLine, warnings: inout [String]) -> MenuBarLine {
        var line = line
        var elements: [MenuBarElement] = []
        for element in line.elements.prefix(32) {
            switch element.content {
            case .text(var text):
                if text.count > 64 { text = String(text.prefix(64)) }
                elements.append(MenuBarElement(id: element.id, content: .text(text)))
            case .metric(let metric):
                if MenuBarMetricID.allCases.contains(metric) {
                    elements.append(element)
                } else {
                    warnings.append("Dropped unsupported metric \(metric.rawValue).")
                }
            case .icon:
                elements.append(element)
            }
        }
        if line.elements.count > 32 { warnings.append("Line truncated to 32 elements.") }
        line.elements = elements
        return line
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        isFinite ? min(range.upperBound, max(range.lowerBound, self)) : range.lowerBound
    }
}
