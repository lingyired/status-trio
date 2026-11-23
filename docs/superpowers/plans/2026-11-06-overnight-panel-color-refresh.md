# 夜间四项改进实施计划

> **For agentic workers:** 执行采用 subagent-driven-development；每项先回归再实现，分项审查后整体复核。用户已授权连续执行、明早统一验收。

**Goal:** 在一个隔离分支完成 #281、#282、#275、#255，交付可测试开发包与验证记录。
**Spec:** `docs/superpowers/specs/2026-11-06-overnight-panel-color-refresh-design.md`
**Architecture:** 复用 SwiftUI 页面、共享图标 scene/配置、Combine 设置传播和 SystemStatusStore 既有取消型刷新任务。
**Tech Stack:** Swift 6 / SwiftUI / AppKit / Combine / Swift Testing，最低 macOS 13；依赖与发布流水线不变。
**Base:** `origin/main=d4598847040a5b2d167ec3825c162270eba3492b`。

## 全局限制

不修改原工作区/别人的未提交改动。不合并 main、不发布、不关闭 issue。不启动真实前台 UI、不启用 STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS。保留菜单栏/Dock 同源。文案完整覆盖所有随包语言。full 是最后交付检查，不每次编辑运行。

## Review Focus

1. 无有效流带时卡片必须保持四角圆润；细分支端点不能露缝或溢出。
2. 两行底部按钮独立 hover，右侧空白也能触发原动作，辅助功能角色不丢。
3. 蓝牙图标颜色与音量颜色组合互不影响；指定设备/自动设备与 Dock 的缓存更新同步。
4. 新旧 defaults 部分存在、越界/NaN、无电池的 Mac 不得选错或丢失已有值。
5. 快速插拔电和改间隔不得堆叠刷新任务；stop/deinit 后不会重新启动；未生效的另一个滑条不重启等待。

## Task 1：电池页交互与图形（独立执行，可与 Task 2 并行）

**Files:**
- Modify `Sources/StatusTrioCore/UI/BatteryDetailsView.swift`
- Modify `Sources/StatusTrioCore/UI/BatteryPowerFlowView.swift`
- Create 最小专用 ButtonStyle/Shape 文件（若需要）
- Test `Tests/StatusTrioCoreTests/BatteryDetailsLayoutTests.swift`
- Test `Tests/StatusTrioCoreTests/BatteryPowerFlowTests.swift` / 新建针对几何/离屏截图的 Swift Testing 文件

**Interfaces:** 保持 BatteryDetailsView 的两个 onOpen... 回调接口；Shape 只接受连接侧，复用 PowerCardSurface，不改变共享其他卡片。

- [ ] 先增加行为/几何回归并跑 focused filter 记录旧实现失败；避免只查源码字符串或镜像实现。
- [ ] 将两行改为整行原生按钮与独立 hover，维持标题左对齐和文字样式。
- [ ] 实现 macOS 13 可用单侧圆角，连接时才启用，fill/stroke 相同 shape。
- [ ] 覆盖单/多/无分支、无输入、电池输入、深浅色和透明度设置；离屏绘图不创建真实窗口。
- [ ] 跑 `bash scripts/test.sh 'BatteryDetailsLayoutTests|BatteryPowerFlow'`，输出审查证据与未测交互。

## Task 2：双刷新间隔（拥有共享设置/本地化文件，Task 3 最后整合这些文件）

**Files:**
- Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift`
- Modify `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify `Sources/StatusTrioCore/Localization/LocalizationKey.swift` 与 `Resources/Localizations/*/Localizable.strings`
- Test `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`、`SystemStatusStoreTests.swift`、必要的新 Swift Testing suite

**Interfaces:**
- `@Published var refreshIntervalOnBatterySeconds: Double`
- `@Published var refreshIntervalOnPowerSeconds: Double`
- `func refreshInterval(forPluggedIn: Bool) -> Duration`（无电池由调用侧视作接电）或等价明确命名纯逻辑
- 复用 `func setRefreshInterval(_ interval: Duration)`，改变时只取消/重建 fallback 等待

- [ ] 回归先覆盖新装、旧值迁移、部分新 key、持久化、夹紧/非有限值、两种电源和无电池选择。
- [ ] 以可控 sleep 验证即时取消、新等待生效、同值/非生效设置不重启、start/stop/deinit 生命周期；先看到旧行为失败。
- [ ] 增加两个独立设置和迁移；必要时保留旧 API 兼容内部原测试，但新生产传播只用双值。
- [ ] CombineLatest 两个值与去重电源类型，选择最终生效间隔；维护任务取消边界。
- [ ] Settings 两行滑条及当前生效说明，12 语言完整键。
- [ ] 跑 focused Settings/refresh/lifetime tests；向 lead 移交共享文件，之后不再写共享设置和本地化。

## Task 3：蓝牙图标独立配色（lead；共享文件须等 Task 2 移交）

**Files:**
- Modify `Sources/StatusTrioCore/Models/BluetoothAudioIconOptions.swift`
- Modify `Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift`
- Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify `Sources/StatusTrioCore/Settings/SettingsStore+IconAppearance.swift`
- Modify `Sources/StatusTrioCore/UI/Settings/AppIconMiddleIconView.swift` 或真实对应中间图标设置组件
- Modify `Sources/StatusTrioCore/Localization/LocalizationKey.swift` 与全部本地化 strings
- Inspect `Sources/StatusTrioCore/App/AppIconController.swift`、`UI/Icon/DockIconRenderer.swift`，仅在尚未传播共享 scene 时改动
- Test `SettingsStoreTests`、`IconPresentationMapperTests`、`IconSurfaceIntegrationTests` 与新 Swift Testing suite

**Interfaces:** `BluetoothAudioIconOptions.usesIconColor: Bool = true`；`SettingsStore.usesBluetoothAudioIconColor: Bool`，key `usesBluetoothAudioIconColor` 默认 true，发布配置必须保留新字段。

- [ ] 先回归图标/音量 4 种开关组合、自动/指定设备、手选符号、两种表面 scene 与 render key。
- [ ] 给 options 增加默认 true 字段，mapper 仅将蓝牙符号 color 从固定 `.bluetooth` 改为配置选择 `.primary`。
- [ ] 审查所有重建 BluetoothAudioIconOptions 的位置，避免中途丢字段。
- [ ] Task 2 移交后持久设置/发布链/中间图标页独立 toggle/12语言。
- [ ] 跑 mapper、Settings、Dock parity 和 `Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests`。

## Task 4：整体审查、验证、验收交付

**Files:** `docs/verification/2026-11-06-overnight-panel-color-refresh.md` 与必要离屏验收截图。

- [ ] 独立审查四项需求与最终 diff，修复确有证据的问题并补必要回归。
- [ ] 重新 fetch origin/main，记录是否推进，核对共享文件没有覆盖；若基线改变，按项目规则重检。
- [ ] final tree 运行 `bash scripts/verify-local.sh full`，日志包含 branch/SHA/工作树差异、命令和状态；失败先找根因，不弱化断言。
- [ ] 用 `bash scripts/build-worktree.sh release no-open` 制作带独立 bundle ID/codename 的验收包，记录确切路径、构建 SHA/dirty state/平台验证；不安装覆盖正式应用。
- [ ] 报告四项完成情况、通过范围、跳过可见 UI、Ventura 与手动验收 NOT RUN；提供明早逐项操作与预期。
- [ ] 检查无遗留测试进程，所有 relevant background jobs 收集；保留 worktree 与开发包，不合并或关闭 issue。

## 执行记录

计划写入后开始实施。后续裁定、失败根因、验证结果由验收报告记录。
