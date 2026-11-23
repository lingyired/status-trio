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

### 本轮结果

- `swift build`（库）通过。
- `swift build --build-tests`：进行中（记录结果）。
- 待办：`scripts/test.sh` 全量、`verify-local.sh full`、`verify-local.sh docs`。

## 已记录的外部/环境限制（后续 NOT RUN/BLOCKED）

- 多版本真机（macOS 15/26/27；最低 13）运行时验证：本机无法覆盖 → NOT RUN。
- App Store Connect `com.lingai.StatusTrio` 注册状态：需人工在 ASC 实查 → NOT RUN。
- App Review 审核意见：外部流程 → NOT RUN。
- Developer ID 签名/公证/DMG/发布：按用户规则不在本机执行 → NOT RUN。
