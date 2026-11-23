# 顶部圆弧设置分组统一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「顶部圆弧」页三种来源的设置重新分组，统一为「外环内容 → 顶部标识（尺寸在最上）→ 圆弧/进度 → 颜色 → 其它」。

**Architecture:** 仅重组 `AppIconRingView` 的 SwiftUI 视图分组与顺序，复用现有 `SettingsGroup`/`SettingsRow`/`topMarkerSizeRow`；不触碰持久化、mapper、渲染器。

**Tech Stack:** SwiftUI / macOS AppKit（Debug 开发版）。

**Spec:** `docs/superpowers/specs/2026-11-12-ring-settings-grouping-design.md`

## Global Constraints

- 纯视图重组，不改 `IconConfigurationV1`/`HardwareRingConfiguration`/mapper/渲染器。
- 所有控件的绑定、标签 key、可用性条件保持不变。
- 本机电池「顶部标识大小」仍受 `isBatterySymbolSizeEnabled` 约束。
- 开发者「无电池模拟」开关仍留在「外环内容」卡片且仅 DEBUG。
- AirPods 无颜色设置，不放空的「颜色」卡。
- macOS 13+ 兼容，不引入新控件样式或新依赖。

## Review Focus

- 本机电池：抽出顶部标记后，四种标记（供电/充电/接通电源/无电池）一个都不能丢，绑定不变。
- AirPods：拆分后「左右双圆弧」和「回退电池」开关仍然存在且绑定不变。
- 系统监控：顶部标识组提前后，圆弧/颜色/高级三组内容与顺序完整。
- 无电池（`effectiveHasBattery == false`）时：提示卡在最上，顶部标识组按现有 `isBatterySymbolSizeEnabled` 逻辑仍可用。
- 切换来源时组间不应出现重复行或丢失行。

---

### Task 1: 本机电池分组重排（顶部标识独立并在最上）

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/AppIconRingView.swift`

**Interfaces:**
- Consumes: 现有 `topMarkersContent`、`topMarkerSizeRow`、`progressGroup`、`colorsGroup`、`effectsGroup`、`store.isBatterySymbolSizeEnabled`
- Produces: 新的 `batteryTopMarkerGroup` 计算属性；`body` 中本机电池分支顺序为 `batteryTopMarkerGroup → progressGroup → colorsGroup → effectsGroup`

- [ ] **Step 1: 抽组** — 把 `outerRingContentGroup` 内 `if store.outerRingContent == .systemBattery { … topMarkersContent … }` 的顶部标记区整体移出，新建 `batteryTopMarkerGroup`：`SettingsGroup(.settingsBatteryGroupTopMarkers)`，第一行为 `topMarkerSizeRow`（在 `store.isBatterySymbolSizeEnabled` 时显示），随后是原有 `topMarkersContent`。
- [ ] **Step 2: 移除尺寸行** — 从 `progressGroup` 删除原先 gated 的「顶部标识大小」`SettingsRow`（已迁入 `batteryTopMarkerGroup`），避免重复。
- [ ] **Step 3: 重排 body** — 本机电池分支改为 `batteryTopMarkerGroup; progressGroup; colorsGroup; effectsGroup`；`outerRingContentGroup` 只保留选择器 + DEBUG 无电池模拟开关。
- [ ] **Step 4: 验证** — `bash scripts/test.sh 'SettingsView|AppIconRing'`；`swift build`。期望：编译通过、相关测试 0 失败。（纯布局重组，无新增逻辑单测；依赖编译 + 既有设置页测试 + 手动检查。）
- [ ] **Step 5: Commit** — `git commit -m "refactor(settings): 本机电池分组统一，顶部标识独立置顶"`

### Task 2: AirPods 分组拆分（顶部标识 / 圆弧 / 回退）

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/AppIconRingView.swift`

**Interfaces:**
- Consumes: `store.airPodsRingUsesDualRing`、`store.showsAirPodsTopSymbolInRing`、`store.airPodsRingFallsBackToBattery`、`topMarkerSizeRow`
- Produces: `airPodsTopMarkerGroup`、`airPodsArcGroup`、`airPodsFallbackGroup`；`body` 中 AirPods 分支按此顺序

- [ ] **Step 1: 拆分** — 将原 `airPodsRingGroup` 拆为三组：`airPodsTopMarkerGroup`（`SettingsGroup(.settingsRingAirPodsGroup)`：第一行 `topMarkerSizeRow`，第二行「显示 AirPods 顶部符号」toggle）、`airPodsArcGroup`（标题用「圆弧」，含「左右双圆弧」toggle）、`airPodsFallbackGroup`（标题「回退」，含「无 AirPods 回退本机电池环」toggle）。
- [ ] **Step 2: body 顺序** — AirPods 分支输出 `airPodsTopMarkerGroup; airPodsArcGroup; airPodsFallbackGroup`。
- [ ] **Step 3: 验证** — `bash scripts/test.sh 'SettingsView|AppIconRing|SettingsVisualChoicePicker'`；`swift build`。期望 0 失败。
- [ ] **Step 4: Commit** — `git commit -m "refactor(settings): AirPods 分组拆分为顶部标识/圆弧/回退"`

### Task 3: 系统监控分组顺序统一

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/AppIconRingView.swift`

**Interfaces:**
- Consumes: `hardwareArcGroup`、`hardwareTopGroup`、`hardwareColorGroup`、`hardwareAdvancedGroup`
- Produces: `hardwareRingGroups` 顺序为 `hardwareTopGroup → hardwareArcGroup → hardwareColorGroup → hardwareAdvancedGroup`

- [ ] **Step 1: 重排** — 调整 `hardwareRingGroups` 的 `@ViewBuilder` 顺序，使顶部标识组在最前（组内已有 `topMarkerSizeRow` 在最上）。
- [ ] **Step 2: 验证** — `bash scripts/test.sh 'HardwareRing|SettingsView|HardwareMonitor'`；`swift build`。期望 0 失败。
- [ ] **Step 3: Commit** — `git commit -m "refactor(settings): 系统监控分组顺序统一，顶部标识置顶"`

### Task 4: 整体验证与开发版冒烟

**Files:** 无代码改动

- [ ] **Step 1: 全量本地验证** — `bash scripts/verify-local.sh quick 'SettingsView|AppIconRing|LocalizationParity|HardwareRing'`。期望：`Local verification passed`。
- [ ] **Step 2: 构建并正常启动开发版** — `bash scripts/build-worktree.sh debug open`，确认可启动、设置三来源分组顺序符合设计、无重复/丢失行。
- [ ] **Step 3: 报告** — 汇报组顺序、验证结果、剩余风险（无）。

## Self-Review（written inline）

- Spec coverage: 三来源分组/顺序/尺寸置顶/Task1-3 覆盖；验证 Task4。
- Step scan: 每步单一动作、有可检查结果；未写实现体（视图重组由实现者按现有控件组合）。
- Type consistency: 复用既有属性名，未引入新类型。
- Review Focus: 见上，Task1-3 的验证步骤覆盖切换来源与无电池情形（手动）。
- Proportion: 计划短于 spec，未转录实现。
