import Foundation

/// The concrete semantic catalog for Status Trio settings.
///
/// This is authored data, not derived from UserDefaults. It intentionally covers
/// the modules and complex cases described by the settings-semantic plan; the
/// Phase 0 inventory is the checklist that Phase 4 grows this catalog against.
///
/// Logical ids are stable and semantic. They are deliberately **not** UserDefaults
/// keys; `storageKey` records the real underlying key when the provider is core
/// settings, and is `nil` when the setting is virtual or owned by another provider.
enum SettingsSemanticCatalog {

    // MARK: - Value helpers

    private static func s(_ value: String) -> SettingsTransferValue { .string(value) }
    private static func b(_ value: Bool) -> SettingsTransferValue { .bool(value) }
    private static func n(_ value: Double) -> SettingsTransferValue { .number(value) }

    private static func opt(_ id: String, _ title: String, _ description: String? = nil) -> SettingsOptionDescriptor {
        SettingsOptionDescriptor(id: id, title: title, description: description, value: s(id))
    }

    /// Build a preference with only the fields the author knows.
    private static func pref(
        _ id: String,
        _ title: String,
        _ category: String,
        _ type: SettingsValueType,
        _ description: String? = nil,
        _ configure: (inout SettingsPreferenceDescriptor) -> Void = { _ in }
    ) -> SettingsPreferenceDescriptor {
        var descriptor = SettingsPreferenceDescriptor(
            id: id, title: title, category: category, type: type, description: description
        )
        configure(&descriptor)
        return descriptor
    }

    /// A UI-only underlying field: persisted and readable by the service, but not
    /// separately exposed as an ordinary writable user setting.
    private static let underlyingOnly = SettingsAccessPolicy(
        uiAccessible: false,
        developmentProfile: false,
        transferable: false,
        externalRead: false,
        externalWrite: false
    )

    /// Described but not yet wired to a provider adapter: visible in the UI and
    /// in the schema, but not writable by a development profile or externally.
    private static let describedNotWritable = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: false,
        transferable: false,
        externalRead: true,
        externalWrite: false
    )

    /// Described, sensitive (device identity / paths), and not writable by a
    /// profile or externally.
    private static let sensitiveDescribed = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: false,
        transferable: false,
        externalRead: false,
        externalWrite: false,
        containsSensitiveInfo: true
    )

    /// A setting with a real system side effect (login item, helper, power).
    private static let systemRestricted = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: false,
        transferable: false,
        externalRead: false,
        externalWrite: false,
        requiresConfirmation: true,
        containsSensitiveInfo: false,
        systemSideEffect: true
    )

    // MARK: - Registry

    static func makeRegistry(appVersion: String? = nil) -> SettingsSemanticRegistry {
        SettingsSemanticRegistry(
            schemaVersion: currentSchemaVersion,
            appVersion: appVersion,
            preferences: preferences,
            features: features,
            capabilities: capabilities,
            actions: actions
        )
    }

    static let currentSchemaVersion = 1

    // MARK: - Capabilities

    static let capabilities: [SettingsCapabilityDescriptor] = [
        SettingsCapabilityDescriptor(id: "ui.liquidGlass", title: "Liquid Glass 界面", description: "当前系统是否支持 NSGlassEffectView（macOS 26+）。"),
        SettingsCapabilityDescriptor(id: "hardware.hasBattery", title: "内置电池", description: "当前机器是否内置电池。"),
        SettingsCapabilityDescriptor(id: "hardware.hasFan", title: "风扇", description: "当前机器是否有可读风扇转速。"),
        SettingsCapabilityDescriptor(id: "sensor.cpu.temperature", title: "CPU 温度传感器", description: "是否可读取 CPU 温度。"),
        SettingsCapabilityDescriptor(id: "sensor.gpu.temperature", title: "GPU 温度传感器", description: "是否可读取 GPU 温度。"),
        SettingsCapabilityDescriptor(id: "permission.bluetooth", title: "蓝牙权限", description: "是否已获得蓝牙访问权限。"),
        SettingsCapabilityDescriptor(id: "permission.location", title: "定位权限", description: "是否已获得定位权限（Wi-Fi 名称等）。"),
        SettingsCapabilityDescriptor(id: "helper.available", title: "Helper 可用", description: "特权 Helper 是否已安装。"),
        SettingsCapabilityDescriptor(id: "helper.ready", title: "Helper 就绪", description: "特权 Helper 是否已连接并就绪。"),
        SettingsCapabilityDescriptor(id: "integration.betterDisplay", title: "BetterDisplay", description: "是否检测到 BetterDisplay 集成。"),
        SettingsCapabilityDescriptor(id: "distribution.direct", title: "直发版本", description: "是否为 GitHub Direct 分发版本。"),
        SettingsCapabilityDescriptor(id: "distribution.appStore", title: "App Store 版本", description: "是否为 App Store 分发版本。"),
    ]

    // MARK: - Actions

    static let actions: [SettingsActionDescriptor] = [
        SettingsActionDescriptor(id: "action.checkForUpdates", title: "检查更新", description: "触发一次 Sparkle 更新检查。", systemSideEffect: false, accessPolicy: .uiOnly),
        SettingsActionDescriptor(id: "action.chargeToFullNow", title: "立即充满电", description: "通过 Helper 立即把充电上限设为 100%。", systemSideEffect: true, accessPolicy: .restricted),
        SettingsActionDescriptor(id: "action.enableLidSleep", title: "启用盒盖不睡眠", description: "通过 Helper 开启合盖不睡眠。", systemSideEffect: true, accessPolicy: .restricted),
        SettingsActionDescriptor(id: "action.requestBluetoothPermission", title: "请求蓝牙权限", description: "弹出系统蓝牙授权提示。", systemSideEffect: true, accessPolicy: .restricted),
        SettingsActionDescriptor(id: "action.installHelper", title: "安装 Helper", description: "安装特权 Helper。", systemSideEffect: true, accessPolicy: .restricted),
        SettingsActionDescriptor(id: "action.readChargeLimit", title: "读取系统充电上限", description: "读取当前系统充电上限。", systemSideEffect: false, accessPolicy: .uiOnly),
        SettingsActionDescriptor(id: "action.resetIcon", title: "重置图标", description: "把图标外观恢复为默认配置。", systemSideEffect: false, accessPolicy: .uiOnly),
    ]

    // MARK: - Preferences

    static let preferences: [SettingsPreferenceDescriptor] = [
        // ---- General ----
        pref("general.language", "语言", "general", .enumeration, "App 界面语言；由 Localization 管理，不通过 UserDefaults 存储。") { d in
            d.uiPath = "设置 › 通用 › 语言"
            d.optionsProvider = "localization.languages"
            d.keywords = ["language", "语言"]
            d.accessPolicy = .profileSafe
            d.provider = "localization"
        },
        pref("general.launchAtLogin", "登录时启动", "general", .boolean, "登录时自动启动 App。由系统登录项管理，具有系统副作用。") { d in
            d.uiPath = "设置 › 通用 › 登录时启动"
            d.keywords = ["launch", "login", "启动"]
            d.accessPolicy = systemRestricted
            d.provider = "launchAtLogin"
        },
        pref("general.menuBarRightClickAction", "菜单栏右键行为", "general", .enumeration, "右键点击菜单栏图标时执行的动作。") { d in
            d.uiPath = "设置 › 通用 › 菜单栏右键"
            d.options = [
                opt("contextMenu", "打开右键菜单"),
                opt("toggleLowPowerMode", "切换低电量模式"),
                opt("chargeToFullNow", "立即充满电"),
                opt("toggleMute", "切换静音"),
                opt("toggleWiFi", "切换 Wi-Fi"),
                opt("refreshStatus", "刷新状态"),
                opt("openWiFiSettings", "打开 Wi-Fi 设置"),
                opt("openBluetoothSettings", "打开蓝牙设置"),
                opt("openBatterySettings", "打开电池设置"),
                opt("openSoundSettings", "打开声音设置"),
            ]
            d.storageKey = "menuBarRightClickAction"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("general.iconSize", "图标大小", "general", .number, "菜单栏图标尺寸。") { d in
            d.uiPath = "设置 › 通用 › 图标大小"
            d.range = SettingsNumericRange(min: 16, max: 36)
            d.step = 1
            d.unit = "pt"
            d.defaultValue = n(24)
            d.storageKey = "menuBarIconSize"
            d.accessPolicy = .transferable
            d.provider = "core"
        },

        // ---- Panel ----
        pref("panel.appearance.backgroundStyle", "状态面板背景样式", "panel", .enumeration, "状态面板窗口的背景材质。Liquid Glass 仅在 macOS 26+ 可渲染，旧系统回退到经典材质；降低透明度时始终使用纯色。") { d in
            d.uiPath = "设置 › 状态面板 › 背景样式"
            d.options = [
                opt("liquidGlass", "液态玻璃", "macOS 26+ 原生玻璃材质。"),
                opt("classicMaterial", "经典材质", "Tahoe 之前的毛玻璃材质。"),
                opt("solid", "纯色", "跟随系统明暗的纯色背景。"),
            ]
            d.availableWhen = .capability("ui.liquidGlass")
            d.storageKey = "panelBackgroundStyle"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("panel.appearance.boldText", "面板粗体文字", "panel", .boolean, "同时启用标题/数值的半粗体与说明文字的中等字重。这是一个虚拟设置：一次改动两个底层字重字段。") { d in
            d.uiPath = "设置 › 状态面板 › 粗体文字"
            // `value: nil` means "mirror the triggering value" — both weights follow the toggle.
            d.onChange = [
                SettingsMutationDescriptor(id: "panel.appearance.boldText.titleWeight", operation: .set, value: nil),
                SettingsMutationDescriptor(id: "panel.appearance.boldText.mediumWeight", operation: .set, value: nil),
            ]
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("panel.appearance.boldText.titleWeight", "面板标题字重（底层）", "panel", .boolean, "由“面板粗体文字”联动；不单独暴露。") { d in
            d.storageKey = "statusPanelBoldTextEnabled.v2"
            d.accessPolicy = underlyingOnly
            d.provider = "core"
        },
        pref("panel.appearance.boldText.mediumWeight", "面板说明字重（底层）", "panel", .boolean, "由“面板粗体文字”联动；不单独暴露。") { d in
            d.storageKey = "statusPanelMediumTextEnabled.v2"
            d.accessPolicy = underlyingOnly
            d.provider = "core"
        },
        pref("panel.behavior.showOnHover", "悬停展开状态面板", "panel", .boolean, "鼠标悬停菜单栏图标时自动展开状态面板。") { d in
            d.uiPath = "设置 › 状态面板 › 悬停展开"
            d.storageKey = "showsPanelOnHover"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("panel.behavior.keepOpenWhenOpeningSettings", "打开设置时保持面板", "panel", .boolean, "从状态面板打开设置时保持面板不关闭。") { d in
            d.uiPath = "设置 › 状态面板 › 打开设置时保持面板"
            d.storageKey = "keepsStatusPanelOpenWhenOpeningSettings"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("panel.modules.enabled", "启用的面板模块", "panel", .set, "状态面板中启用的模块集合及顺序。") { d in
            d.uiPath = "设置 › 状态面板 › 模块"
            d.optionsProvider = "panel.sections"
            d.storageKey = "enabledPopupSections"
            d.accessPolicy = .transferable
            d.provider = "core"
        },

        // ---- Icon / outer ring / center / footer ----
        pref("icon.outerRing.source", "外环来源", "icon", .enumeration, "菜单栏图标外环显示的内容。") { d in
            d.uiPath = "设置 › 图标 › 外环来源"
            d.options = [
                opt("systemBattery", "Mac 电池"),
                opt("airPodsBattery", "AirPods 电池"),
                opt("hardwareMonitor", "系统监控"),
            ]
            d.storageKey = "outerRingContent"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("icon.outerRing.hardware.layout", "硬件外环布局", "icon", .enumeration, "硬件监控外环的画法：单环一个指标，双环一主一副。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 布局"
            d.options = [opt("single", "单环"), opt("dual", "双环")]
            d.defaultValue = s("single")
            d.effectiveWhen = .equals(preference: "icon.outerRing.source", value: s("hardwareMonitor"))
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("icon.outerRing.hardware.primaryMetric", "硬件外环主要指标", "icon", .enumeration, "硬件外环的主指标。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 主要指标"
            d.optionsProvider = "hardware.ringMetrics"
            d.effectiveWhen = .equals(preference: "icon.outerRing.source", value: s("hardwareMonitor"))
            d.constraints = [
                SettingsConstraint(
                    kind: .distinctValues,
                    other: "icon.outerRing.hardware.secondaryMetric",
                    when: .equals(preference: "icon.outerRing.hardware.layout", value: s("dual")),
                    resolution: .swap,
                    message: "双环主副指标不能相同，选择重复指标时自动交换。"
                )
            ]
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("icon.outerRing.hardware.secondaryMetric", "硬件外环次要指标", "icon", .enumeration, "硬件外环的副指标（仅双环布局生效）。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 次要指标"
            d.optionsProvider = "hardware.ringMetrics"
            d.effectiveWhen = .allOf([
                .equals(preference: "icon.outerRing.source", value: s("hardwareMonitor")),
                .equals(preference: "icon.outerRing.hardware.layout", value: s("dual")),
            ])
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("icon.outerRing.hardware.ringSlots", "启用的硬件圆环", "icon", .set, "状态面板硬件摘要中启用的圆环（CPU/GPU/RAM/SSD）。至少保留一个；如需隐藏全部圆环请关闭“显示硬件圆环”，不要清空集合。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 圆环"
            d.options = [opt("cpu", "CPU"), opt("gpu", "GPU"), opt("ram", "内存"), opt("ssd", "SSD")]
            d.constraints = [
                SettingsConstraint(kind: .minimumCount, resolution: .reject, message: "至少保留一个硬件圆环。", min: 1)
            ]
            d.storageKey = "enabledHardwareRingSlotsV1"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("icon.outerRing.hardware.memoryPressureColors", "内存压力颜色", "icon", .map, "顶部标识与底部指示器共用的内存压力三档颜色（正常/警告/严重）；默认沿用历史绿/橙/红，改一处两处同时生效。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 内存压力颜色"
            d.storageKey = "hardwareRingConfigurationV1"
            d.accessPolicy = describedNotWritable
            d.provider = "core"
        },
        pref("icon.center.source", "中间槽来源", "icon", .enumeration, "菜单栏与 Dock 共享的中间槽内容来源。") { d in
            d.uiPath = "设置 › 图标 › 中间来源"
            d.options = [
                opt("network", "网络"),
                opt("bluetoothDevice", "蓝牙设备"),
                opt("inputSource", "输入源"),
                opt("batteryPercentage", "电池电量"),
                opt("power", "功率"),
                opt("chargingStatus", "充电状态"),
            ]
            d.storageKey = "connectionCenterSource"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("icon.footer.source", "底部指标来源", "icon", .enumeration, "图标下方指示条报告的数量来源。") { d in
            d.uiPath = "设置 › 图标 › 底部指标"
            d.options = [
                opt("volume", "音量"),
                opt("wifi", "Wi-Fi 信号"),
                opt("battery", "电池电量"),
                opt("metric", "硬件指标"),
                opt("hidden", "隐藏"),
            ]
            d.storageKey = "bottomIndicatorSource"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("icon.footer.metric", "底部指标的具体指标", "icon", .enumeration, "底部指标来源选择“硬件指标”时，具体显示哪个指标。") { d in
            d.uiPath = "设置 › 图标 › 底部指标 › 指标"
            d.optionsProvider = "hardware.ringMetrics"
            d.effectiveWhen = .equals(preference: "icon.footer.source", value: s("metric"))
            d.storageKey = "bottomIndicatorMetric"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },

        // ---- Hardware monitor ----
        pref("hardware.rings.enabled", "显示硬件圆环", "hardware", .boolean, "是否在状态面板显示系统监控硬件圆环。关闭它可隐藏全部圆环而不清空圆环集合。") { d in
            d.uiPath = "设置 › 监控 › 显示圆环"
            d.defaultValue = b(true)
            d.storageKey = "showsHardwareRings"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .onDemand)
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("hardware.summary.enabled", "显示硬件摘要行", "hardware", .boolean, "在状态面板显示硬件摘要行。") { d in
            d.uiPath = "设置 › 监控 › 摘要行"
            d.defaultValue = b(true)
            d.storageKey = "showsHardwareSummaryRow"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("hardware.topApps.enabled", "显示占用最高的 App", "hardware", .boolean, "在状态面板显示 Top Apps。") { d in
            d.uiPath = "设置 › 监控 › Top Apps"
            d.defaultValue = b(true)
            d.storageKey = "showsHardwareTopApps"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("hardware.temperature.enabled", "温度监控", "hardware", .boolean, "采集并显示温度指标。关闭后相关温度读取停止，外环/底部温度指标会被替换。") { d in
            d.uiPath = "设置 › 监控 › 温度监控"
            d.defaultValue = b(true)
            d.storageKey = "hardwareTemperatureMonitoringEnabledV1"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["temperatureSampling"], activation: .onDemand)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.history.backgroundEnabled", "后台历史采集", "hardware", .boolean, "在后台持续采集硬件历史数据（即使面板未打开）。会带来持续开销，按需开启。") { d in
            d.uiPath = "设置 › 监控 › 后台历史"
            d.storageKey = "hardwareBackgroundHistoryEnabled"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareHistory"], activation: .continuous)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.cpuUsage", "CPU 占用刷新频率（秒）", "hardware", .integer, "面板上 CPU 占用指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 2, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareCPUUsageRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.gpuUsage", "GPU 占用刷新频率（秒）", "hardware", .integer, "面板上 GPU 占用指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 2, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareGPUUsageRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.memory", "内存刷新频率（秒）", "hardware", .integer, "面板上内存指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 2, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareMemoryRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.network", "网络刷新频率（秒）", "hardware", .integer, "面板上网络速度指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 1, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareNetworkRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.temperature", "温度刷新频率（秒）", "hardware", .integer, "面板上温度指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 4, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareTemperatureRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.refresh.disk", "磁盘刷新频率（秒）", "hardware", .integer, "面板上磁盘读写指标多久刷新一次。") { d in
            d.uiPath = "设置 › 监控 › 面板更新频率"
            d.range = SettingsNumericRange(min: 1, max: 8)
            d.unit = "s"
            d.storageKey = "hardwareDiskRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.topApps.refreshSeconds", "高占用应用刷新频率（秒）", "hardware", .integer, "详情页底部高占用应用列表多久刷新一次；内存列表受自身 6 秒下限限制。") { d in
            d.uiPath = "设置 › 监控 › 高占用应用刷新频率"
            d.range = SettingsNumericRange(min: 1, max: 30)
            d.unit = "s"
            d.storageKey = "hardwareTopAppsRefreshSeconds"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.history.windowMinutes", "历史记录长度（分钟）", "hardware", .integer, "硬件历史图表的窗口长度。") { d in
            d.uiPath = "设置 › 监控 › 历史长度"
            d.range = SettingsNumericRange(min: 1, max: 180)
            d.unit = "min"
            d.storageKey = "hardwareHistoryWindowMinutes"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("hardware.network.downloadCapMbps", "下载速度上限（Mbps）", "hardware", .number, "网络速度图表按此上限归一化。") { d in
            d.uiPath = "设置 › 监控 › 网络 › 下载上限"
            d.range = SettingsNumericRange(min: 1, max: 100000)
            d.unit = "Mbps"
            d.storageKey = "hardwareDownloadCapMbps"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("hardware.network.uploadCapMbps", "上传速度上限（Mbps）", "hardware", .number, "网络速度图表按此上限归一化。") { d in
            d.uiPath = "设置 › 监控 › 网络 › 上传上限"
            d.range = SettingsNumericRange(min: 1, max: 100000)
            d.unit = "Mbps"
            d.storageKey = "hardwareUploadCapMbps"
            d.accessPolicy = .transferable
            d.provider = "core"
        },

        // ---- Battery & keep awake ----
        pref("battery.thresholds.critical", "低电量颜色阈值", "battery", .number, "电池低于该百分比时图标转为低电量颜色。") { d in
            d.uiPath = "设置 › 电池 › 低电量阈值"
            d.range = SettingsNumericRange(min: 0, max: 100)
            d.unit = "%"
            d.storageKey = "batteryCriticalThreshold"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("battery.thresholds.full", "满电阈值", "battery", .number, "电池达到该百分比时视为满电（仅用于显示，不等于系统充电上限）。") { d in
            d.uiPath = "设置 › 电池 › 满电阈值"
            d.range = SettingsNumericRange(min: 0, max: 100)
            d.unit = "%"
            d.storageKey = "batteryFullThreshold"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("battery.automation.autoLowPower", "自动开启低电量模式", "battery", .boolean, "电量低于阈值时自动开启系统低电量模式。具有真实系统影响。") { d in
            d.uiPath = "设置 › 电池 › 自动低电量模式"
            d.storageKey = "autoEnablesLowPowerMode"
            d.constraints = [
                SettingsConstraint(kind: .requires, other: "battery.automation.lowPowerThreshold", resolution: .reject, message: "需先设置低电量模式阈值。")
            ]
            d.accessPolicy = systemRestricted
            d.provider = "core"
        },
        pref("battery.automation.lowPowerThreshold", "自动低电量模式阈值", "battery", .number, "触发自动低电量模式的电量百分比（独立于低电量颜色阈值）。") { d in
            d.uiPath = "设置 › 电池 › 自动低电量模式阈值"
            d.range = SettingsNumericRange(min: 0, max: 100)
            d.unit = "%"
            d.defaultValue = n(20)
            d.storageKey = "autoLowPowerThreshold"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("battery.powerFlow.enabled", "显示电量流向", "battery", .boolean, "在面板电池模块显示输入/电池/系统功率流向图。") { d in
            d.uiPath = "设置 › 电池 › 电量流向"
            d.storageKey = "showsBatteryPowerFlow"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("battery.highEnergyApps.enabled", "显示高耗能 App", "battery", .boolean, "在电池模块显示高耗能 App 列表。") { d in
            d.uiPath = "设置 › 电池 › 高耗能 App"
            d.storageKey = "showsHighEnergyApps"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["energySampling"], activation: .periodic)
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("keepAwake.displayControl", "显示“保持屏幕常亮”按钮", "battery", .boolean, "在面板显示保持屏幕常亮的控制按钮（仅显示控件）。") { d in
            d.uiPath = "设置 › 保持唤醒 › 屏幕常亮"
            d.storageKey = "showsKeepScreenButton"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("keepAwake.lidControl", "显示“盒盖不睡眠”按钮", "battery", .boolean, "在面板显示盒盖不睡眠的控制按钮（仅显示控件，不代表已开启）。") { d in
            d.uiPath = "设置 › 保持唤醒 › 盒盖不睡眠"
            d.storageKey = "showsLidSleepButton"
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("keepAwake.allowLidSleepOnBattery", "使用电池时允许盒盖不睡眠", "battery", .boolean, "在电池供电时允许合盖不睡眠。具有真实系统影响。") { d in
            d.uiPath = "设置 › 保持唤醒 › 电池供电"
            d.storageKey = "allowLidSleepOnBattery"
            d.accessPolicy = systemRestricted
            d.provider = "core"
        },
        pref("keepAwake.autoDisableOnLowBattery", "低电量时自动关闭盒盖不睡眠", "battery", .boolean, "电量过低时自动停止盒盖不睡眠。具有真实系统影响。") { d in
            d.uiPath = "设置 › 保持唤醒 › 低电量自动关闭"
            d.storageKey = "autoDisableLidSleepOnLowBattery"
            d.accessPolicy = systemRestricted
            d.provider = "core"
        },

        // ---- Bluetooth ----
        pref("bluetooth.deviceList.enabled", "显示蓝牙设备列表", "bluetooth", .boolean, "在面板显示蓝牙设备列表。") { d in
            d.uiPath = "设置 › 蓝牙 › 设备列表"
            d.storageKey = "showsBluetoothDeviceList"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("bluetooth.batteryLevels.enabled", "显示蓝牙设备电量", "bluetooth", .boolean, "显示已连接蓝牙设备的电量。") { d in
            d.uiPath = "设置 › 蓝牙 › 设备电量"
            d.storageKey = "showsBluetoothBatteryLevels"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("bluetooth.appleBattery.backgroundRefresh", "后台刷新 Apple 设备电量", "bluetooth", .boolean, "在后台定期读取 Apple 设备（AirPods 等）电量。") { d in
            d.uiPath = "设置 › 蓝牙 › 后台刷新"
            d.storageKey = "refreshesAppleBatteriesInBackground"
            d.performanceImpact = SettingsPerformanceImpact(resources: ["appleBatterySampling"], activation: .periodic)
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },
        pref("bluetooth.devices.hidden", "隐藏的蓝牙设备", "bluetooth", .set, "按设备地址隐藏的蓝牙设备集合。设备地址属于敏感信息。") { d in
            d.uiPath = "设置 › 蓝牙 › 隐藏设备"
            d.storageKey = "hiddenBluetoothDeviceAddresses"
            d.accessPolicy = SettingsAccessPolicy(
                uiAccessible: true,
                developmentProfile: false,
                transferable: false,
                externalRead: false,
                externalWrite: false,
                requiresConfirmation: false,
                containsSensitiveInfo: true,
                systemSideEffect: false
            )
            d.provider = "core"
        },

        // ---- Audio ----
        pref("audio.output.maxVisibleDevices", "输出设备最大显示数量", "audio", .integer, "输出设备列表中最多显示的数量。") { d in
            d.uiPath = "设置 › 音量 › 输出设备数量"
            d.range = SettingsNumericRange(min: 1, max: 20)
            d.storageKey = "maxVisibleOutputDevices"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("audio.output.showAllDevices", "显示全部输出设备", "audio", .boolean, "忽略最大数量限制，显示全部输出设备。") { d in
            d.uiPath = "设置 › 音量 › 显示全部输出设备"
            d.storageKey = "alwaysShowsAllOutputDevices"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("audio.input.maxVisibleDevices", "输入设备最大显示数量", "audio", .integer, "输入设备列表中最多显示的数量。") { d in
            d.uiPath = "设置 › 麦克风 › 输入设备数量"
            d.range = SettingsNumericRange(min: 1, max: 20)
            d.storageKey = "maxVisibleInputDevices"
            d.accessPolicy = .transferable
            d.provider = "core"
        },
        pref("audio.input.showAllDevices", "显示全部输入设备", "audio", .boolean, "忽略最大数量限制，显示全部输入设备。") { d in
            d.uiPath = "设置 › 麦克风 › 显示全部输入设备"
            d.storageKey = "alwaysShowsAllInputDevices"
            d.accessPolicy = .transferable
            d.provider = "core"
        },

        // ---- Brightness ----
        pref("brightness.betterDisplay.combined", "BetterDisplay 合并亮度", "brightness", .boolean, "使用 BetterDisplay 的合并亮度控制。仅在检测到 BetterDisplay 时可见。") { d in
            d.uiPath = "设置 › 亮度 › BetterDisplay"
            d.storageKey = "useBetterDisplayCombinedBrightness"
            d.visibleWhen = .capability("integration.betterDisplay")
            d.accessPolicy = .profileSafe
            d.provider = "core"
        },

        // ---- Additional battery / charging ----
        pref("battery.charging.boltHeartbeat", "充电闪电心跳动画", "battery", .boolean, "充电时电池闪电图标的脉动动画。") { d in
            d.uiPath = "设置 › 电池 › 充电效果 › 心跳"
            d.storageKey = "showsChargingBoltHeartbeat"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.charging.menuBarEffect", "菜单栏充电效果", "battery", .boolean, "在菜单栏图标上显示充电效果。") { d in
            d.uiPath = "设置 › 电池 › 充电效果 › 菜单栏"
            d.storageKey = "showsMenuBarChargingEffect"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.charging.dockEffect", "Dock 充电效果", "battery", .boolean, "在 Dock 图标上显示充电效果。") { d in
            d.uiPath = "设置 › 电池 › 充电效果 › Dock"
            d.storageKey = "showsDockChargingEffect"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.splitGapProgress", "电量环断口进度", "battery", .boolean, "电量环在断口处按进度绘制。") { d in
            d.uiPath = "设置 › 电池 › 电量环"
            d.storageKey = "batterySplitGapProgress"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.powerInfoBar.enabled", "功率信息条", "battery", .boolean, "在面板电池模块显示输入/电池/系统功率信息条（实验性）。") { d in
            d.uiPath = "设置 › 电池 › 功率信息条"
            d.storageKey = "showsBatteryPowerInfoBar"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.chargeToFullButton.enabled", "显示立即充满按钮", "battery", .boolean, "显示“立即充满电”按钮（仅显示控件，不代表执行）。") { d in
            d.uiPath = "设置 › 电池 › 立即充满按钮"
            d.storageKey = "showsChargeToFullNowButton"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.automation.controlsLowPowerMode", "允许控制低电量模式", "battery", .boolean, "允许 App 控制系统低电量模式。具有系统影响。") { d in
            d.uiPath = "设置 › 电池 › 低电量模式控制"
            d.storageKey = "controlsLowPowerMode"; d.accessPolicy = systemRestricted; d.provider = "core"
        },
        pref("battery.statusColors.enabled", "使用电池状态颜色", "battery", .boolean, "按电量状态为电池图标着色。") { d in
            d.uiPath = "设置 › 电池 › 状态颜色"
            d.storageKey = "usesBatteryStatusColors"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.simulateNoBattery", "模拟无电池", "battery", .boolean, "开发/演示用：模拟设备无电池。") { d in
            d.uiPath = "设置 › 电池 › 模拟无电池"
            d.storageKey = "simulatesNoBattery"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.confirmWiFiPowerOff", "关闭 Wi-Fi 前确认", "battery", .boolean, "执行关闭 Wi-Fi 前要求确认。") { d in
            d.uiPath = "设置 › 电池 › Wi-Fi 关闭确认"
            d.storageKey = "confirmsWiFiPowerOff"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.appleDevicesAndBattery.enabled", "显示 Apple 设备与电量", "battery", .boolean, "显示 Apple 设备及其电量。") { d in
            d.uiPath = "设置 › 电池 › Apple 设备"
            d.storageKey = "showsAppleDevicesAndBattery"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.bluetoothPowerControl.enabled", "显示蓝牙开关控件", "battery", .boolean, "显示蓝牙电源开关控件。") { d in
            d.uiPath = "设置 › 电池 › 蓝牙开关"
            d.storageKey = "showsBluetoothPowerControl"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.wifiPowerControl.enabled", "显示 Wi-Fi 开关控件", "battery", .boolean, "显示 Wi-Fi 电源开关控件。") { d in
            d.uiPath = "设置 › 电池 › Wi-Fi 开关"
            d.storageKey = "showsWiFiPowerControl"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.symbolScale", "电池符号缩放", "battery", .number, "电池图标的符号缩放比例。") { d in
            d.uiPath = "设置 › 电池 › 符号缩放"
            d.storageKey = "batterySymbolScale"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.chargeToFullRestoreLimit", "充满后恢复的充电上限", "battery", .number, "立即充满电后恢复到该充电上限百分比。") { d in
            d.uiPath = "设置 › 电池 › 充满后恢复上限"
            d.range = SettingsNumericRange(min: 0, max: 100); d.unit = "%"
            d.storageKey = "chargeToFullRestoreLimit"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.highEnergyApps.refreshIntervalSeconds", "高耗能 App 刷新间隔", "battery", .number, "高耗能 App 列表的刷新间隔。") { d in
            d.uiPath = "设置 › 电池 › 高耗能 App › 刷新间隔"
            d.unit = "s"; d.storageKey = "highEnergyAppsRefreshIntervalSeconds"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.marker.onBattery", "电池百分比标记", "battery", .enumeration, "使用电池时电量环顶部的标记样式。") { d in
            d.uiPath = "设置 › 电池 › 标记 › 使用电池"
            d.options = [opt("percentage", "百分比"), opt("bolt", "闪电"), opt("plug", "插头"), opt("hidden", "隐藏")]
            d.storageKey = "batteryOnBatteryMarker"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.marker.charging", "充电标记", "battery", .enumeration, "充电时电量环顶部的标记样式。") { d in
            d.uiPath = "设置 › 电池 › 标记 › 充电"
            d.options = [opt("percentage", "百分比"), opt("bolt", "闪电"), opt("plug", "插头"), opt("hidden", "隐藏")]
            d.storageKey = "batteryChargingMarker"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.marker.connected", "已连接标记", "battery", .enumeration, "已连接电源时电量环顶部的标记样式。") { d in
            d.uiPath = "设置 › 电池 › 标记 › 已连接"
            d.options = [opt("percentage", "百分比"), opt("bolt", "闪电"), opt("plug", "插头"), opt("hidden", "隐藏")]
            d.storageKey = "batteryConnectedMarker"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.marker.noBattery", "无电池标记", "battery", .enumeration, "无电池时的标记样式。") { d in
            d.uiPath = "设置 › 电池 › 标记 › 无电池"
            d.options = [opt("percentage", "百分比"), opt("bolt", "闪电"), opt("plug", "插头"), opt("hidden", "隐藏")]
            d.storageKey = "batteryNoBatteryMarker"; d.accessPolicy = .profileSafe; d.provider = "core"
        },

        // ---- Additional icon / network indicators ----
        pref("icon.airPods.ringUsesDualRing", "AirPods 使用双环", "icon", .boolean, "AirPods 电量使用双环显示左右耳。") { d in
            d.uiPath = "设置 › 图标 › AirPods › 双环"
            d.storageKey = "airPodsRingUsesDualRing"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.outerRing.hardware.splitGapProgress", "硬件环断口进度", "icon", .boolean, "硬件外环在断口处按进度绘制。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环 › 断口进度"
            d.storageKey = "hardwareRingSplitGapProgress"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.ring.monochromeCharging", "单色充电环", "icon", .boolean, "充电环使用单色绘制。") { d in
            d.uiPath = "设置 › 图标 › 充电环单色"
            d.storageKey = "monochromeChargingRing"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.airPods.topSymbolInRing", "AirPods 顶部符号", "icon", .boolean, "在 AirPods 环顶部显示符号。") { d in
            d.uiPath = "设置 › 图标 › AirPods › 顶部符号"
            d.storageKey = "showsAirPodsTopSymbolInRing"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.network.wifiIconForEthernet", "以太网用 Wi-Fi 图标", "icon", .boolean, "以太网连接时使用 Wi-Fi 图标。") { d in
            d.uiPath = "设置 › 图标 › 网络 › 以太网图标"
            d.storageKey = "showsWiFiIconForEthernet"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.network.wifiIconForHotspot", "热点用 Wi-Fi 图标", "icon", .boolean, "个人热点连接时使用 Wi-Fi 图标。") { d in
            d.uiPath = "设置 › 图标 › 网络 › 热点图标"
            d.storageKey = "showsWiFiIconForHotspot"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.network.wifiIconForInternetSharing", "共享用 Wi-Fi 图标", "icon", .boolean, "互联网共享时使用 Wi-Fi 图标。") { d in
            d.uiPath = "设置 › 图标 › 网络 › 共享图标"
            d.storageKey = "showsWiFiIconForInternetSharing"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.network.wifiIconForTemporaryConnection", "临时连接用 Wi-Fi 图标", "icon", .boolean, "临时连接时使用 Wi-Fi 图标。") { d in
            d.uiPath = "设置 › 图标 › 网络 › 临时连接图标"
            d.storageKey = "showsWiFiIconForTemporaryConnection"; d.accessPolicy = .profileSafe; d.provider = "core"
        },

        // ---- Additional panel / network / audio / brightness ----
        pref("panel.behavior.detailsAlongside", "详情面板并排展开", "panel", .boolean, "详情页面在状态面板旁并排展开。") { d in
            d.uiPath = "设置 › 状态面板 › 详情并排"
            d.storageKey = "showsPanelDetailsAlongside"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("panel.behavior.scrollWheelStepPercent", "滚轮步进百分比", "panel", .number, "面板滚轮每次调整的百分比步进。") { d in
            d.uiPath = "设置 › 状态面板 › 滚轮步进"
            d.unit = "%"; d.storageKey = "popupScrollWheelStepPercent"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("network.chart.fixedScale", "网络图表固定刻度", "network", .boolean, "网络速度图表使用固定刻度而非自适应。") { d in
            d.uiPath = "设置 › 网络 › 图表固定刻度"
            d.storageKey = "hardwareNetworkChartFixedScale"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("network.prioritizeErrors", "优先显示网络错误", "network", .boolean, "网络异常时优先显示错误而非其他图标。") { d in
            d.uiPath = "设置 › 网络 › 优先错误"
            d.storageKey = "prioritizesNetworkErrors"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("network.showLocalIPAddress", "显示本地 IP", "network", .boolean, "在面板显示本地 IP 地址。") { d in
            d.uiPath = "设置 › 网络 › 本地 IP"
            d.storageKey = "showsLocalIPAddress"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("network.symbolScale", "Wi-Fi 符号缩放", "network", .number, "Wi-Fi 图标的符号缩放比例。") { d in
            d.uiPath = "设置 › 网络 › 符号缩放"
            d.storageKey = "wifiSymbolScale"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("audio.popup.scrollAdjustsVolume", "滚轮调整音量", "audio", .boolean, "在面板上滚动滚轮调整音量。") { d in
            d.uiPath = "设置 › 音量 › 滚轮调整音量"
            d.storageKey = "popupPanelScrollAdjustsVolume"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("audio.popup.naturalScrolling", "自然滚动方向", "audio", .boolean, "音量滚轮使用自然滚动方向。") { d in
            d.uiPath = "设置 › 音量 › 自然滚动"
            d.storageKey = "popupVolumeNaturalScrolling"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("audio.spatialControls.enabled", "显示空间音频控件", "audio", .boolean, "显示空间音频（Spatial Audio）控制。") { d in
            d.uiPath = "设置 › 音量 › 空间音频"
            d.storageKey = "showsSpatialAudioControls"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("brightness.sliderMatchesBrightnessThickness", "滑块匹配亮度条粗细", "brightness", .boolean, "面板音量滑块粗细匹配亮度条。") { d in
            d.uiPath = "设置 › 亮度 › 滑块粗细"
            d.storageKey = "panelLevelSliderMatchesBrightnessThickness"; d.accessPolicy = .profileSafe; d.provider = "core"
        },

        // ---- Refresh intervals / SSD / remaining scalars ----
        pref("battery.refreshInterval.onBattery", "电池供电刷新间隔", "battery", .number, "电池供电时状态刷新间隔（秒）。") { d in
            d.uiPath = "设置 › 电池 › 刷新间隔"; d.unit = "s"
            d.storageKey = "statusRefreshIntervalOnBatterySeconds"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.refreshInterval.onPower", "接电源刷新间隔", "battery", .number, "接电源时状态刷新间隔（秒）。") { d in
            d.uiPath = "设置 › 电池 › 刷新间隔"; d.unit = "s"
            d.storageKey = "statusRefreshIntervalOnPowerSeconds"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.appleBattery.refreshIntervalMinutes", "Apple 设备电量刷新间隔", "battery", .integer, "后台读取 Apple 设备电量的间隔（分钟）。") { d in
            d.uiPath = "设置 › 电池 › Apple 设备 › 刷新间隔"; d.unit = "min"
            d.storageKey = "appleBatteryRefreshIntervalMinutes"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.maxVisibleDevices", "蓝牙设备最大显示数量", "bluetooth", .integer, "蓝牙设备列表最多显示的数量。") { d in
            d.uiPath = "设置 › 蓝牙 › 最大数量"; d.range = SettingsNumericRange(min: 1, max: 20)
            d.storageKey = "maxVisibleBluetoothDevices"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.listeningMode.enabled", "显示聆听模式", "bluetooth", .boolean, "显示 AirPods 聆听模式控制。") { d in
            d.uiPath = "设置 › 蓝牙 › 聆听模式"
            d.storageKey = "showsBluetoothListeningMode"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.listeningMode.previewEnabled", "预览聆听模式", "bluetooth", .boolean, "在设置页预览聆听模式控件。") { d in
            d.uiPath = "设置 › 蓝牙 › 聆听模式预览"
            d.storageKey = "previewsBluetoothListeningMode"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.listeningMode.previewDeviceCount", "预览设备数量", "bluetooth", .integer, "聆听模式预览使用的设备数量。") { d in
            d.uiPath = "设置 › 蓝牙 › 聆听模式预览"
            d.storageKey = "bluetoothListeningModePreviewDeviceCount"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.listeningMode.previewDeviceName", "预览设备名称", "bluetooth", .string, "聆听模式预览使用的设备名称。") { d in
            d.uiPath = "设置 › 蓝牙 › 聆听模式预览"
            d.storageKey = "bluetoothListeningModePreviewDeviceName"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.listeningMode.previewLanguage", "预览语言", "bluetooth", .string, "聆听模式预览使用的语言。") { d in
            d.uiPath = "设置 › 蓝牙 › 聆听模式预览"
            d.storageKey = "bluetoothListeningModePreviewLanguage"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("bluetooth.conversationAwarenessControls.enabled", "显示对话感知控件", "bluetooth", .boolean, "显示 AirPods 对话感知（Conversation Awareness）控件。") { d in
            d.uiPath = "设置 › 蓝牙 › 对话感知"
            d.storageKey = "showsConversationAwarenessControls"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.ssd.includeExternalInPercent", "外置磁盘计入百分比", "hardware", .boolean, "SSD 占用百分比时计入外置磁盘。") { d in
            d.uiPath = "设置 › 监控 › SSD › 外置磁盘"
            d.storageKey = "hardwareSSDIncludeExternalInPercentV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },

        // ---- Enumerated appearance & placement (scalar, provider-wired) ----
        pref("icon.appIconPlacement", "图标显示位置", "icon", .enumeration, "图标显示在菜单栏、Dock 或两者（Menu Bar 与 Dock 渲染同源）。") { d in
            d.uiPath = "设置 › 图标 › 位置"
            d.options = [opt("menuBar", "菜单栏"), opt("dock", "Dock"), opt("both", "两者")]
            d.storageKey = "appIconPlacement"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.dockIconBackground", "Dock 图标背景", "icon", .enumeration, "Dock 图标背景明暗。") { d in
            d.uiPath = "设置 › 图标 › Dock 背景"
            d.options = [opt("system", "跟随系统"), opt("dark", "深色"), opt("light", "浅色")]
            d.storageKey = "dockIconBackgroundPreference"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.airPodsRingFallback", "AirPods 环回退来源", "icon", .enumeration, "AirPods 环无数据时回退显示的内容。") { d in
            d.uiPath = "设置 › 图标 › AirPods › 回退"
            d.options = [opt("battery", "Mac 电池"), opt("hardwareMonitor", "系统监控")]
            d.storageKey = "airPodsRingFallback"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.cpuRingCenterContent", "CPU 环中心内容", "icon", .enumeration, "CPU 圆环中心显示温度或频率。") { d in
            d.uiPath = "设置 › 图标 › 硬件环 › CPU 中心"
            d.options = [opt("temperature", "温度"), opt("frequency", "频率")]
            d.storageKey = "cpuRingCenterContentV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.gpuRingCenterContent", "GPU 环中心内容", "icon", .enumeration, "GPU 圆环中心显示温度或频率。") { d in
            d.uiPath = "设置 › 图标 › 硬件环 › GPU 中心"
            d.options = [opt("temperature", "温度"), opt("frequency", "频率")]
            d.storageKey = "gpuRingCenterContentV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.ringStrokeStyle", "圆环描边粗细", "icon", .enumeration, "圆环描边粗细样式。") { d in
            d.uiPath = "设置 › 图标 › 描边"
            d.options = [opt("light", "细"), opt("regular", "标准"), opt("bold", "粗")]
            d.storageKey = "ringStrokeStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.inputSourceMarkerStyle", "输入源标记样式", "icon", .enumeration, "输入源指示的样式。") { d in
            d.uiPath = "设置 › 图标 › 输入源标记"
            d.options = [opt("systemIcon", "系统图标"), opt("script", "脚本"), opt("zhong", "中")]
            d.storageKey = "inputSourceMarkerStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("icon.localPluginDirectories", "本地图标插件目录", "icon", .orderedList, "用户显式启用的本地图标包目录（路径属敏感信息）。") { d in
            d.uiPath = "设置 › 图标 › 插件"
            d.storageKey = "localIconPluginDirectories.v1"
            d.accessPolicy = SettingsAccessPolicy(uiAccessible: true, developmentProfile: false, transferable: false, externalRead: false, externalWrite: false, requiresConfirmation: false, containsSensitiveInfo: true, systemSideEffect: false)
            d.provider = "core"
        },
        pref("audio.volumeDisplayStyle", "音量指示样式", "audio", .enumeration, "底部音量指示使用点阵或弧线。") { d in
            d.uiPath = "设置 › 音量 › 指示样式"
            d.options = [opt("dots", "点阵"), opt("arc", "弧线")]
            d.storageKey = "volumeDisplayStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("battery.bottomIndicatorStyle", "电池底部指示样式", "battery", .enumeration, "底部电池指示使用点阵或弧线。") { d in
            d.uiPath = "设置 › 电池 › 指示样式"
            d.options = [opt("dots", "点阵"), opt("arc", "弧线")]
            d.storageKey = "batteryBottomIndicatorStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.metricBottomIndicatorStyle", "硬件指标底部样式", "hardware", .enumeration, "底部硬件指标使用点阵或弧线。") { d in
            d.uiPath = "设置 › 监控 › 底部指标样式"
            d.options = [opt("dots", "点阵"), opt("arc", "弧线")]
            d.storageKey = "metricBottomIndicatorStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("network.wifiBottomIndicatorStyle", "Wi-Fi 底部样式", "network", .enumeration, "底部 Wi-Fi 指示使用点阵或弧线。") { d in
            d.uiPath = "设置 › 网络 › 底部样式"
            d.options = [opt("dots", "点阵"), opt("arc", "弧线")]
            d.storageKey = "wifiBottomIndicatorStyle"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.ring.memoryDisplayMode", "内存环显示模式", "hardware", .enumeration, "内存环显示已用或剩余。") { d in
            d.uiPath = "设置 › 监控 › 内存环"
            d.optionsProvider = "RingValueDisplayMode"
            d.storageKey = "memoryRingDisplayModeV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.ring.ssdDisplayMode", "SSD 环显示模式", "hardware", .enumeration, "SSD 环显示已用或剩余。") { d in
            d.uiPath = "设置 › 监控 › SSD 环"
            d.optionsProvider = "RingValueDisplayMode"
            d.storageKey = "ssdRingDisplayModeV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.ssd.externalVolumePaths", "外置磁盘卷路径", "hardware", .set, "计入 SSD 统计的外置磁盘卷路径（路径属敏感信息）。") { d in
            d.uiPath = "设置 › 监控 › SSD › 外置卷"
            d.storageKey = "hardwareSSDExternalVolumePathsV1"
            d.accessPolicy = SettingsAccessPolicy(uiAccessible: true, developmentProfile: false, transferable: false, externalRead: false, externalWrite: false, requiresConfirmation: false, containsSensitiveInfo: true, systemSideEffect: false)
            d.provider = "core"
        },

        // ---- Complex / composite / sensitive settings ----
        // Described for coverage; live write adapters for these composite/colour
        // blobs are deliberately not wired yet (see the implementation report).
        pref("audio.hiddenOutputDevices", "隐藏的输出设备", "audio", .set, "按设备 UID 隐藏的输出设备（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 音量 › 隐藏设备"; d.storageKey = "hiddenOutputDeviceUIDs"; d.accessPolicy = sensitiveDescribed
        },
        pref("audio.hiddenInputDevices", "隐藏的输入设备", "audio", .set, "按设备 UID 隐藏的输入设备（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 麦克风 › 隐藏设备"; d.storageKey = "hiddenInputDeviceUIDs"; d.accessPolicy = sensitiveDescribed
        },
        pref("brightness.hiddenDisplays", "隐藏的显示器", "brightness", .set, "按显示器 ID 隐藏的亮度设备（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 亮度 › 隐藏显示器"; d.storageKey = "hiddenBrightnessDisplayIDs"; d.accessPolicy = sensitiveDescribed
        },
        pref("battery.statusColors", "电池状态颜色", "battery", .object, "各电量状态的自定义颜色（放电/充电/已连接/低电量/高电量/严重）；复合设置，含 batteryStatusColors.* 子键。") { d in
            d.uiPath = "设置 › 电池 › 状态颜色"; d.storageKey = "batteryStatusColors.discharging"; d.accessPolicy = describedNotWritable
        },
        pref("bluetooth.deviceOrder", "蓝牙设备排序", "bluetooth", .orderedList, "蓝牙设备列表的显示顺序。") { d in
            d.uiPath = "设置 › 蓝牙 › 排序"; d.storageKey = "bluetoothDeviceOrder"; d.accessPolicy = describedNotWritable
        },
        pref("bluetooth.volumeColor", "蓝牙音量颜色", "bluetooth", .taggedUnion, "蓝牙音量指示颜色（自动或自定义）。") { d in
            d.uiPath = "设置 › 蓝牙 › 音量颜色"; d.storageKey = "bluetoothVolumeColor"; d.accessPolicy = describedNotWritable
        },
        pref("bluetooth.nearbySelections", "附近蓝牙设备选择", "bluetooth", .orderedList, "附近蓝牙电量设备的显式选择（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 蓝牙 › 附近设备"; d.storageKey = "nearbyBLEConsent.v1"; d.accessPolicy = sensitiveDescribed
        },
        pref("bluetooth.trustedAppleDevices", "受信任的 Apple 设备", "bluetooth", .orderedList, "已记录的受信任 Apple 设备元数据（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 蓝牙 › 受信任设备"; d.storageKey = "trustedAppleDeviceMetadata.v1"; d.accessPolicy = sensitiveDescribed
        },
        pref("hardware.summaryMetrics", "启用的硬件摘要指标", "hardware", .set, "状态面板硬件摘要行启用的指标集合。") { d in
            d.uiPath = "设置 › 监控 › 摘要指标"; d.optionsProvider = "HardwareSummaryMetric"
            d.storageKey = "enabledHardwareSummaryMetricsV1"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
        pref("hardware.metricColors", "硬件指标颜色", "hardware", .map, "各硬件指标的自定义颜色映射。") { d in
            d.uiPath = "设置 › 监控 › 指标颜色"; d.storageKey = "hardwareMonitorMetricColorsV1"; d.accessPolicy = describedNotWritable
        },
        pref("icon.bluetoothIconColor", "蓝牙图标颜色", "icon", .taggedUnion, "蓝牙图标的颜色（系统蓝/主色/自定义）。") { d in
            d.uiPath = "设置 › 图标 › 蓝牙颜色"; d.storageKey = "bluetoothIconColor"; d.accessPolicy = describedNotWritable
        },
        pref("icon.bluetoothNetworkIconDevice", "蓝牙网络图标设备", "icon", .deviceReference, "用作网络图标的蓝牙设备地址（设备标识属敏感信息）。") { d in
            d.uiPath = "设置 › 图标 › 蓝牙网络设备"; d.storageKey = "bluetoothNetworkIconDeviceAddress"; d.accessPolicy = sensitiveDescribed
        },
        pref("icon.hardwareDiskRingColor", "硬件磁盘环颜色", "icon", .color, "硬件磁盘环的自定义颜色。") { d in
            d.uiPath = "设置 › 图标 › 磁盘环颜色"; d.storageKey = "hardwareDiskRingColorV1"; d.accessPolicy = describedNotWritable
        },
        pref("icon.hardwareRingConfiguration", "硬件外环配置", "icon", .object, "硬件外环的结构化配置（布局/主副指标/顶部内容/颜色/覆盖项）；含顶部标识与底部指示器共用的内存压力三档颜色（#398）；语义层另以嵌套 id 暴露常用字段。") { d in
            d.uiPath = "设置 › 图标 › 硬件外环"; d.storageKey = "hardwareRingConfigurationV1"; d.accessPolicy = describedNotWritable
        },
        pref("icon.slotBindings", "图标槽位绑定", "icon", .object, "图标各槽位的绑定配置（IconSlotBindingsV1 编码）。") { d in
            d.uiPath = "设置 › 图标 › 槽位绑定"; d.accessPolicy = describedNotWritable
        },
        pref("panel.levelSliderColor", "面板滑块颜色", "panel", .taggedUnion, "面板音量/亮度滑块的颜色（自动或自定义）。") { d in
            d.uiPath = "设置 › 状态面板 › 滑块颜色"; d.storageKey = "panelLevelSliderColor"; d.accessPolicy = describedNotWritable
        },
        pref("panel.sectionOrder", "面板模块顺序", "panel", .orderedList, "状态面板模块的显示顺序。") { d in
            d.uiPath = "设置 › 状态面板 › 模块顺序"; d.storageKey = "popupSectionOrder"; d.accessPolicy = describedNotWritable
        },
        pref("panel.modules.hardwareMonitor", "面板显示系统监控模块", "panel", .boolean, "在状态面板显示系统监控模块（CPU/GPU/内存/SSD 等）。") { d in
            d.uiPath = "设置 › 状态面板 › 模块 › 系统监控"; d.accessPolicy = .profileSafe; d.provider = "core"
        },
    ]

    // MARK: - Features

    static let features: [SettingsFeatureDescriptor] = [
        SettingsFeatureDescriptor(
            id: "panel.hardware",
            title: "系统监控面板",
            description: "状态面板中的系统监控模块父功能。",
            mutations: [SettingsMutationDescriptor(id: "hardware.rings.enabled", operation: .set, value: b(true))],
            performanceImpact: SettingsPerformanceImpact(resources: ["hardwareSampling"], activation: .onDemand)
        ),
        SettingsFeatureDescriptor(
            id: "hardware.panel.rings",
            title: "硬件圆环",
            description: "硬件监控圆环区域。",
            requires: ["panel.hardware"],
            mutations: [SettingsMutationDescriptor(id: "hardware.rings.enabled", operation: .set, value: b(true))]
        ),
        SettingsFeatureDescriptor(
            id: "hardware.panel.cpu",
            title: "CPU 圆环",
            description: "显示 CPU 指标的硬件圆环。",
            requires: ["panel.hardware", "hardware.panel.rings"],
            mutations: [
                SettingsMutationDescriptor(id: "icon.outerRing.source", operation: .set, value: s("hardwareMonitor")),
                SettingsMutationDescriptor(id: "icon.outerRing.hardware.layout", operation: .set, value: s("single")),
                SettingsMutationDescriptor(id: "icon.outerRing.hardware.primaryMetric", operation: .set, value: s("cpuUsage")),
            ]
        ),
        SettingsFeatureDescriptor(
            id: "hardware.panel.gpu",
            title: "GPU 圆环",
            description: "显示 GPU 指标的硬件圆环。",
            requires: ["panel.hardware", "hardware.panel.rings"],
            mutations: [
                SettingsMutationDescriptor(id: "icon.outerRing.source", operation: .set, value: s("hardwareMonitor")),
                SettingsMutationDescriptor(id: "icon.outerRing.hardware.layout", operation: .set, value: s("single")),
                SettingsMutationDescriptor(id: "icon.outerRing.hardware.primaryMetric", operation: .set, value: s("gpuUsage")),
            ]
        ),
        SettingsFeatureDescriptor(
            id: "hardware.panel.gpu.temperature",
            title: "GPU 温度显示",
            description: "在 GPU 圆环中显示 GPU 温度；需要先开启 GPU 圆环。",
            requires: ["panel.hardware", "hardware.panel.rings", "hardware.panel.gpu"],
            mutations: [SettingsMutationDescriptor(id: "hardware.temperature.enabled", operation: .set, value: b(true))],
            performanceImpact: SettingsPerformanceImpact(resources: ["temperatureSampling"], activation: .onDemand)
        ),
        SettingsFeatureDescriptor(
            id: "panel.bluetooth",
            title: "蓝牙面板",
            description: "状态面板蓝牙模块。",
            mutations: [SettingsMutationDescriptor(id: "bluetooth.deviceList.enabled", operation: .set, value: b(true))]
        ),
        SettingsFeatureDescriptor(
            id: "panel.audio.input",
            title: "麦克风输入模块",
            description: "状态面板的输入设备模块。",
            mutations: [SettingsMutationDescriptor(id: "audio.input.maxVisibleDevices", operation: .set, value: n(3))]
        ),
        SettingsFeatureDescriptor(
            id: "battery.powerFlow",
            title: "电量流向",
            description: "面板电池模块的功率流向图。",
            mutations: [SettingsMutationDescriptor(id: "battery.powerFlow.enabled", operation: .set, value: b(true))]
        ),
        SettingsFeatureDescriptor(
            id: "battery.highEnergyApps",
            title: "高耗能 App",
            description: "面板电池模块的高耗能 App 列表。",
            mutations: [SettingsMutationDescriptor(id: "battery.highEnergyApps.enabled", operation: .set, value: b(true))]
        ),
        SettingsFeatureDescriptor(
            id: "keepAwake.displayControl",
            title: "屏幕常亮控制",
            description: "面板中的屏幕常亮控件。",
            mutations: [SettingsMutationDescriptor(id: "keepAwake.displayControl", operation: .set, value: b(true))]
        ),
        SettingsFeatureDescriptor(
            id: "keepAwake.lidControl",
            title: "盒盖不睡眠控制",
            description: "面板中的盒盖不睡眠控件。",
            mutations: [SettingsMutationDescriptor(id: "keepAwake.lidControl", operation: .set, value: b(true))]
        ),
    ]
}
