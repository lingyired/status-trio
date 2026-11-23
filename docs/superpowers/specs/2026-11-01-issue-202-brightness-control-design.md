# 屏幕亮度控制设计（Issue #202）

Date: 2026-11-01

Status: 设计稿（未实现）。本轮先写设计与计划，实现从外接屏开始，内置屏随后。

Branch: `feat/issue-202-brightness-control`

Base: `origin/main` at `1a0e4753007c8467a3586c72edbd729638080724`

## 1. 目标与已确认范围

Issue #202 是功能请求：增加屏幕亮度调节，支持内屏和外屏，参考
[MonitorControl](https://github.com/MonitorControl/MonitorControl)。

维护者已确认（2026-11-01）：

- **范围**：外接屏 + 内置屏都支持，分两阶段，先外屏后内置。
- **后端**：外接屏复用现有 DDC 基建（VCP `0x10` 亮度），内置屏走私有
  `DisplayServices`（维护者于 2026-11-01 测试后批准破例，避免强制安装 BetterDisplay）。
- **入口**：状态面板滑块 + 设置页开关，交互对齐现有音量。

成功标准（对齐现有音量体验）：

- 状态面板里每一块可调控的屏幕都有一个亮度滑块，拖动即改。
- 设置页可开关「亮度」分区、选择每个外屏的后端；设置持久化。
- 外屏走直接 DDC；内置屏走 `DisplayServices`；两者互不影响。
- 失败/过期写入绝不显示成乐观成功值（fail closed）。
- 现有音量、DDC、BetterDisplay 行为不回归。

**不在本轮范围**：菜单栏滚轮/全局快捷键调亮度、DDC 写入的硬件级真机验证
（本环境只能做到单元测试 + 构建，真机效果标 NOT RUN）。

## 2. 现状（不改动前的事实）

- 外接屏音量已走一条成熟的直连 DDC 链路：`DDCTargetResolver`（纯匹配）+
  `DDCDisplayTransport`（IOKit/I2C）+ `DDCVolumeCoordinator`（串行 worker /
  generation / watchdog）+ `DDCVolumeReply`（解析与校验）。VCP 码目前写死为
  `0x62`（`DDCReadProfile.volumeVCP`）。
- 屏幕身份：`DDCFramebufferSnapshot.edidUUID` 与 Core Audio 的外部输出 UID 相同；
  `DDCTargetResolver` 用「UID == framebuffer EDID UUID」定位显示器的
  `dispextN` 分支，再用分支 token 匹配唯一的 `DCPAVServiceProxy`。
- 内置屏没有外部 framebuffer，现有 DDC 链路完全不覆盖。
- BetterDisplay 集成已存在：`BetterDisplayIntegrationClient`（
  DistributedNotificationCenter 请求/响应 + OSD 事件），音量协调器按
  音频输出 UID 工作。OSD 事件里 `controlTarget == "brightness"` 当前被当作
  非音频事件忽略。
- 面板分区由 `PopupSection` 枚举 + `SettingsStore.enabledPopupSections` 驱动；
  音量状态经 `VolumePanelState` / `AudioPanelMapper` 映射，视图是
  `VolumeControlsView`，滑块草稿由 `VolumeControlInteraction` 持有。

## 3. 设计原则

1. **不按品牌判定。** 后端选择只看运行时探测结果，不出现「某型号」硬编码。
2. **能力分离。** 「能读」不自动等于「能写」；只有读回与写入一致才算
   `writeVerified`。
3. **单一写入者。** 同一块屏同一时刻只有一个后端可写。
4. **fail closed。** 目标不唯一、回复不合法、读回不一致时一律不写、不显示
   乐观值。
5. **不改 BetterDisplay 偏好、不静默提权、不引入第三方依赖。**
6. **外屏与内置屏都不依赖第三方软件；内置屏使用 `DisplayServices` 私有 API（维护者批准的例外）。**

## 4. 数据模型

新增（`Sources/StatusTrioCore/Models/`，与音量模型并列）：

```swift
enum BrightnessBackend: String, Codable, CaseIterable, Sendable {
    case directDDC      // 外屏默认
    case displayServices // 内置屏默认（私有 DisplayServices）
    case betterDisplay  // 外屏可选后端
}

enum BrightnessControlSource: Equatable, Sendable {
    case directDDC
    case betterDisplay
    case unavailable(reason: BrightnessUnavailableReason)
}

enum BrightnessUnavailableReason: String, Equatable, Sendable {
    case noBackend          // 没有可用后端（如内置屏且 BetterDisplay 缺失）
    case appAbsent          // BetterDisplay 未运行
    case unresponsive
    case writeNotConfirmed
    case resolveFailed
    case readFailed
    case timeout
    case unsupportedVCP     // 显示器拒绝 VCP 0x10
}

struct DisplayBrightness: Equatable, Sendable {
    let id: String              // displayUUID（CGDisplayCreateUUIDFromDisplayID）
    let name: String
    let isBuiltin: Bool
    let scalar: Double?         // 0...1，nil = 未知/不可读
    let canAdjust: Bool
    let backend: BrightnessBackend
    let source: BrightnessControlSource
}

struct BrightnessStatus: Equatable, Sendable {
    let displays: [DisplayBrightness]
    let transitionGeneration: UInt64
    static let placeholder = BrightnessStatus(displays: [], transitionGeneration: 0)
}
```

`StatusSnapshot` 增加 `let brightness: BrightnessStatus`（默认 `.placeholder`），
`SystemStatusStore` 增加对应的 monitor 依赖与发布。

## 5. 屏幕枚举（新增 `DisplayCatalog`）

新增 `Sources/StatusTrioCore/Display/DisplayCatalog.swift`，用 CoreGraphics：

- `CGGetOnlineDisplayList` 取在线显示器。
- `CGDisplayIsBuiltin(id)` 区分内置/外接。
- `CGDisplayCreateUUIDFromDisplayID(id)` 取稳定 `displayUUID`（与 IORegistry 的
  `EDID UUID` 同源，用于匹配 DDC framebuffer）。
- 名称优先 `NSScreen.localizedName`，回退 `CGDisplay` 尺寸描述。
- 产出纯数据 `DisplayDescriptor { id, name, isBuiltin, width, height }`，硬件读取
  与纯模型分离，便于单测（`DisplayCatalogTests` 用注入的假 provider）。

## 6. 后端

### 6.1 外接屏：直接 DDC（VCP `0x10`）

**最小侵入式泛化**，不重写音量链路：

- `DDCReadProfile` 增加 `static let brightnessVCP: UInt8 = 0x10`，并把
  `getVCPRequest` / `setVCPRequest` 的 `vcp` 参数保留为可传参（已有 `vcp`
  形参，默认 `volumeVCP`），亮度传 `brightnessVCP`。
- `DDCVolumeReply` / `DDCVolumeReplyKind` 的校验目前写死 `bytes[4] == 0x62`；
  改为「校验期望 VCP 形参」，默认 `0x62`。错误名 `unsupportedVolumeVCP`
  保留给音量路径；亮度用新错误名或参数化。
- `DDCDisplayTransport`：读取/写方法增加 `feature`/`vcp` 参数（默认 volume）。
  复用同一 `resolve(uid:)`（亮度传入 displayUUID 作为 uid 去匹配 EDID UUID）。
- 新增 `Sources/StatusTrioCore/Display/DDCBrightnessCoordinator.swift`，按屏幕
  串行 worker 做 resolve → Get VCP `0x10` → 校验 → Set VCP `0x10` → 读回确认，
  复用现有 `DDCWorker` / watchdog / generation 模式。能力状态映射到
  `BrightnessControlSource`。

**身份匹配**：对该外屏 `CGDisplayCreateUUIDFromDisplayID` 得到的 UUID 作为
`uid` 传给 `DDCTargetResolver.resolve`。若与 EDID UUID 不相等（旧系统/特殊
显示器），解析失败即 `resolveFailed`，不猜测。

### 6.2 内置屏：DisplayServices（私有 API）

- 新增 `Sources/StatusTrioCore/Display/DisplayServicesBrightnessController.swift`：
  `dlopen` Apple 私有 `DisplayServices` 框架，`DisplayServicesGetBrightness` /
  `DisplayServicesSetBrightness` 读写内置屏亮度。
- 写后读回确认（容差 2%），未确认即 `writeNotConfirmed`；符号/框架不可用即
  `source = .unavailable(.noBackend)`，不崩溃、不显示可拖动滑块。
- 这是维护者批准的「私有 API」例外：macOS 无公开内置屏亮度 API，否则只能强制
  用户安装 BetterDisplay。

### 6.2b 外屏可选 BetterDisplay 后端（非必需）

- 现有 `BetterDisplayBrightnessCoordinator` 保留为外屏的可选后端；默认外屏不用它。

### 6.3 单一写入者

某屏标记为 `betterDisplay` 后端时，其 DDC 路径对该屏停用；反之亦然。配置在
外屏默认 `directDDC`（可配置 `betterDisplay`）、内置屏自动走 `displayServices`。

## 7. 监控与接线

- 新增 `Sources/StatusTrioCore/Monitoring/BrightnessMonitor.swift`
  （`@MainActor`，实现 `BrightnessMonitoring` 协议：`updates`、
  `start/stop/refresh/recover`、`setDisplayAsleep`、`topologyChanged`、
  `setBackend(_:for:)`），持有 `DisplayCatalog`、外屏 DDC 协调器、内置屏
  DisplayServices 控制器、可选 BetterDisplay 协调器，聚合发布 `BrightnessStatus`。
- `MonitorProtocols.swift` 增加 `BrightnessMonitoring`。
- `AppEnvironment.makeStore` 增加 `brightnessMonitor` 参数并创建默认实例；
  `SystemStatusStore` 订阅并写入 `StatusSnapshot.brightness`。
- 屏幕热插拔/唤醒用 `NSApplication.didChangeScreenParametersNotification` +
  现有 display-asleep 通知驱动 `topologyChanged()`。

## 8. 展示与 UI

- 新增 `PopupSection.brightness`（`titleKey`/`systemImage` = `"sun.max"`）。
  默认**不**加入 `defaultEnabledPopupSections`；沿用 `vpnPopupSectionIntroduced`
  的「首次引入」模式给存量用户一次性提示/默认开启，具体见计划任务。
- 新增 `Presentation/Panel/BrightnessPanelState.swift` +
  `BrightnessPanelMapper`：把 `BrightnessStatus` 映射为每屏一行
  `BrightnessRow { id, name, isBuiltin, scalar, canAdjust, source }`。
- 新增 `UI/BrightnessControlsView.swift`：每屏一行 = 名称/图标 + 滑块；
  复刻音量滑块的 `BrightnessControlInteraction`（草稿/身份/世代），
  拖动调用 `actions.setBrightness(displayID:value:)`，结束调用
  `actions.finishBrightnessAdjustment(displayID:)`。
- `StatusPanelActions` 增加上述两个动作，转发到 `SystemStatusStore`。
- `StatusPanelViewModel` 增加 `@Published private(set) var brightness` 并在
  快照更新时刷新；`StatusPopoverView` 按 `visiblePopupSections` 顺序渲染。
- 设置页（Audio/新增 Display 组）：亮度分区开关 + 每外屏后端选择
  （直接 DDC / BetterDisplay）+ 可用性/失败原因文案。

## 9. 设置持久化

`SettingsStore`：

- `brightnessPopupSectionEnabled`（或复用 `enabledPopupSections` 集合，
  优先复用集合）。
- `externalBrightnessConfigurations: [String: ExternalBrightnessConfiguration]`
  （key = displayUUID），字段 `backend`、`betterDisplayUUID?`，默认
  `directDDC`；提供 `sanitized()`。
- 复用现有 `bindExternalVolumeSettings` 的模式新增绑定/校验。

## 10. 并发与生命周期

- 所有 monitor / UI 状态 `@MainActor`；I2C 与 BetterDisplay 请求离开主 actor。
- 每屏一个串行 worker；用 generation + watchdog，与 `DDCVolumeCoordinator`
  一致；睡眠/切屏/停止时取消在途任务，不写入过期值。
- 不新增常驻轮询：亮度只在面板可见、拓扑变化、唤醒、用户拖动时读取，
  与音量 `setDetailsVisible` 需求驱动一致。

## 11. 本地化

新增 key（`LocalizationKey`）：分区标题、每屏行无障碍标签、后端选项
（直接 DDC / BetterDisplay）、失败原因、设置说明。必须补齐
`Resources/*.lproj/Localizable.strings` 的现有语言集合（en, zh-Hans,
zh-Hant, de, es, fr, it, ja, ko, pt-BR, ru, ar）。

## 12. 验证

- 单元测试（无硬件，mock transport/client）：
  - `DDCBrightnessReplyTests`：VCP `0x10` 请求/回复解析与校验。
  - `DDCBrightnessCoordinatorTests`：读→写→读回确认、fail closed、过期不写。
  - `DisplayCatalogTests`：内置/外接分类、UUID 稳定性。
  - `BetterDisplayBrightnessTests`：get/set 参数、缺失应用、未确认。
  - `BrightnessPanelMapperTests`：状态映射。
  - `BrightnessPanelInteractionTests`：草稿/身份/世代。
- 本地验证：`bash scripts/verify-local.sh full`（涉及 state/concurrency/新 UI）。
- **真机 DDC 亮度、内置屏 BetterDisplay 亮度：NOT RUN**（本环境无法验证硬件
  效果；需维护者在真机确认）。

## 13. 风险

- `CGDisplayCreateUUIDFromDisplayID` 与 IORegistry `EDID UUID` 在旧系统可能不
  相等 → 解析失败即报错，不猜测；真机需验证。
- BetterDisplay 的 `brightness` 命令参数键以实际版本为准 → 先用现有 client
  做最小 get 探测并在真机核对。
- 新增面板分区会改变 `PopupSection` 全量枚举 → 需同步 `CaseIterable` 排序、
  设置 UI 与所有 `switch` 分支，确保穷尽。
