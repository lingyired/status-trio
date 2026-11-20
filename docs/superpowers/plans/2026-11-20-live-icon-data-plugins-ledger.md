# 实时图标数据源 — 执行 Ledger

- 工作树：`/Users/lingsmbp/Documents/aiwork/status-trio/.agents/worktrees/live-icon-data-plugins`
- 计划：`docs/superpowers/plans/2026-11-20-live-icon-data-plugins.md`
- 起始提交：`b1ce4fa7`（origin/main，2026-11-20 抓取）
- 修复提交：`877e80f7`（fix-ring-datasource-demand，基点 `2ae26a1c`）
- 本次执行者：auto/deepseek-v4.1-flash + max；未进行任何 Git 写操作，提交由上层会话处理。

## 环境裁决

- Flash 无头会话仅负责工作树内的源码、文档和测试。禁止写共享 Git 元数据、创建替代 Git 目录、尝试审批或清理其他工作树。当前工作树上的修复补丁经上层会话确认与 877e80f7 一致，直接从该源码状态继续。
- DSH 文件沙箱阻止 SwiftPM 自带的 `sandbox-exec`（`sandbox_apply: Operation not permitted`），`swift test`/`swift build` 需加 `--disable-sandbox`。为按原脚本入口运行，本次用临时 PATH shim（`/tmp/st-shim/swift`）只给 `test`/`build` 注入该参数；未改仓库脚本。
- `TestUserDefaultsTests` 的 2 个用例需要删除 `~/Library/Preferences/*.plist`，DSH workspace-write 沙箱不允许；这是环境限制而非本次改动。其余 1247 个测试通过。
- 未执行 Git fetch/compare，未验证远端是否又前进；上层会话提交前需自行核对。
- 未连接真实 UI/macOS 13 环境；可见 UI 测试按默认策略跳过，真实运行时、签名、公证、DMG、Universal、App Store 构建均未验证。

## 任务进度

- [x] 将 877e80f7 补丁带入工作树，尚未写入共享 Git 提交。
- [x] 任务 1 — 生产链路、实时投影与回归锁定。
  - 新增 `IconHardwareDemandWiring`，从 `AppEnvironment` 提取真实设置发布 + 图标输出 + 需求登记路径；`AppEnvironment` 改用它。
  - `SettingsStore.iconConfiguration(from:inputSourceMarkerStyle:)` 现在把 `prioritizesNetworkErrors` 投影到 `centerOverride.networkProblemOverridesPrimary`。
  - 新增 `IconLiveDemandIntegrationTests`：CPU+内存双环在图标 tick 后仍保留双指标；隐藏一侧只释放该表面；网络异常覆盖随真实设置开关切换并在网络恢复后回到输入法。
  - 目标过滤：`IconLiveDemandIntegrationTests|PhaseOneCorrectnessTests|IconDependencyDemandTests|IconSlotResolverTests`，46/46 通过。
- [x] 任务 2 — 槽位绑定、一次性迁移与底部四态。
  - `IconContentBinding` 改为 Codable；新增 `IconSlotBindingsV1`/`IconSlotBindingSelection`/`IconSlotBindingsCodec`，未知非空 ID 往返保留，空主绑定隐藏并丢弃备用。
  - `SettingsStore` 新增 `iconSlotBindings`、一次性迁移、显式 setter、旧分项设置同步；损坏/更高版本 payload 原字节保留，本次运行退回分项设置。
  - 运行时解析改为以绑定为准：外环/中间/底部 resolver 接受 `IconSlotBindingSelection`；`FooterResolver` 支持音量、Wi-Fi、电池、隐藏四种宿主渲染结果（网络/电池插件新增 footer 呈现）。
  - `SettingsPreferenceCatalog` 增加 `iconSlotBindings`，经同一 setter 导入；外部目录/路径不进入迁移。
  - 停用的 2.0 设计器没有生产引用；`IconDesignerEditorModel`、`IconDesignerEditHistory`、`IconDesignerEditSnapshot`、`IconDesignerInspectorModel` 已从产品 target 移入 `Tests/StatusTrioCoreTests/TestSupport/`，历史编辑/撤销/检查器测试继续运行，产品不再编译废弃编辑器。保留颜色控件、`IconDesignerEditingModel`、预览与资源。
  - `bootstrapIconConfiguration()` 继续解码已存 V1、读取旧分项设置并在内存中应用兼容迁移；启动不再创建、规范化或写回 `iconConfigurationV1`。仅显式 `updateIconConfiguration`/reset 仍持久化。新增新装、二次启动和旧 payload 字节保持测试。
  - 目标过滤：`IconSlotBindingPersistenceTests|IconConfigurationMigrationTests|IconContentPluginResolutionTests|IconSlotResolverTests|SettingsPreferenceCatalogTests|SettingsTransfer|StatusIconPreviewCardTests`，89/89 通过。
  - 清理后过滤：`IconDesigner|IconConfigurationMigrationTests|IconSlotBindingPersistenceTests|CenterPercentageInteractiveRangeTests|PresentationArchitectureTests`，104/104 通过；新增产品源码无四个废弃模型引用检查通过。
  - `swift build --target StatusTrioCore` 通过（7.45 秒）；`scripts/check-forbidden-patterns.sh` 通过。未运行 full，留待上层在最终树执行。
- [x] 任务 3 — 宿主统一需求与订阅生命周期。
  - 新增 `IconPresentationDemand`：区分实际绘制的 `selectedBindings`、必须保持订阅的 `subscribedBindings` 与实际依赖；解析结果同时携带 trace binding、dependencies 和 demand。
  - `IconPresentationViewModel` 单独发布 `demand`，场景像素去重不再抑制需求变化；硬件 tick 改为看绑定而不是持久化 V1。
  - 新增 `IconLiveSourceCoordinator`（跨槽位/表面引用计数、generation token 丢弃迟到旧回调）和 `IconLiveResolutionCoalescer`（首值立即、0.25 秒内合并、最多 4 次/秒、保留尾值）。
  - `AppEnvironment` 的外部读图刷新走 coalescer；硬件需求由 `IconHardwareDemandWiring` 消费 `demand`，按 placement 释放单侧。
  - 内存环依赖从实际选中 binding 的依赖取得；音量/Wi-Fi 不启动硬件采样；硬件备用只在真正被选中时采样；外部主绑定在备用绘制期间仍保留订阅。
  - 目标过滤：`IconLiveSourceCoordinatorTests|IconLiveDemandIntegrationTests|HardwareMonitorPanelDemandTests|IconPresentationViewModelTests|Issue30WiFiAlignmentTests`，44/44 通过。
- [x] 任务 4 — 本地实时 JSON 插件。
  - 新增 `LocalIconPluginManifest`、`LocalIconPluginCatalog`、`LocalIconPluginFeed`、`LocalIconPlugin`、`LocalIconPluginRuntime`、`LocalIconPluginAccess`。
  - schema 1、ID/标题/槽位/类型校验、16 项上限、重复插件 ID 全部不可选、16 KiB 上限、`O_NOFOLLOW` + `fstat` 普通文件校验、异步读取。
  - 文本 ≤16 字符且拒绝控制字符；fraction 有限且在 0...1；15 秒过期、未来 2 秒拒绝、旧读数不覆盖新读数；目录 vnode 监听支持原子替换；无文件/畸形立即回退。
  - 运行时按 `subscribedBindings` 只启动被需要的 feed；包删除/禁用保留原绑定并走备用，恢复后原选择自动生效；设置页新增“本地 JSON 插件”目录管理与三个槽位的本地来源菜单；12 语言文案齐全。
  - 首版仅直装版读取本地包。沙箱运行隐藏入口并跳过目录解析。App Store 构建线未验证。
  - 样例与文档：`docs/icon-content-plugins.md`、`docs/examples/local-icon-plugin/`（manifest、data、原子替换脚本）、`docs/api/icon-presentation.md` 更新。
  - 目标过滤：`LocalIconPluginTests|IconLiveSourceCoordinatorTests|IconContentPluginRegistryTests|IconSlotBindingPersistenceTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests`，37/37 通过；后续新增 latency 42→57→过期回退→重新写入恢复用例后，`LocalIconPluginTests` 14/14。
- [x] 交付验证（构建与独立开发版完成；完整 profile 因环境权限停在测试步骤，见下）。

## 测试与构建证据

### 已通过

| 范围 | 命令（均含 `--disable-sandbox`） | 结果 |
| --- | --- | --- |
| 任务 1 | `swift test --filter 'IconLiveDemandIntegrationTests|PhaseOneCorrectnessTests|IconDependencyDemandTests|IconSlotResolverTests'` | 46/46 |
| 任务 2 | `swift test --filter 'IconSlotBindingPersistenceTests|IconConfigurationMigrationTests|IconContentPluginResolutionTests|IconSlotResolverTests|SettingsPreferenceCatalogTests|SettingsTransfer|StatusIconPreviewCardTests'` | 89/89 |
| 任务 3 | `swift test --filter 'IconLiveSourceCoordinatorTests|IconLiveDemandIntegrationTests|HardwareMonitorPanelDemandTests|IconPresentationViewModelTests|Issue30WiFiAlignmentTests'` | 44/44 |
| 任务 4 | `swift test --filter 'LocalIconPluginTests|IconLiveSourceCoordinatorTests|IconContentPluginRegistryTests|IconSlotBindingPersistenceTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests'` | 37/37 |
| 回归 | `IconAppearancePublisherTests`、`IconContentDependencyTests`、`SettingsPreferenceCatalogTests` | 全部通过 |
| 禁止模式 | `bash scripts/check-forbidden-patterns.sh` | 通过（曾因新增 `func order` 误触 `options.order`，已改名为 `isOrderedBefore`） |
| Debug 构建 | `swift build --disable-sandbox` | 通过 |
| Release 构建 | `swift build -c release --disable-sandbox` / `build-worktree.sh release no-open` | 通过（最终 93.78 s，bundle 契约与 Helper 校验通过） |
| 完整测试（脚本，最终） | `PATH=/tmp/st-shim:$PATH bash scripts/test.sh` | 1249 个测试 / 179 suites；1247 通过，仅 `TestUserDefaultsTests` 2 个环境权限失败 |
| 最终聚焦回归 | 12 个相关 suite 合并过滤 | 140/140 |
| 独立开发版 | `PATH=/tmp/st-shim:$PATH bash scripts/build-worktree.sh release no-open` | 成功：`dist/StatusTrio.app`，`com.lingsmbp.StatusTrio.dev.live-icon-data-plugins`，codename `Live Icon Data Plugins`，arm64，Ad-hoc |

### 环境限制 / 未验证

- `PATH=/tmp/st-shim:$PATH bash scripts/verify-local.sh full`：在 `Swift tests + forbidden patterns` 步骤因上述 2 个 `TestUserDefaultsTests` 环境权限失败而停止（`.build/local-verification/status.txt`：`step=Swift tests + forbidden patterns exit=1`），未进入 Release bundle、平台契约和离线发布模拟；单独 `swift build -c release` 通过。
- 已通过临时目录上的真实文件监听回归，覆盖原子替换、过期回退和恢复。菜单栏和 Dock 实机验收、macOS 13 运行、可见 UI、正式签名、公证、DMG、Universal 打包和 App Store 构建仍待验证。
- 可见 UI 测试保持默认跳过；未设置 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1`。
- `current` 分支相对 `origin/main` 的远端比较未做（禁止 Git fetch）；上层会话提交前需核对。
