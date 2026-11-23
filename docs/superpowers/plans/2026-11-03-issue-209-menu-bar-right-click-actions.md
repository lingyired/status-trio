# Issue #209 菜单栏右键自定义快捷动作 Implementation Plan

> **For agentic workers:** 在当前隔离 worktree 内用当前模型 inline 执行（executing-plans）。用户明确要求新建分支/worktree 并由当前模型执行，不要把实现外包给其他模型。

**Goal:** 让菜单栏图标右键执行用户单选的可配置动作：默认维持现有右键菜单，另可切换低电量模式、立刻充满/取消充满、静音切换；结构可扩展到以后新增动作。

**Spec:** GitHub issue #209「菜单栏图标右键支持自定义动作（低电量/当前菜单/立刻充满/静音切换），并做成可扩展的快捷动作」。

**Architecture:** 新增 `MenuBarRightClickAction` 枚举（用户选择）+ 纯函数 `MenuBarRightClickRouter`（动作 × 可用性 → 结果，可测、无 AppKit）。持久化落在 `SettingsStore`，默认 `.contextMenu`，未知原始值回退。`StatusBarController` 仅改右键分支按路由执行，左键/面板/Dock 不变。立刻充满复用 `ChargeToFullNowController`，新增一个不依赖面板可见性的快捷切换方法。设置页在 General 增加选择器，选中动作当前不可用时给出提示；运行时不可用一律回退到显示右键菜单。

**Stack:** Swift 6、SwiftUI/AppKit、XCTest、macOS 13+。

**Base:** `458bf6c441b77ce1ee67e71f7fd6a3d5fba44951`（= 建分支时的 main HEAD，含 #224）。

## Global constraints

- 只在 `feat/209-menu-bar-right-click-actions` linked worktree 内改动；不碰其他 worktree / 不复制别的会话未提交改动。
- 左键（打开面板）完全不变；Dock 图标右键不动。
- 只实现 4 个动作，不新增额外动作；但结构支持扩展（新增 case + 处理即可，选择器与路由自动覆盖）。
- 运行时若选中动作不可用（低电量 helper 未就绪 / 立刻充满不支持或当前无从充满 / 无输出设备可静音），回退为显示右键菜单，不静默失败。
- 低电量 / 立刻充满 / 静音都是 toggle 语义。
- 12 种已发布语言全部补齐本地化键（`LocalizationParityTests` / `LocalizationTests` 强制）。
- 交付前跑 `quick`（含受影响的 focused 测试），因触及 AppKit 点击/状态存储/充电状态机，再跑 `full`。开发版用 `scripts/build-worktree.sh` 构建，不装到生产 App 上。
- 不改 `main`、不合并、不发布、不动 release。

## File structure

- **Create** `Sources/StatusTrioCore/Models/MenuBarRightClickAction.swift`: 枚举 + `titleKey` 映射；`id` 用于 SwiftUI。
- **Create** `Sources/StatusTrioCore/UI/MenuBarRightClickRouter.swift`: `MenuBarQuickActionAvailability`、`MenuBarRightClickOutcome`、纯 `outcome(for:availability:)`。
- **Modify** `Sources/StatusTrioCore/Settings/SettingsStore.swift`: 新增 `menuBarRightClickActionDefaultsKey`、`@Published var menuBarRightClickAction`（didSet 持久化 rawValue）、init 读取 + 回退。
- **Modify** `Sources/StatusTrioCore/UI/StatusBarController.swift`: 持有 `chargeToFullNow`；右键分支改为按路由执行；不可用回退 `showMenu()`；低电量/静音动作调用现有能力。
- **Modify** `Sources/StatusTrioCore/Battery/ChargeToFullNowController.swift`: 新增 `performQuickToggle(battery:) -> Bool`（合成 demand，update + performPrimaryAction，返回是否真的执行）。
- **Modify** `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift`: 新增右键动作选择行 + 不可用提示；接收可选 `statusStore` / `chargeToFullNow`。
- **Modify** `Sources/StatusTrioCore/UI/Settings/SettingsView.swift`: 把 `statusStore`、`chargeToFullNow` 传给 `GeneralSectionView`。
- **Modify** `Sources/StatusTrioCore/Localization/LocalizationKey.swift` + `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`（12 语言）: 新增键。
- **Create** `Tests/StatusTrioCoreTests/MenuBarRightClickRouterTests.swift`: 纯映射测试。
- **Modify** `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`: 默认值/持久化/未知值回退。
- **Modify** `Tests/StatusTrioCoreTests/ChargeToFullNowControllerTests.swift`: 快捷切换（可开始→开始；进行中→取消；无从充满→返回 false）。

## 接口（先定死，避免实现漂移）

```swift
// Models/MenuBarRightClickAction.swift
enum MenuBarRightClickAction: String, CaseIterable, Identifiable, Sendable {
    case contextMenu
    case toggleLowPowerMode
    case chargeToFullNow
    case toggleMute
    var id: Self { self }
    var titleKey: LocalizationKey { ... } // 四个动作名称
}

// UI/MenuBarRightClickRouter.swift
enum MenuBarRightClickOutcome: Equatable {
    case showContextMenu
    case toggleLowPowerMode
    case toggleChargeToFullNow
    case toggleMute
}
struct MenuBarQuickActionAvailability: Equatable {
    var lowPowerMode: Bool
    var chargeToFullNow: Bool
    var mute: Bool
    func isAvailable(_ action: MenuBarRightClickAction) -> Bool { ... }
}
enum MenuBarRightClickRouter {
    static func outcome(for action: MenuBarRightClickAction,
                        availability: MenuBarQuickActionAvailability) -> MenuBarRightClickOutcome
}

// SettingsStore
static let menuBarRightClickActionDefaultsKey = "menuBarRightClickAction.v1"
@Published var menuBarRightClickAction: MenuBarRightClickAction // 默认 .contextMenu，未知值回退

// ChargeToFullNowController
@discardableResult
func performQuickToggle(battery: BatteryStatus) -> Bool
```

## Task 1: 纯模型 + 路由（TDD）

- [ ] 先写 `MenuBarRightClickRouterTests`：`.contextMenu` 恒为 `.showContextMenu`；每个动作在可用时映射到对应 outcome；每个动作在不可用时回退 `.showContextMenu`；`MenuBarQuickActionAvailability.isAvailable` 与映射一致；枚举 `rawValue` round-trip。
- [ ] `bash scripts/test.sh 'MenuBarRightClickRouterTests'`，观察 RED。
- [ ] 实现枚举 + router，观察 GREEN。
- [ ] 提交（可与 SettingsStore 一起）。

## Task 2: SettingsStore 持久化（TDD）

- [ ] 在 `SettingsStoreTests` 增加：默认 `.contextMenu`；跨实例持久化；`menuBarRightClickActionDefaultsKey` 存未知串回退 `.contextMenu`；`$menuBarRightClickAction` 发布变化。
- [ ] 观察 RED，然后加 key + `@Published` + init 读取回退，观察 GREEN。

## Task 3: 立刻充满快捷切换（TDD）

- [ ] 在 `ChargeToFullNowControllerTests` 增加：电池连电源未满且支持时可开始并进入 applying/charging；已有 session 时再点执行取消；无从充满（未连电源/已满/无电池）返回 false 且不改变 presentation。
- [ ] 观察 RED，实现 `performQuickToggle(battery:)`（合成 `settingEnabled:true, popoverVisible:true, batterySectionVisible:true` 的 demand，`update` 后按 `presentation` 判定是否可动作并 `performPrimaryAction()`，随后私有地清掉合成 demand），观察 GREEN。

## Task 4: StatusBarController 右键路由接线

- [ ] 存储 `chargeToFullNow`；`handleClick` 的 `.right` 分支：先 `popover.performClose(nil)`，再按 `MenuBarRightClickRouter.outcome(for: settings.menuBarRightClickAction, availability: ...)` 执行。
- [ ] availability：`lowPowerMode = settings.controlsLowPowerMode && PrivilegedHelperManager.shared.isReady`；`chargeToFullNow = chargeToFullNow?.isSettingAvailable ?? false`；`mute = store.liveVolume.canMute`。
- [ ] 执行：`.showContextMenu` → `showMenu()`；`.toggleLowPowerMode` → `store.lowPowerMode.setLowPowerMode(!store.lowPowerMode.isLowPowerMode)`；`.toggleChargeToFullNow` → `chargeToFullNow?.performQuickToggle(battery: store.snapshot.battery)` 返回 false 时 `showMenu()`；`.toggleMute` → `store.toggleMute()`。
- [ ] 左键路径不变。

## Task 5: General 设置页 + 本地化

- [ ] `GeneralSectionView` 增加 `var statusStore: SystemStatusStore? = nil`、`var chargeToFullNow: ChargeToFullNowController? = nil`、`@ObservedObject private var helper: PrivilegedHelperManager = .shared`。
- [ ] 在全局快捷键 / 刷新间隔之间加一行：`SettingsRow` + 右侧 `Picker`（`ForEach(MenuBarRightClickAction.allCases)`，Text 用本地化动作名，`settingsMenuPickerWidth()`）。
- [ ] 选中动作不可用时，行下方显示 `SettingsHintRow` 提示（回退为显示菜单）。
- [ ] `SettingsView` 把 `statusStore`、`chargeToFullNow` 传入。
- [ ] `LocalizationKey` 增 7 个键；12 个 `Localizable.strings` 全部补齐（标题、描述、四动作名、不可用提示）。
- [ ] 跑 `LocalizationParityTests` / `LocalizationTests` 观察 GREEN。
- [ ] 更新 `StatusMenuBuilderTests` 不涉及（右键菜单文案不变），确认无回归。

## Task 6: 集成验证与交付

- [ ] `bash scripts/verify-local.sh quick 'MenuBarRightClickRouterTests|SettingsStoreTests|ChargeToFullNowControllerTests|StatusMenuBuilderTests|LocalizationParityTests|LocalizationTests|SettingsViewTests'`。
- [ ] `bash scripts/verify-local.sh full`（最终整合树）。
- [ ] `bash scripts/build-worktree.sh no-open` 构建开发版 bundle，确认 dev bundle id / codename 正确、可构建。
- [ ] 若可安全做实例级 GUI 验证则按 `background-ui-testing` skill 执行；否则相关交互步骤记 `BLOCKED/NOT RUN` 并说明（不抢鼠标、不用合成全局事件）。
- [ ] 记录 base/ahead、验证范围；提交最终改动到分支；**不合并 main、不发布**。

## Self-review 关注点

- 未知持久化值是否回退 `.contextMenu`。
- 右键不可用是否回退菜单而非静默失败。
- 左键是否完全不变；Dock 右键未触碰。
- 12 语言键是否齐全、占位符一致。
- 快捷充电是否可能残留合成 demand 影响面板状态（`performQuickToggle` 后清理）。

## 追加动作（2026-11-03，用户确认后扩展）

在原有 4 个动作基础上追加，仍走同一套 `MenuBarRightClickAction` + router 结构：

- `toggleWiFi` 切换 Wi-Fi 开关：`SystemStatusStore.toggleWiFiPower()` →
  `WiFiNetworkController.setPowerFromQuickAction(_:)`（不依赖面板可见性，直接下发一次
  电台开关；普通面板路径仍受 `isActive` 约束）。
- `refreshStatus` 刷新状态：`SystemStatusStore.refreshAll()`。
- 导航类 `openWiFiSettings` / `openBluetoothSettings` / `openBatterySettings` /
  `openSoundSettings`：复用 `StatusBarController` 已有的系统设置面板打开方法。

导航与刷新类无运行时前置条件，始终可用；Wi-Fi 开关在无接口（`.unavailable`）时回退菜单。
未加入蓝牙开关（关闭需二次确认）与输入法切换（可能有多个输入法）。

顺带把「打开状态面板」快捷键行的「录制」按钮宽度对齐到 `SettingsMetrics.menuPickerWidth`。

最终：验证通过后合并到 `main` 并推送。
