# 充电 / 连接电源时使用黑白圆环 — 实现计划

Spec: `docs/superpowers/specs/2026-11-10-ring-charging-monochrome-design.md`

核心：新增全局开关「充电 / 连接电源时用黑白」，替换掉「单色电量弧」一键预设。
低/高电量模式、临界低电量颜色与优先级不变。无电池机器默认开启（黑白）。

---

## Task 1 — 设置：`monochromeChargingRing`（`Bool?`）

**文件**：`Sources/StatusTrioCore/Settings/SettingsStore.swift`

1. 默认键（放在 `simulatesNoBatteryDefaultsKey` 旁）：
   ```swift
   static let monochromeChargingRingDefaultsKey = "monochromeChargingRing"
   ```
2. `@Published` 属性（放在 `usesBatteryStatusColors` 之后）：
   ```swift
   /// nil = automatic: black/white on a battery-less Mac, connected colour when a
   /// battery is present. An explicit value fixes the user's choice.
   @Published var monochromeChargingRing: Bool? {
       didSet {
           if let value = monochromeChargingRing {
               defaults.set(value, forKey: Self.monochromeChargingRingDefaultsKey)
           } else {
               defaults.removeObject(forKey: Self.monochromeChargingRingDefaultsKey)
           }
       }
   }
   ```
3. init 读取（在 `usesBatteryStatusColors` 之后）：
   ```swift
   self.monochromeChargingRing =
       (defaults.object(forKey: Self.monochromeChargingRingDefaultsKey) as? Bool)
   ```
4. **删除**：`applyMonochromeBatteryArcPreset()`、`clearMonochromeBatteryArcPreset()`、
   `isMonochromeBatteryArcActive`。
5. `var batteryIconOptions`：增加 `monochromeCharging: monochromeChargingRing`。

**测试**（新文件 `Tests/StatusTrioCoreTests/RingChargingMonochromeSettingsTests.swift`）：
- 默认 `nil`；
- 设 `true` / `false` 后新 store 读到同值；
- `store.batteryIconOptions.monochromeCharging` 跟随该值。

---

## Task 2 — 模型 + 外观链

**文件**：`Sources/StatusTrioCore/Models/BatteryIconOptions.swift`
- 增加字段 `let monochromeCharging: Bool?`。
- 唯一初始化器增加参数 `monochromeCharging: Bool? = nil` 并 `self.monochromeCharging = monochromeCharging`。
- `.standard` 不需要显式传（默认 nil）。

**文件**：`Sources/StatusTrioCore/Settings/SettingsStore+IconAppearance.swift`
- `BatteryAppearanceInputs` 增加 `var monochromeChargingRing: Bool?`。
- `batteryInputsPublisher`：把 `$monochromeChargingRing` 并入 `appearance` 的
  `CombineLatest4`（或再 combineLatest 一层），填入 `BatteryAppearanceInputs`。
- `BatteryAppearanceInputs.options(ringStrokeScale:)` 增加
  `monochromeCharging: monochromeChargingRing`。

---

## Task 3 — 颜色映射

**文件**：`Sources/StatusTrioCore/Models/StatusMappings.swift`
```swift
static func batteryColorRole(
    _ battery: BatteryStatus,
    criticalThreshold: Int = 20,
    isHighPowerMode: Bool = false,
    treatAsConnected: Bool = false,
    monochromeCharging: Bool = false
) -> BatteryColorRole {
    ...
    if battery.isCharging || battery.isConnectedToPower || treatAsConnected {
        return monochromeCharging ? .foreground : .charging
    }
    return .foreground
}
```
（critical → lowPower → highPower 顺序不变。）

**文件**：`Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift`
`batteryState` 中：
```swift
let monochromeCharging = options.monochromeCharging ?? !isPresent
let role: BatteryColorRole = options.usesStatusColors
    ? StatusMappings.batteryColorRole(
        battery,
        criticalThreshold: options.criticalThreshold,
        isHighPowerMode: isHighPowerMode,
        treatAsConnected: !isPresent,
        monochromeCharging: monochromeCharging
    )
    : .foreground
```

**测试**（`IconPresentationMapperTests` 或新文件）：
- 有电池充电：开关关 → `.powered`；开关开 → `.primary`。
- 有电池连接：关 → `.powered`；开 → `.primary`。
- 无电池（nil 自动）：→ `.primary`（黑/白）。
- 无电池（显式 false）：→ `.powered`。
- 充电 + 低电量模式：低电量 → `.lowPower`（即使开关开也不被黑白覆盖）。
- 充电 + 高电量模式：→ `.highPower`。
- 临界低电量（有电池）：→ `.critical`。

---

## Task 4 — 本地化

**删除** 以下键（枚举 + 12 个 `.lproj`）：`settingsBatteryMonochromeArc`、
`settingsBatteryMonochromeArcDescription`、`settingsBatteryMonochromeArcApply`、
`settingsBatteryMonochromeArcApplied`、`settingsBatteryMonochromeArcCancel`
（对应 `settings.battery.monochromeArc*`）。

**新增**：
- `settingsBatteryMonochromeCharging = "settings.battery.monochromeCharging"`
- `settingsBatteryMonochromeChargingDescription = "settings.battery.monochromeChargingDescription"`

英文 / 简中值：
- title：`Black & white when charging or on power` / `充电 / 连接电源时用黑白`
- description：`Draw the ring in black or white while charging or connected to power. Low Power Mode and High Power Mode keep their own colours. A Mac with no battery defaults to this.`
  / `充电或连接电源时，圆环用黑/白。低电量和高电量模式仍用各自颜色。没有电池的 Mac 默认开启。`
（其余 10 语言同义翻译。）

**更新** `settings.battery.noBatteryHiddenOptions`：
- 简中：`这台 Mac 没有电池：电量百分比和充电指示不适用。圆环默认黑白，可在上面关闭以使用连接电源色；低电量和高电量模式仍用各自颜色。`
- 英文：`This Mac has no battery: the percentage and charging indicator do not apply. The ring is black and white by default; turn it off above to use the connected-power colour. Low Power Mode and High Power Mode keep their colours.`

本地化 parity 测试必须仍通过。

---

## Task 5 — UI

**文件**：`Sources/StatusTrioCore/UI/Settings/AppIconRingView.swift`（colorsGroup）
- 用 `SettingsToggleRow` 替换原「单色电量弧」`SettingsRow`+`Button`：
  ```swift
  SettingsToggleRow(
      symbol: "circle.lefthalf.filled",
      tint: .gray,
      title: localization.string(.settingsBatteryMonochromeCharging),
      subtitle: localization.string(.settingsBatteryMonochromeChargingDescription),
      isOn: Binding(
          get: { store.monochromeChargingRing ?? !effectiveHasBattery },
          set: { store.monochromeChargingRing = $0 }
      )
  )
  ```
- 更新 `noBatteryHintGroup` 注释与提示文案引用（用更新后的 `noBatteryHiddenOptions`）。

**文件**：`Sources/StatusTrioCore/UI/Settings/SettingsVisualPreviews.swift`
- `RingStrokeStylePreview` 的 `BatteryIconOptions(...)` 增加
  `monochromeCharging: store.monochromeChargingRing`。

其余手工构造 `BatteryIconOptions` 的地方依赖默认 `nil`（自动）即可，无需改动。

---

## Task 6 — 验证与交付

1. `bash scripts/test.sh 'RingChargingMonochromeSettingsTests|IconPresentationMapperTests|LocalizationParityTests|SettingsViewTests|AppIconRingViewTests'`
2. `bash scripts/verify-local.sh full`（渲染路径，必须 full）。
3. `bash scripts/build-worktree.sh debug open`，用「模拟无电池」核对：默认黑白、可切绿、低/高电量模式仍上色。
4. 提交；issue #309 保持 `status: needs-verification`。
