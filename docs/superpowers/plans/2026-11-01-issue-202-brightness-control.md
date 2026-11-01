# 屏幕亮度控制实现计划（Issue #202）

> **For agentic workers:** 本计划按任务分阶段执行。实现从外屏（直接 DDC）开始，
> 内置屏（BetterDisplay）随后。步骤用 `- [ ]` 勾选跟踪。

**Goal:** 在状态面板和设置页提供屏幕亮度调节：外接屏走直接 DDC（VCP `0x10`），
内置屏走 BetterDisplay。

**Spec:** `docs/superpowers/specs/2026-11-01-issue-202-brightness-control-design.md`

**Branch:** `feat/issue-202-brightness-control`

**Base:** `origin/main` at `1a0e4753007c8467a3586c72edbd729638080724`

## Global Constraints

- 只在本 worktree 工作；不改 `main`。
- 部署目标 macOS 13；不新增第三方依赖；不静默提权；外屏不依赖第三方软件。
- 保留现有音量 / DDC / BetterDisplay 行为；不回归其测试。
- 所有 UI / 状态在 `@MainActor`；I2C 与 BetterDisplay 请求离开主 actor。
- 不新增常驻轮询；需求驱动读取。
- 失败/过期写入绝不显示乐观值。
- 真机 DDC / 内置屏亮度效果：**NOT RUN**（本环境无法验证硬件）。
- 本地验证：`bash scripts/verify-local.sh full`。

## 写入域（避免并发冲突）

| 域 | 文件 |
| --- | --- |
| 契约/模型 | `Models/Brightness*.swift`, `MonitorProtocols.swift` |
| DDC 后端 | `Audio/DDCReadProfile.swift`, `Audio/DDCVolumeReply.swift`, `Audio/DDCDisplayTransport.swift`, `Display/DDCBrightnessCoordinator.swift`, `Display/DisplayCatalog.swift` |
| BetterDisplay 后端 | `Display/BetterDisplayBrightnessCoordinator.swift`, `Audio/BetterDisplayIntegrationClient.swift`（仅 OSD 亮度事件） |
| 监控/接线 | `Monitoring/BrightnessMonitor.swift`, `Models/StatusSnapshot.swift`, `Store/SystemStatusStore.swift`, `App/AppEnvironment.swift` |
| 展示/UI | `Models/PopupSection.swift`, `Presentation/Panel/Brightness*.swift`, `Presentation/Panel/StatusPanelViewModel.swift`, `Presentation/Panel/StatusPanelActions.swift`, `UI/BrightnessControlsView.swift`, `UI/StatusPopoverView.swift` |
| 设置/本地化 | `Settings/SettingsStore.swift`, `UI/Settings/*`, `Localization/LocalizationKey.swift`, `Resources/*.lproj/Localizable.strings` |

## Phase 0 — 契约（Lead）

- [ ] T0.1 新增 `Models/BrightnessStatus.swift`：`BrightnessBackend`、
  `BrightnessControlSource`、`BrightnessUnavailableReason`、`DisplayBrightness`、
  `BrightnessStatus`（见 spec §4）。
- [ ] T0.2 `MonitorProtocols.swift` 增加 `BrightnessMonitoring` 协议
  （`updates`、`start/stop/refresh/recover`、`setDisplayAsleep`、
  `topologyChanged`、`setBackend(_:for:)`）。
- [ ] T0.3 `StatusSnapshot` 增加 `brightness`（默认 `.placeholder`）。
- [ ] T0.4 `swift build` 通过（其余层先用占位实现）。

## Phase 1 — 外接屏直接 DDC

- [ ] T1.1 `DisplayCatalog`：CoreGraphics 枚举 + 纯 `DisplayDescriptor`；
  单测 `DisplayCatalogTests`。
- [ ] T1.2 泛化 DDC VCP：`DDCReadProfile.brightnessVCP = 0x10`；
  `getVCPRequest`/`setVCPRequest` 传 `vcp`；`DDCVolumeReply` 校验参数化期望 VCP。
  单测 `DDCBrightnessReplyTests`。
- [ ] T1.3 `DDCDisplayTransport` 读/写增加 `feature` 参数（默认 volume）；
  亮度用 `brightnessVCP`。`DDCBrightnessCoordinator` 串行 worker：
  resolve(displayUUID) → Get `0x10` → 校验 → Set `0x10` → 读回确认；
  fail closed、generation、watchdog。单测 `DDCBrightnessCoordinatorTests`
  （mock transport）。
- [ ] T1.4 `BrightnessMonitor` 外屏部分：按 `DisplayCatalog` 外屏逐个协调器，
  聚合发布 `BrightnessStatus`。
- [ ] T1.5 `SystemStatusStore` / `AppEnvironment` 接线（store 订阅 brightness，
  转发到快照；环境创建默认 monitor）。

## Phase 2 — 内置屏 BetterDisplay

- [ ] T2.1 `BetterDisplayBrightnessCoordinator`：get/set `brightness`（按
  displayUUID），写后读回；缺失/未响应映射 `BrightnessControlSource`。
  单测 `BetterDisplayBrightnessTests`。
- [ ] T2.2 `BetterDisplayIntegrationClient` 识别 OSD `controlTarget ==
  "brightness"` 为亮度事件（不新增 OSD 绘制）。
- [ ] T2.3 `BrightnessMonitor` 内置屏部分接入。
- [ ] T2.4 后端选择：外屏默认 `directDDC`，内置屏仅 `betterDisplay`；单一写入者。

## Phase 3 — 展示 / UI / 设置 / 本地化

- [ ] T3.1 `PopupSection.brightness`（标题、`sun.max`）；`CaseIterable` 排序、
  所有 `switch` 穷尽；默认启用策略沿用「首次引入」模式。
- [ ] T3.2 `BrightnessPanelState` + `BrightnessPanelMapper`；
  `BrightnessControlInteraction`（草稿/身份/世代）。
- [ ] T3.3 `StatusPanelViewModel` 增加 `brightness`；`StatusPanelActions`
  增加 `setBrightness` / `finishBrightnessAdjustment`。
- [ ] T3.4 `UI/BrightnessControlsView`（每屏一行：名称 + 滑块 + 可用性）。
- [ ] T3.5 `StatusPopoverView` 渲染新分区。
- [ ] T3.6 `SettingsStore`：`ExternalBrightnessConfiguration`（按 displayUUID，
  默认 `directDDC`，`sanitized()`）+ 绑定；设置页新增「显示/亮度」组。
- [ ] T3.7 `LocalizationKey` + 12 个 `Localizable.strings` 补齐。
- [ ] T3.8 单测：`BrightnessPanelMapperTests`、`BrightnessPanelInteractionTests`、
  `BrightnessSettingsTests`。

## Phase 4 — 集成与验证

- [ ] T4.1 `swift build` + 全部相关单测绿。
- [ ] T4.2 `bash scripts/verify-local.sh full`（记录 SHA、分支、未验证项）。
- [ ] T4.3 更新 `docs/verification/issue-202-brightness-control.md`：
  记录单元测试结果、真机 NOT RUN 项、风险。
- [ ] T4.4 Lead 复核 final diff；确认无共享文件冲突、无回归。

## 依赖关系

- Phase 1 依赖 Phase 0 契约。
- Phase 2 依赖 Phase 0；与 Phase 1 可并行（不同文件域）。
- Phase 3 展示层依赖 Phase 0 模型；后端可用性可在 mock 下先行。
- Phase 4 最后。
