# Status Trio 双发行 V2 — 能力模型（Capability Model）设计草案

- **日期：** 2026-11-23
- **状态：** 设计草案（DESIGN ONLY）。**未修改任何源码。** 文中 Swift 代码是类型草图，用于评审，不是可直接编译的最终实现。
- **对应计划：** 《Status Trio 双发行平台 V2 重构计划》§3.2「调整功能能力模型」、§2/§4 Provider 路由、§6 UI 集成。
- **实现基线：** 旧分支 `codex/dual-distribution-platform`（`8fbb673b`）；目标合并 `origin/main`（评估时 `89aa9d1e`）。

---

## 0. 一页纸结论

1. 现有能力模型只有 **5 态**（`available / permissionRequired / unsupported / temporarilyUnavailable / notVerified`）+ **14 个 capability ID**，且 `DistributionCapabilityPolicy` 是「渠道 → 静态记录」的单层查表。它**无法表达「由外部 Helper 提供 / Helper 未安装 / 需更新 / 缺授权」**，这正是 V2 要补的。
2. 建议把能力判定拆成**三层**，各司其职：
   - **Provider 路由层**（渠道只决定「可选哪些 Tier」）→ `Native → External Helper → Unavailable`。
   - **可用性状态层**（单一 9 态枚举，表达最终结果与原因）。
   - **呈现映射层**（状态 → 文案 key / 主操作 / 是否可点）。
3. **核心不变式：** 渠道身份**只**约束「哪些 Provider 允许被选择」，**绝不**直接等于最终可用性；`Direct` 现有 runtime gate 仍是权威，新模型只能「约束/解释」，不能「凭空点亮」。
4. 落地采用**增量、不破坏**路线：先扩枚举（旧值保留别名）→ 引入 `ResolutionContext` → 接 Helper 报告 → 最后换 UI 文案。每一步都能独立编译、独立测试。
5. 交付一张 **9 态 × 文案 × 动作** 映射表、一张 **14+ 能力 × 渠道 × Helper 状态** 解析矩阵，以及一份 **Helper 能力报告协议** 契约，作为 Phase 1–4 的直接输入。

---

## 1. 现状盘点（已核对代码）

### 1.1 现有状态枚举

`Sources/StatusTrioCore/Distribution/CapabilityAvailability.swift`：

```swift
enum CapabilityAvailability: Equatable, Sendable {
    case available
    case permissionRequired
    case unsupported(reason: String)
    case temporarilyUnavailable(reason: String)
    case notVerified
    var isActionable: Bool { if case .available = self { true } else { false } }
}
```

### 1.2 现有能力 ID 与策略

`DistributionCapabilityPolicy.swift` 定义了 14 个稳定 ID（rawValue 与 `PlatformCapabilityRecord.capability` 对齐）：

```
updates, ddc, bluetooth.apple-listening-mode, bluetooth.battery-levels,
bluetooth.radio-power, power.privileged-helper, power.private-readers,
wifi.internet-sharing, mobile-battery.helper, bluetooth.huawei-listening-mode,
bluetooth.public-readers, power.charge-to-full-now, audio.external-volume,
power.application-energy
```

策略模型：`PlatformCapabilities.direct = []`（空 → **Direct 现有 runtime gate 权威**）；`PlatformCapabilities.appStore` 给出静态 `PlatformCapabilityRecord`；`DistributionCapabilityPolicy` 把 Store 记录**覆盖合并**到 Store 契约上，`blocksControl` / `unavailableReasonKey` / `availability(of:)` 供 UI 与动作层查询。

### 1.3 现状的三个缺口

| 缺口 | 后果 |
|---|---|
| 5 态里没有「Helper 维度」 | App Store 现在只能把高级能力标成 `unsupported`／静态禁止，无法表达「装了 Enhancer 就能用」 |
| 策略是「渠道 → 静态表」单层 | 无法随 `OS 版本 / 设备 / Helper 安装与授权 / 协议版本` 动态变化 |
| `isActionable` 只认 `available` | 无法区分「可立即执行（native / helper）」与「需先安装/授权/更新（给入口）」 |

---

## 2. 目标模型总览（三层）

```
            ┌─────────────────────────────────────────────┐
            │  CapabilityResolutionContext                 │
            │  channel · osVersion · deviceProfile         │
            │  · helperStatus · runtimeProbe               │
            └───────────────┬─────────────────────────────┘
                            │  resolve(capabilityID, context)
                            ▼
   ┌────────────────────────────────────────────────────────────┐
   │ 层 A  Provider 路由：allowedTiers(id, channel)              │
   │        .native → .externalHelper → .unavailable             │
   │   渠道只决定"允许选哪些 Tier"，不决定"能不能用"            │
   └───────────────┬────────────────────────────────────────────┘
                   ▼  选定 Tier 后由该 Tier 自报真实状态
   ┌────────────────────────────────────────────────────────────┐
   │ 层 B  可用性状态：CapabilityAvailability（9 态）            │
   │   nativeAvailable / helperProvided / helperNotInstalled /   │
   │   helperUpdateRequired / helperMissingAuthorization /       │
   │   unsupported / temporarilyUnavailable / permissionDenied / │
   │   notVerified                                               │
   └───────────────┬────────────────────────────────────────────┘
                   ▼   状态 → 呈现
   ┌────────────────────────────────────────────────────────────┐
   │ 层 C  呈现映射：copyKey · primaryAction · isActionable ·    │
   │        severity（normal / info / needsAction / blocked）     │
   └────────────────────────────────────────────────────────────┘
```

**关键分离：** 层 A 是「渠道策略」，层 B 是「真实世界状态」，层 C 是「给用户看什么、能点什么」。三者不可混为一谈——这正是计划 §3.2「渠道身份只决定可选择哪些 Provider」的落地方式。

---

## 3. 类型设计（Swift 草图）

> 以下为设计草图，命名/放置位置可评审调整。目标模块：`StatusTrioCore/Distribution`。

### 3.1 层 B：可用性状态（9 态）

```swift
/// 最终可用性。9 态 = 现有 5 态 + 4 个 Helper 态。
/// 保留旧名兼容：.available == .nativeAvailable, .permissionRequired == .permissionDenied(nil)
enum CapabilityAvailability: Equatable, Sendable {
    /// 主程序进程内原生可用（含 Direct 现有 runtime gate 判定通过）。
    case nativeAvailable
    /// 由已连接、已授权、协议兼容的外部 Enhancer 提供。
    case helperProvided
    /// 该能力只能由 Enhancer 提供，但 Enhancer 未安装。
    case helperNotInstalled
    /// Enhancer 已安装，但协议/版本低于该能力要求。
    case helperUpdateRequired
    /// Enhancer 已安装且版本兼容，但缺少系统授权（TCC/entitlement）。
    case helperMissingAuthorization
    /// 当前 macOS / 硬件不支持该能力（客观不支持）。
    case unsupported(reason: String)
    /// 设备/环境暂时不可用（拔线、休眠、切设备等，稍后可恢复）。
    case temporarilyUnavailable(reason: String)
    /// 用户拒绝了系统权限（可引导去设置）。
    case permissionDenied(reason: String)
    /// 尚未验证（无证据，不得当成可用）。
    case notVerified

    /// 用户此刻能否直接触发该功能的"执行"动作。
    var isActionable: Bool {
        switch self {
        case .nativeAvailable, .helperProvided: true
        default: false
        }
    }
}
```

**为什么 payload 只放 `reason: String`：** 保持 `Equatable/Sendable` 简单，便于跨 XPC/快照；结构化细节（版本号、缺哪个授权）放在独立的 `HelperRuntimeStatus` 里，不在 availability 里复制。

### 3.2 层 A：Provider Tier 与渠道选择

```swift
enum CapabilityProviderTier: Sendable { case native, externalHelper, unavailable }

/// 能力源码归属：决定某渠道"允许"哪些 Tier。
/// 该字段来自源码审计（direct-only-sources 的新版），不是运行时猜测。
enum CapabilitySourceClass: Sendable {
    case sharedPublic      // 两渠道都编译（公开 API / 共享逻辑）
    case directPrivate     // 只在 Direct 编译（私有 API / 私有框架 / 特权）
    /// 尚未审计/未分类。**默认按最严格处理**：从 Store 构建闭包排除，
    /// 路由上等同 directPrivate，Phase 1 审计后才能提升为 sharedPublic。
    /// CI 必须在「未分类文件进入 Store 闭包」时报错（安全默认 / 最小权限）。
    case unclassified
}

/// 渠道 **只**决定允许的 Tier 顺序；不直接给最终可用性。
func allowedTiers(for id: CapabilityID,
                  channel: DistributionChannel,
                  sourceClass: CapabilitySourceClass) -> [CapabilityProviderTier] {
    switch channel {
    case .direct:
        // Direct 全量：先原生，再可选外部 Helper（不强制用户安装）。
        return [.native, .externalHelper]
    case .appStore:
        // Store：共享公开能力先原生；私有/未分类能力只能靠外部 Helper；否则不可用。
        switch sourceClass {
        case .sharedPublic:           return [.native, .externalHelper]
        case .directPrivate, .unclassified: return [.externalHelper]
        }
    }
}
```

> **Direct 兼容性保证：** Direct 的 `native` Tier 判定继续复用现有 runtime gate（`PlatformCapabilities.direct` 保持空表语义），因此**新模型在 Direct 上只做「可解释的约束层」，不改变任何既有可用性**。

### 3.3 Helper 运行时状态（供层 A/B 使用）

```swift
struct HelperRuntimeStatus: Equatable, Sendable {
    enum Installation: Equatable, Sendable {
        case notInstalled
        case installed(HelperIdentity)
    }
    enum ServiceState: Equatable, Sendable {
        case ready
        case missingAuthorization(reason: String)
        case updateRequired(installed: Int, required: Int)   // protocolVersion
        case failed(reason: String)
    }
    struct HelperIdentity: Equatable, Sendable {
        let marketingVersion: String        // 1.2.0
        let protocolVersion: Int            // 协议主版本
        let teamID: String                  // 校验与主程序期望一致
        let advertisedCapabilities: Set<CapabilityID>
        let services: [HelperService: ServiceState]
    }
    var installation: Installation
}
```

- `advertisedCapabilities` 来自 Enhancer 通过版本化协议**主动上报**的能力清单——主程序不探测、不猜测。
- 主程序只信任 **Team ID 匹配 + 白名单渠道（direct / appStore 两个 bundle id）** 的连接。
- `services` 的 `missingAuthorization` 用于区分「装了但没给系统授权」（如需要屏幕录制/辅助功能/完全磁盘访问的 service）。

### 3.4 解析上下文与结果

```swift
struct CapabilityResolutionContext: Sendable {
    let channel: DistributionChannel
    let osVersion: OperatingSystemVersion
    let deviceProfile: DeviceProfile          // Apple Silicon? 有电池? 外接屏? 等
    let helper: HelperRuntimeStatus
    // runtimeProbe 由各 Tier 注入（native 走现有 reader，helper 走报告）
}

struct CapabilityResolution: Equatable, Sendable {
    let capability: CapabilityID
    let tier: CapabilityProviderTier
    let availability: CapabilityAvailability
    // 层 C 由 availability + capability 派生，不单独存。
}
```

### 3.5 层 C：呈现映射

```swift
enum CapabilityPrimaryAction: Equatable, Sendable {
    case perform                         // 直接执行（native / helper）
    case openEnhancerInstallGuide        // 打开"安装说明"（不自动下载）
    case openEnhancerComponentCheck      // 打开"辅助组件"检查页
    case requestHelperUpdate             // 提示去更新 Enhancer
    case openSystemPrivacyPane(Pane)     // 去系统设置授权
    case retry                           // 暂时不可用，稍后重试
    case learnMoreUnsupported            // 说明系统不支持
    case none                            // 仅提示，无操作
}

enum CapabilitySeverity: Sendable { case normal, info, needsAction, blocked }

extension CapabilityResolution {
    var primaryAction: CapabilityPrimaryAction { /* 见 §4 映射表 */ }
    var copyKey: String { /* 见 §4 */ }
    var severity: CapabilitySeverity { /* 见 §4 */ }
}
```

---

## 4. 状态 → 文案 → 动作 映射表

| 状态 | 含义 | `isActionable` | severity | 主操作 | 文案 key（示意） |
|---|---|:---:|---|---|---|
| `nativeAvailable` | 原生直接可用 | ✅ | normal | `.perform` | `capability.native.available` |
| `helperProvided` | 由 Enhancer 提供，可直接用 | ✅ | normal | `.perform` | `capability.helper.ready` |
| `helperNotInstalled` | 需 Enhancer，但未安装 | ❌ | needsAction | `.openEnhancerInstallGuide` | `capability.helper.notInstalled` |
| `helperUpdateRequired` | 已装但版本旧 | ❌ | needsAction | `.requestHelperUpdate` | `capability.helper.updateRequired` |
| `helperMissingAuthorization` | 已装但缺系统授权 | ❌ | needsAction | `.openSystemPrivacyPane` | `capability.helper.missingAuth` |
| `unsupported` | 系统/硬件不支持 | ❌ | blocked | `.learnMoreUnsupported` | `capability.unsupported` |
| `temporarilyUnavailable` | 设备临时不可用 | ❌ | info | `.retry` | `capability.temporarilyUnavailable` |
| `permissionDenied` | 用户拒绝权限 | ❌ | needsAction | `.openSystemPrivacyPane` | `capability.permissionDenied` |
| `notVerified` | 未验证 | ❌ | info | `.learnMoreUnsupported` | `capability.notVerified` |

**UI 铁律（对应计划 §6）：**
- `helperNotInstalled / helperUpdateRequired / helperMissingAuthorization` **只在用户主动打开对应面板/点击控件时**显示说明入口，**不得每次打开面板弹窗**。
- `notVerified` **不得**渲染成可点击的成功态；`helperProvided` 也不得在 Helper 报告未到时提前点亮。

---

## 5. 解析算法（Native → External Helper → Unavailable）

```swift
func resolve(_ id: CapabilityID, in ctx: CapabilityResolutionContext) -> CapabilityResolution {
    // 1) 先过客观硬门槛：系统版本 / 硬件。硬不支持直接 unsupported，不再尝试 Helper。
    if let hard = platformHardGate(id, ctx.osVersion, ctx.deviceProfile) {
        return .init(capability: id, tier: .unavailable, availability: hard)
    }

    // 2) 按渠道允许的 Tier 顺序逐个尝试。
    for tier in allowedTiers(for: id, channel: ctx.channel, sourceClass: sourceClass(of: id)) {
        switch tier {
        case .native:
            // 仅 sharedPublic + 允许 native 的渠道会走到这里。
            // Direct 继续用现有 runtime gate；Store 用公开 API 运行时探测。
            if let a = nativeAvailability(id, ctx) { return .init(capability: id, tier: .native, availability: a) }
        case .externalHelper:
            if let a = helperAvailability(id, ctx.helper) { return .init(capability: id, tier: .externalHelper, availability: a) }
        case .unavailable:
            break
        }
    }

    // 3) 都不可用：根据"是否本可被 Helper 提供"给出最准确的原因。
    let fallback: CapabilityAvailability
    if sourceClass(of: id) == .directPrivate && helperCouldServe(id) {
        fallback = ctx.helper.installation == .notInstalled ? .helperNotInstalled : .notVerified
    } else {
        fallback = .unsupported(reason: "no-provider")
    }
    return .init(capability: id, tier: .unavailable, availability: fallback)
}
```

**`helperAvailability` 的判定顺序（对应 4 个 Helper 态）：**

```
helper.installation == .notInstalled
      → .helperNotInstalled
   installed:
     protocolVersion < requiredFor(id)        → .helperUpdateRequired
     !advertisedCapabilities.contains(id)     → .notVerified       （装了但没声明支持）
     service(id).state == .missingAuthorization → .helperMissingAuthorization
     service(id).state == .ready              → .helperProvided
     service(id).state == .failed             → .temporarilyUnavailable(reason)
```

**优先级说明：** 先「装没装」→ 再「版本够不够」→ 再「有没有声明支持」→ 再「有没有授权」→ 最后才是可用。这样每个原因都是用户能立即行动的单一动作。

---

## 6. 能力 × 渠道 × Helper 解析矩阵（初版）

> `sourceClass` 一列为**初版建议**，Phase 1 必须对 `origin/main` 全量新增源码重新审计后定稿（计划 §3.1）。**未审计前一律按 `.unclassified` 处理（默认从 Store 闭包排除、按 directPrivate 路由）**——即表里标 `sharedPublic` 的项也要审计确认后才敢真正共享。`helper` 列为「该能力若走外部 Helper，由哪个 Service 提供」。

| Capability ID | sourceClass | Direct 解析 | Store（无 Helper） | Store（Helper ready） | helper Service |
|---|---|---|---|---|---|
| `updates` | 按渠道注入 | native(Sparkle) | native(SystemManaged) | — | — |
| `bluetooth.battery-levels` | sharedPublic | native | native/public | native（优先） | — |
| `bluetooth.public-readers` | sharedPublic | native | native/public | native | — |
| `bluetooth.huawei-listening-mode` | sharedPublic | native | native/public | native | — |
| `bluetooth.apple-listening-mode` | directPrivate | native(private HAL) | `helperNotInstalled` | `helperProvided` | Audio/Display |
| `bluetooth.radio-power` | directPrivate | native(private) | `helperNotInstalled` | `helperProvided` | Audio/Display |
| `ddc` | directPrivate | native(DDCPrivateAPI) | `helperNotInstalled` | `helperProvided` | Audio/Display |
| `audio.external-volume` | directPrivate | native(BetterDisplay) | `helperNotInstalled` | `helperProvided` | Audio/Display |
| `power.charge-to-full-now` | directPrivate | native(PowerUI) | `helperNotInstalled` | `helperProvided` | Charge |
| `power.privileged-helper` | directPrivate | native(PowerHelper) | `helperNotInstalled` | `helperProvided` | Power |
| `power.private-readers` | directPrivate | native(SMC/powerd) | `helperNotInstalled` | `helperProvided` | Sensor |
| `power.application-energy` | sharedPublic(候选) | native(libproc) | native/public 或 `unsupported` | native | — |
| `wifi.internet-sharing` | directPrivate | native(未文档化) | `unsupported` | `unsupported`（Helper 不覆盖） | — |
| `mobile-battery.helper` | directPrivate | native(子进程) | `helperNotInstalled` 或内嵌 | `helperProvided` | Device |

### 6.1 新增的 capability ID（已定稿，供 V2 计划 §4.2 使用）

| 新 ID | sourceClass | 说明 | helper Service |
|---|---|---|---|
| `sensors.smc` | directPrivate | SMC 温度/风扇/电力 | Sensor |
| `sensors.cpu-frequency` | directPrivate | IOReport CPU 频率 | Sensor |
| `power.sleep-control` | directPrivate | 合盖不睡眠（含租约恢复） | Power |
| `power.high-power-mode` | directPrivate | 高电量模式 | Power |
| `power.low-power-mode` | directPrivate | 低电量模式（读公开、写需 Helper） | Power |
| `display.external-brightness` | directPrivate | DDC 外接屏亮度 | Audio/Display |

> **决策：`power.low-power-mode` 独立拆出**，不再挂在 `power.privileged-helper` 下。理由：读（公开功率状态）与写（切低电量模式）可用性不同，混在一个 ID 里会出现「显示可用、实际写失败」的谎报。这正是按「能力粒度对齐权限边界」的行业做法。

---

## 7. Direct 兼容与降级不变式

1. **直接渠道零退化：** `PlatformCapabilities.direct = []` 语义保留；Direct 的 `native` Tier 判定继续走既有 runtime gate。新模型对 Direct 只新增「解释性文案」，不改可用性。
2. **Helper 永不是启动前置：** 所有 `helperNotInstalled` 都是**可运行的空缺态**，主程序照常启动；只是对应控件显示安装入口。
3. **每条能力都有降级路径：** `native` 不可用 → `externalHelper` → `unavailable`，每一跳都有明确状态，不允许「静默消失」。
4. **不预设审核通过：** 即使 Helper 技术可用，`helperProvided` 也必须在文档里标注「技术可用 ≠ App Review 通过」，审核结论单列。

---

## 8. Helper 能力报告协议（契约草案）

对应计划 §4.3。这里只给与能力模型相关的契约，安全细节另出 `docs/enhancer-protocol.md`。

```swift
/// 版本化握手：客户端 → 服务端 (hello) / 服务端 → 客户端 (report)
struct HelperHello: Codable, Sendable {
    let protocolMin: Int
    let protocolMax: Int
    let clientChannel: DistributionChannel   // 只接受 direct / appStore 白名单
    let clientBundleID: String
    let clientTeamID: String                 // 服务端校验
}

struct HelperCapabilityReport: Codable, Sendable {
    let protocolVersion: Int                 // 服务端选定
    let marketingVersion: String
    let serverTeamID: String
    let capabilities: [CapabilityDescriptor]
    struct CapabilityDescriptor: Codable, Sendable {
        let id: String                       // == CapabilityID.rawValue
        let service: String                  // power / charge / sensor / audio / device
        let authorization: AuthorizationState // granted / missing(reason) / denied
        let minProtocolVersion: Int
    }
}
```

**规则：**
- 未知客户端 / 非白名单渠道 / Team ID 不符 → 拒绝并记录，不返回能力清单。
- `capabilities` 里没声明的 ID，客户端判为 `notVerified`（不是"可用"）。
- 每个写入操作**单独鉴权**；`CapabilityDescriptor` 只表示"能提供服务"，不等于"允许任意命令"。
- 协议版本只增不减；`minProtocolVersion > protocolVersion` 的项降级为 `helperUpdateRequired`。

---

## 9. 观测与生命周期

- Helper 状态是**事件驱动**：连接建立/断开、授权变化、版本变化时更新 `HelperRuntimeStatus` 并重发一次 `CapabilityResolution` 快照给 UI。
- **不轮询**：不新增后台定时探测（守住计划 §5 P2「无需求不采集」和项目「不新增轮询/后台任务」约束）。
- 所有状态快照 `Sendable`，在 MainActor 上发布；不跨队列传 IOBluetooth/CoreWLAN 对象（沿用旧 architecture 约定）。
- 主程序退出/崩溃：Helper 侧的写入（如合盖不睡眠）靠租约自恢复，与能力状态解耦。

---

## 10. 落地步骤（增量、每步可编译可测）

| 步骤 | 内容 | 破坏性 | 测试 |
|---|---|---|---|
| **S1** | 扩 `CapabilityAvailability` 为 9 态，旧值加 `@available` 别名（`available↔nativeAvailable`、`permissionRequired↔permissionDenied(nil)`） | 低（编译期兼容） | 枚举 exhaustive 单测 |
| **S2** | 引入 `CapabilitySourceClass` + `allowedTiers()`，先只对现有 14 ID 静态分类；`DistributionCapabilityPolicy` 保留旧 `availability(of:)` 但内部走新 `resolve()` | 低 | `allowedTiers` 真值表测试 |
| **S3** | 引入 `HelperRuntimeStatus`（先默认为 `.notInstalled`，不接真实 Helper） | 低 | 状态注入测试 |
| **S4** | 接 Phase 2 的 Helper 报告，填充 `HelperRuntimeStatus`；`helperAvailability()` 生效 | 中 | 协议契约 + 假 Helper 测试 |
| **S5** | 层 C：UI 改用 `primaryAction/copyKey/severity`，替换现有 `unavailableReasonKey`；加「辅助组件」统一页 | 中 | 快照/本地化回归 |
| **S6** | 删除旧别名与旧 `unavailableReasonKey` 分支 | 收尾 | 全量 |

> 每一步都应能独立合并进 `feat/dual-distribution-v2`，Phase 0 的 Direct 回归不被 S1–S3 影响。

---

## 11. 测试矩阵

- **枚举/解析纯逻辑：** `allowedTiers(channel, sourceClass)` 真值表；`resolve()` 覆盖 9 态 × 4 个 Helper 子状态全部路径。
- **优先级：** 硬门槛 > 未安装 > 需更新 > 未声明 > 缺授权 > 可用 的短路顺序。
- **Direct 零退化：** 对每个原有 14 ID，Direct 解析结果与旧 `availability(of:)` 一致（golden test）。
- **Helper 协议：** 白名单/Team ID/版本不兼容/越界能力 ID 全部拒绝。
- **本地化：** 9 态 × 每语言 copyKey 存在性回归（纳入 `verify-local.sh docs`）。
- **UI：** 「未安装不弹窗」的显式测试；`notVerified` 不可点。

---

## 12. 决策记录（已定稿，按行业惯例）

> 以下 5 项已按 Swift / Apple 平台工程通行做法定稿，作为实现依据；不再留作开放问题。

| # | 决策 | 定稿选择 | 依据（行业规则） |
|---|---|---|---|
| D1 | 枚举命名 | `.nativeAvailable`（弃用 `.available`）；`.permissionDenied(reason:)`（弃用 `.permissionRequired`） | 自描述命名：多态并存时用能区分来源/结果的词。`.permissionRequired` 语义模糊（"需要申请"还是"已被拒绝"），Apple TCC 以 `denied` 表达拒绝 |
| D2 | Helper 态 payload | 枚举只带 `reason: String`；结构细节（版本、缺授权项）放 `HelperRuntimeStatus` | 胖枚举反模式：保持 `Equatable/Sendable/XPC` 轻量，聚合状态放独立模型 |
| D3 | `power.low-power-mode` | **独立拆出** | 能力粒度对齐权限边界：读公开/写特权，混在一起会谎报可用 |
| D4 | 新增 ID 命名 | `sensors.* / display.* / power.*` 点分小写前缀 | 与既有 `bluetooth.* / power.* / wifi.*` 命名空间一致 |
| D5 | 分类默认值 | 新增 `.unclassified`，**默认最严格**（Store 排除 + 按 directPrivate 路由），审计后才可升 `sharedPublic`；CI 拦截未分类文件进入 Store 闭包 | 安全默认 / 最小权限：未验证即默认排除，符合计划「未分类不得自动进 Store 闭包」 |

**对实现的含义：**
- S2 落地时，`.unclassified` 必须能让 CI 在「未审计文件被编进 Store 闭包」时失败，而不是静默放过。
- 旧名 `.available` / `.permissionRequired` 在 S1 以 `@available(*, deprecated, renamed:)` 过渡，S6 删除。
- 新增 ID 定稿清单：`sensors.smc`、`sensors.cpu-frequency`、`power.sleep-control`、`power.high-power-mode`、`power.low-power-mode`、`display.external-brightness`。

---

*本文件为设计草案，未修改源码、未创建 worktree、未合并。分类矩阵需 Phase 1 源码审计定稿；§12 的 5 项决策已定稿。*
