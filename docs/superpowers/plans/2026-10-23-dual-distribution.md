# Status Trio Dual Distribution Implementation Plan

> **For agentic workers:** Use `executing-plans` to execute the assigned phase task by task. The user selected DeepSeek as implementer; do not spawn nested implementers or change its model.

**Goal:** 保留 GitHub Direct 全部现有能力，渐进建立可独立构建、沙盒运行且不含 Direct 私有实现的 Mac App Store 渠道。

**Architecture:** 共享模型、SwiftUI/AppKit、状态与渲染，发行入口注入不同系统实现。采用无环目标依赖图和可审计构建闭包隔离私有代码；渠道标识只表达构建身份。先交付小型 Phase A PR，再逐个接入系统边界与 Store 工程。

**Tech Stack:** Swift 6、SwiftPM、SwiftUI/AppKit、Xcode 27 / SDK >=26、macOS >=13、XCTest/Swift Testing、shell contracts、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-10-23-dual-distribution-design.md`。

## Global Constraints

- 原始需求材料：`/Users/lingsmbp/Downloads/STATUS_TRIO_DUAL_DISTRIBUTION_PLAN.md`，已完整读取；以用户要求及本仓库规则为授权边界。
- 工作分支：`codex/dual-distribution-foundation`；基线 `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`；执行前重新 fetch 比较。
- worktree：`/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`。
- 实现模型固定 `auto/deepseek-v4.1-flash`，reasoning `max`；重试保留同一设置。
- 用户后续明确授权本轮完成 A–F 全部开发；按阶段连续实施，不在 A 完成后等待再次批准。
- 父代理拥有最终集成、review、提交、分支 push、PR 创建；实现代理不操作 index、commit、push 或 PR。
- 不自动 merge、不修改生产 Secrets、不触发正式 release、不建 tag/DMG、不上传 ASC、不提交审核。
- Direct Bundle ID `com.lingsmbp.StatusTrio` 不变；Store 候选 ID `com.lingsmbp.StatusTrio.AppStore` 未注册核验。
- macOS >=13；SDK >=26；正式 release runner `xcode-27`；保留 Swift 6 并发约束。
- Store 编译的共享 Core 不依赖 Sparkle、DDCPrivateAPI 或 DirectPlatform；
  Direct 保留原 SwiftPM 聚合模块。两个独立目标通过显式 source membership 选择
  adapter/composition，不为访问控制扩大 internal 类型的 public 面积；Store 成品
  不含私有实现、root Helper、Sparkle。该选择及成本已记录在 spec 和执行 ledger。
- 不改图标场景、动画、设备分类、轮询、现有 Direct 权限或默认遥测语义。
- 全部 Swift 测试统一走 `bash scripts/test.sh [filter]`；最终集成树执行风险对应 profile。
- 状态/DI/编译边界或 Package 变化最低 `bash scripts/verify-local.sh full`；文案另补 `docs`。
- 本轮用户已授权先重写再委派执行；无需再次要求选择模型或执行方式。

## Review Focus

1. Store 构建身份配上 Direct Bundle ID 和 production marker，遥测仍必须关闭。
2. 未定义渠道编译条件的 `swift run StatusTrio` 和开发 Bundle ID 保持 Direct 行为。
3. `notVerified`、未授权和暂时不可达保持可区分，不能误启用硬件操作。
4. 初始化默认值、singleton 和设置页可能绕过 composition root；后续迁移须覆盖所有引用。
5. 沙盒 home URL、锁、UserDefaults、TCC、Launch at Login 需要分别证明隔离，两个锁名不同不是完整共存验收。

## 阶段及交付顺序

| Phase | 最小交付 | Gate | PR CI 状态 |
| --- | --- | --- | --- |
| A | 身份与可用性契约、遥测防误开、审计/矩阵、Direct 基线 | full + docs；不宣称 Store 产品存在 | 明确记录尚无 PR 双渠道 CI |
| B1 | 更新服务注入；Sparkle 调用移出共享 UI/启动链 | 更新回退/展示回归 + full | 加入无密钥 Direct/契约 PR checks |
| B2 | DDC、私有蓝牙/HAL、root Helper、电源读取逐边界抽离 | 每片独立 full；DAG/source closure contracts | 每个新边界有禁止依赖契约 |
| C | 可复现 Store app target、沙盒产物审计、同装身份 | Store build + Direct full + fixture negative tests | 同一个 PR 加入真正 Store build/audit，之后不得跳过 |
| D | 公开 API 沙盒 providers、权限/真机矩阵 | 对应回归 + 沙盒手工证据 | 双渠道强制检查 |
| E | 关于页、能力 UI、i18n/隐私/商品页材料 | full + docs + 双渠道实际 UI | 双渠道强制检查 |
| F | 手动 Store archive 验证、版本与工作流收尾 | 离线 workflow fixtures + 双渠道构建 | 不新增任何自动发布 |

每片完成更新文档与验收结果。后续 PR 基于届时最新 origin/main 建立；
本轮不自动 merge；A–F 在开发分支按顺序集成，交付阶段证据与完整开发 PR。
阶段退出因证书/硬件不足时记录 BLOCKED/NOT RUN，并交付已经验证的部分。

## Phase A — 渠道基础子任务

### Task A1: 冻结基线与审计

**Files**

- Read: `Package.swift`、`Sources/StatusTrioCore/App/AppEnvironment.swift`、`AppDelegate.swift`、`UpdaterManager.swift`。
- Read: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`、`App/PrivilegedHelperManager.swift`、`Telemetry/TelemetryEligibility.swift`。
- Read: `Sources/DDCPrivateAPI/include/DDCPrivateAPI.h`、`Audio/DDCDisplayTransport.swift`、`Audio/BluetoothListeningModeHAL.swift`、`Monitoring/IOBluetoothRadioPowerBackend.swift`。
- Read: `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`、`Monitoring/MobileBatteryController.swift`、`Monitoring/SystemPowerReader.swift`、`Monitoring/SystemChargeLimitReader.swift`。
- Read: `scripts/build-app.sh`、`scripts/verify-local.sh`、`.github/workflows/*.yml`、`Support/Info.plist`。
- Create: `docs/distribution-architecture.md`、`docs/verification/2026-10-23-dual-distribution-phase-a.md`。

**Interfaces:** 本任务不改代码；产出后续边界抽取所需的入口、DAG、默认构造路径与验证清单。

- [x] 阅读 AGENTS 与本 phase 对应的 performance、macos-compatibility、release、release-validation 规则。
- [x] 执行以下只读基线检查，记录 SHA、工具链、系统与 dirty 状态：

```bash
git fetch origin main
git rev-parse HEAD origin/main
git status --short --branch
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
bash scripts/test.sh 'TelemetryEligibilityTests|TelemetryConsentTests|SingleInstanceGuardTests'
swift build
```

- [x] 文档写明 main 的版本 plist 与提交标题差异，不修改版本，不推断公开号。
- [x] 补全设计文件的代码审计；列明哪些文件只有协议、哪些带实际私有调用、哪些默认构造会回流。
- [x] 将外部参考记录成固定 SHA、实际读取文件、采用/不采用点；不要复制第三方 Team/entitlements 或私有 IORegistry 假设。

**Gate:** 基线失败必须先记录原始失败、位置与原因；不通过重跑、放宽断言或调整超时“修绿”。
与本任务无关的旧失败不能冒充本轮通过，也不扩展修复范围。

### Task A2: 最小编译身份及运行状态契约

**Files**

- Create: `Sources/StatusTrioCore/Distribution/DistributionChannel.swift`。
- Create: `Sources/StatusTrioCore/Distribution/CapabilityAvailability.swift`。
- Create: `Tests/StatusTrioCoreTests/DistributionChannelTests.swift`。
- Create: `Tests/StatusTrioCoreTests/CapabilityAvailabilityTests.swift`。

**Interfaces**

```swift
enum DistributionChannel: String, CaseIterable, Sendable {
    case direct
    case appStore

    static var current: Self {
        #if STATUS_TRIO_APP_STORE
        .appStore
        #else
        .direct
        #endif
    }

    var productionBundleIdentifier: String {
        switch self {
        case .direct: "com.lingsmbp.StatusTrio"
        case .appStore: "com.lingsmbp.StatusTrio.AppStore"
        }
    }
}

enum CapabilityAvailability: Equatable, Sendable {
    case available
    case permissionRequired
    case unsupported(reason: String)
    case temporarilyUnavailable(reason: String)
    case notVerified

    var isActionable: Bool {
        if case .available = self { true } else { false }
    }
}
```

以上为此 phase 的最小内部接口。`productionBundleIdentifier` 是发行候选元数据，
不能拿它覆盖脚本派生的开发 Bundle ID 或实际运行的 defaults/lock 身份。
若仓库发现同义状态先复用，差异写进验证记录；不增加新的 public 面积。
本 phase 不把 Availability 接入全部 UI；它是经测试的共享契约，实际 provider 接线归 B–E。

- [x] 先写失败测试，至少包含以下约束：

```swift
import XCTest
@testable import StatusTrioCore

final class DistributionChannelTests: XCTestCase {
    func testProductionIdentitiesStayDistinct() {
        XCTAssertEqual(DistributionChannel.direct.productionBundleIdentifier,
                       "com.lingsmbp.StatusTrio")
        XCTAssertEqual(DistributionChannel.appStore.productionBundleIdentifier,
                       "com.lingsmbp.StatusTrio.AppStore")
        XCTAssertNotEqual(DistributionChannel.direct.productionBundleIdentifier,
                          DistributionChannel.appStore.productionBundleIdentifier)
    }

    func testDefaultBuildRemainsDirect() {
        #if STATUS_TRIO_APP_STORE
        XCTAssertEqual(DistributionChannel.current, .appStore)
        #else
        XCTAssertEqual(DistributionChannel.current, .direct)
        #endif
    }
}

final class CapabilityAvailabilityTests: XCTestCase {
    func testOnlyAvailableCanPerformActions() {
        XCTAssertTrue(CapabilityAvailability.available.isActionable)
        let blocked: [CapabilityAvailability] = [
            .permissionRequired, .unsupported(reason: "distribution"),
            .temporarilyUnavailable(reason: "device disconnected"), .notVerified
        ]
        for state in blocked { XCTAssertFalse(state.isActionable) }
    }

    func testUnknownAndDeniedAreNotUnsupported() {
        XCTAssertNotEqual(CapabilityAvailability.notVerified,
                          .unsupported(reason: "distribution"))
        XCTAssertNotEqual(CapabilityAvailability.permissionRequired, .notVerified)
    }
}
```

- [x] `bash scripts/test.sh 'DistributionChannelTests|CapabilityAvailabilityTests'`，确认失败指向缺失类型。
- [x] 实现上述最小接口，重复同一命令，要求通过。
- [x] 用同一份源文件进行独立编译条件 smoke，不编译整个现有 Core 为 Store：

```bash
swiftc -typecheck Sources/StatusTrioCore/Distribution/DistributionChannel.swift
swiftc -DSTATUS_TRIO_APP_STORE -typecheck Sources/StatusTrioCore/Distribution/DistributionChannel.swift
```

- [x] 若验证 `.current` 的 Store 分支，生成临时 harness 与原始源一起编译运行，并断言 `.appStore`；
  不复制实现、不改 manifest、不向完整 Direct 包添加标识后宣称 Store build。

**Gate:** 默认渠道 Direct；构建条件可解析；无运行时 Bundle/环境/receipt 推测；所有能力状态无设备访问、副作用和 actor 越界。

### Task A3: 用真实调用点固定遥测边界

**Files**

- Modify: `Sources/StatusTrioCore/Telemetry/TelemetryEligibility.swift`。
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`，限 telemetry context 的构造参数。
- Modify: `Tests/StatusTrioCoreTests/TelemetryEligibilityTests.swift`。

**Interfaces:** 给现有 context 增加尾部默认参数 `channel: DistributionChannel = .current`；
保持现有构造调用的源码兼容。不重写 Reporter，不改 consent/defaults。
Swift 的 memberwise initializer 对默认 `let` 属性不能按所需方式覆盖时，写显式 initializer。

```swift
struct TelemetryEligibilityContext: Sendable {
    let bundleIdentifier: String?
    let productionMarker: Bool
    let isDebugBuild: Bool
    let channel: DistributionChannel

    init(bundleIdentifier: String?, productionMarker: Bool, isDebugBuild: Bool,
         channel: DistributionChannel = .current) {
        self.bundleIdentifier = bundleIdentifier
        self.productionMarker = productionMarker
        self.isDebugBuild = isDebugBuild
        self.channel = channel
    }
}
```

- [x] 增加测试：Store channel + Direct ID + marker + release 仍 false；
  Store channel + Store ID 同样 false；Direct 现有生产 release 保持 true；
  Direct 开发 ID / nil ID / Debug / marker false 全保持 false。
- [x] 跑 `bash scripts/test.sh 'TelemetryEligibilityTests|TelemetryConsentTests'`，观察新增测试因缺失 channel 接口或约束而失败。
- [x] 在既有 eligibility 布尔表达式添加 `context.channel == .direct`，
  由 `AppEnvironment.live()` 的 context 明确传 `channel: .current`。
- [x] 重跑同一测试，加跑
  `bash scripts/test.sh 'TelemetryReporterTests|AppEnvironmentTelemetryLifecycleTests'`。
- [x] 确认无遥测请求、真实 defaults 修改或权限请求；
  不把 Store ID 添入生产 allowlist，不因元数据存在就宣称 Store analytics 已支持。

**Gate:** 共享调用点实际消费编译身份；Direct 原有资格和用户同意链不变；
Store 无论 Bundle ID 如何都不能通过资格检查。

### Task A4: 功能矩阵与完整本地验收

**Files**

- Create: `docs/distribution-feature-matrix.md`。
- Update: `docs/distribution-architecture.md`、本 phase verification 文档及本计划 checkbox。

- [x] 矩阵逐行覆盖：菜单栏/Dock、基础电池/充电、Wi-Fi 信号/SSID/扫描/电源、
  已知网络、Bluetooth 枚举/连接/电源、BLE、HID/AirPods 电量、监听模式、
  CoreAudio/输入输出设备、DDC、powerd/SMC、低电量读/写、
  iOS helper、VPN/有线/本地 IP、输入法、快捷键、登录启动、更新、遥测、设置与锁。
- [x] 每行列 `Direct 当前路径` / `Store 编译政策` / `Store 实测` / `验收步骤`。
  此 phase 所有 Store 硬件/沙盒结果为 `NOT RUN`；
  Direct 代码路径标“现有实现”，不捏造本轮硬件 PASS。
- [x] 独立列出后续必做：allow/deny/revoke 权限、不同 OS 与硬件、休眠唤醒、
  设备移除、同装、节能与 Menu Bar/Dock 对齐。
- [x] 执行最终验证，保留命令/退出码/日志，不重复包装 Swift 测试逻辑：

```bash
bash scripts/verify-local.sh full
bash scripts/verify-local.sh docs
git diff --check
git diff --stat
```

`full` 自带 suite、Release build、非 Universal ad hoc app bundle、platform/helper、
兼容及离线发布模拟；不要把它说成 Developer ID、公证、DMG、Universal 或 UI runtime 验收。
测试日志分别另存，避免 docs profile 覆盖 full 的 `.build/local-verification` 日志。
若完整构建触发依赖下载/原有失败，保留首个失败和阶段，不添加无限重试。

- [x] 交还父代理：修改路径、测试计数与状态、首个失败、未验证项、潜在回归；
  不自行 commit/push/建 PR；父代理在 A 验收后接续 B–F。

**Phase A completion:** 必须包含上述实际 Swift 代码、通过的契约测试和如实的构建结果；
仅设计文档不能满足此阶段。若 full 失败，阶段为 PARTIAL，不得宣称通过或创建“已验证”PR。


### Phase A execution ledger

执行模型：`auto/deepseek-v4.1-flash`、`max`；worktree
`/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`。
父代理拥有 review/commit/push/PR；本轮未操作 index/HEAD，不 commit、push、merge、
发布或送审。未运行 `sdd-workspace` 脚本；按计划与任务约束直接在 worktree 执行。

- A1 Ruling: baseline targeted tests 已在前次执行中通过 18/18；当时首个包装命令
  因 zsh 保留变量 `status` 失败，修改变量名后重跑。包装失败与测试失败已分开记录，
  未使用 `status` 作为 shell 变量。成本若错：基线证据定位偏差，需重跑 targeted tests。
- A1 Ruling: 当前 worktree 开始时已有两份未跟踪文件（本计划与 design spec），
  以及 `.build` 测试缓存；保留并接续，不重写全局范围或 B–F 交付文字。成本若错：
  后续 review 需要用 baseline/final diff 区分本轮文件。
- A2 Ruling: `CapabilityAvailability` 按计划保留在共享 Core internal 面积，未接入
  UI/provider；现有 `BluetoothAvailability` 等是各子系统运行时状态，语义不同，
  强行复用会把 `notVerified` 与设备/授权状态混淆。成本若错：E 阶段需要增加映射层。
- A2 Ruling: Store 仅用原始 `DistributionChannel.swift` + Store flag harness 验证
  `.current`；不把完整 Direct Core 伪装成 Store package。成本若错：Store source
  closure 的真实编译仍留到 C/E 的 target/audit。
- A3 Ruling: Store 遥测一律通过 `channel == .direct` fail closed，显式保留用户
  consent/defaults/Reporter 路径；不把 Store Bundle ID 加入 allowlist。成本若错：
  未来启用 Store analytics 必须另写隐私、披露与同意方案。
- A1–A3 evidence:
  - baseline targeted: `.build/dual-distribution-logs/a1-baseline-telemetry-singleinstance-rerun.log`
    → PASS 18/18；`swift build` exit 0。
  - A2 RED → `.build/dual-distribution-logs/a2-distribution-contract-red.log`
    exit 1（missing types）；GREEN 4/4。
  - A2 source harness → `.build/dual-distribution-logs/a2-distribution-channel-source-harness.log`
    → `store branch current=appStore`。
  - A3 telemetry eligibility/consent → PASS 14/14；
    reporter/lifecycle → PASS 11/11。
- A4 first `full` was blocked during MobileBattery source acquisition after its
  Swift suite (750/750), Helper suite (15/15), and Release build passed. The
  owned session was interrupted with exit 130; evidence is retained.
- A4 Ruling: copied six clean, manifest-pinned source repositories from the
  existing main-checkout cache into this worktree and did not copy the compiled
  ARM64 prefix. This is a dependency-acquisition repair, not a test retry.
  Cost if wrong: release packaging still needs a clean hosted-cache check.
- A4 final `bash scripts/verify-local.sh full` → exit 0; evidence:
  `.build/dual-distribution-logs/a4-verify-local-full-rerun.log`.
- A4 final `bash scripts/verify-local.sh docs` → exit 0; evidence:
  `.build/dual-distribution-logs/a4-verify-local-docs.log`.
- A4 mobile-battery cache repair evidence:
  `.build/dual-distribution-logs/a4-mobile-battery-cache-recovery.log`.
## Phase B — 去除共享层发行依赖

按 B1 → B2a → B2b → B2c 切片，每片单独可回退；
开始每片前把其接口、文件清单和失败测试补成与 Phase A 同等细度的执行计划。
不得依据以下路线图直接一次性搬完目录。

### B1: 更新服务与最小跨模块边界

- 创建 `UpdateServicing`（MainActor）与 UI 可观察的共享更新状态；
  状态至少包含 update delivery、manual-check availability、automatic preference。
  用共享 façade/适配 publisher 供 SwiftUI 观察，避免把 `any ObservableObject` 直接塞入 `@ObservedObject`。
- `AppDelegate`、General/About、设置窗口依赖注入服务；Direct 适配器保留
  `UpdaterManager`、`UpdateFallbackUserDriver`、`UpdateSourceFallback`、
  `ManualUpdatePresentation` 的原有回退与窗口行为。
- Store 适配器呈现系统管理更新，不带“检查 GitHub 更新”、Sparkle Binding 或下载入口。
- 在 `Sources/StatusTrio/main.swift` 或专属 Direct bootstrap 组装；
  `AppDelegate()` 的既有公共入口兼容方案必须有具体测试，不能循环 import DirectPlatform。
- 新增 PR checks：`pull_request`、只读权限、无 secret、同一 merge SHA、
  Direct tests/bundle/contract；workflow policy 离线正反 fixtures 同 PR 更新。
- Gate：Core 与共享 UI 无 Sparkle import；源码与链接依赖实际脱钩；
  更新 fake 测试、镜像回退及展示回归、`verify-local.sh full` 通过。

### B2a: DDC 和私有音频/蓝牙

- 将 DDC 系统访问、IOBluetoothRadioPowerBackend、私有 HAL/订阅/endpoint discovery 移至 DirectPlatform。
- 沿用 `BluetoothRadioPowerBacking`、现有 listening-mode 与音量边界；
  DDC transport 不再将 `io_service_t`/Direct target 类型泄漏至共享控制协议。
- CoreAudio 公开读写、IOBluetooth 公开设备连接、CoreBluetooth scanner 保留共享或公开 platform；
  不删除 IOBluetooth framework 来“排除私有 API”。
- `SystemStatusStore`、DDC coordinator、蓝牙 controller 的默认参数全部改为安全依赖输入或入口工厂；
  测试 fake 不依赖私有 target 的初始化副作用。
- Gate：默认 Direct 行为、DDC 读写回验、蓝牙 permission/demand/listening-mode、
  AirPods/minorType/电池回归、full；源码闭包对私有数值选择器也有 negative fixtures。

### B2b: 提权与未文档化电源访问

- 抽离 PrivilegedHelperManager、root XPC 客户端、LowPowerModeControlSynchronizer、
  SystemPowerReader、SystemChargeLimitReader；settings singleton 引用一并消除。
- 公开低电量模式读取、公开电池/充电和共享展示模型留在 Core。
- `PowerHelperProtocol` 若含 Objective-C selector/privileged 常量，Store 不依赖；
  单纯共享低电量状态另用无特权协议，而非“协议 target 就一定安全”。
- Gate：Direct lifecycle/approval/readiness、helper bundle 和 strict tests、full；
  Store fake 不注册 daemon、不执行 AppleSMC 或私有 plist 读取。

### B2c: 共享安全 composition root

- 实现 Direct/Store 的最终无环逻辑 DAG。按 spec 的同模块组装形式，
  Direct 聚合目标保留原名，Store 独立编译共享安全源和 Store adapter；
  不强制新建物理 Platform/contracts 模块，不新增无使用者的 public API。
- `AppEnvironment.live()`/`makeStore()` 不得继续默认创建 Direct 对象。
  启动/停止、取消、deinit 和按需资源所有权继续由原 owner 管理。
- Gate：`swift run StatusTrio` 开发路径保持；共享资源 `Bundle.module` 归属明确；
  Store-safe Core 可独立编译，传递依赖无 Sparkle/private/helper，full。

## Phase C — 真正 Store 工程及双渠道 CI

**预计新增文件：** `AppStore/project.yml`、共享 xcconfig/Store plist、
`Distribution/AppStore.entitlements`、`scripts/build-app-store.sh`、
`scripts/verify-app-store-bundle.sh`、对应 fixture scripts。
选择 XcodeGen 时固定版本与生成命令，提交 spec 和共享 schemes 的生成依据；
不要求维护者手动点 Xcode 才能重现。

1. Store app target 链接已拆干净的 Core + StorePlatform，入口只有一个；
   保持同一 UI/资源、最低 macOS 13、SDK floor 26、Swift 6。
2. 默认 Store 输出目录与 Direct `dist/StatusTrio.app` 不同；
   Store 构建名清晰可并存。根据实际访问选最小 entitlements 与用途描述，
   不加入未测试的 temporary exceptions、私有 mach-lookup 或沙盒逃逸 helper。
3. 版本先从 Support/Info.plist 生成配置；比对两个包 version/build/source SHA。
   不把 `GITHUB_RUN_NUMBER` 当作跨工作流统一递增保证；
   无 ASC 授权时上传递增校验标 BLOCKED。
4. 按 Foundation container-aware Application Support URL 解析锁路径，
   实测现有 home URL 行为；Direct 旧路径保持兼容。
   测试两个 bundle ID/锁并发、不同 defaults suites 与启动身份。
5. 同 PR 扩展 PR checks 为 Direct + Store 必过 job；增加 source graph、
   Mach-O audit、资源本地化/版本/entitlement 检查。

产物审计至少覆盖全部 Mach-O、Frameworks、XPCServices、Helpers、LaunchServices、
LaunchDaemons/Agents 和 symlink 逃逸；禁止静默忽略无法读取的二进制。
检查动态依赖（`otool -L`）、undefined/ObjC symbols（`nm`）、动态加载字符串、
签名 entitlements、SU 元数据、helper 文件名与 plist。
私有 HAL 数值 ABI 由源码排除清单和 linker map/source provenance 额外证明；
不能只搜 `lstm` 四个字母，也不能禁止全部 `dlopen`。
fixtures 覆盖 clean、Sparkle、私有 symbol、dlsym string、嵌套 helper、
错 entitlement、不可读文件和资源文本误报。

Gate：unsigned compile、ad hoc/development sandbox signed bundle、实际 sandbox runtime
分别报告；没有证书不伪造后两者；Store 应用真正运行后才记 Sandbox PASS。
Direct full 与 Store build/audit 同时通过；本阶段以后 PR 不允许条件跳过 Store 检查。

## Phase D — 公开实现与真机验证

沿现有协议接 Store readers：先基础电池/CoreAudio/网络，再 CoreWLAN + 定位，
再公开蓝牙枚举/连接/CoreBluetooth BLE，最后 iOS helper 实验。
不为适配 Store 改写 Direct 的设备命名、minorType、左右耳/盒和缓存语义。
共享 parser 只在不携带 Direct 副作用时复用。

每项用相同记录格式：
`source SHA | build/signing | OS | hardware | entitlements | allow/deny/revoke |
steps | observed result | PASS/FAIL/BLOCKED/NOT RUN | evidence path`。

Wi-Fi setPower、蓝牙 connect/disconnect、输入法选择、快捷键、SMAppService、
HID/AirPods 电量、VPN/IP 各自记录，不将“公开 API”直接等于“沙盒可用”。
所有 operation 必须处理 denied、unknown、device absent、sleep/wake、cancel；
无法读取时回报原因，不增加高频 polling 或让 UI 留下可点击死按钮。
无硬件项继续记录 NOT RUN；私有路径保持 compiled out。

Gate：公开功能在 Store 可独立使用的最小组合通过；
Ventura 与当前 macOS runtime 分开列；full + 双渠道 CI。

## Phase E — 产品与隐私接线

- `CapabilityAvailability` 与编译政策注入共享 UI/Actions，两者都不能漏检；
  Menu Bar/Dock 使用同一场景语义。notVerified 不伪装 available。
- About 底部增加发行说明与官方开源项目链接，文字低权重；
  Store 无付款/完整版 CTA、跨渠道下载器/安装器。
- General 不显示 Sparkle 自动更新设置；Battery 不显示无实现的 root 控制；
  仍保留可读取的公开状态与明确权限反馈。
- 更新全部现有语言、usage descriptions、隐私文档和 Store 元数据/截图需求。
  Store 遥测保持关闭；如启用另写方案和数据披露，不在此顺手打开。
- Gate：full、docs、定位/蓝牙拒绝 UI、未测设备、紧凑窗口、
  两渠道 About 与更新 UI 实际验收；官网仅交付仓库真实可改范围。

## Phase F — 发行收尾与操作手册

新增 `.github/workflows/app-store.yml`，仅 `workflow_dispatch`，
显式 source SHA/version/build、编译/archive/audit/内部 artifact；
默认不自动签名获取权限、不上传、不送审。
无凭据记录 `needs signing credentials`，保留 compile artifact，
但 unsigned archive 不作为可上传成品。

保留 Direct release.yml 不变；
如必须调整共享版本输入，单独提供 offline frozen-artifact/recovery/monotonicity
fixtures，证明 verify 没有签名 secrets、publish 无重建、tag/appcast/SHA 合同不变。
PR job 不依赖 distribution Environment 的人工审批或发布凭据。
不修改现有 GitHub branch protection；可报告建议的 required check 名称。

Gate：两渠道同 SHA 构建/版本合同、离线 CI 正反例、fresh checkout 可复现；
ASC App ID 可注册、签名、上传、审核和正式发行保持维护者后续操作。

## 每阶段报告及回退

报告必须包含：实际代码路径、tested SHA/dirty tree、命令与退出码、
Direct/Store 差异矩阵、硬件与沙盒缺口、风险及下一片。
`merged`、`built`、`released` 不混用。
回退以阶段独立 commit 的反向补丁/revert 计划描述；
未获授权不实际回退共享 main，不 destructive reset、不删除他人工作。

父代理创建阶段 PR 前复核对应 diff，fetch origin/main 比较；
main 若改变则只做语义兼容集成并复验受影响范围，不擅自更新 main。
每个 PR body 描述该阶段实际交付与验证，后续阶段使用依赖分支而非自动合并；
最终交付覆盖 A–F 的开发结果，分别列出编译、静态审计、签名与沙盒 runtime 证据。
不能将候选 identity、编译契约或 unsigned archive 当作已经完成可发布 Store 应用。
