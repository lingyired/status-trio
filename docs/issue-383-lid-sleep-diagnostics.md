# Issue #383 — 合盖不睡眠诊断码

为了让用户反馈「合盖不睡眠」失败时能快速定位原因，而不是只看到一句笼统的
「暂时无法读取状态」，helper 会在 XPC 错误字符串前带一个稳定的、与语言无关的
诊断码，形如 `DS-R4: SleepDisabled not found in pmset -g`。

- 码通过现有的 `String?` 错误通道传输，**不改 XPC 方法签名、不升协议版本**。
- 旧 helper 只发纯文本、没有码时，app 归为 `DS-R0`，仍显示原有文案。
- app 在提示后追加「（错误码 DS-R4）」，同时用 `os.Logger`
  （subsystem `com.lingsmbp.StatusTrio`，category `SleepControl`）记录码与 detail。

## 读取侧（点「合盖不睡眠」时读取 `disablesleep`）

| 码 | 含义 | 典型原因 |
| --- | --- | --- |
| `DS-R0` | 未分类 / 旧 helper 无码 | 老版本 helper，或没有可识别的码 |
| `DS-R1` | `pmset` 启动失败 | helper 运行环境异常，`Process.run` 失败 |
| `DS-R2` | `pmset -g` 超时 | pmset 卡住，超过 runner 超时被 kill |
| `DS-R3` | `pmset -g` 退出码非 0 | 看 detail 里的 stderr |
| `DS-R4` | 输出里没有 `SleepDisabled` 行 | **已不再上报**：`pmset -g` 只在设置被写过至少一次后才打印该行，未用过即「关闭」，见下文「DS-R4 后续」 |
| `DS-R5` | `SleepDisabled` 值不是 `0/1` | 输出格式/本地化变化，解析失败 |
| `DS-H1` | helper 没响应 | XPC 超时/不可用（冷启动重试后仍失败） |
| `DS-X0` | 其他未知错误 | 非预期的传输层错误 |

## 写入侧（开启/关闭 `disablesleep`）

| 码 | 含义 |
| --- | --- |
| `DS-W1` | `pmset` 启动失败 |
| `DS-W2` | `pmset` 超时 |
| `DS-W3` | `pmset` 退出码非 0（detail 含 pmset 原文，如 `Unsupported mode 3`） |
| `DS-W4` | 写入后观察到的状态与请求不一致（app 侧判定） |

## 排障

1. 让用户报出提示里的码（如 `DS-R2`）。
2. 需要更细信息时，取统一日志：
   `log show --predicate 'category == "SleepControl"' --last 1h`
3. `DS-R3` / `DS-W3` 的 detail 里有 pmset 的 stderr，通常是原因所在。
4. `DS-R5` 需要看该机型 `pmset -g` 的原始输出再补解析规则（`DS-R4` 已改为按「关闭」处理，见下节）。

## DS-R4 后续（缺键按「关闭」处理）

实测与多份资料一致：`pmset -g` **只有在 `disablesleep` 被写过至少一次之后**才会
打印 `SleepDisabled` 这一行；从未用过的 Mac 输出里没有它，而值本身是「关闭」
（真正为 `1` 时一定打印 `SleepDisabled 1`）。

因此 daemon 读取侧（`PowerModeService.readDisableSleepDiagnosed`）现在把
`parseSleepDisabledDiagnosed` 返回的 `.keyMissing` 当作 `.value(false)`，而不再报
`DS-R4`。纯解析层 `DisableSleepCommand` 仍保留 `keyMissing`，`DS-R4` 枚举也保留
（兼容旧诊断、便于将来校验），但生产路径不再产生它。

- 触发场景：全新/重置过电源管理的 Mac 上首次点「合盖不睡眠」。
- 用户侧临时解法（会写入该行，之后不再缺）：`sudo pmset -a disablesleep 1 && sudo pmset -a disablesleep 0`。
- 真正读不到（`pmset` 启动失败/超时/非 0 退出/值不可解析/helper 无响应）仍分别报 `DS-R1..R3`、`DS-R5`、`DS-H1`。

## 超时对齐

app 的 XPC 等待必须长于 daemon 跑一条命令的最坏耗时，否则 app 会先超时、重试，
导致同一条 `pmset` 被并发执行两次，并且拿到的是 `DS-H1`（传输超时）而不是
daemon 的真实诊断码。

- daemon 单个 `pmset` 子进程超时：`PowerHelperTiming.pmsetProcessTimeout = 3s`
- 两个有界管道排空各 1s（pid 持有管道时）：最坏再加 2s
- app 单次 XPC 等待：`PowerHelperTiming.clientRequestTimeout = 6s`（> 3+2s）

由 `Tests/StatusTrioPowerHelperTests/DisableSleepCommandTests` 里的
`testClientWaitsLongerThanTheDaemonForOneCommand` 守护，防止以后漂移。

相关代码：`Sources/PowerHelperProtocol/DisableSleepDiagnostic.swift`、
`Sources/StatusTrioPowerHelper/PowerModeService.swift`、
`Sources/StatusTrioCore/Monitoring/SleepControlController.swift`。
