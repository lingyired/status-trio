# Status Trio 双发行 V2 — 实施进度与决策记录

> 本文件随 Phase 推进持续更新。只读评估见 `docs/dual-distribution-v2-assessment.md`；能力模型设计见 `docs/dual-distribution-v2-capability-model.md`。

## Phase 0 — 合并最新 main

- **工作区：** `../status-trio-dual-distribution-v2`（分支 `feat/dual-distribution-v2`），独立 worktree，未动旧分支与旧 worktree。
- **基线：** 旧分支 `codex/dual-distribution-platform` = `8fbb673b`；合并目标 `origin/main` = `89aa9d1e`；共同祖先 `171349f8`（v1.8.0）。
- **规模：** main 独有 1060 提交，旧分支独有 24 提交；48 个内容冲突（无 delete/modify、无 rename）。

### 关键判断：旧分支与 main 是「平行重构」，不是机械冲突

旧分支把 `AppEnvironment` 拆成 `extension AppEnvironment { static func live() }`（`Platform/DirectAppEnvironment.swift`）+ 一批 `Direct*` Provider 实现 + 公开读取器；main 则在同一时期把 `AppEnvironment` 演进到 885 行单体，并新增了硬件监控、AirPods、DDC 亮度、充电到满、睡眠控制等大功能。两边同名类型大量撞车（`SystemPowerSample`、`PowerUIChargeController` 等）。

### Phase 0 采取的合并策略（§2.2「以 main 为准」）

- **Direct 生产代码** `Sources/StatusTrioCore`：整体对齐 `origin/main`，**只额外保留**纯分发模型：
  - `Distribution/CapabilityAvailability.swift`
  - `Distribution/DistributionChannel.swift`
  - `Distribution/DistributionCapabilityPolicy.swift`
  - `Platform/PlatformCapabilities.swift`
- **旧分支的 Provider 抽取/公开读取器**（`Platform/Direct*`、`SystemPowerReading`、`PublicAccessoryBatteryReader`、`PublicBluetoothPairedDeviceReader`、`CoreWLANKnownNetworkProvider`、`PowerUIChargeController`(独立文件)、`VolumeFeedbackPlaying` 等）：移到 `AppStore/reference/` 保留、**不参与编译**，留待 Phase 1 基于 main 重新接线。
- **测试** `Tests/StatusTrioCoreTests`：整体对齐 `origin/main`，只保留 3 个纯分发模型单测（`CapabilityAvailabilityTests` / `DistributionCapabilityPolicyTests` / `DistributionChannelTests`）；其余依赖旧 Provider 抽取的分支测试移入 `AppStore/reference/Tests/`。
- **本地化**：把分支的 7 个分发键（`settings.distribution.*`、`settings.updates.systemManaged`、`capability.unavailableDistribution`、`capability.notVerified`）补回 `LocalizationKey` 与 12 个 `.strings`（纯分发模型自带，无冲突）。
- **脚本冲突**：`scripts/test-verify-local.sh`、`test-verify-local-bundle.sh` 取两侧测试列表并集（保留 main 的 dmg/gitee 测试 + 分支的 app-store 测试）。

> 说明：旧分支的 Store 工程（`AppStore/`）、审计脚本、分发文档均保留在树中。Store 构建在 Phase 0 **预期失败**（依赖被移出的 Provider），其失败点记录于下，作为 Phase 1 修复输入。

### 本轮结果（Phase 0 验收）

merge commit：`875419ec`（双父：`8fbb673b` 旧分支 + `89aa9d1e` origin/main）。

- ✅ `swift build`（库）通过。
- ✅ `swift build --build-tests` 通过。
- ✅ `bash scripts/test.sh`：**1278 tests / 183 suites 全部通过**。
- ✅ `bash scripts/verify-local.sh docs`：通过（含双分发 workflow 契约 114/114）。
- ✅ `bash scripts/verify-local.sh full`：**exit 0，head=875419ec**。覆盖全量 Swift 套件、Release 构建、非 Universal app bundle、平台/SDK 契约、App Store 源码闭包 89/89、bundle 契约 80/80、archive dSYM 5/5、双分发 workflow 114/114、语义策略 85/85。
- ✅ GitHub Direct 编译/测试完整恢复；最新 main 功能保留。

### Store 构建失败点（Phase 0 预期失败，作为 Phase 1 输入）

本机 `xcodegen 2.46.0` 可用（`/opt/homebrew/bin/xcodegen`），但 Store 构建会因旧 Provider 被移出而失败，具体失败点：

1. `AppStore/Platform/StoreAppEnvironment.swift` 引用已移至 `AppStore/reference/` 的类型：
   - `UnavailableMobileBatteryReader`
   - `CoreWLANKnownNetworkProvider`
   - `PublicBluetoothPairedDeviceReader`
   - `PublicAccessoryBatteryReader`
2. `AppStore/direct-only-sources.txt` 有 12 条路径在当前 `Sources/` 中已不存在（指向已移动/被 main 重命名的文件）：
   `Platform/DirectAccessoryPowerNotifyEventMonitor`、`DirectAppEnvironment`、`DirectBluetoothListeningMode{Backend,EndpointProvider,ListenerBackend}`、`DirectDDCFactory`、`DirectInternetSharingDetector`、`DirectPrivilegedPowerClient`、`DirectSettingsStore`、`DirectSubprocessReaders`、`DirectSystemIconAppearanceReader`、`Battery/PowerUIChargeController`。
3. 需按计划 §3.1 对 `origin/main` 全量新增源码重新审计并重建 `direct-only-sources.txt`（不得沿用旧清单）。

**实跑 `APP_STORE_UNSIGNED=1 bash scripts/build-app-store.sh release no-open` 的两轮真实失败点（顺序暴露）：**

- 第 1 层（已修）：manifest 列出 12 个已不存在文件 → 已从 `AppStore/direct-only-sources.txt` 剪除（安全、正确）。
- 第 2 层（未修，需人工审计）：manifest 漏标了 5 个 `import PowerHelperProtocol` 的共享文件，被源闭包检查判定不得进 Store：
  - `Monitoring/HighPowerModeClient.swift`
  - `Monitoring/HighPowerModeController.swift`
  - `Monitoring/HighPowerModeSystemReader.swift`
  - `Monitoring/LowPowerModeClient.swift`
  - `Monitoring/SleepControlController.swift`
  这 5 个是 main 新功能文件，需判断「改造成公开路径 / 归为 Direct-only / 走外部 Helper」，不能盲加排除（否则可能把私有实现放进 Store）。
- 第 3 层（预期，未到）：`AppStore/Platform/StoreAppEnvironment.swift` 依赖 4 个已移入 `AppStore/reference/` 的公开读取器（`UnavailableMobileBatteryReader`、`CoreWLANKnownNetworkProvider`、`PublicBluetoothPairedDeviceReader`、`PublicAccessoryBatteryReader`），它们又依赖一并被移出的 Platform 协议层——需在 main 基础上重建 Store 读取器层。

> 结论：Store 可编译不是「补几个文件」能解决，而是需要按 §3.1 对 main 全量新增源码逐文件分类 + 重建 Store 组合。属 Phase 1 剩余主要工程量，本轮未完成。

## Phase 1 — 能力模型（已落地部分）

依据 `docs/dual-distribution-v2-capability-model.md`，在 main 基线上实现纯分发能力层（无 UI/运行时探测耦合，可独立单测）：

- **9 态枚举** `CapabilityAvailability`：`nativeAvailable / helperProvided / helperNotInstalled / helperUpdateRequired / helperMissingAuthorization / unsupported(reason:) / temporarilyUnavailable(reason:) / permissionDenied(reason:) / notVerified`；新增 `isActionable`、`isCompositionBlocked`；旧名 `.available` / `.permissionRequired` 以 `@available(deprecated, renamed:)` 过渡（设计 D1）。
- **路由引擎** `Distribution/CapabilityRouting.swift`：
  - `CapabilityProviderTier`（native / externalHelper / unavailable）
  - `CapabilitySourceClass`（sharedPublic / directPrivate / unclassified，默认最严格，设计 D5）
  - `HelperService`（power / charge / sensor / audioDisplay / device）
  - `HelperRuntimeStatus`（安装/协议版本/上报能力/每服务授权状态）
  - `CapabilityResolutionContext`、`CapabilityCatalog`（含 `provisional` 分类）、`CapabilityResolution`（`primaryAction` / `severity`）
  - `CapabilityRouter.allowedTiers` + `resolve`：`Native → External Helper → Unavailable`，Helper 态严格按「未安装 → 版本低 → 未声明 → 缺授权 → 可用」短路。
- **能力 ID**：`DistributionCapabilityID` 增补 6 个（`sensors.smc`、`sensors.cpu-frequency`、`power.sleep-control`、`power.high-power-mode`、`power.low-power-mode`、`display.external-brightness`，设计 D3/D4）。
- **既有引用同步**：`PlatformCapabilities` 用 `.nativeAvailable`；`DistributionCapabilityPolicy` 的两个 switch 覆盖 9 态。
- **测试**：`CapabilityRoutingTests`(15) + `CapabilityAvailabilityTests`(3) + `DistributionChannelTests`(2) 全部通过；全量 `scripts/test.sh` 通过（记录于提交）。

**未完成（Phase 1 剩余 / 受规模阻塞）**：
- Provider 注入到 `AppEnvironment` 的运行时接线（原计划 S2–S4）尚未做，属 Phase 2/4 与 Store 重接线的一部分。
- 计划 Phase 1 验收「Store 可编译，源码闭包正确」**未达成**：Store 工程仍依赖被移出的旧 Provider（见上「Store 构建失败点」），需基于 main 重建 Store 组合与 `direct-only-sources.txt` 全量审计。

## 已记录的外部/环境限制（后续 NOT RUN/BLOCKED）

- 多版本真机（macOS 15/26/27；最低 13）运行时验证：本机无法覆盖 → NOT RUN。
- App Store Connect `com.lingai.StatusTrio` 注册状态：需人工在 ASC 实查 → NOT RUN。
- App Review 审核意见：外部流程 → NOT RUN。
- Developer ID 签名/公证/DMG/发布：按用户规则不在本机执行 → NOT RUN。

## 总体状态与交付（截至本次）

- **分支：** `feat/dual-distribution-v2`（worktree `../status-trio-dual-distribution-v2`）。**未合并到 main、未推送、未发布。**
- **提交序列：**
  - `875419ec` merge: origin/main → feat/dual-distribution-v2（Phase 0，双父）
  - `c1b72cb0` docs: Phase 0 验证结果与 Store 失败点
  - `7b781f5c` feat(distribution): 9 态能力模型 + Provider 路由引擎（Phase 1）
- **已完成并本地验证：**
  - Phase 0：`verify-local.sh full` exit 0、`docs` 通过、`scripts/test.sh` 全绿；GitHub Direct 完整恢复，最新 main 功能保留。
  - Phase 1（能力层）：9 态能力模型 + 路由引擎 + 单测，全量测试通过。
- **未完成 / 阻塞：**
  - Phase 1 剩余：Store 工程重建与 `direct-only-sources.txt` 全量审计 — **已产出施工单** `docs/dual-distribution-v2-store-audit.md`（8 个需协议化的共享文件 + 5 个 PowerHelperProtocol importer + Provider 抽取重构计划）。工作量较大，本轮未完成。
  - Phase 2–6：外部 Enhancer/IPC 需签名沙盒真机 + 第二 App 安装验证；多版本真机、ASC 注册、App Review、签名公证发布均超出本机可验证范围 → NOT RUN/BLOCKED。
- **按计划停止条件：** Store 基础版当前不可编译，尚未达到「保持 Store 基础版可用」的兜底前提；在 Store 重接线完成前，不建议对外宣称双发行可用。

## Store 编译剩余工作量评估（Round 9 结论）

Store 目标已成功进入 xcodebuild 编译阶段（membership + framework 分类全通过），剩余 ~612 errors / 27 个共享文件。深入 DDC / VolumeFeedback 族后确认：这些错误不是「再放回几个文件」能收敛，而是 **5 个枢纽共享文件被私有类型反向渗透**，需要协议化重构：

- `Settings/SettingsStore.swift`（引用 `SystemVolumeFeedbackPreference`(beep 私有偏好)、`SystemChargeLimitReader`、DDC 等）
- `Store/SystemStatusStore.swift`（引用 DDC、`SystemChargeLimitReader`、`PrivilegedHelperManager`、`VolumeFeedbackPlaying`、`MobileBattery*` 等）
- `App/AppDelegate.swift`（引用 `PrivilegedHelperManager`、`UpdaterManager`）
- `Monitoring/VolumeMonitor.swift`（引用 `DDCVolumeCoordinator`/`DDCVolumeTransport`/`DDCVolumeUpdate`/`BetterDisplayFramebufferReader`）
- `Monitoring/BrightnessMonitor.swift`（DDC/BetterDisplay 亮度）

加上 ~22 个 UI/消费方文件。同时私有子系统本身规模大：DDC 子系统 1217 行（`DDCDisplayTransport` 436 / `DDCVolumeCoordinator` 410 / `DDCReadProfile` 175 / `DDCTargetResolver` 154），类型（`DDCVolumeTransport`/`DDCFeatureTransport`/`DDCVolumeUpdate`/`DDCVolumeCapability`）分散在被排除文件里，需先抽协议再改消费方。

**结论**：让 App Store 目标真正编译通过，等价于把旧分支 24 提交的 Platform 分层在 main 上重做一遍（Power/Charge 已完成，剩 DDC、Sensor、外观、Wi‑Fi、Settings、Store 组合、AppDelegate 引导）。这是**多日架构工程**，不适合在单会话里高风险硬推。当前分支 Phase 0 已达硬门槛并长期保持全绿；Store 编译作为独立排期更稳妥。

外部项（多系统真机、ASC 注册、App Review、Developer ID 签名/公证/发布）按计划记为 NOT RUN。
