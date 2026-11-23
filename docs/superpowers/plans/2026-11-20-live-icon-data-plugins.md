# 实时图标数据源 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**目标**　现有设置可独立绑定外环、中间和底部数据源。用户脚本写入本地 JSON 后，菜单栏和 Dock 随最新读数更新。

**架构**　设置保存槽位绑定。宿主按需订阅数据生产者，将同一份类型化快照交给已有注册表和解析器。解析结果分开交付绘制场景和活跃来源，前者按可见变化去重，后者负责采样请求。

**技术栈**　Swift、Combine、Foundation、AppKit、Swift Testing/XCTest。macOS 13 起。仅复用系统框架。

**设计依据**　[内置图标插件契约](../../icon-content-plugins.md)与[图标数据更新边界](../../api/icon-presentation.md#7-后续功能与插件的接入清单)。本计划以当前设置页为用户入口，停用的 2.0 设计器不进入交付。

## 通用约束

- 首先确认远端 `main` 和 `fix-ring-datasource-demand`。计划编写时分别为 `b1ce4fa7` 和 `877e80f7`，共同基点 `2ae26a1c`。使用独立 worktree，从更新的 main 集成修复提交，保护主目录和他人的工作树。每项通过后可在本地单独提交，留待用户验收和决定合并推送。
- 菜单栏和 Dock 使用同一图标配置、数据和解析结果。保留现有尺寸、配色、硬件按需采样和权限边界。普通测试关闭可见 UI。
- 以触发断言失败的测试开始行为改动。每项在 `scripts/test.sh` 跑针对性测试，最终集成树执行 `bash scripts/verify-local.sh full`。真实 UI 或 macOS 13 运行证据分别报告。
- 本地 JSON 是唯一外部接入方式。用户负责运行生产者。宿主读取批准的目录，支持显示文本和归一化数值，按现有槽位样式渲染。配置版本、绑定 ID 和输入限制见任务 4。

## 审查重点

- 图标刷新将 CPU＋内存误缩成 CPU，或面板与图标互相释放采样所有权。见任务 1、3。
- 用户旧偏好和旧 V1 文件相冲突，重启或导入后改回旧选择。见任务 2。
- 不同来源恰好画出相同图形，来源变化仍应更新采样。见任务 3。
- 插件文件替换、断连、恢复或重复 ID 不得抹掉用户保存的选择。见任务 2、4。
- 畸形、超大或符号链接输入不得卡住宿主，多个槽位及表面使用同源只读一次。见任务 4。

### 任务 1 — 修复生产链路并锁定回归

**文件**　[AppEnvironment.swift](../../../Sources/StatusTrioCore/App/AppEnvironment.swift)、[SettingsStore+IconCompatibility.swift](../../../Sources/StatusTrioCore/Settings/SettingsStore+IconCompatibility.swift)、[PhaseOneCorrectnessTests.swift](../../../Tests/StatusTrioCoreTests/PhaseOneCorrectnessTests.swift)，新增 `Tests/StatusTrioCoreTests/IconLiveDemandIntegrationTests.swift`。

- [x] 给实际生产订阅提取可注入宿主的测试接线，让测试驱动原设置发布、图标输出及需求登记。断言面板关闭、V1 为 CPU、实时设置为 CPU＋内存时，图标输出后菜单栏及 Dock demand 仍为 `[.cpuUsage, .memoryUsage]`，隐藏一侧只释放其 owner。复原旧读法确认失败后再恢复修复。
- [x] 增加真实设置投影用例。离线且输入法数据可用时，开关打开断言 `.overridden(.networkProblem)`，关掉断言 `.inputSource`，网络恢复返回输入法。由当前 `prioritizesNetworkErrors` 填入 `centerOverride.networkProblemOverridesPrimary`。
- [x] 执行 `bash scripts/test.sh 'IconLiveDemandIntegrationTests|PhaseOneCorrectnessTests|IconDependencyDemandTests|IconSlotResolverTests'`，确认所有匹配断言通过。

### 任务 2 — 统一三个槽位的设置和绑定，清理旧设计器

**文件**　[IconCompositionConfiguration.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Configuration/IconCompositionConfiguration.swift)、[IconContentPlugin.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Plugins/IconContentPlugin.swift)、[IconContentLegacyAdapter.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Plugins/IconContentLegacyAdapter.swift)、[SettingsStore+IconCompatibility.swift](../../../Sources/StatusTrioCore/Settings/SettingsStore+IconCompatibility.swift)、[SettingsStore+IconPresentation.swift](../../../Sources/StatusTrioCore/Settings/SettingsStore+IconPresentation.swift)、[SettingsPreferenceCatalog.swift](../../../Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift)、[FooterResolver.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Resolution/FooterResolver.swift)及现有外环、中间、底部设置控件。新增 `IconSlotBindingPersistenceTests.swift`。

- [x] 把 `IconContentBinding(pluginID: String, presentationID: String)` 变为可编码的稳定标识。新增版本化 `IconSlotBindingsV1` 保存外环、中间、底部各自的可空主绑定和备用绑定。主绑定为空表示隐藏。未知非空 ID 可解码、可回存并进入回退链。内置 ID 保留，由适配器转换已支持的旧枚举。
- [x] 在新存储缺失时从当前有效分项设置导入槽位选择、现有回退及覆盖语义。迁移仅运行一次，受损或更新版本的数据保留原始字节，本次运行用分项设置回退。随后正常设置控件通过同一个 setter 改绑定。保留原分项键及既有导入字段兼容，旧版导入通过同一 setter，禁止外部包或本机目录路径随设置迁移。测试覆盖旧快照冲突、二次启动、未知来源往返和旧版导入。
- [x] 将实际渲染改为读取绑定，底部音量、Wi-Fi、电池和隐藏分别接入原有宿主渲染结果。保持三槽的默认、网络覆盖、蓝牙选择和回退结果。为当前设置可选的组合加迁移前后场景对照。旧 schema 解码和兼容映射保留，移除停用编辑器的启动写回、编辑、撤销、检查器。逐项查生产引用，保留颜色控件、当前预览所需的值和资源。更新 [插件说明](../../icon-content-plugins.md)中过时的设计器段落。
- [x] 执行 `bash scripts/test.sh 'IconSlotBindingPersistenceTests|IconConfigurationMigrationTests|IconContentPluginResolutionTests|IconSlotResolverTests|SettingsPreferenceCatalogTests|SettingsTransfer|StatusIconPreviewCardTests'`。确认缺失的插件恢复时自动回到原选择，三个槽位仍可通过原设置使用。

### 任务 3 — 让宿主统一管理来源订阅

**文件**　[IconPresentationViewModel.swift](../../../Sources/StatusTrioCore/Presentation/Icon/IconPresentationViewModel.swift)、[IconCompositionResolver.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Resolution/IconCompositionResolver.swift)、[IconContentDependencies.swift](../../../Sources/StatusTrioCore/Presentation/Icon/Plugins/IconContentDependencies.swift)、[IconSourceDemandBridge.swift](../../../Sources/StatusTrioCore/App/IconSourceDemandBridge.swift)、[AppEnvironment.swift](../../../Sources/StatusTrioCore/App/AppEnvironment.swift)。新增 `IconLiveSourceCoordinator.swift` 和同名测试。

- [x] 测试先覆盖同一数据源被多个槽位或表面引用时只启动一次，最后一个需要它的消费者离开才取消。测试相同像素但不同绑定仍更新需求，晚到的旧订阅事件不能覆盖新来源。
- [x] 给运行时解析结果携带实际选中的 `IconContentBinding` 和依赖。以单独发布的需求状态驱动采样而非图标图片的输出去重。运行时数据发布通过宿主的共享快照进入解析。使用可注入的时钟及合并调度器，首个有意义的新值及时出现，后续突发更新合并，每秒最多四次由外部读数触发的图标解析，连续更新不饿死尾值。
- [x] 内存环接到该路径，继续共享硬件监控采样。面板关闭、硬件主来源/回退切换、后台 placement 和停止均可测，音量/Wi-Fi 不启动硬件指标采样。硬件回退仅在实际启用时采样。外部主来源在被选中且有启用的表面时仍保留订阅，确保失效后可恢复。备用外部来源在主来源不可用时订阅。
- [x] 执行 `bash scripts/test.sh 'IconLiveSourceCoordinatorTests|IconLiveDemandIntegrationTests|HardwareMonitorPanelDemandTests|IconPresentationViewModelTests|Issue30WiFiAlignmentTests'`，确认生命周期、回退和绘制独立去重。

### 任务 4 — 接入用户的本地实时 JSON 插件

**文件**　新增 `Sources/StatusTrioCore/Presentation/Icon/Plugins/External/LocalIconPluginManifest.swift`、`LocalIconPluginCatalog.swift`、`LocalIconPluginFeed.swift`、`Tests/StatusTrioCoreTests/LocalIconPluginTests.swift`，扩展现有三个来源选择器和图标插件文档。

- [x] 定义 schema 1。由当前图标设置显式启用的包目录含 `manifest.json` 和固定文件 `data.json`。清单包含 `schemaVersion`、`pluginID`、`title`、`presentations`，每项包含 `id`、`slot`、`kind`。外部 ID 为 ASCII 字母数字、点、下划线或连字符，长度 1–128，禁止 `builtin.` 前缀。包内最多 16 项，重复插件 ID 的外部包均不可选。中间可用 `text`，外环和底部可用 `fraction`。读数包含 `schemaVersion`、UTC ISO 8601 `observedAt`、按 presentation ID 索引的 `values`。文本最多 16 个字符且拒绝控制字符，数值须有限并在 `0...1`。读数 15 秒后失效，时间超前 2 秒以上拒绝，较旧读数不能覆盖仍在使用的新读数。
- [x] 测试清单和样本错误、越界、文本控制字符、重复 ID、未来或过期时间、删除数据文件、订阅取消与晚到事件。每文件最多 16 KiB。使用经批准目录的描述符打开固定子文件，拒绝符号链接及非普通文件，异步读取并限制字节数。监听目录变更以支持原子替换，按任务 3 合并，宿主按过期截止安排失效，即使脚本停止写入也能回退。
- [x] 注册已批准的包并让用户在现有槽位选择器里选来源。禁用或删除包后以备用来源显示，重新启用后恢复原槽位选择。用 `latency` 文本演示从 `42 ms` 更新到 `57 ms`，停止写入后回退，重新写入后恢复。文档给出清单样例、通过临时文件原子替换的样例以及本机目录权限说明。外部包入口只在直装版提供。当前分支未验证 App Store 的沙箱目录授权，沙箱构建隐藏入口并跳过外部目录读取。
- [x] 执行 `bash scripts/test.sh 'LocalIconPluginTests|IconLiveSourceCoordinatorTests|IconContentPluginRegistryTests|IconSlotBindingPersistenceTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests'`。报告按策略跳过的可见 UI。

### 交付

- [ ] 对最终集成 SHA 执行 `bash scripts/verify-local.sh full`，记录结果并检查 diff。做最终全支路审查，核对设置迁移、关闭采样、文件边界和菜单栏/Dock 同源。
- [x] 通过 `bash scripts/build-worktree.sh release no-open` 产出独立开发版供用户手动验收。验收覆盖 CPU＋内存闭面板刷新、网络开关、三个槽位的旧偏好、脚本更新与过期回退。保留 worktree 及本地提交。
