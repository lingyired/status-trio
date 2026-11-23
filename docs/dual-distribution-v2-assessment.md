# Status Trio 双发行平台 V2 重构计划 — 评估报告

- **评估日期：** 2026-11-23
- **评估对象：** `Status Trio 双发行平台 V2 重构计划`（2026-11-23 版）
- **评估方式：** 只读。用 `git rev-parse` / `git merge-tree` / `git diff` / `git show` 核对当前仓库，未创建 worktree、未合并、未改任何源码。
- **注意：** 本报告是「开工前的体检」，不是对计划逐字背书。下面所有数字都来自当前仓库快照，执行时应以 `git fetch` 后的最新 `origin/main` 复核。

---

## 0. 结论先行

1. **方向可行，计划结构合理。** 「复用 1.8.0 双发行基建 → 合并最新 main → 外部独立 Enhancer + Provider 路由」在工程上自洽，旧分支确实留了一套可复用的 Distribution/Platform/AppStore 基建。
2. **Phase 0 的真实成本是 48 个内容冲突，不是「随便 merge 一下」。** 但好消息：**没有 delete/modify、没有 rename 冲突**，全部是三方内容合并，可审计、可解。冲突量集中在本地化（13 个文件）与 UI/Settings 高频改动上。
3. **最硬的三个风险都不在「合并」，在「MAS 沙盒 ↔ 外部 Enhancer」。** 跨 App 的 Mach Service 访问、独立安装的 Helper 注册/签名校验、PowerUI 私有实现移出主程序，全是技术未验证 + 审核未知。计划自己也把「签名沙盒真机连接成功」列为 Phase 2 硬门槛——**建议把这个门槛提前成整体 go/no-go 闸门**，IPC 不通就别急着做 P3 迁移。
4. **计划里有 3 处与当前代码不符，需要先校正**（能力枚举、旧 direct-only 清单、单实例/充电层的既有实现程度），否则会低估或错估工作量。
5. **建议：** Phase 0 拆成「机械合并」+「冲突分类施工单」两步；先在独立 spike 分支验证沙盒 IPC 原型；Phase 0 结束产出一份「main 功能清单 × 可用性」基线，作为后续回归依据。

---

## 1. 基线核对（事实）

| Ref | SHA | 提交时间 | 说明 |
|---|---|---|---|
| `origin/main` | `89aa9d1e` | 2026-11-23 01:09 | 最新，含 PR #373 |
| `main`（本地） | `a5a7ebb4` | 2026-11-22 16:40 | 落后 origin/main 2 个提交 |
| `codex/dual-distribution-platform` | `8fbb673b` | 2026-10-30 08:44 | 旧双发行分支 |
| `codex/dual-distribution-foundation` | `95858e07` | 2026-10-23 23:37 | 更早的基础设施分支 |
| **共同祖先（merge-base）** | `171349f8` | 2026-10-29 22:54 | 即 **v1.8.0** 发布提交 |

- **分叉规模（origin/main … 旧分支）：** main 独有 **1060** 提交，旧分支独有 **24** 提交。
- **main 自 v1.8.0 以来新增源文件（按目录）：** UI 93、Presentation 60、Monitoring 47、Models 18、Resources 14、Audio 11、App 9、Settings 6、Display 6、VPN 2，另有 AirPods helper / PowerHelperProtocol 新命令 / AirPodsAudioContext（C 源码）等。
- **旧分支 24 提交内容：** 主要是 `Distribution/`（3 文件）、`Platform/Direct*` 与 Provider 协议（约 22 文件）、`AppStore/` 工程与审计夹具、`Distribution/AppStore.entitlements`、`scripts/build-app-store.sh` 等 16 个 store 脚本、约 18 个新测试文件，以及 6 份 distribution 文档。

**结论：** 旧分支是「薄基建 + 大量文档/审计脚本」，main 是「大量新功能」。二者重叠的共享文件才会冲突——下面第 3 节量化。

---

## 2. 计划事实核对（对照当前代码）

| # | 计划中的说法 | 代码真相（已核对） | 处理建议 |
|---|---|---|---|
| 2.1 | 能力模型原本是 `available / unsupported / notVerified`（3 态），需扩展 | 实际 `CapabilityAvailability` 已有 **5 态**：`available`、`permissionRequired`、`unsupported(reason:)`、`temporarilyUnavailable(reason:)`、`notVerified` | 计划需修订。目标 9 态实际只需**新增** 4 个 Helper 相关态：`helperProvided` / `helperNotInstalled` / `helperUpdateRequired` / `helperMissingAuthorization`，并给出每个态的 UI 文案与 `isActionable` 语义 |
| 2.2 | GitHub ID `com.lingsmbp.StatusTrio`；Store ID `com.lingai.StatusTrio`，需核实 ASC 注册 | `DistributionChannel.swift` 中两者与计划一致 ✅；但 **ASC 注册状态无法离线核实** | 列为外部待办：需在 App Store Connect 实查 `com.lingai.StatusTrio` 是否已注册 |
| 2.3 | 复用 `DistributionChannel`、`DistributionCapabilityPolicy`、`PlatformCapabilities`、`StoreAppEnvironment`、`direct-only-sources.txt`、`build-app-store.sh` 等 | 全部存在 ✅：`Sources/StatusTrioCore/Distribution/`、`Sources/StatusTrioCore/Platform/`、`AppStore/Platform/StoreAppEnvironment.swift`、`AppStore/direct-only-sources.txt`（31 行）、`scripts/build-app-store.sh` + 16 个 store 审计/contract 脚本 | 可直接复用，但清单需重审（见 2.4） |
| 2.4 | 旧 `direct-only-sources.txt` 不得沿用，需重审全部新增源码 | 该清单只覆盖 1.8.0 时代文件；main 新增 **47 个 Monitoring、11 个 Audio、6 个 Display** 等新文件均**未纳入** | 计划判断正确。Phase 1 必须对 main 全量新增源码重新分类，且「未分类文件默认不进 Store 闭包」的机制要真正生效 |
| 2.5 | `AppEnvironment / SystemStatusStore` 以最新 main 为准重新接入 | `AppEnvironment.swift` 是冲突热点（main 侧 39 提交）；但 **`SystemStatusStore.swift` 根本不在冲突列表**——单侧变更，无需三方协调 | 工作量比计划假设更小；重点只在 `AppEnvironment` |
| 2.6 | 直接复用最新 main 的 `BatteryChargeControlling` / `PowerUIChargeController` / `ChargeToFullNowController` / `ChargeToFullNowSession` | main 的充电逻辑集中在 `BatteryChargeControlling.swift`（**214 行**，含 PowerUI）；旧分支把它拆成 `BatteryChargeControlling.swift`（**77 行**抽象）+ 独立 `PowerUIChargeController.swift` | **P1 的重点手术点**：先吃下 main 214 行逻辑，再把 PowerUI Bridge 抽成 Provider。不要拿旧分支的 77 行抽象覆盖 main |
| 2.7 | 两版本单实例锁、设置、容器需隔离 | `SingleInstanceGuard` 旧分支已按 `channel + bundleIdentifier` 分锁（per-channel lock 文件）✅ | §3.3 单实例隔离已部分具备，需再验证「登录项 / Helper 注册键 / TCC」的隔离 |
| 2.8 | Phase 0 验收跑 `scripts/verify-local.sh full|docs` | 两侧都有 `scripts/verify-local.sh` ✅ | 验收命令可用 |
| 2.9 | 旧分支有 `AppStore/AppEnvironment` 等，但计划未提旧分发文档 | 旧分支已有 6 份文档：`app-store-product.md`、`distribution-architecture.md`、`distribution-feature-matrix.md`、`distribution-ci.md`、`distribution-operations.md`、`distribution-privacy.md` | 建议 Phase 0/1 先读这些旧文档，在 main 基础上**更新**而非重写 |

---

## 3. 冲突热点与工作量分布

**冲突预演方式：** `git merge-tree --write-tree --name-only origin/main codex/dual-distribution-platform`（不改工作区）。结果：**48 个内容冲突文件**；已逐一确认 **48 个在两侧都存在**（无 delete/modify、无 rename）。

按性质分四类：

| 类别 | 文件数 | 典型文件 | 处理方式 |
|---|---:|---|---|
| 甲 · 本地化 | 13 | 12 个 `Localizable.strings`（各约 240 次 main 提交）+ `LocalizationKey.swift`（207） | **机械可脚本化**：以 main 为准，补回旧分支新增键；冲突最大但风险最低 |
| 乙 · 生命周期/DI/UI | 12 | `AppEnvironment`(39)、`SettingsStore`(117)、`StatusPanelViewModel`(75)、`StatusPanelActions`(12)、`SettingsView`(28)、`BatterySectionView`(35) 等 | **人工**：按 main 业务逻辑，重新注入 Provider 依赖 |
| 丙 · 功能语义 | 11 | `Battery/BatteryChargeControlling`、`Monitoring/*Reader`、`SystemPowerReader`(10)、`LowPowerModeClient`、`UpdaterManager` 等 | **人工**：按 main 语义，重划 Provider 边界 |
| 丁 · 其它 | 12 | `AppDelegate`(5)、`PanelPresentationMapper`(29)、`StatusPopoverView`(66)、若干 `UI/*View` | 人工，多为 UI 调整 |

**解读：**
- 冲突主要由 **main 的 UI / 本地化 / Settings 高频演进**造成，而不是旧分支的基建本身（基建文件如 `DistributionCapabilityPolicy.swift`、`PlatformCapabilities.swift` 根本不冲突）。
- 真正需要「读懂再改」的只有乙、丙两类约 23 个文件，且核心就 `AppEnvironment` 一个枢纽。
- `StatusPopoverView`(66 次) 与 `PanelPresentationMapper`(29) 说明面板层在 main 里改了很多，Phase 4「界面保持一致」要格外小心别把 main 的新面板做丢。

> 完整 48 行清单见附录 A。

---

## 4. 架构风险评估（按阶段）

| ID | 风险 | 影响 | 当前状态 | 验证门槛 |
|---|---|---|---|---|
| **R1** | MAS 沙盒主程序能否连接**独立安装**的 Enhancer（跨 App Mach Service / XPC） | 阻断 P0–P3 全部 Helper 能力；审核未知 | **未验证，无代码** | Phase 2 最小沙盒 IPC 原型，真机签名连接成功；单独记录所需 entitlement 与审核意见 |
| **R2** | 独立 Enhancer 的注册/授权/卸载（`SMAppService`/`SMJobBless`、Team ID + Bundle ID 校验、双渠道白名单） | 高 | 旧分支有 `PrivilegedHelperManager` 与 contract 脚本，但不是「独立安装」形态 | 安装器 + 卸载校验 + 拒绝未知客户端的契约测试 |
| **R3** | PowerUI 私有实现移出主程序，由普通用户进程调用；沙盒主程序经 Helper 间接使用 | 高 | main 有 `test-powerui-charge-restore.sh` 可复用为契约基线 | 开启/取消/恢复充电上限均有真实读回 |
| **R4** | Sensor 受限采集在签名沙盒内的合法性 + 按需调度 | 中 | main 已有 `HardwareBackgroundDemandController` / `HardwareMetricDemandResolver` | 无消费者时停止采集可观测；沙盒内公开/受限读集合规 |
| **R5** | 双渠道并存：设置/容器/登录项/更新/TCC/Helper 注册互不影响 | 中 | bundle id 不同天然分容器；`SingleInstanceGuard` 已分锁 | 同时安装两版，设置/登录项/更新通道互不覆盖；Helper 注册无冲突 |
| **R6** | 重构破坏 Candidate 发布复用体系（build/publish candidate） | 中 | main 的 `build-candidate`/`publish-candidate` + 多个 bundle contract 脚本 | 保留发布契约测试，Publish 阶段零重建 |
| **R7** | 合并把 main 新功能做丢 / 旧控制器覆盖新业务 | 中高 | 48 冲突 | 逐文件按计划 §2.2 决策表处理，**禁止全局 `-X ours/-X theirs`** |

**总体判断：** R1 是唯一的「一票否决级」不确定项。计划 §10 的停止条件「若沙盒主程序无法以可接受方式连接 Enhancer，就保持 App Store 基础版可用」是正确兜底，但**应把它前移为整个项目的 go/no-go 闸门**，而不是等做完 P3 才发现。

---

## 5. 计划本身的缺口 / 建议补强

1. **能力枚举先定稿再做迁移。** 建议先产出一张 9 态映射表：状态 × `isActionable` × UI 文案 key × 由哪个 Tier（Native/Helper/Unavailable）产生。
2. **缺「合并后功能基线」。** Phase 0 结束时先产出「main 全功能清单 × 当前可用性」基线文档，后续每个 Phase 都对照它防回归。
3. **旧 worktree 处置未写入计划。** 计划要新建 `../status-trio-dual-distribution-v2`，但本机 `~/.codex/worktrees` 下**已存在该分支的旧 worktree**；同名 branch/worktree 会冲突，开工前需先确认「复用还是清理」。
4. **Phase 顺序可优化。** P1(Charge) / P0(Power) 都依赖 Phase 2 的 IPC 原型；建议先打通 R1 原型再投入 P3，避免 IPC 不可行时白做迁移。UI 集成（Phase 4）可与 IPC 原型并行。
5. **缺审核证据模板。** 交付 §9.14 要求「独立记录 App Review 意见」，建议单列一份 `App Review 意见记录` 文档骨架。
6. **停止条件表应显式标出 go/no-go。** 把「Phase 2 签名沙盒真机连接成功」标为硬闸门。

---

## 6. 建议的下一步（均不改代码）

1. **定稿能力枚举 + Provider 路由规则**（纯设计评审）。
2. **`git fetch` 后复核 `origin/main`** 是否又前进（当前 `89aa9d1e`），再冻结 Phase 0 的合并目标 SHA。
3. **用本报告 §3 的分类做 Phase 0 施工单**：甲类脚本化、乙/丙类人工逐个过决策表。
4. **开独立 spike 分支做 R1 最小沙盒 IPC 原型**（不并入主线，仅验证可行性）。
5. **决定旧 worktree 处置**（复用 in-place 还是新建独立目录）。

---

## 附录 A：完整 48 项冲突清单（含 main 侧提交数）

| # | 文件 | main 提交数 | 类别 |
|---:|---|---:|---|
| 1 | `App/AppDelegate.swift` | 5 | 丁-其它 |
| 2 | `App/AppEnvironment.swift` | 39 | 乙-生命周期/DI/UI |
| 3 | `App/LowPowerModeControlSynchronizer.swift` | 2 | 丙-功能语义 |
| 4 | `App/UpdaterManager.swift` | 5 | 丙-功能语义 |
| 5 | `Audio/CoreAudioBluetoothDeviceMapper.swift` | 1 | 丙-功能语义 |
| 6 | `Battery/BatteryChargeControlling.swift` | 2 | 丙-功能语义 |
| 7 | `Localization/LocalizationKey.swift` | 207 | 甲-本地化 |
| 8 | `Monitoring/BatteryDetailsController.swift` | 2 | 丙-功能语义 |
| 9 | `Monitoring/BatteryDetailsReader.swift` | 15 | 丙-功能语义 |
| 10 | `Monitoring/BluetoothAccessoryBatteryReader.swift` | 2 | 丙-功能语义 |
| 11 | `Monitoring/LowPowerModeClient.swift` | 1 | 丙-功能语义 |
| 12 | `Monitoring/SystemPowerReader.swift` | 10 | 丙-功能语义 |
| 13 | `Presentation/Panel/PanelPresentationMapper.swift` | 29 | 丁-其它 |
| 14 | `Presentation/Panel/StatusPanelActions.swift` | 12 | 乙-生命周期/DI/UI |
| 15 | `Presentation/Panel/StatusPanelViewModel.swift` | 75 | 乙-生命周期/DI/UI |
| 16 | `Resources/ar.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 17 | `Resources/de.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 18 | `Resources/en.lproj/Localizable.strings` | 241 | 甲-本地化 |
| 19 | `Resources/es.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 20 | `Resources/fr.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 21 | `Resources/it.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 22 | `Resources/ja.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 23 | `Resources/ko.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 24 | `Resources/pt-BR.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 25 | `Resources/ru.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 26 | `Resources/zh-Hans.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 27 | `Resources/zh-Hant.lproj/Localizable.strings` | 240 | 甲-本地化 |
| 28 | `Settings/SettingsStore.swift` | 117 | 乙-生命周期/DI/UI |
| 29 | `UI/BluetoothStatusView.swift` | 14 | 丁-其它 |
| 30 | `UI/IconGuideOnboardingView.swift` | 1 | 丁-其它 |
| 31 | `UI/OnboardingWindowController.swift` | 2 | 丁-其它 |
| 32 | `UI/Settings/AboutSectionView.swift` | 5 | 乙-生命周期/DI/UI |
| 33 | `UI/Settings/AudioSectionView.swift` | 21 | 乙-生命周期/DI/UI |
| 34 | `UI/Settings/BatterySectionView.swift` | 35 | 乙-生命周期/DI/UI |
| 35 | `UI/Settings/BluetoothSectionView.swift` | 22 | 乙-生命周期/DI/UI |
| 36 | `UI/Settings/GeneralSectionView.swift` | 14 | 乙-生命周期/DI/UI |
| 37 | `UI/Settings/NetworkSectionView.swift` | 9 | 乙-生命周期/DI/UI |
| 38 | `UI/Settings/SettingsView.swift` | 28 | 乙-生命周期/DI/UI |
| 39 | `UI/Settings/SettingsWindowController.swift` | 5 | 丁-其它 |
| 40 | `UI/StatusPopoverView.swift` | 66 | 乙-生命周期/DI/UI |
| 41 | `Tests/.../AppEnvironmentTelemetryLifecycleTests.swift` | 7 | 丁-其它 |
| 42 | `Tests/.../LowPowerModeControlSynchronizerTests.swift` | 1 | 丙-功能语义 |
| 43 | `Tests/.../MobileBatteryHelperReaderTests.swift` | 8 | 丙-功能语义 |
| 44 | `Tests/.../PanelActionAlignmentTests.swift` | 7 | 丁-其它 |
| 45 | `Tests/.../SettingsWindowControllerTests.swift` | 7 | 丁-其它 |
| 46 | `Tests/.../SummaryActionAlignmentTestSupport.swift` | 2 | 丁-其它 |
| 47 | `scripts/test-verify-local-bundle.sh` | 6 | 丁-其它 |
| 48 | `scripts/test-verify-local.sh` | 6 | 丁-其它 |

> 本表由 `git merge-tree --write-tree --name-only origin/main codex/dual-distribution-platform` 生成，48 项均已确认两侧存在（无 delete/modify、无 rename）。`main 提交数` = `git log base..origin/main -- <file>` 的提交数，用于衡量该文件的演进热度。

---

*本报告为只读评估，未创建 worktree、未合并、未修改任何源码。执行 Phase 0 前请重新 `git fetch` 并复核 `origin/main`。*
