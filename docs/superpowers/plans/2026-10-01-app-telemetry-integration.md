# Status Trio × app-telemetry 集成计划

> 基于 status-trio `main` 与 app-telemetry 在 2026-10-01 的实际状态。
>
> 本文档给**另一个会话**（status-trio 仓库）执行客户端改动。
> 服务端改动已经完成并测试通过，见 §4。

---

## 0. 结论先行

**服务端已经改完了**，新增了本轮要用的字段和接口（§4 列了全部改动）。

客户端要做三件事：

1. 在 `StatusTrioCore` 里加一个遥测客户端，发 **12 个字段**（原来 9 个，新增
   `os_language` / `app_language` / `attributes`）。
2. 加一个「匿名使用统计」开关和对应的隐私说明（13 个语言同步）。
3. 把 README / docs 里「本项目不含遥测」的承诺改成准确的新描述。

**没有服务端任务，没有数据库迁移，没有 entitlements 改动。**

---

## 1. 现状核查

### 1.1 服务端

**服务端已部署完成（2026-10-01），可以开始客户端工作了。**

| 项 | 状态 |
|---|---|
| Worker | `app-telemetry`，域名 `https://telemetry.lingai.net` |
| 线上版本 | `2134cc62-21a6-4773-a2a6-bbead05416c0` |
| D1 迁移 | ✅ `0003_language_and_attributes.sql` 已应用到远程库，5 条既有行全部保留 |
| app 注册 | ✅ `status-trio` 已在 `config/apps.json`，含 `attributes.app_icon_placement` 声明 |
| `GET /v1/health` | ✅ `200 {"ok":true,"service":"app-telemetry","version":1}` |
| `POST /v1/ping` | ✅ 实测接受 12 字段 payload，三个新字段正确落库 |
| `attributes` 嵌套禁止字段 | ✅ 实测 `400 {"reason":"forbidden field: attributes.hostname"}` |
| 未声明属性 | ✅ 实测 `200`，该键被丢弃，心跳不失败 |
| `GET /v1/apps`、`/v1/stats/*`、`/` | ⛔ **`403 stats_disabled`**（`STATS_PUBLIC = "false"`）→ 见 §3 决策 3 |
| 真实装机数据 | **零**。库里 5 行全是测试数据，真实用户一条都没有 |

> ⚠️ 那 5 行测试数据（`1.3.3`×2、`0.0.0-plan`、`0.0.0-deploycheck`×2）会让第一次打开看板时
> 看到假的装机量。清理命令见 §10，**在做客户端集成前清掉最省事**。

### 1.2 客户端零集成

- `Sources/StatusTrioCore` 下没有任何 `URLSession` 调用，没有任何 `actor` 声明。
- `Package.swift` 没有网络依赖，`Support/Info.plist` 没有 App Sandbox、没有 network entitlement。
  → **接入不需要改 entitlements**。
- `app-telemetry/examples/swift/AppTelemetryClient.swift` 是参考实现（322 行），但它是给
  「通用宿主应用」写的，且**只发 9 个字段**——直接拷会漏掉语言和属性，见 §5.8。

### 1.3 本次集成要触碰的现有承诺

改代码不改文案就是文档撒谎：

- `README.md:196`
  > It does not use App Sandbox or require a network entitlement, and **it does not include telemetry or analytics**.
- `docs/analytics-snapshot.md:15-17`
  > **Status Trio ships no telemetry**, nothing runs on a user's machine…

第二处讲的是 **GitHub 侧快照**（`scripts/snapshot-analytics.py`），跟本次是**两回事**，
要改写措辞把两者区分开，而不是删掉。

---

## 2. 目标与非目标

**目标**

- 装机量、活跃安装（7d/30d）、版本分布、macOS 版本分布、架构分布。
- **语言受众分析**：用户的系统语言 vs 实际看到的 app 语言，用来决定「下一个加哪个翻译」。
- **图标位置分布**：menuBar / dock / both，用来判断 Dock 图标值不值得继续维护。
- **升级惰性**：`first_app_version`（服务端自己算，客户端不用发），
  看板新增了「First observed version」面板与之对照。

  术语一律叫 **first observed version / 首次观测版本**，**不要**叫「首次安装版本」——
  telemetry 上线前就存在的用户，第一次上报时只能看到当时的版本；长期关闭后重新打开同理。
- 复用 GitHub Release 的 `download_count` 对账「下载量 vs 装机量」。
- 关掉开关后**一个包都不发**。

**非目标**

- 不做崩溃上报、不做事件埋点、不做用户级漏斗。
- 不做 A/B、不做远程配置下发。
- 不引入第三方分析 SDK。只发 `/v1/ping` 一个端点。

---

## 3. 需要先拍板的三个决策

### 决策 1：默认开还是默认关

| 方案 | 效果 | 代价 |
|---|---|---|
| **A. 默认关 + 首次启动显式询问** | 信任成本最低 | 样本量小、偏差大（只有愿意开的人） |
| **B. 默认开 + 首次启动告知**（参考实现的姿态） | 立刻拿到接近全量的数据 | 与 §1.3 现有承诺落差最大，必须在 release notes 说明 |
| **C. 默认关 + 只在设置页提供开关** | 改动最小 | 几乎收不到数据 |

**建议 B**：Status Trio 的分发量级下，opt-in 的样本量撑不起「版本分布」「语言受众」这类判断。
但要接受 §7 的文档改写幅度。

> 这个决策决定 §5.7 的默认值和 §6/§7 的措辞。

### 决策 2：开关放哪

- **A.** General 设置页新增一个 `SettingsToggleRow`（`GeneralSectionView` 的 `systemGroup`）。
- **B.** 复用 onboarding（`OnboardingWindowController` / `IconGuideOnboardingPolicy`）加一页说明。

**建议 A**，首次启动如果本来就走 onboarding，顺带提一句即可。

### 决策 3：怎么看到数据（**阻塞验收**）

`STATS_PUBLIC = "false"`，所以 `/`、`/v1/apps`、`/v1/stats/*` 现在全部 403。

- **A.** Cloudflare Access 后面开读接口（推荐）。
- **B.** 把 `STATS_PUBLIC` 改成 `"true"` 重新部署（数据全是聚合值，但会公开）。

注意：**`ping` 和 `health` 不受这个开关影响**，所以客户端可以先上线，看板后补。

---

## 4. 服务端改动：已完成

已经改完、测试通过（**323 个测试全绿**），这里是客户端需要知道的契约。

### 4.0 部署状态

```text
2026-10-01  远程迁移 0003 已应用（8 commands, 3.24ms），既有行全部保留
2026-10-01  已部署 2134cc62-21a6-4773-a2a6-bbead05416c0
2026-10-01  线上冒烟通过（12 字段 ping / 禁止字段 400 / 未声明属性丢弃）
```

客户端可以直接按下面的契约开始实现。

### 4.1 新字段

| 字段 | 必填 | 客户端要发吗 | 说明 |
|---|---|:---:|---|
| `os_language` | 否 | ✅ | **系统语言**，即受众本身 |
| `app_language` | 否 | ✅ | **实际生效的界面语言** |
| `attributes` | 否 | ✅ | app 自己声明的扩展字段（当前只有 `app_icon_placement`） |
| `first_app_version` | — | ❌ **不要发** | 服务端自己记录，客户端发了也会被忽略 |

### 4.2 新接口

| 接口 | 返回 |
|---|---|
| `GET /v1/stats/:appId/os-languages?days=30` | `[{ os_language, count }]` |
| `GET /v1/stats/:appId/app-languages?days=30` | `[{ app_language, count }]` |
| `GET /v1/stats/:appId/attributes?name=app_icon_placement&days=30` | `[{ value, count }]` |
| `GET /v1/stats/:appId/first-versions?days=30` | `[{ first_app_version, count }]` |

未声明的属性名返回 `404 {"error":"unknown attribute"}`。

`first-versions` 要配「Version adoption」一起看：某个版本在「首次观测」里大、在
「当前版本」里小 → 人离开了；两边都大 → 人卡在那儿没更新。

### 4.3 服务端保留期（隐私文档必须按这个写）

| 数据 | 保留期 |
|---|---|
| `daily_activity`（日活历史） | **365 天**，之后由 cron 分批删除（`ACTIVITY_RETENTION_DAYS`） |
| `install_state`（安装状态，含 `first_app_version` / 语言 / 属性） | **永不自动删除**。V1 明确不裁剪 |
| `download_snapshots` / `release_download_snapshots` | 永不自动删除 |

⚠️ **隐私文档不能笼统写「所有遥测数据保留 365 天」**——那是错的，`ACTIVITY_RETENTION_DAYS`
只管日活历史。安装状态会一直保留到运维手动删除。

另外：服务端**没有**按安装删除的接口。用户关闭开关是「停止未来上报」，
**不会**删除已经形成的聚合统计。文档要如实这么说。

### 4.4 校验规则（客户端必须遵守）

- `os_language` / `app_language`：必须匹配 `^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*`，**最长 16 字符**。
  不符合就**丢掉这个字段**（心跳仍然成功，不会 400）。
- `attributes`：必须是**一层扁平对象**，值只能是字符串（或数字，会被转成字符串）。
  - 键要匹配 `^[a-z][a-z0-9_]{1,31}$`
  - 最多 8 个键，每个值最长 64 字符
  - **嵌套对象 / 数组会被丢掉**
  - 键不在 app 的声明里 → 丢掉；值不在声明的 `values` 里 → 丢掉
  - ⚠️ **唯一会整包 400 的情况**：`attributes` 里出现禁止字段名（`hostname`/`ssid`/`serial`/`ip`/`token` 等）。
    其他地方嵌套禁止字段是无害的（会被丢弃），唯独这里因为内容会入库所以拒收。
- `schema_version` **必须保持 `1`**。服务端是严格相等校验，发 `2` 会被 400。

---

## 5. 客户端设计

### 5.1 文件布局

新增（都在 `Sources/StatusTrioCore/Telemetry/`）：

```text
Sources/StatusTrioCore/Telemetry/
  TelemetryClient.swift          # 发送逻辑，actor
  TelemetryConfiguration.swift   # 端点 / appID / distribution / 超时 / 冷却
  TelemetryHeartbeat.swift       # wire format（12 个字段）
  TelemetryLanguageTag.swift     # 系统语言 → BCP-47 短标签（见 §5.5）
```

修改：

| 文件 | 改动 |
|---|---|
| `Settings/SettingsStore.swift` | 新增 `sharesAnonymousAnalytics` + defaults key |
| `UI/Settings/GeneralSectionView.swift` | 新增一个开关行 |
| `App/AppEnvironment.swift` | `start()` 里触发一次发送 |
| `Localization/LocalizationKey.swift` | 新增 2–3 个 key |
| `Resources/*.lproj/Localizable.strings` | **12 个语言**同步（见 §6） |
| `README.md`、`docs/analytics-snapshot.md`、`docs/known-limitations.md` | 承诺同步 |

> 注意：不是 13 个语言。实际是 `ar, de, en, es, fr, it, ja, ko, pt-BR, ru, zh-Hans, zh-Hant` 共 **12** 个。

### 5.2 身份与状态

**install_id**：首次运行生成一个随机 `UUID().uuidString`，存 `UserDefaults`。

- **绝不可以**从硬件、网络或账号信息派生。服务端会做
  `install_hash = HMAC-SHA256(pepper, "status-trio:" + install_id)`，客户端只需保证源头随机。
- key 用 `"telemetry.installationId"`。

**状态键**（统一 `telemetry.` 前缀）：

```text
telemetry.installationId        # 随机 UUID
telemetry.lastSuccessfulDay     # yyyy-MM-dd，本地日
telemetry.lastAttemptAt         # Date
```

**`UserDefaults` 必须可注入**：现有 `SettingsStore` 和 `Localization` 都支持 `init(defaults:)`，
遥测客户端保持一致，否则 §8 的测试只能污染真实 defaults。

### 5.3 发送策略

沿用参考实现，这几条都经得起推敲，不要「优化」掉：

- 成功一次后**当天不再发**（**本地日**）。
- 失败后 **6 小时冷却**。`lastAttemptAt` 要在请求**之前**写，这样超时和崩溃也受冷却约束。
- **2.5 s 超时**，`URLSessionConfiguration.ephemeral`，`waitsForConnectivity = false`。
- 只有 **HTTP 2xx** 算成功。
- 任何失败都静默，只在 `DEBUG` 打日志。
- 重入保护：多条启动路径并发时只发一个。

**一个容易忽略的细节**：客户端按**本地日**判重，服务端按 **UTC 日** 记 `active_days`。
两者错开时（例如 UTC+8），某天可能发不出 ping，导致 `established`（要求 2 个不同 UTC 日）
延迟一天成立。这是可接受的偏差——**不要**改用 UTC 判重，那会让用户晚上被判定
「今天已经发过」而实际还在昨天。

### 5.4 payload（12 个字段）

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
  "attributes": { "app_icon_placement": "menuBar" }
}
```

| 字段 | 取值 |
|---|---|
| `app_version` | `CFBundleShortVersionString` |
| `build` | `CFBundleVersion` |
| `os_name` | 固定 `"macOS"` |
| `os_version` | `ProcessInfo` 的 **major.minor**，如 `27.0`。**不带** patch，**不带** build（`26A434` 不发） |
| `arch` | 编译期 `#if arch(arm64)` → `arm64` / `x86_64` |
| `distribution` | 固定 `"github"`（理由见下） |
| `os_language` | 见 §5.5 |
| `app_language` | `localization.resolvedLanguage.rawValue` |
| `attributes` | 见 §5.6 |

⚠️ `app_version` 和 `build` 要**两个独立字段**。不要用
`AppMetadata.versionDisplayString` 的 `"1.4.0 (17)"` 拼接结果。

**`distribution` 固定 `"github"`：** 服务端允许清单是
`["github","direct","appstore","homebrew","unknown"]`，白名单外记 `unknown` 而不是拒收。
但**同一个 DMG 被 Homebrew cask 转发时，二进制里没有任何东西能区分自己是从哪来的**——
所以它是常量，不是变量。真要分渠道是另一个设计问题。

**不要发**：device name、serial、hardware UUID、SSID、Bluetooth 设备、Apple ID、用户名、IP、位置。
命中 `FORBIDDEN_PATTERNS` 会**整包 400**。

### 5.5 语言字段怎么取（**本计划最容易做错的地方**）

#### 两个字段分别是什么

- `os_language` = **系统语言**（`Locale.preferredLanguages`），受众本身。
- `app_language` = **实际生效的界面语言**（`Localization.resolvedLanguage`），用户真正看到的。

**为什么不能只发一个。** `AppLanguage` 只认 12 种，泰语用户会被 fallback 成 `en`。
只发 `app_language` 的话，你看到的永远是「又一个英语用户」，**永远学不到该加泰语**。

两个一对比，结论直接出来：

```text
os_language=th  app_language=en   → 泰语用户在硬看英文   ← 该加翻译
os_language=ja  app_language=ja   → 日文用户已被服务     ← 不用动
os_language=zh-Hant  app_language=zh-Hans → 台湾用户看到简体 ← 可能是 bug
```

第三行还顺带暴露一个潜在问题，挺值。

#### 取值规则（关键）

**`app_language` 直接取 `localization.resolvedLanguage.rawValue`**，一定是那 12 个之一。

**`os_language` 用这个规则归一化**：

```swift
// 伪代码：系统语言 → 上报用的短标签
func osLanguageTag(preferred: [String]) -> String? {
    guard let first = preferred.first else { return nil }

    // 1. 如果 app 自己认得这个语言，就用它的 rawValue。
    //    这样和 app_language 的取值域完全对齐，"未被服务" 的判断就是精确的集合差。
    if let known = AppLanguage.match(first) {
        return known.rawValue          // "ja", "pt-BR", "zh-Hant", ...
    }

    // 2. 认不得的（th / vi / id / ...），发归一化后的原始标签，
    //    保留主语言 + 脚本，丢掉地区。
    return normalizeRawTag(first)      // "th", "zh-Hans", ...
}
```

`normalizeRawTag` 的做法：`_` → `-`，按 `-` 切开，取**主语言小写**，
如果第二段是 4 个字母（脚本，如 `Hans`/`Latn`）就保留并首字母大写，**丢掉地区**。

这样做的三个好处：

1. **取值域对齐**：已服务的语言，`os_language` 和 `app_language` 用的是同一套字符串。
   判断「系统语言里有哪些没有对应的 app 语言」就是一次精确的集合差，不会有假阳性。
   （如果不这么做，`pt-BR` 用户的 `os_language` 会是 `pt`，看起来像没人服务。）
2. **保留 zh 的脚本区分**：`zh-Hans` / `zh-Hant` 是两种语言，不能合并。
3. **丢掉地区**：`en-US` / `en-GB` / `en-AU` 都算 `en`。地区对「该不该加翻译」没帮助，
   只是多余的指纹熵。

**边界情况**：`AppLanguage.match` 是现成的 `static func`，在
`Sources/StatusTrioCore/Localization/AppLanguage.swift`。它已经处理了
`zh` / `zh-CN` / `zh-SG` → 简体，`zh-TW` / `zh-HK` → 繁体，`pt` / `pt-BR` → 巴西葡语。
**复用它，不要重写。**

⚠️ **读系统语言要用 `Locale.preferredLanguages`，不要用 `localization.preference`。**
后者是用户的**手动选择**（`.system` 或某个 `.language(x)`），一个手动选了英语的
德语用户，系统语言应该报 `de` 而不是 `en`。这两个语义不同，别搞混。

（`Localization` 里的 `preferredLanguages` 是 `private`，用 `Locale.preferredLanguages` 就行。）

#### 长度上限

≤16 字符。`normalizeRawTag` 之后最长的可能是 `zh-Hant`（7）或 `sr-Latn`（7），
远低于上限，但**仍然要显式截断防御**，别依赖「不可能超」。

### 5.6 attributes

当前只声明了一个属性：

```json
"attributes": { "app_icon_placement": "menuBar" }
```

值直接取 `AppIconPlacement.rawValue`（`menuBar` / `dock` / `both`），
它本来就是 `String` 枚举，不用转换。

服务端声明在 `config/apps.json`：

```json
"app_icon_placement": { "values": ["menuBar", "dock", "both"] }
```

**如果客户端发了声明外的值，会被静默丢掉**（心跳仍然成功）。所以客户端和服务端的
枚举值必须一致——**改 `AppIconPlacement` 时记得同步服务端 `config/apps.json`**。

这是个真实的耦合点。建议在客户端加一条测试断言枚举的 `allCases` 与写死的列表一致，
并在 `AppIconPlacement.swift` 顶部加一句注释指向服务端配置文件。

**将来加新属性**：服务端改 `config/apps.json` 一行即可，**不用迁移、不用改 worker、不用改看板**
（看板从 `/v1/apps` 读声明，自己把面板长出来）。客户端加一个键就行。

### 5.7 接入点与开关

**接入点**：`AppEnvironment.start()` 末尾，必须是「不阻塞启动」的形式：

```swift
// AppEnvironment.start() 内
Task.detached(priority: .background) {
    await telemetryClient.sendHeartbeatIfNeeded()
}
```

选 `AppEnvironment` 而不是 `AppDelegate`：`AppEnvironment.live()` 是现成的依赖装配点，
测试可以直接构造；`AppDelegate` 只管进程生命周期。

**开关**：`SettingsStore` 加 `@Published var sharesAnonymousAnalytics: Bool` + `didSet` 落盘
（照抄 `showsBatteryPercentage` 的写法）。发送前先读，关了**直接返回，连 URL 都不构造**。

按决策 1：B → `?? true`，A → `?? false`。

### 5.8 与参考实现的差异（必须处理）

`examples/swift/AppTelemetryClient.swift` **只发 9 个字段**，直接拷会漏掉语言和属性。

| 参考实现 | Status Trio 里应该怎么改 |
|---|---|
| payload 只有 9 个字段 | 补 `os_language` / `app_language` / `attributes`，见 §5.4–§5.6 |
| `nonisolated(unsafe) static var enabledOverride` | 去掉。用 `SettingsStore` 的开关，不要第二套全局状态 |
| `#if DEBUG` 默认关 | 逻辑挪进 `SettingsStore`。注意 `swift test` 是 debug 配置，**测试里要能显式打开**，否则测不到发送路径 |
| `UserDefaults.standard` 硬编码 | 改成可注入的 `defaults` |
| key 前缀 `appTelemetry.` | 改 `telemetry.` |
| `static let shared` 单例 | 改成由 `AppEnvironment` 持有并注入，便于测试 |

⚠️ **`scripts/check-forbidden-patterns.sh`** 禁止把 actor-isolated 方法当函数值传递
（`docs/swift-ci-compatibility.md` 记录过 IRGen 崩溃）。`AppEnvironment.start()` 里写成
`sendHeartbeat` 之类的裸引用会被这个脚本拦下。用 §5.7 的闭包写法。

---

## 6. 本地化与文案

`LocalizationKey` 新增（放 `settings.*` 段）：

```text
settings.analytics.title
settings.analytics.description
```

**12 个 `.lproj/Localizable.strings` 必须全部同步**：
`ar, de, en, es, fr, it, ja, ko, pt-BR, ru, zh-Hans, zh-Hant`。

`LocalizationParityTests` 会校验「key 集合完全一致」和「占位符完全一致」，漏一个语言就红。
占位符规则是 `%[@dfs]` 和 `%%`——建议这两条文案**不带占位符**，减少出错面。

文案要回答：「为什么收集、收集什么、怎么匿名化、在哪里关」。
参考 app-telemetry README 那份隐私声明，但翻译成用户视角的短句，不要照抄法律腔。

---

## 7. 文档与承诺同步

| 文件 | 现状 | 改法 |
|---|---|---|
| `README.md:196` | "does not include telemetry or analytics" | 改为准确描述：默认姿态 + 关掉方式 + 隐私说明入口 |
| `docs/analytics-snapshot.md:15-17` | "Status Trio ships no telemetry" | 消歧：本文档讲 GitHub 侧快照；应用侧遥测另有说明 |
| `docs/known-limitations.md` | 无相关条目 | 新增：`/v1/ping` 可伪造；卸载与关闭统计在服务端不可区分 |
| 新增 `docs/privacy-telemetry.md` | — | 完整声明：字段清单、HMAC 与 pepper、**不收集**清单、开关位置、保留期（365 天） |
| `release-notes/<version>/zh-Hans.md` + `en.md` | — | 主动说明本次变更。选决策 1 的 B 时**必须**写 |

release notes 的硬性规则：`en.md` 和 `zh-Hans.md` 必填，`publish=true` 时要求全部 12 个语言，
每个文件首行是含 `%VERSION%` / `%BUILD%` 的 `# <title>`。
`bash scripts/validate-appcast-notes.sh` 会校验。

---

## 8. 测试计划

新增 `Tests/StatusTrioCoreTests/TelemetryClientTests.swift`，用 `URLProtocol` stub 网络层：

1. **开关关闭时一个请求都不发**（断言计数为 0）——最重要的一条。
2. 首次运行生成 UUID 并落盘；第二次复用同一个。
3. 成功后写 `lastSuccessfulDay`；同一天再调用不发送。
4. 失败（`500` / 超时 / 无网络）后 6 小时内不再尝试。
5. 只有 2xx 记成功；`404 unknown_app` 和 `429` 都算失败。
6. payload **恰好 12 个字段**，键名与 `app-telemetry/src/validation.js` 的 `ALLOWED_FIELDS` 对齐
   （注意：`first_app_version` **不在**客户端可发列表里）。
7. `os_version` 是 `major.minor` 两段；`arch` ∈ `{arm64, x86_64}`。
8. `install_id` 不等于任何硬件标识（约束性断言，防回归）。
9. 并发调用两次只发一个请求（重入保护）。

**语言字段专项测试**：

10. 系统语言 `th`（app 不认）→ `os_language == "th"`，`app_language == "en"`。
11. 系统语言 `zh-TW` → `os_language == "zh-Hant"`（复用 `AppLanguage.match` 的映射）。
12. 系统语言 `pt-BR` → `os_language == "pt-BR"`（**不是** `pt`，否则集合差会有假阳性）。
13. 系统语言 `en-GB` → `os_language == "en"`（丢掉地区）。
14. 用户手动把 app 设成英语、系统是德语 → `os_language == "de"`、`app_language == "en"`。
15. 标签长度不超过 16 字符。

**属性专项测试**：

16. `app_icon_placement` 三个 `allCases` 都能通过服务端声明校验
    （写死列表做断言，把 §5.6 的耦合显式化）。
17. `attributes` 里没有嵌套对象。

新增 `SettingsStore` 测试：`sharesAnonymousAnalytics` 默认值符合决策 1，
赋值后持久化、重建 store 后读回一致。

---

## 9. 验证与发布流程

按 `AGENTS.md`，本地通过不等于 CI 通过：

```bash
# 1. 本地（会先跑 check-forbidden-patterns.sh）
bash scripts/test.sh

# 2. Release 构建
swift build -c release

# 3. 非发布 release 预检 —— 本次改动触碰 actor 隔离 / @MainActor / SwiftUI Binding，
#    AGENTS.md 要求必须先跑这个才能合并或发布
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=<next-version> \
  -f build=<next-build> \
  -f publish=false
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

CI 是 `macos-26` / Xcode 26.6 / Swift 6.3.3，本机工具链更新，所以第 3 步**不能省**。

**手工冒烟**（构建后）：

```bash
# 指向本地 Worker，避免污染生产库
cd ~/Documents/aiwork/app-telemetry && npm run dev
# 然后确认本地 D1 出现 status-trio 行，字段与 §5.4 一致：
npx wrangler d1 execute app-telemetry --local --json --command \
  "SELECT app_version, first_app_version, os_language, app_language, attributes \
   FROM install_state WHERE app_id='status-trio'"
```

上线后核对：

```bash
cd ~/Documents/aiwork/app-telemetry
npx wrangler d1 execute app-telemetry --remote --json --command \
  "SELECT os_language, app_language, COUNT(*) c FROM install_state \
   WHERE app_id='status-trio' GROUP BY 1,2 ORDER BY c DESC"
```

**「该加哪个翻译」的查询。**

⚠️ **不要用「`os_language` 不在观测到的 `app_language` 集合里」这个写法。**
它看起来对，但有个假阳性：一个日本用户手动把界面切成英语，如果他是唯一一个
`os_language='ja'` 的安装，`app_language` 集合里就没有 `ja`，查询会把 `ja`
误报成「不支持」——而 app 明明支持日语。

正确做法是拿**固定支持集合**判断：

```sql
SELECT os_language, COUNT(*) AS audience
FROM install_state
WHERE app_id = 'status-trio'
  AND os_language IS NOT NULL
  AND os_language NOT IN (
    'ar','de','en','es','fr','it','ja','ko','pt-BR','ru','zh-Hans','zh-Hant'
  )
GROUP BY os_language
ORDER BY audience DESC;
```

另开一条 mismatch 查询（系统语言和生效语言不一致的）：

```sql
SELECT os_language, app_language, COUNT(*) AS installs
FROM install_state
WHERE app_id = 'status-trio'
  AND os_language IS NOT NULL AND app_language IS NOT NULL
  AND os_language <> app_language
GROUP BY os_language, app_language
ORDER BY installs DESC;
```

注意 **mismatch 不一定是 bug**——用户可能主动改了界面语言。它是待解释的信号，不是告警。

---

## 10. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| **UDP:53 被干扰导致 `telemetry.lingai.net` 解析失败** | 客户端静默失败，一个包都收不到；只在部分网络出现，本地开发很难发现 | 实测：`dig @114.114.114.114 telemetry.lingai.net`（UDP）返回**空**，同一服务器 `+tcp` 正常返回 Cloudflare IP。系统 resolver 默认走 UDP，所以 `URLSession` 直连会失败。**缓解**：客户端**不要**做 IP 兜底（硬编码 IP 在变更时更脆）；§9 冒烟用真实网络跑一次；上线后若长期零数据，**先排查 DNS 再怀疑客户端逻辑** |
| `attributes` 枚举双写不一致 | 客户端改了枚举、服务端没同步，属性被静默丢掉 | §5.6 的测试 16 + `AppIconPlacement.swift` 顶部注释指向 `config/apps.json` |
| README 承诺从「无遥测」变成 opt-out | 信任落差、issue 风险 | 决策 1 选 A 可完全规避；选 B 必须在 release notes 主动说明 |
| `os_language` 写错成「生效语言」 | 语言受众分析完全失效（所有未支持语言塌缩成 en） | §5.5 + §8 的测试 10/14 专门盯这个 |
| 与 Sparkle 更新链路冲突 | — | 无冲突：只在启动时读当前 bundle 版本 |
| 服务端数据可伪造 | 装机量虚高 | 已知取舍。看数据以 `established`（2+ 不同 UTC 日）为准 |

**回滚**：客户端回滚就是关掉开关 / 回退代码，服务端无状态可回滚。

**清理测试残留**（库里 3 行测试数据：2 行 curl 示例 + 1 行链路验证）。
两个表都要删，只删 `install_state` 会让 `daily_activity` 留下没有对应安装的日活记录：

```bash
cd ~/Documents/aiwork/app-telemetry

# 1. 先确认命中行
npx wrangler d1 execute app-telemetry --remote --json --command \
  "SELECT app_version, last_seen_day FROM install_state WHERE app_id='status-trio'"

# 2. 再删（先看清楚上面返回了什么）
npx wrangler d1 execute app-telemetry --remote --command \
  "DELETE FROM install_state WHERE app_id='status-trio' AND app_version IN ('1.3.3','0.0.0-plan')"
npx wrangler d1 execute app-telemetry --remote --command \
  "DELETE FROM daily_activity WHERE app_id='status-trio' AND app_version IN ('1.3.3','0.0.0-plan')"
```

> ⚠️ **破坏性操作**。执行前务必先跑第 1 步，确认返回的正是那 3 行测试数据再删。
> 如果已经有真实用户上报（`1.4.0` 之类的新版本），**按 `install_hash` 精确删，不要按版本号删**。

---

## 11. 分阶段任务清单

**阶段 0 — 拍板**
- [ ] 决策 1（默认开 / 默认关）
- [ ] 决策 2（开关位置）
- [ ] 决策 3（Cloudflare Access 或临时打开 `STATS_PUBLIC`）

**阶段 1 — 客户端骨架**
- [ ] `TelemetryConfiguration` / `TelemetryHeartbeat` / `TelemetryClient`
- [ ] `TelemetryLanguageTag`（§5.5 的归一化）
- [ ] 按 §5.8 处理与参考实现的差异
- [ ] `TelemetryClientTests` 全绿（尤其测试 1 和 10–15）

**阶段 2 — 接入与开关**
- [ ] `SettingsStore.sharesAnonymousAnalytics` + 测试
- [ ] `GeneralSectionView` 新增开关行
- [ ] `AppEnvironment.start()` 接入（用闭包，避开 `check-forbidden-patterns.sh`）

**阶段 3 — 本地化**
- [ ] `LocalizationKey` 新增 key
- [ ] 12 个 `Localizable.strings` 同步，`LocalizationParityTests` 通过

**阶段 4 — 文档**
- [ ] `README.md:196` 改写
- [ ] `docs/analytics-snapshot.md` 消歧
- [ ] 新增 `docs/privacy-telemetry.md`
- [ ] `docs/known-limitations.md` 补两条
- [ ] release notes（中英）

**阶段 5 — 验证与发布**
- [ ] `bash scripts/test.sh` + `swift build -c release`
- [ ] `release.yml` 非发布预检通过
- [ ] 本地 Worker 冒烟：D1 出现字段正确的 status-trio 行
- [ ] 发布后核对线上数据

---

## 12. 验收标准

1. `/v1/stats/status-trio/summary` 返回非零的 observed / established installations。
2. 关闭开关的应用实例**完全不产生网络请求**（测试断言，不靠肉眼）。
3. 一个 `install_id` 在多个 UTC 日出现后，`established_installations` 正确递增。
4. **一个系统语言是泰语的安装，在 `os-languages` 里显示为 `th`，而不是塌缩进 `en`。**
5. **`os-languages` 里出现 `app-languages` 中不存在的语言**——这是「该加哪个翻译」的直接信号。
6. `attributes` 里 `app_icon_placement` 的分布能反映 menuBar / dock / both。
7. 12 个语言文件的 key 与占位符完全一致（`LocalizationParityTests` 绿）。
8. README 与 docs 里不再有「本项目不含任何遥测」这类已不成立的表述。
9. CI（`release.yml` `publish=false`）在 `macos-26` / Xcode 26.6 / Swift 6.3.3 下通过。

---

## 附：关键事实速查

```text
端点           https://telemetry.lingai.net/v1/ping
app_id         status-trio
schema_version 1  ← 必须保持 1
必填字段       schema_version, app_id, install_id, app_version
可选字段       build, os_name, os_version, arch, distribution,
               os_language, app_language, attributes
不可发         first_app_version（服务端自己记，发了会被忽略）
身份           install_hash = HMAC-SHA256(INSTALL_ID_PEPPER, "status-trio:" + install_id)
语言上限       16 字符，匹配 ^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*
attributes     一层扁平对象，≤8 键，值 ≤64 字符，键须服务端声明
频率上限       MIN_INTERVAL_S=3600，FLOOD_THRESHOLD_S=60
保留期         ACTIVITY_RETENTION_DAYS=365
看板           https://telemetry.lingai.net/  （需先解决 STATS_PUBLIC 或加 Access）
参考实现       app-telemetry/examples/swift/AppTelemetryClient.swift（只发 9 字段，需补）
契约文档       app-telemetry/README.md「What it collects」+ app-telemetry-plan.md §7/§8
服务端字段表   app-telemetry/src/validation.js 的 ALLOWED_FIELDS（但 first_app_version 不在其中）
属性声明       app-telemetry/config/apps.json → apps.status-trio.attributes
```
