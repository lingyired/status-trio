# Status Trio × app-telemetry 集成计划 v2

> 基于原始 `2026-10-01-app-telemetry-integration.md` 重新整理。
>
> 本版保留既有服务端契约与字段设计，重点修正客户端生命周期、长期驻留 App 的活跃统计、遥测同意迁移、开发构建污染、Swift 6 并发边界、时间节流和测试可维护性。
>
> **执行目标：可直接交给 Codex 在 `status-trio` 仓库实施。**
>
> 计划基线：Status Trio `main` / app-telemetry 2026-10-01 状态。

---

## 0. 结论与已拍板设计

本轮只做 **匿名/假名化的安装与活跃统计**，不做行为事件埋点。

客户端最终结构：

```text
AppEnvironment (@MainActor)
        │
        ├── SettingsStore
        ├── Localization
        │
        └── TelemetryReporter (@MainActor)
                │
                │ 负责：
                │ - 生命周期 start / stop
                │ - consent / production eligibility
                │ - 6h 周期检查
                │ - wake / 开启统计时立即检查
                │ - 从 MainActor 快照当前 app 状态
                │
                ▼
          TelemetryClient (actor)
                │
                │ 负责：
                │ - install_id
                │ - success / failure cooldown
                │ - 重入保护
                │ - payload 编码
                │ - UserDefaults 状态
                │
                ▼
        TelemetryTransport
                │
                ▼
       URLSession ephemeral
                │
                ▼
https://telemetry.lingai.net/v1/ping
```

### 本版相对旧 plan 的关键调整

1. **不再只在 App 启动时发一次。**
   Status Trio 是长期驻留菜单栏 App，只在 `AppEnvironment.start()` 发一次会让 7d/30d 活跃安装退化成「最近重启过 App 的用户」。

2. 新增 `TelemetryReporter`：
   - 启动时检查一次；
   - App 常驻期间每 **6 小时**检查一次；
   - Mac 从睡眠唤醒时检查一次；
   - 用户从关闭切换为开启统计时立即检查一次；
   - 真正成功发送仍约 **每天最多一次**。

3. **不用 `Task.detached`。**
   `AppEnvironment` / `SettingsStore` / `Localization` 都在 `@MainActor`，由 `TelemetryReporter @MainActor` 快照状态，再调用 `TelemetryClient actor`。

4. **开发版绝不污染生产统计。**
   除用户开关外，再加 production eligibility：
   - 非正式 bundle id → 不发；
   - `DEBUG` → 不发；
   - 正式 release pipeline 没写入 `STTelemetryProduction=true` → 不发。

5. **install_id 延迟生成。**
   disabled / undecided / development build 不生成 `telemetry.installationId`。
   只有真正准备发送第一条 heartbeat 时才创建随机 UUID。

6. **节流从「本地自然日」改成 timestamp。**
   - `lastSuccessfulAt`
   - `lastAttemptAt`
   - success minimum interval = 20h
   - failed attempt cooldown = 6h

   Reporter 每 6h 检查，正常常驻情况下实际约 24h 成功一次，不再处理本地日 / UTC 日错位问题。

7. **升级用户与新安装分开处理 consent。**
   - **既有安装升级**：保持原来的「无 telemetry」信任边界，默认关闭；release notes + Settings 明确告知，用户可主动打开。
   - **全新安装**：onboarding 中明确说明，开关默认开启；在用户完成 onboarding / disclosure 之前不发任何请求。
   - 不增加升级用户强制弹窗。

8. `first_app_version` 在 UI / 文档里统一解释为：
   **first observed app version / 首次观测版本**，
   不能称为「首次安装版本」。

9. 语言 tag **不截断**。
   normalize 后若不满足长度 / regex，直接 omit 该 optional 字段。

10. 测试不再要求 payload 「恰好 12 个字段」。
    改为：
    - required 字段存在；
    - optional 字段存在时合法；
    - 无 unknown / forbidden 字段。

---

# 1. 目标与非目标

## 1.1 目标

需要得到：

- observed installations；
- established installations；
- 7d / 30d active installations；
- app version 分布；
- macOS major.minor 分布；
- CPU architecture 分布；
- 系统语言 `os_language`；
- 实际 UI 语言 `app_language`；
- App 图标位置 `menuBar / dock / both`；
- 服务端首次观测版本；
- GitHub Release `download_count` 与 observed installations 的粗粒度对照。

同时满足：

- 用户关闭后完全不发 telemetry 网络请求；
- 开发版 / 测试版 / worktree 不进入生产库；
- 不采集硬件唯一标识；
- 不采集 Wi-Fi / 蓝牙 / 用户账号等信息；
- 不引入第三方 analytics SDK；
- telemetry 失败不影响 Status Trio 正常启动和功能。

## 1.2 非目标

本轮不要做：

- crash reporting；
- page view；
- popup 打开次数；
- button click；
- 用户行为事件；
- feature usage funnel；
- A/B；
- remote config；
- session replay；
- performance traces；
- 设备指纹；
- 用户账号系统；
- 卸载追踪；
- IP 定位；
- Bluetooth / Wi-Fi 内容上传。

---

# 2. 服务端契约：本轮客户端视为冻结

服务端已经完成，本计划默认 **不修改 Worker schema**。

端点：

```text
POST https://telemetry.lingai.net/v1/ping
```

基础字段：

```text
schema_version
app_id
install_id
app_version
build
os_name
os_version
arch
distribution
os_language
app_language
attributes
```

其中：

```text
schema_version = 1
app_id = "status-trio"
```

`first_app_version`：

- 客户端 **不要发送**；
- 服务端首次看到 install 时自己记录；
- Dashboard / 文档中显示名称改为：
  - `First observed version`
  - `首次观测版本`

不要解释成「首次安装版本」。

原因：

- telemetry 上线前已经存在的用户第一次上报时只能看到当前版本；
- 用户长期关闭 telemetry 后再打开，同样只能看到重新开始观测时的版本。

---

# 3. 隐私与 consent 策略

## 3.1 Settings 状态

在 `SettingsStore` 新增：

```swift
static let sharesAnonymousAnalyticsDefaultsKey = "sharesAnonymousAnalytics"
static let telemetryConsentVersionDefaultsKey = "telemetryConsentVersion"

@Published var sharesAnonymousAnalytics: Bool
```

当前 consent schema：

```text
TelemetryConsent.currentVersion = 1
```

持久化：

```text
sharesAnonymousAnalytics
telemetryConsentVersion
```

不要只靠一个 Bool 判断迁移状态。

---

## 3.2 既有安装迁移

Status Trio 已经有用于识别旧安装的逻辑：

```text
SUHasLaunchedBefore
hasSeenIconGuide
hasCompletedIconGuideOnboarding
```

不要重新发明另一套 incompatible 判断。

新增 telemetry setting 时：

### 如果判断为既有安装

初始化：

```text
sharesAnonymousAnalytics = false
telemetryConsentVersion = 1
```

含义：

- 保持过去「无 telemetry」的信任边界；
- 新版本不会因为升级自动开始联网；
- Settings 中显示 telemetry 开关；
- release notes 明确说明新增匿名使用统计能力；
- 用户主动打开后才开始发送。

**不要给升级用户弹一个强制 telemetry modal。**

---

## 3.3 全新安装

全新安装进入现有 onboarding。

在 onboarding 增加一个简短 telemetry disclosure，默认 toggle 为 ON：

```text
Share anonymous usage statistics    [ ON ]

Helps improve Status Trio by sending limited installation,
version, language, and icon-placement statistics.
No device name, Wi-Fi details, Bluetooth details, account
information, or hardware identifiers are sent.
```

具体文案必须本地化。

关键行为：

```text
用户尚未完成 disclosure
    ↓
consent 未完成
    ↓
TelemetryReporter 不发送
```

用户完成 onboarding：

```text
sharesAnonymousAnalytics = 用户最终 toggle
telemetryConsentVersion = 1
```

之后才允许 Reporter 尝试 heartbeat。

即：

**UI 可以默认 ON，但 acknowledgement 之前网络仍然是 OFF。**

---

## 3.4 用户以后切换开关

### OFF → ON

立即触发：

```swift
await telemetryReporter.sendIfNeeded()
```

若没有 install ID：

```text
此刻才生成 UUID
```

### ON → OFF

立即：

- 不再启动新的 request；
- 取消 Reporter 自己尚未执行的 telemetry attempt task；
- 若 transport 支持取消当前 request，则取消；
- 不删除现有 `install_id`。

保留 install ID 的原因：

```text
用户 OFF → ON 不应该被统计成一个全新的 installation
```

关闭统计表示：

```text
停止未来上报
```

而不是：

```text
删除服务端已经形成的历史聚合统计
```

隐私文档必须明确这一点。

---

# 4. Production Eligibility：防止开发数据污染

这是本版必须增加的保护层。

## 4.1 三层条件

Telemetry 必须同时满足：

```text
1. 用户 consent 已完成且 sharesAnonymousAnalytics == true
2. build eligibility == production
3. client throttle 允许发送
```

Production eligibility 必须检查：

```text
bundle identifier == com.lingsmbp.StatusTrio
AND
STTelemetryProduction == true
AND
非 DEBUG build
```

---

## 4.2 Info.plist marker

`Support/Info.plist` 新增：

```xml
<key>STTelemetryProduction</key>
<false/>
```

源码默认必须是：

```text
false
```

这样：

- `swift run`
- 本地 `swift build`
- worktree build
- Agent build
- 用户从源码自行 build

默认都不会进入生产 telemetry。

---

## 4.3 正式 release pipeline

`build-app.sh` 支持：

```bash
TELEMETRY_PRODUCTION=1
```

当且仅当该值为 `1`：

```bash
/usr/libexec/PlistBuddy \
  -c "Set :STTelemetryProduction true" \
  "$CONTENTS/Info.plist"
```

正式发布路径明确传：

```text
TELEMETRY_PRODUCTION=1
```

普通：

```bash
bash scripts/build-app.sh release
```

不要自动变成 production telemetry build。

---

## 4.4 Eligibility 封装

新增纯逻辑：

```swift
struct TelemetryEligibilityContext: Sendable {
    let bundleIdentifier: String?
    let productionMarker: Bool
    let isDebugBuild: Bool
}

enum TelemetryEligibility {
    static func isEligible(_ context: TelemetryEligibilityContext) -> Bool
}
```

测试可以直接覆盖：

```text
正式 bundle + marker true + release → true
dev bundle → false
marker false → false
debug → false
```

不要在 unit test 里真的依赖当前测试进程 Bundle。

---

# 5. 客户端文件布局

新增：

```text
Sources/StatusTrioCore/Telemetry/
  TelemetryReporter.swift
  TelemetryClient.swift
  TelemetryTransport.swift
  TelemetryModels.swift
  TelemetryConfiguration.swift
  TelemetryEligibility.swift
  TelemetryLanguageTag.swift
```

职责：

### `TelemetryReporter.swift`

`@MainActor`

负责：

- lifecycle；
- settings subscription；
- wake notification；
- periodic check；
- production eligibility；
- consent；
- 从 `SettingsStore` / `Localization` 取得 MainActor 状态；
- 构造 `TelemetryContext`；
- 调用 client。

### `TelemetryClient.swift`

`actor`

负责：

- install ID；
- last attempt / success；
- cooldown；
- duplicate / reentrancy；
- JSON 编码；
- 调 Transport；
- 处理 HTTP 结果。

### `TelemetryTransport.swift`

定义：

```swift
protocol TelemetryTransport: Sendable {
    func send(
        request: URLRequest
    ) async throws -> HTTPURLResponse
}
```

生产实现：

```text
URLSessionTelemetryTransport
```

测试实现：

```text
RecordingTelemetryTransport
StubTelemetryTransport
```

优先使用 protocol stub。

**不要把所有网络测试都建立在 URLProtocol 全局 hook 上。**

### `TelemetryModels.swift`

包含：

```text
TelemetryHeartbeat
TelemetryContext
TelemetryAttribute
```

### `TelemetryConfiguration.swift`

包含：

```text
endpoint
appID
schemaVersion
successMinimumInterval
failureCooldown
reporterCheckInterval
requestTimeout
distribution
```

### `TelemetryEligibility.swift`

只做纯 eligibility 逻辑。

### `TelemetryLanguageTag.swift`

只做 system language normalize / validate。

---

# 6. 状态与 UserDefaults

Telemetry client 使用统一前缀：

```text
telemetry.installationId
telemetry.lastSuccessfulAt
telemetry.lastAttemptAt
```

Settings：

```text
sharesAnonymousAnalytics
telemetryConsentVersion
```

不要继续使用：

```text
telemetry.lastSuccessfulDay
```

---

## 6.1 install_id

首次真正允许发送时：

```swift
UUID().uuidString
```

要求：

- 完全随机；
- 不从硬件生成；
- 不从 MAC address 生成；
- 不从 hostname 生成；
- 不从 serial 生成；
- 不从 Apple ID 生成；
- 不从 Keychain ID 生成；
- 不从 Bluetooth address 生成；
- 不从 Wi-Fi 信息生成。

生命周期：

```text
首次成功/尝试发送前生成
    ↓
写 telemetry.installationId
    ↓
之后持续复用
```

如果请求失败：

```text
仍保留同一 ID
```

否则失败重试会制造不同 installation。

---

## 6.2 UserDefaults 测试隔离

测试必须使用独立 suite。

可以沿用项目已有：

```swift
UserDefaults(suiteName:)
```

的测试模式。

Telemetry 代码不得把：

```swift
UserDefaults.standard
```

硬编码在不可替换的全局 singleton 里。

如果 Swift 6 对 `UserDefaults` 跨 actor 产生 Sendable 问题：

优先选择：

- 将 defaults 的读取/写入封装在 client actor 创建时的内部状态适配器；
- 或通过 suite name / 小型 persistence abstraction 注入；

**不要为了绕过编译器大面积使用 `nonisolated(unsafe)` / `@unchecked Sendable`。**

---

# 7. Heartbeat 调度

## 7.1 Reporter 生命周期

`AppEnvironment` 增加：

```swift
let telemetryReporter: TelemetryReporter
```

`start()`：

```swift
func start() {
    ...
    store.start()
    telemetryReporter.start()
}
```

`stop()`：

```swift
func stop() {
    telemetryReporter.stop()
    ...
    store.stop()
}
```

确保 start / stop 对称。

---

## 7.2 不使用 `Task.detached`

禁止：

```swift
Task.detached {
    await telemetryClient.sendHeartbeatIfNeeded()
}
```

使用由 Reporter 持有的 structured task：

```swift
periodicTask = Task { [weak self] in
    ...
}
```

Reporter 本身为：

```swift
@MainActor
final class TelemetryReporter
```

读取：

```text
settings
localization
Bundle metadata
appIconPlacement
```

全部在 MainActor 完成。

生成一个纯 `Sendable`：

```swift
TelemetryContext
```

再传给：

```text
TelemetryClient actor
```

---

## 7.3 周期检查

配置：

```text
reporterCheckInterval = 6 hours
successMinimumInterval = 20 hours
failureCooldown = 6 hours
```

Reporter：

```text
start
  ↓
attempt
  ↓
sleep 6h
  ↓
attempt
  ↓
sleep 6h
  ↓
...
```

`attempt` 本身非常轻：

```text
consent
eligibility
client throttle
```

大多数时间不会产生网络请求。

为什么 success interval 用 20h：

- Reporter 6h 一个 tick；
- 正常情况下依然约 24h 发一次；
- 如果机器睡眠 / tick 漂移，不容易逐日向后漂；
- 不再依赖日历日期、时区和 DST。

---

## 7.4 Wake trigger

订阅：

```text
NSWorkspace.didWakeNotification
```

唤醒后：

```text
sendIfNeeded()
```

Client 自己判断 cooldown。

因此唤醒并不代表一定发请求。

`stop()` 必须移除 observer / subscription。

---

## 7.5 Settings trigger

订阅：

```text
settings.$sharesAnonymousAnalytics
```

只在：

```text
false → true
```

时触发一次 `sendIfNeeded()`。

不要在：

```text
appIconPlacement
language
icon settings
```

每次变化时立即上报。

这些值等待下一次 heartbeat 即可。

---

# 8. Client throttle 与请求状态

## 8.1 判断顺序

调用 client 时：

```text
1. isSending?
2. lastSuccessfulAt 是否 < 20h?
3. lastAttemptAt 是否 < 6h?
4. 获取/生成 install ID
5. 写 lastAttemptAt = now
6. 构造 request
7. 发请求
8. 2xx → 写 lastSuccessfulAt
```

注意：

`lastAttemptAt` 必须在真正发请求 **之前** 写入。

原因：

- timeout；
- crash；
- network unavailable；

都不能造成启动循环疯狂重试。

---

## 8.2 重入保护

Actor 内：

```swift
guard !isSending else { return }
isSending = true
defer { isSending = false }
```

即使：

```text
startup tick
wake notification
settings ON
periodic timer
```

同时发生，也只能有一个 request。

---

## 8.3 成功标准

只有：

```text
HTTP 200...299
```

算成功。

以下全部：

```text
400
404
429
500
timeout
DNS error
offline
cancelled
```

不写 `lastSuccessfulAt`。

失败：

```text
lastAttemptAt 已经存在
```

所以 6h 内不会继续重试。

---

# 9. URLSession

生产 Transport 使用：

```swift
URLSessionConfiguration.ephemeral
```

设置：

```text
waitsForConnectivity = false
request timeout = 2.5s
resource timeout = 2.5s 或略高
```

要求：

- 不依赖 shared cookie storage；
- 不持久化 cache；
- 不持久化 credentials；
- telemetry 失败静默；
- release build 不弹 UI；
- `DEBUG` 可输出一条非常简短的失败原因。

Telemetry 不得影响：

```text
App launch
menu bar
Dock icon
Bluetooth
Wi-Fi
audio
Sparkle updater
```

---

# 10. Payload

Wire format：

```json
{
  "schema_version": 1,
  "app_id": "status-trio",
  "install_id": "<random uuid>",
  "app_version": "1.4.0",
  "build": "17",
  "os_name": "macOS",
  "os_version": "27.0",
  "arch": "arm64",
  "distribution": "github",
  "os_language": "th",
  "app_language": "en",
  "attributes": {
    "app_icon_placement": "menuBar"
  }
}
```

---

## 10.1 Required / optional

客户端必须存在：

```text
schema_version
app_id
install_id
app_version
```

其余按照服务端 contract 为 optional。

因此测试禁止再写：

```text
payload.count == 12
```

改成验证：

```text
required keys ⊆ payload keys
payload keys ⊆ ALLOWED_CLIENT_KEYS
```

---

## 10.2 字段来源

| 字段 | 来源 |
|---|---|
| `schema_version` | 固定 `1` |
| `app_id` | 固定 `status-trio` |
| `install_id` | 随机 UUID |
| `app_version` | `CFBundleShortVersionString` |
| `build` | `CFBundleVersion` |
| `os_name` | `macOS` |
| `os_version` | `ProcessInfo` major.minor |
| `arch` | `arm64` / `x86_64` |
| `distribution` | `github` |
| `os_language` | `Locale.preferredLanguages` |
| `app_language` | `localization.resolvedLanguage.rawValue` |
| `attributes.app_icon_placement` | `settings.appIconPlacement.rawValue` |

不要使用：

```text
AppMetadata.versionDisplayString
```

因为：

```text
1.4.0 (17)
```

不能代替：

```text
app_version = 1.4.0
build = 17
```

---

# 11. distribution 的准确语义

当前：

```text
distribution = github
```

这里必须在注释 / 文档中解释成：

```text
binary artifact origin
```

而不是：

```text
user acquisition channel
```

同一 GitHub DMG 被 Homebrew Cask 转发时，App 本身无法可靠知道用户究竟：

```text
从 GitHub 页面下载
还是 brew install
```

因此：

- 当前固定 `github`；
- dashboard 不得把它展示成「GitHub 带来了多少用户」；
- 将来若 App Store 有独立二进制，再区分 `appstore`。

---

# 12. 系统语言与 App 语言

## 12.1 两个字段必须同时保留

```text
os_language
app_language
```

语义不同：

```text
os_language
= 用户系统首选语言
= 潜在受众

app_language
= Status Trio 最终实际显示语言
```

示例：

```text
th / en
```

表示：

```text
泰语系统用户正在使用英文 fallback
```

这是新增翻译的真正信号。

---

## 12.2 app_language

直接：

```swift
localization.resolvedLanguage.rawValue
```

值域：

```text
ar
de
en
es
fr
it
ja
ko
pt-BR
ru
zh-Hans
zh-Hant
```

---

## 12.3 os_language

来源：

```swift
Locale.preferredLanguages.first
```

不要用：

```text
Localization.preference
```

后者表示用户手动选择的 app language，不是 OS audience language。

---

## 12.4 normalize

逻辑：

```swift
func osLanguageTag(preferred: [String]) -> String? {
    guard let first = preferred.first else { return nil }

    if let known = AppLanguage.match(first) {
        return known.rawValue
    }

    return normalizeUnknownLanguage(first)
}
```

unknown language：

```text
1. "_" → "-"
2. primary language lowercased
3. 如果紧跟 4 字母 script，保留 Script
4. 丢地区
5. validate
```

示例：

```text
th-TH       → th
vi-VN       → vi
sr-Latn-RS  → sr-Latn
en-GB       → en       // AppLanguage.match
zh-TW       → zh-Hant  // AppLanguage.match
pt-BR       → pt-BR    // AppLanguage.match
pt-PT       → pt       // 当前 app 不支持 European Portuguese
```

---

## 12.5 不得截断

禁止：

```swift
String(tag.prefix(16))
```

因为可能产生半截 BCP-47 subtag。

正确流程：

```text
normalize
  ↓
regex validate
  ↓
length <= 16
  ↓
合法 → send
非法 → nil / omit
```

服务端：

```text
^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*
```

客户端也应有对应防御性 validator。

---

# 13. Attributes

当前只发：

```json
{
  "app_icon_placement": "menuBar"
}
```

来源：

```swift
settings.appIconPlacement.rawValue
```

当前枚举：

```text
menuBar
dock
both
```

服务端 config 也必须一致。

在：

```text
AppIconPlacement.swift
```

附近增加短注释：

```text
Telemetry contract:
app-telemetry/config/apps.json
apps.status-trio.attributes.app_icon_placement
```

---

## 13.1 Client 侧只构造允许字段

不要建立：

```text
任意 Dictionary<String, Any>
```

再交给 server 清理。

客户端应该只从编译期已知字段构造：

```swift
struct TelemetryAttributes: Codable, Sendable {
    let appIconPlacement: String
}
```

CodingKey：

```text
app_icon_placement
```

这样不会意外把：

```text
hostname
ssid
serial
ip
token
```

等键塞进 attributes，触发整包 400。

---

# 14. TelemetryReporter context snapshot

Reporter 在 MainActor 构造：

```swift
struct TelemetryContext: Sendable {
    let appVersion: String
    let build: String?
    let osName: String
    let osVersion: String?
    let architecture: String?
    let distribution: String?
    let osLanguage: String?
    let appLanguage: String?
    let appIconPlacement: String?
}
```

注意：

```text
install_id 不属于 Reporter context
```

它由 Client 自己管理。

这样可以保证：

- MainActor 数据不会逃逸；
- Client 不需要直接引用 `SettingsStore`；
- Client 不需要直接引用 `Localization`；
- Client 不需要跨 actor 访问 SwiftUI/ObservableObject。

---

# 15. AppEnvironment 集成

`AppEnvironment.live()`：

创建：

```text
TelemetryTransport
TelemetryClient
TelemetryReporter
```

并注入：

```text
settings
localization
```

`AppEnvironment` 持有 Reporter 生命周期。

不要：

```text
TelemetryClient.shared
```

不要：

```text
global singleton
```

测试应该能自己构造环境 / reporter / client。

---

# 16. Settings UI

在 General 设置加入：

```text
Usage Statistics
```

或现有语言体系对应名称。

推荐结构：

```text
Share anonymous usage statistics                     [toggle]
Help improve Status Trio by sharing limited
installation, version, language, and display
configuration statistics.

[Privacy Details…]
```

点击：

```text
Privacy Details…
```

打开：

```text
docs/privacy-telemetry.md
```

对应网页地址；如果项目没有 docs host，则打开 GitHub 对应文档。

不要在设置正文堆完整字段清单。

---

# 17. 本地化

新增至少：

```text
settings.analytics.title
settings.analytics.description
settings.analytics.privacyDetails

onboarding.analytics.title
onboarding.analytics.description
onboarding.analytics.toggle
```

根据实际 onboarding UI 可微调 key，但：

- 12 个语言全部同步；
- parity test 必须通过；
- 尽量不带 format placeholder。

当前语言：

```text
ar
de
en
es
fr
it
ja
ko
pt-BR
ru
zh-Hans
zh-Hant
```

---

# 18. 隐私文档

新增：

```text
docs/privacy-telemetry.md
```

必须说明：

## 收集

```text
random installation ID
app version
build
macOS major.minor
architecture
binary distribution
OS language
effective app language
app icon placement
```

## 不收集

```text
name
email
Apple ID
username
hostname
serial number
hardware UUID
MAC address
SSID
Wi-Fi password
Bluetooth device names
Bluetooth addresses
IP in application payload
location
files
clipboard
keystrokes
audio
```

---

## 18.1 对 install ID 的准确描述

不要简单写：

```text
完全无法关联
```

因为同一个随机 installation ID 可以跨天关联 heartbeat。

准确表述：

```text
Status Trio generates a random installation identifier.
It is not derived from your hardware, account, or network.
The telemetry service hashes the identifier before storing
the installation identity used for statistics.
```

中文同义。

术语可使用：

```text
anonymous usage statistics
```

作为 UI 名称，但完整文档必须解释：

```text
stable random installation identifier
```

避免让用户误以为每条 request 完全 unlinkable。

---

## 18.2 IP 表述

不要写：

```text
服务器永远看不到 IP
```

HTTP 基础设施必然能处理连接来源信息。

准确写：

```text
IP address is not included in the telemetry payload and is
not stored as an app-telemetry installation attribute.
```

如果未来确认 Worker / Cloudflare logging 行为，可以另行扩展。

---

## 18.3 retention 不得过度承诺

当前已知：

```text
ACTIVITY_RETENTION_DAYS = 365
```

这明确支持：

```text
activity history retention
```

但不能自动推导：

```text
所有 install_state 数据 365 天后都会删除
```

所以隐私文档发布前必须确认 server 实际 retention。

若 server 当前只有 daily activity 365 天：

文案应该明确区分：

```text
daily activity history: 365 days
installation state: <actual server policy>
```

**不要笼统写「所有 telemetry 保留 365 天」。**

如果希望统一成 365 天，那属于另一个 server task，不能由客户端文案假设。

---

# 19. README / docs 同步

必须全仓扫描：

```bash
rg -n \
  "no telemetry|no analytics|does not include telemetry|ships no telemetry|不含.*遥测|不包含.*统计" \
  README* docs
```

不要只修改：

```text
README.md
```

Status Trio 有多语言 README。

所有仍然承诺：

```text
no telemetry
```

的翻译版本都要同步。

---

## 19.1 analytics-snapshot 文档

保留 GitHub repository analytics snapshot，但改成：

```text
This document describes repository-side GitHub analytics snapshots.
It is separate from Status Trio's optional in-app usage statistics.
```

不要把两套统计混成一个系统。

---

## 19.2 known limitations

至少记录：

```text
telemetry ping can be forged
uninstall cannot be distinguished from inactivity
disabled telemetry cannot be distinguished from an inactive installation
distribution=github is artifact origin, not reliable acquisition channel
first_app_version means first observed version
```

---

# 20. Release notes

telemetry 首次发布的 release notes 必须主动写。

既有用户：

```text
Anonymous usage statistics are off by default for upgrades.
You can enable them in Settings.
```

新安装：

```text
New installations are shown a usage-statistics option during onboarding.
No telemetry is sent before that onboarding choice is completed.
```

明确：

```text
No third-party analytics SDK is included.
```

中英 release notes 都要写。

如果 `publish=true` 要求 12 个 release note locale，按现有脚本规则完成。

---

# 21. 测试设计

新增：

```text
Tests/StatusTrioCoreTests/TelemetryEligibilityTests.swift
Tests/StatusTrioCoreTests/TelemetryLanguageTagTests.swift
Tests/StatusTrioCoreTests/TelemetryClientTests.swift
Tests/StatusTrioCoreTests/TelemetryReporterTests.swift
```

并扩展：

```text
SettingsStoreTests
LocalizationParityTests
```

---

# 22. Eligibility 测试

至少：

1. production bundle + marker true + release → eligible。
2. dev bundle → false。
3. production bundle + marker false → false。
4. debug → false。
5. nil bundle id → false。

不要依赖真实测试 runner 的 bundle id。

---

# 23. Consent / Settings 测试

至少：

1. 既有安装升级：
   ```text
   sharesAnonymousAnalytics == false
   consentVersion == 1
   ```
2. fresh install onboarding 完成前：
   ```text
   Reporter 不发
   ```
3. fresh install onboarding 选择 ON：
   ```text
   consentVersion == 1
   analytics == true
   ```
4. fresh install选择 OFF：
   ```text
   analytics == false
   ```
5. settings 改值持久化。
6. 重建 `SettingsStore` 后读取一致。
7. disabled 时不会生成 `telemetry.installationId`。

---

# 24. TelemetryLanguageTag 测试

至少：

```text
th        → th
th-TH     → th
vi-VN     → vi
sr-Latn   → sr-Latn
sr-Latn-RS→ sr-Latn
zh-TW     → zh-Hant
zh-HK     → zh-Hant
zh-CN     → zh-Hans
pt-BR     → pt-BR
pt-PT     → pt
en-GB     → en
de-DE     → de
```

并测试：

```text
invalid
empty
oversized
malformed
```

必须：

```text
return nil
```

而不是截断。

---

# 25. TelemetryClientTests

使用：

```text
StubTelemetryTransport
RecordingTelemetryTransport
```

不要依赖真正网络。

至少：

### install ID

1. 第一次真正 attempt 时生成 UUID。
2. 第二次复用同一个。
3. disabled path 不生成。
4. failed request 后仍复用同一个。

### throttle

5. successful request 写 `lastSuccessfulAt`。
6. 20h 内跳过。
7. 超过 20h 可再次发。
8. request 前写 `lastAttemptAt`。
9. 失败后 6h 内跳过。
10. 6h 后可以重试。

时间必须可注入：

```swift
now: @Sendable () -> Date
```

或等价 clock abstraction。

测试不要真的 sleep 6 小时。

### HTTP

11. 2xx success。
12. 400 failure。
13. 404 failure。
14. 429 failure。
15. 500 failure。
16. network error failure。
17. timeout failure。

### concurrency

18. 并发两个 sendIfNeeded，只产生一个 transport request。

---

# 26. Payload contract 测试

不要：

```swift
XCTAssertEqual(payload.keys.count, 12)
```

改成：

```text
required keys:
schema_version
app_id
install_id
app_version
```

允许 optional：

```text
build
os_name
os_version
arch
distribution
os_language
app_language
attributes
```

断言：

```text
payload 没有任何 unknown key
payload 没有 first_app_version
payload 没有 forbidden key
attributes 只有 app_icon_placement
attributes 没有 nested object
```

---

## 26.1 Metadata

测试：

```text
os_version = major.minor
```

禁止：

```text
27.0.1
26A434
```

`arch`：

```text
arm64
x86_64
```

`app_version` / `build` 独立。

---

# 27. ReporterTests

Reporter 的网络决策测试使用 fake client / recorder。

至少：

1. `start()` 立即 attempt 一次。
2. consent false → client 不被调用。
3. eligibility false → client 不被调用。
4. consent true + eligibility true → client 被调用。
5. OFF → ON 触发一次 attempt。
6. ON → OFF 不触发。
7. wake notification 触发 attempt。
8. 多个 trigger 靠近发生时，client 最终仍只有一个真实 request。
9. `stop()` 后：
   - periodic task 取消；
   - wake 不再触发；
   - settings change 不再触发。
10. `start()` 重复调用幂等，不产生两个 scheduler。

不要依赖 6h 真时间。

将 reporter interval / sleeper 抽成可测试 dependency，或把周期循环与「是否应该 attempt」分离成纯逻辑。

---

# 28. attributes contract 测试

断言：

```swift
Set(AppIconPlacement.allCases.map(\.rawValue))
==
Set(["menuBar", "dock", "both"])
```

这是客户端与：

```text
app-telemetry/config/apps.json
```

之间的显式 contract。

未来修改 `AppIconPlacement` raw value 时，让测试明确提醒同步 server config。

---

# 29. 首次观测版本的数据解释

Dashboard / SQL / docs：

禁止：

```text
First install version
Original install version
```

使用：

```text
First observed version
```

升级行为分析只能在 telemetry 上线一段时间后作为近似 cohort 使用。

不要对 telemetry 上线前用户的历史安装版本做推断。

---

# 30. 「该加哪个翻译」查询修正

旧 plan 使用：

```sql
os_language NOT IN (
    SELECT DISTINCT app_language ...
)
```

这依赖当前数据集中是否恰好出现某个 app language，不够稳。

Status Trio 已知支持语言集合，应直接用固定支持集合判断：

```sql
SELECT os_language, COUNT(*) AS audience
FROM install_state
WHERE app_id = 'status-trio'
  AND os_language IS NOT NULL
  AND os_language NOT IN (
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt-BR',
    'ru',
    'zh-Hans',
    'zh-Hant'
  )
GROUP BY os_language
ORDER BY audience DESC;
```

这才是真正的：

```text
OS language not currently supported by Status Trio
```

另开一条 mismatch 查询：

```sql
SELECT os_language, app_language, COUNT(*) AS installs
FROM install_state
WHERE app_id = 'status-trio'
  AND os_language IS NOT NULL
  AND app_language IS NOT NULL
  AND os_language <> app_language
GROUP BY os_language, app_language
ORDER BY installs DESC;
```

注意：

```text
mismatch 不一定是 bug
```

用户可能手动改了 app language。

---

# 31. STATS_PUBLIC 不阻塞客户端发布

当前：

```text
STATS_PUBLIC = false
```

导致：

```text
/v1/apps
/v1/stats/*
dashboard
```

403。

这不应继续作为 Status Trio 客户端集成的阻塞条件。

客户端验收可以通过：

```text
remote D1
```

验证。

Cloudflare Access / public stats dashboard 归入独立 operator task。

因此：

```text
客户端可以先上线
dashboard 后补
```

---

# 32. DNS 风险

保留旧 plan 已发现的：

```text
telemetry.lingai.net
UDP resolver 某些网络下可能异常
```

要求：

- 不硬编码 Cloudflare IP；
- 不做客户端 IP fallback；
- production smoke test 必须用真实 URLSession；
- 上线后若长期零数据，优先检查 DNS；
- DNS failure 按普通 telemetry failure 静默处理；
- 不影响 Status Trio。

---

# 33. 本地验证

## 33.1 单元测试

```bash
bash scripts/test.sh
```

## 33.2 release compile

```bash
swift build -c release
```

## 33.3 验证普通本地 build 不具备 production telemetry eligibility

检查：

```text
STTelemetryProduction == false
```

## 33.4 构造 production-like 测试 bundle

只用于手工验证：

```bash
TELEMETRY_PRODUCTION=1 \
bash scripts/build-app.sh release no-open
```

不要在这一步连接生产 endpoint。

TelemetryConfiguration 在开发 smoke test 中应允许依赖注入本地 endpoint。

---

# 34. 本地 Worker smoke test

启动：

```bash
cd ~/Documents/aiwork/app-telemetry
npm run dev
```

Status Trio 测试构建使用：

```text
http://127.0.0.1:<wrangler-port>/v1/ping
```

不要靠修改生产 constant 再忘记改回来。

endpoint 必须通过：

```text
TelemetryConfiguration
```

注入。

确认本地 D1：

```sql
SELECT
    app_version,
    first_app_version,
    os_language,
    app_language,
    attributes
FROM install_state
WHERE app_id='status-trio';
```

验证：

```text
install ID 能稳定识别同一 installation
first_app_version 由 server 生成
languages 正确
attributes 正确
```

---

# 35. Release workflow 预检

按项目现有 AGENTS / CI 规则：

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=<next-version> \
  -f build=<next-build> \
  -f publish=false

gh run watch <run-id> \
  --repo lingyired/status-trio \
  --exit-status
```

另外新增检查：

```text
publish=false artifact 不应该因为 test runner / workflow 自身运行而产生 heartbeat
```

正式 artifact 中：

```text
STTelemetryProduction == true
```

---

# 36. 正式发布后验证

先清理确认无误的旧测试数据。

破坏性 D1 DELETE：

- 必须先 SELECT；
- 只删除明确识别出来的测试 installation；
- 如果真实数据已经进入库，禁止粗暴按 app version 全删。

发布后至少验证：

```sql
SELECT
    os_language,
    app_language,
    COUNT(*) AS installs
FROM install_state
WHERE app_id='status-trio'
GROUP BY 1, 2
ORDER BY installs DESC;
```

以及：

```text
app_icon_placement
app version
OS version
arch
```

---

# 37. 资源与性能要求

Telemetry 在 steady state：

```text
每 6h 一次本地轻量 check
约每天一次 ≤ 数 KB HTTPS POST
```

不得新增：

```text
高频 Timer
常驻 polling thread
新的 system_profiler
新的 Bluetooth scan
新的 location request
新的 background daemon
```

Reporter 的 periodic Task 应处于 suspend 状态，不产生 CPU busy loop。

---

# 38. 错误处理

Telemetry 任何错误：

```text
silent failure
```

Release build：

- 不 alert；
- 不 notification；
- 不 badge；
- 不 retry storm；
- 不写大量 log。

DEBUG：

允许：

```text
[Telemetry] skipped: disabled
[Telemetry] skipped: cooldown
[Telemetry] failed: timeout
```

不要 log：

```text
install_id
完整 request body
任何潜在 user/network value
```

---

# 39. 不允许做的事情

Codex 实施时明确禁止：

- 不引入 Firebase；
- 不引入 PostHog；
- 不引入 Sentry analytics；
- 不引入 Mixpanel；
- 不引入 Amplitude；
- 不引入 analytics dependency；
- 不增加 App Sandbox；
- 不增加 network entitlement；
- 不使用 Keychain 保存 install ID；
- 不从硬件生成 ID；
- 不发设备名；
- 不发 hostname；
- 不发 serial；
- 不发 SSID；
- 不发 Bluetooth device；
- 不发 IP 字段；
- 不发 location；
- 不发 `first_app_version`；
- 不升级 `schema_version`；
- 不用 `Task.detached`；
- 不加 `TelemetryClient.shared`；
- 不把 development build 指向 production telemetry；
- 不用语言字符串截断制造合法性假象；
- 不因为 telemetry error 阻塞启动。

---

# 40. 分阶段实施

## Phase 0 — Contract / migration tests

- [ ] 为 telemetry consent migration 写 failing tests。
- [ ] 为 existing install / fresh install 写测试。
- [ ] 为 production eligibility 写 failing tests。
- [ ] 确认 server contract 仍是 schema v1。

---

## Phase 1 — Eligibility + build pipeline

- [ ] 新增 `TelemetryEligibility.swift`。
- [ ] `Support/Info.plist` 新增 `STTelemetryProduction=false`。
- [ ] `scripts/build-app.sh` 支持 `TELEMETRY_PRODUCTION=1`。
- [ ] 正式 release path 设置 production marker。
- [ ] worktree / ordinary build 保持 false。
- [ ] tests green。

---

## Phase 2 — Models / language / transport

- [ ] `TelemetryConfiguration.swift`
- [ ] `TelemetryModels.swift`
- [ ] `TelemetryLanguageTag.swift`
- [ ] `TelemetryTransport.swift`
- [ ] language tests。
- [ ] eligibility tests。
- [ ] transport stub。

---

## Phase 3 — TelemetryClient

- [ ] actor。
- [ ] lazy install ID。
- [ ] `lastAttemptAt`。
- [ ] `lastSuccessfulAt`。
- [ ] 20h success throttle。
- [ ] 6h failure cooldown。
- [ ] 2xx success。
- [ ] reentrancy guard。
- [ ] payload encoding。
- [ ] client tests 全绿。

---

## Phase 4 — Settings / consent

- [ ] `sharesAnonymousAnalytics`。
- [ ] `telemetryConsentVersion`。
- [ ] existing install 默认 OFF migration。
- [ ] fresh install onboarding disclosure。
- [ ] disclosure 完成前 no request。
- [ ] Settings General toggle。
- [ ] Settings tests。
- [ ] onboarding tests。

---

## Phase 5 — TelemetryReporter

- [ ] `@MainActor TelemetryReporter`。
- [ ] startup attempt。
- [ ] 6h check loop。
- [ ] wake trigger。
- [ ] OFF → ON trigger。
- [ ] stop cleanup。
- [ ] idempotent start。
- [ ] context snapshot。
- [ ] reporter tests。

---

## Phase 6 — AppEnvironment

- [ ] `AppEnvironment.live()` 装配 transport / client / reporter。
- [ ] `start()` 启动 reporter。
- [ ] `stop()` 停止 reporter。
- [ ] 不用 global singleton。
- [ ] 不用 `Task.detached`。
- [ ] 生命周期 tests。

---

## Phase 7 — Localization / UI

- [ ] analytics Settings row。
- [ ] onboarding disclosure。
- [ ] privacy link。
- [ ] 12 locales。
- [ ] LocalizationParityTests green。

---

## Phase 8 — Documentation

- [ ] `docs/privacy-telemetry.md`。
- [ ] `docs/analytics-snapshot.md` 消歧。
- [ ] `docs/known-limitations.md`。
- [ ] 扫描并修改所有 README locale 的 no-telemetry 承诺。
- [ ] 文档使用 first observed version。
- [ ] distribution 明确 artifact origin。
- [ ] retention 文案与 server 实际行为一致。

---

## Phase 9 — Release notes

- [ ] zh-Hans。
- [ ] en。
- [ ] 若发布脚本要求则全部 12 locale。
- [ ] 明确 legacy upgrades 默认 OFF。
- [ ] 明确 new install onboarding choice。
- [ ] 明确 no third-party analytics SDK。

---

## Phase 10 — Validation

- [ ] `bash scripts/test.sh`
- [ ] `swift build -c release`
- [ ] release workflow `publish=false`
- [ ] ordinary build telemetry marker false
- [ ] official artifact telemetry marker true
- [ ] local Worker smoke
- [ ] DNS smoke
- [ ] production smoke
- [ ] D1 field inspection

---

# 41. 验收标准

全部满足才算完成：

1. 既有 Status Trio 用户升级后 **默认不发送 telemetry**。
2. 全新用户在 onboarding disclosure 完成前 **完全不发送 telemetry**。
3. 用户明确启用后，才能创建第一次 telemetry installation ID。
4. 关闭开关时不产生 telemetry HTTP request。
5. 开发 / Debug / worktree build 永远不能写生产 telemetry。
6. 正式 release artifact 明确带 `STTelemetryProduction=true`。
7. App 启动后不要求用户每天重启才能计入 7d / 30d active。
8. 长期驻留期间 Reporter 能周期检查 heartbeat。
9. 正常常驻情况下成功 heartbeat 大约每天一次。
10. 失败后 6h 内不重试。
11. concurrent triggers 只产生一个 request。
12. `install_id` 是随机 UUID，不来自硬件 / 网络 / account。
13. OFF → ON 不制造新的 installation ID。
14. payload 不发送 `first_app_version`。
15. `first_app_version` 在 UI / docs 被解释成 first observed version。
16. `os_language=th` 不会塌缩成 `en`。
17. `zh-TW → zh-Hant`。
18. `pt-BR → pt-BR`。
19. `en-GB → en`。
20. invalid language tag 被 omit，不截断。
21. attributes 只有允许的 `app_icon_placement`。
22. menuBar / dock / both 与 server config 一致。
23. payload contract 测试不依赖固定字段总数。
24. telemetry 失败对 Status Trio 功能没有用户可见影响。
25. 所有 12 个 locale parity tests 通过。
26. 所有 README / docs 不再包含已经不准确的「绝无 telemetry」承诺。
27. privacy 文档准确描述 stable random install identifier。
28. privacy 文档不错误宣称 HTTP infrastructure 看不到 IP。
29. retention 文案不把 `ACTIVITY_RETENTION_DAYS=365` 错写成所有数据统一 365 天。
30. CI release preflight 通过。

---

# 42. Codex 执行约束

执行时遵守：

1. **先写测试，再改 production code。**
2. 每一 Phase 完成后跑相关 targeted tests。
3. 不要在一个巨大 commit 中同时做：
   ```text
   telemetry core + onboarding redesign + unrelated refactor
   ```
4. 不顺手重构 Status Trio 其他模块。
5. 遇到 Swift 6 concurrency warning：
   - 优先调整 actor boundary / dependency；
   - 不使用 unsafe annotation 压掉。
6. 保持：
   ```text
   AppEnvironment = composition root
   SettingsStore / Localization = MainActor state
   TelemetryReporter = lifecycle adapter
   TelemetryClient = isolated network/state engine
   ```
7. telemetry 必须是：
   ```text
   best-effort
   non-blocking
   optional
   silent-on-failure
   ```

---

# 43. 推荐实现顺序

为了降低 Codex 一次改动过大导致回归，按以下顺序提交最稳：

```text
Commit 1
test: add telemetry eligibility and language contract tests

Commit 2
feat: add telemetry production eligibility and build marker

Commit 3
feat: add telemetry models transport and client

Commit 4
test: cover telemetry client throttling and concurrency

Commit 5
feat: add analytics preference and consent migration

Commit 6
feat: add telemetry reporter lifecycle

Commit 7
feat: wire telemetry into app environment

Commit 8
feat: add telemetry settings and onboarding disclosure

Commit 9
docs: document privacy and update telemetry claims

Commit 10
chore: add localized release notes and final validation
```

如果仓库当前工作区已有其他未提交改动：

```text
不要重置
不要覆盖
不要 force checkout
```

只修改本计划范围内的文件，并在最终 summary 中列出所有实际变更。

---

# 44. 最终输出要求

Codex 完成后输出：

```text
1. Summary
2. Files changed
3. Consent migration behavior
4. Production eligibility behavior
5. Heartbeat scheduling behavior
6. Payload fields
7. Privacy guarantees / known limitations
8. Tests run
9. Release preflight result
10. Manual verification still required
```

尤其明确报告：

```text
existing upgrades default OFF
fresh installs require onboarding acknowledgement
development builds cannot report
long-running app can refresh active status without restart
```

这四项是本次 v2 集成是否真正完成的核心判断。
