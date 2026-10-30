# 双渠道发行 Phase A 验证记录

日期：2026-10-23。

## 范围与身份

| 项目 | 值 |
| --- | --- |
| branch | `codex/dual-distribution-foundation` |
| baseline | `b9b7961f7eb34ed555ca791f5769883cbf3b1b78` |
| worktree | `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio` |
| scope | Phase A A1–A4 only |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 |
| macOS SDK | 27.0 |
| implementation | worktree changes; no commit, index, push, PR, merge, or release |

## A1 基线与审计

`git fetch origin main` 后，HEAD 与 `origin/main` 都指向
`b9b7961f7eb34ed555ca791f5769883cbf3b1b78`。`git status --short --branch`
开始时只显示两份尚未跟踪的计划/设计文件；没有修改主 checkout。

`Support/Info.plist` 是 `1.7.0 (38)`，而 main 最新提交标题是
`Release v1.7.2 appcast`。本轮不修改版本，也不推断当前公开号。

基线证据：

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Identity/toolchain/dirty audit | PASS | `.build/dual-distribution-logs/a1-baseline-audit.log` |
| Targeted baseline tests | PASS 18/18 | `.build/dual-distribution-logs/a1-baseline-telemetry-singleinstance-rerun.log` |
| `swift build` | PASS, exit 0 | `.build/dual-distribution-logs/a1-baseline-swift-build.log` |

先前首个证据采集包装命令失败，原因是 zsh 的保留变量 `status`；失败发生在
包装层，不是 Swift 测试失败。只修改包装变量后重跑，未把 `status` 继续用作
shell 变量。targeted baseline 随后为 18/18。

已读取并落实到审计的限制：

- `Package.swift` 仍是 Direct 超集 DAG，无 Store target。
- `AppEnvironment.live()`、`SystemStatusStore` 默认参数与多个 singleton 仍构造
  Direct 具体实现；分配了 B2 composition-root 边界。
- Apple AirPods 私有 HAL 与 Huawei 公开 IOBluetooth SPP 已分开记录。
- `WiFiMonitor` 的 `com.apple.nat` detector 单独列为未文档化风险，没有删除
  公开 CoreWLAN 路径。
- `DockVisibilityMonitor` 使用公开 CGWindow metadata，Store 效果 NOT RUN，
  不为动画增加权限。
- 代码路径、依赖、私有调用、公开候选和外部固定 SHA 参考已写入
  `docs/distribution-architecture.md`；功能覆盖见
  `docs/distribution-feature-matrix.md`。

## A2 发行身份与可用性契约

RED 命令：

```bash
bash scripts/test.sh 'DistributionChannelTests|CapabilityAvailabilityTests'
```

退出码 1；失败原因为 `DistributionChannel` 与 `CapabilityAvailability`
尚不存在。日志：`.build/dual-distribution-logs/a2-distribution-contract-red.log`。

GREEN 结果：4 tests，0 failures；日志：
`.build/dual-distribution-logs/a2-distribution-contract-green.log`。

独立原始源 smoke：

- 默认 `DistributionChannel.swift` typecheck PASS。
- `-DSTATUS_TRIO_APP_STORE` typecheck PASS。
- 临时 harness 与原始源一起编译并实际运行，输出
  `store branch current=appStore`。
- 证据：`.build/dual-distribution-logs/a2-distribution-channel-source-harness.log`。

没有复制实现、修改 manifest、向完整 Direct package 注入 Store flag，或声称
存在 Store build。

## A3 遥测边界

`TelemetryEligibilityContext` 增加尾部默认参数 `channel: .current`；
`AppEnvironment.live()` 显式传 `.current`。Eligibility 同时要求
`channel == .direct`，所以 Store 不能靠 Direct Bundle ID、Store Bundle ID 或
production marker 取得资格。Reporter、consent/defaults 和网络 transport 未改。

结果：

| 命令 | 结果 | 证据 |
| --- | --- | --- |
| `bash scripts/test.sh 'TelemetryEligibilityTests|TelemetryConsentTests'` | PASS 14/14 | `.build/dual-distribution-logs/a3-telemetry-eligibility-consent-green.log` |
| `bash scripts/test.sh 'TelemetryReporterTests|AppEnvironmentTelemetryLifecycleTests'` | PASS 11/11 | `.build/dual-distribution-logs/a3-telemetry-reporter-lifecycle-green.log` |

本轮没有发送遥测请求、修改真实 defaults/consent、请求权限，或把 Store ID
加入 Direct allowlist。Store analytics 仍无产品实现。

## A4 最终本地验证

首次 `full` 在 Swift suite 750 tests、Helper 15 tests 和 Release build 通过后，
停在 App bundle 的 MobileBattery source fetch。该网络获取持续约 6 分钟；执行
session 被中止，退出码 130。首次日志保留在
`.build/dual-distribution-logs/a4-verify-local-full.log`，状态记为 BLOCKED on
source acquisition，不记为 Swift/build 失败。

修复依赖获取前置：主 checkout 的
`.build/mobile-battery/sources` 6 个 pinned repo 经只读 commit/clean 核对后，
复制到本 worktree 的 `.build/mobile-battery/sources`；没有复制编译 prefix。
本 worktree 原 partial 目录重命名为
`.build/mobile-battery.partial-a4-interrupted`。复制脚本第一次因目标
`sources/` 父目录未创建而失败，未写入主 checkout；补建目标目录后 6/6 成功。
证据：`.build/dual-distribution-logs/a4-mobile-battery-cache-recovery.log`。
复制后的 HEAD 全部与 `Support/mobile-battery-dependencies.json` 一致，主
checkout 缓存保持 clean。

最终命令与结果：

| 命令 | exit | 结果 | 独立日志 |
| --- | --- | --- | --- |
| `bash scripts/verify-local.sh full` | 0 | Swift 750/750；Helper 15/15；Release build、ad hoc bundle、平台/Helper/MobileBattery、native checks 与 offline release simulations 通过 | `.build/dual-distribution-logs/a4-verify-local-full-rerun.log` |
| `bash scripts/verify-local.sh docs` | 0 | Localization 19/19；Parity 7/7；ChargingEffect 1/1；MenuBarHelp 2/2；workflow policy PASS | `.build/dual-distribution-logs/a4-verify-local-docs.log` |
| `git diff --check` | 0 | 无 whitespace error | final report |
| `git diff --stat` | 0 | 见 final report | final report |

full 中的 750 tests 是 Swift Testing run；15 是 Helper XCTest suite。full 另有
既有非阻塞编译 warnings（`MemoryPressureMonitor`、`LowPowerModeClient` 和测试
`weak var`），本轮没有通过改测试或放宽断言处理它们。

`full` 不证明 Developer ID、公证、DMG、Universal package、Store sandbox、
App Store upload/review 或硬件 runtime；`docs` 也不是 full suite。

## 未验证项

- 整个 Store 硬件/沙盒矩阵：NOT RUN。
- 没有 Store app target、Store entitlements、sandbox signed bundle 或 runtime。
- 没有 App Store Connect registration/upload、App Review、release、DMG、tag。
- 没有 Developer ID/公证或 Universal package 的本轮新证据。
- 没有 macOS 13 Ventura 真机 runtime。
- 没有 TCC allow/deny/revoke、TCC 数据库改动或真实权限提示。
- 没有硬件、sleep/wake、设备移除、Wi-Fi/蓝牙/DDC/CoreAudio 真机回归。
- 没有两渠道同装、不同 defaults/container、并发锁或启动项实测。
- 没有 Menu Bar/Dock 实机视觉回归；本轮未启动生产 App。
