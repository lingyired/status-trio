# 把最新 main 合并进 V1 图标架构 — 分阶段实施计划

> 状态：计划（未启动）。目标分支从 `feat/icon-core-refactor` 派生一个专门的集成分支来做，`feat/icon-core-refactor` 保持可用（已编译、focused 基本绿）。本计划不改变 `feat/icon-core-refactor` 现有两个提交。

## 1. 背景与现状

- 源分支 `feat/icon-core-refactor`：基于 `codex/v2-settings-icon-designer`（117e35ed），去掉设计器 UI，保留 V1 图标重构（`Presentation/Icon/Configuration`、`Resolution`、`Plugins`）+ V0→V1 迁移。当前 HEAD `3c9ff829`，源码与测试目标可编译，focused 基本绿。
- `origin/main` 已到 `caa0d46a`（2026-11-10）。相对本分支的合并基线（10-23 main 侧 `b9b7961f`）落后 **598 个提交**，本分支领先 40 个。
- 关键事实：**main 与我们是两套不同的图标内核**。
  - main 在**旧图标管线**上持续加特性（#205 分段进度、#235 高功率模式配色、#253 充电符号居中、#275 蓝牙中间图标颜色、#315 电池顶部标记、#297 输入源标记样式，以及亮度/BetterDisplay、电池功耗等设置），并把外观管线重构成多 Publisher。
  - 我们分支把这条管线换成 **V1 配置 + 槽位 Resolver + 插件** 架构。
- 因此这不是机械冲突，而是把 main 的图标新特性**逐项移植进 V1 架构**的特征级集成；同时把 main 的非图标改动整体并入。

## 2. 目标 / 非目标

**目标**
1. 在 `feat/icon-core-refactor` 基础上合入 `origin/main@caa0d46a` 的全部非图标改动。
2. 以 V1 架构为主，把 main 的全部图标新特性移植进 `IconConfigurationV1` + `IconCompositionResolver` + `StatusIconRenderer` + 插件。
3. 交付前 `swift build` 源码+测试编译通过；按 AGENTS 高风险要求跑 `full` 本地验证；图标 related focused 测试全绿（仅允许在**未改动的原始分支 tip 上同样失败**的环境性像素用例例外，且需注明）。

**非目标**
- 不重新引入图标设计器 UI（本分支已移除）。
- 不在本计划内做真正的发布/签名/公证。

## 3. 总体策略（A：新架构为主）

- 共享/演进文件：**以 V1 架构为准**，把 main 的行为修复与新增字段重新表达进新架构。
- 非图标文件：**整体采纳 main**。
- 每个特性独立小步：schema → 存储 → 解析 → 渲染 → 设置页 → 测试，一步一验证，避免一次性大合入后长时间不可用。

## 4. 要移植的 main 图标设置（相对基线新增，均不在当前 V1 schema）

类型定义（origin/main，合并后随非图标改动自动带入或按需 cherry-pick）：
`Sources/StatusTrioCore/Models/BatteryTopMarker.swift`、`BatteryStatusColors.swift`、`BluetoothIconColorSelection.swift`、`InputSourceMarkerStyle.swift`、`BatteryConnectedIndicator.swift`、`BatteryPowerDisplayOptions.swift`、`Monitoring/SystemPowerReader.swift`（`SystemPowerSample`）。

映射建议（新字段一律带默认值，保持 V1 向后兼容；必要时升级 codec 版本做 V1→V2 迁移）：

| main 设置 | 建议落到 V1 | 消费方 |
| --- | --- | --- |
| `batteryOnBatteryMarker` / `batteryChargingMarker` / `batteryConnectedMarker` / `batteryNoBatteryMarker`（#315） | `IconBehaviorConfiguration.batteryMarkers` | OuterRing/中心渲染 |
| `showsBatteryPowerFlow` / `showsBatteryPowerInfoBar` / `showsHighEnergyApps` / `highEnergyAppsRefreshIntervalSeconds` | `IconBehaviorConfiguration.batteryPowerDisplay` | 电池详情/预览 |
| `showsChargingIndicator` | `IconBehaviorConfiguration.showsChargingIndicator` | 渲染 |
| `batterySplitGapProgress`（#205） | `IconBehaviorConfiguration.ringGapProgressMode`（`GapProgressMode`，已加到 `OuterRingState`） | Resolver→OuterRing |
| `batteryConnectedIndicator` | `IconBehaviorConfiguration.batteryConnectedIndicator` | 渲染 |
| `batteryStatusColors` | `IconAppearanceConfiguration.batteryStatusColors` | 调色 |
| `autoLowPowerThreshold` / `autoEnablesLowPowerMode` | `IconBehaviorConfiguration.lowPower` | 解析/面板 |
| `inputSourceMarkerStyle`（#297） | `IconAppearanceConfiguration.inputSourceMarkerStyle` | 中心输入源 |
| `bluetoothIconColor`（#275） | `IconAppearanceConfiguration.bluetoothIconColor`（配合 `IconColorRole.bluetoothIcon`） | 调色 |
| `bluetoothSymbolScale` | `IconAppearanceConfiguration.center.bluetoothSymbolScale` | 渲染尺寸 |
| `showsBluetoothListeningMode` | `IconBehaviorConfiguration.bluetoothAudioCenter.showsListeningMode` | 面板/渲染 |
| `showsWiFiPowerControl` / `confirmsWiFiPowerOff` | `IconBehaviorConfiguration.networkCenter.*` | 设置/面板 |
| 高功率模式（#235）：`SystemPowerSample` + `isHighPowerMode` | **运行时输入**（已加到 `IconPresentationInputs.systemPower` / `isHighPowerMode`），不落盘 | Resolver 给电池环上色 |
| #253 充电符号居中 | 纯渲染几何修复，不动 schema | `StatusIconRenderer` |

`iconConfiguration` 仍作为图标设置的**唯一真源**；上述 main 新增的 `@Published` 属性在 `SettingsStore` 中改为**基于 `iconConfiguration` 的计算属性**（读/写都映射到配置），避免双真源漂移。

## 5. 分阶段任务

### Phase 0 — 集成分支与冻结基线
- [ ] 从 `feat/icon-core-refactor` 建集成分支（如 `feat/icon-core-merge-main`）。
- [ ] 记录并冻结基线：`git fetch origin main`；`MAIN=caa0d46a`；记录 `git merge-base`（当前共同祖先应为 10-23 侧 `b9b7961f` 附近）。
- [ ] 记录冲突清单（见 §7）与 main 新增设置清单（§4）。
- 验收：分支可编译（沿用 `feat/icon-core-refactor` 现状）。

### Phase 1 — 并入 main 非图标改动
- [ ] `git merge origin/main`，冲突按类处理：
  - 本地化（`LocalizationKey.swift` + 各 `*.lproj/Localizable.strings`）：**并集去重**。
  - `docs/*`、`.gitignore`、`scripts/*`：并集或取 main（`build-app.sh` 保留我们的 `APP_OUTPUT_PATH` 覆盖 + main 的 `build_phase` 结构）。
  - `BluetoothDeviceController.swift`：取 main 的 `connectedLevels` + `hasCompletedBatteryRead`，并保留我们的 `batteryLevelsUpdatedAt`。
  - `SystemStatusStore.swift`：保留我们的 `SettingsSurfaceVisibility`，并入 main 的 `isBrightnessSettingsVisible`。
  - `DockIconRenderCache.swift`、`OuterRingState`、`IconColorRole`、`IconPresentationConfiguration`：并集（`inactiveColor` + `gapProgressMode` + `bluetoothIcon` + `runtimeOptions` + `systemPower`/`isHighPowerMode`）。
- [ ] 共享图标管线文件（`SettingsStore`、`SettingsStore+IconAppearance`、`IconPresentationViewModel`、`StatusIconRenderer`）**此阶段先保留我们的版本**，把 main 的差异以 TODO 形式记录，交后续阶段处理。
- 验收：非图标相关模块可编译；记录仍未移植的图标差异。

### Phase 2 — V1 schema 扩展 + 迁移
- [ ] 在 `IconBehaviorConfiguration` / `IconAppearanceConfiguration` 增加 §4 表里的字段（全部带默认值，`CodingKeys` 用 `decodeIfPresent`）。
- [ ] 若判定需要新版本，则 `IconConfigurationV2` + `IconConfigurationCodec` 版本识别 + `IconConfigurationMigration` V1→V2；否则保持 V1 内向后兼容扩展并补 `IconConfigurationMigrationTests`。
- [ ] `IconDesignerDefaults`（保留的模型层）同步默认值。
- 验收：`IconConfigurationMigrationTests`、`IconConfigurationValidationTests` 通过；旧存档可读。

### Phase 3 — SettingsStore 统一
- [ ] 以我们的 `iconConfiguration` 为真源；把 main 新增的图标 `@Published` 改为基于 `iconConfiguration` 的计算属性（读/写映射），移除重复存储。
- [ ] main 新增的**非图标** `@Published`（音量/亮度/设备顺序/刷新间隔等）整体采纳。
- [ ] `SettingsStore+IconAppearance`：保留我们的「单 publisher（iconConfiguration→StatusIconAppearance）」，把 main 新字段并入 `StatusIconAppearance` 的生成。
- 验收：`SettingsStoreTests`、`IconAppearancePublisherTests`、`SettingsSurfaceVisibilityTests` 通过。

### Phase 4 — Resolver/插件消费新字段
- [ ] `IconCompositionResolver` / 各 Slot Resolver / `IconPaletteResolver` 读取 Phase 2 新字段：
  - #205 `gapProgressMode` 写入 `OuterRingState`。
  - #235 用 `IconPresentationInputs.systemPower` / `isHighPowerMode` 决定电池环配色。
  - #275 `bluetoothIconColor` 应用到中间蓝牙字形（`IconColorRole.bluetoothIcon`）。
  - #315 电池标记档位、#297 输入源标记样式。
- 验收：新增/更新对应 Resolver focused 测试（`IconSlotResolverTests`、`IconPaletteResolverTests`、`IconResolutionTraceTests` 等）通过。

### Phase 5 — Renderer
- [ ] 移植 #253 充电符号居中几何修复（不改 schema）。
- [ ] 让渲染器消费 #205/#235/#275/#315 产生的场景字段；与 main 的文本/符号尺寸修复对齐（我们的 `normalizedSizePercentage` 体系 vs main 的 raw scale，二者需要同一套尺寸策略）。
- [ ] 保留本分支已修的 `CenterImageCache` 复用（`resolvedIdentity`）修复。
- 验收：`IconSceneRendererParityTests`、`Issue30WiFiAlignmentTests`、`ChargingEffectRenderingTests`、Menu Bar/Dock parity 测试通过；像素级指纹保持诚实。

### Phase 6 — 设置页
- [ ] 把 main 的设置页新控件并入（不引入设计器）：`AppIconSectionView` / `BatterySectionView` / `BatteryStatusColorsView` / `BluetoothSectionView` / `NetworkSectionView` 等，使新设置可编辑且读写走 Phase 3 的统一存储。
- [ ] 本地化：为主新增文本补 `en` + `zh-Hans`（其余语言按需）。
- 验收：`SettingsViewTests`、`SettingsPagesOptimizationContractTests`（若保留）、本地化回归过滤器通过。

### Phase 7 — 完整验证
- [ ] 迭代期用 focused：`bash scripts/test.sh '<Filter>'`。
- [ ] 交付前跑高风险全量：`bash scripts/verify-local.sh full`（图标/渲染/存储属高风险）。
- [ ] 记录：macOS 13 真机、Ventura、签名/公证、Universal 等仍未验证项，按 AGENTS 的 `NOT RUN` 口径如实标注。
- [ ] 说明唯一允许的失败：在**原始分支 tip 同样失败**的环境性像素用例（如 `IconDesignerCenterBatteryScaleTests.testHundredPercent...`，85.0<87.33，字体光栅度量差异），并保留证据。

### Phase 8 — 收尾
- [ ] 更新相关 docs（`docs/icon-*`, `docs/input-source-center-slot.md`, `docs/ventura-icon-availability.md`）。
- [ ] 迁移说明、变更日志、review findings。
- [ ] 交给用户测试验收（保留分支/worktree，验收通过再合并）。

## 6. 验证与风险

- 每个 Phase 结束都要能编译；任一阶段不可编译就不得推进下一阶段。
- 高风险（图标/渲染/存储 schema/迁移）：交付前必须 `full`；迭代期用 focused。
- 主要风险：
  1. **双真源漂移**：main 的 `@Published` 与 `iconConfiguration` 并存会不一致——严格按 Phase 3 收敛到单真源。
  2. **像素回归**：尺寸体系差异（normalized vs raw scale）需在同一策略下对齐，用现有 parity/指纹测试守住。
  3. **迁移兼容**：扩展 schema 必须向后兼容旧存档；补迁移测试。
  4. **macOS 13/Ventura**：静态契约不等于运行时，真机项记 `NOT RUN` 直到实测。
- 回滚：整段工作放在独立集成分支；`feat/icon-core-refactor` 与 `main` 不受影响，可随时放弃集成分支。

## 7. 合并冲突清单（Phase 1 起点）

已识别 32 个冲突（部分已在“撤出合并”前试解，作为参考）：
- 本地化：`Localization/LocalizationKey.swift`、`Resources/*/Localizable.strings`（12 个）
- 非图标逻辑：`Monitoring/BluetoothDeviceController.swift`、`Store/SystemStatusStore.swift`、`UI/Icon/DockIconRenderCache.swift`、`docs/*`、`scripts/build-app.sh`、`.gitignore`
- 图标结构体（并集）：`Presentation/Icon/IconColorRole.swift`、`OuterRingState.swift`、`IconPresentationConfiguration.swift`
- 图标核心（需重点移植）：`Settings/SettingsStore.swift`（16 处）、`Settings/SettingsStore+IconAppearance.swift`、`Presentation/Icon/IconPresentationViewModel.swift`、`UI/Icon/StatusIconRenderer.swift`
- 测试：`AppIconControllerTests`、`IconPresentationViewModelTests`、`IconSurfaceIntegrationTests`、`InputSourceMonitoringLifecycleTests`、`SettingsViewTests`

## 8. 参考

- 分支现状与交接：`feat/icon-core-refactor`（297d85a4 去设计器 UI；3c9ff829 修图标缓存复用）。
- 原设计器计划：`docs/superpowers/plans/2026-10-09-v2-settings-icon-designer.md`。
- 规则：`AGENTS.md`（Risk-Based Verification、Menu Bar/Dock parity、macOS 13 兼容）。
