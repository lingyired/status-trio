# 遥测集成验收报告

客户端实现验收与生产环境验收分别记录。本次没有向生产端点发送请求，也没有向远程 D1 写入数据。

## 已实现的行为

- **既有安装升级后默认关闭统计。** 只有用户主动开启后才允许上报。全新安装的选择在用户确认说明前保持待确认；直接关闭首次启动引导不会开启统计。
- 发送遥测必须同时满足：用户已确认开启，以及应用包带有正式生产构建标记。开发构建和普通本地构建不能发送。
- 心跳包含随机安装 ID，以及受字段长度限制的应用/macOS 版本、处理器架构、二进制来源（`github`）、归一化后的系统语言、应用界面语言和图标位置。客户端不发送姓名、设备名称、硬件唯一标识、网络详情或时间戳。
- Reporter 在应用启动、系统唤醒以及每隔 6 小时时检查一次。成功发送后至少间隔 20 小时；失败后冷却 6 小时。用户关闭统计或应用停止时，会取消 Reporter 管理的定期任务及正在进行的发送尝试。

完整字段清单、保留期限及隐私边界见[遥测与隐私说明](privacy-telemetry.md)。

## 变更范围

本次实现包括：同意状态迁移与设置持久化、生产资格判断与构建标记、强类型上报数据与语言归一化、URLSession 传输、actor 客户端与 MainActor Reporter、AppEnvironment 生命周期接入、本地化的首次启动说明与设置控件、隐私文档和发布说明、appcast 链接渲染，以及本地验证测试。

## 本地验证

### 单元测试与 Release 编译

- `bash scripts/test.sh`：1,295 个 XCTest 测试，跳过 7 个，失败 0 个；Swift Testing 的 74 个测试套件、444 个测试全部通过。日志：`/tmp/status-trio-telemetry-v2-full-test-script.log`。
- `swift test`：XCTest 和 Swift Testing 的数量同上，失败 0 个。日志：`/tmp/status-trio-telemetry-v2-swift-test.log`。
- `swift build -c release`：通过。日志：`/tmp/status-trio-telemetry-v2-release-build.log`。

### 发布说明与 appcast

- `VERSION=1.4.0 BUILD=17 PUBLISH=false bash scripts/validate-appcast-notes.sh`：12 个本地化版本全部通过，确认没有遥测链接的历史发布说明仍然有效。
- `VERSION=2.0.0 BUILD=18 PUBLISH=false bash scripts/validate-appcast-notes.sh`：通过。生成了 12 个标题和 12 个描述，英文排在第一位；每份 Sparkle 描述都包含可点击的隐私链接。全部 12 份发布说明均写明未引入第三方分析 SDK。

### 应用包与生命周期

普通构建和模拟生产构建均在不启动应用的情况下，通过代码签名校验及 `scripts/verify-platform-version.sh` 检查。两者的最低支持系统均为 macOS 15.0，记录的 SDK 均为 26.0；`STTelemetryProduction` 分别为 `false` 和 `true`。

应用包保存在 `/tmp/status-trio-telemetry-v2/{ordinary,production}/StatusTrio.app`。

实际调用 `AppEnvironment.start()` / `stop()` 的生命周期测试使用模拟的电池、Wi-Fi 和音量监测器，验证了监测器与遥测 Reporter 的启动、停止调用。

### 本地 Worker 冒烟测试

显式启用的本地 Worker 冒烟测试通过 `URLSessionTelemetryTransport` 请求 `http://127.0.0.1:18787/v1/ping`，本地 D1 状态保存在 `/tmp/status-trio-telemetry-v2/worker-state`。

统计关闭时，没有创建本地安装 ID，也没有发起发送尝试；开启后收到 HTTP 200。本地 D1 的 `SELECT` 查询确认了以下数据：

```text
first_app_version=2.0.0
app_version=2.0.0
build=18
os_language=en
app_language=en
attributes={"app_icon_placement":"both"}
```

Worker 源码仅用于读取核对，没有修改。

## 非发布 CI 预检

执行前重新确认：最新正式发布仍为 v1.4.0（2026-09-30），appcast 中最高 build 为 17。随后推送功能分支，并以 version 2.0.0、build 18、`publish=false` 触发 release 工作流预检。

- **运行记录：** [36844103043](https://github.com/lingyired/status-trio/actions/runs/36844103043)。
- **结果：通过。** 运行日期为 2026-10-01，环境为 macOS 26.6.2、Xcode 26.6（17F113）和 Swift 6.3.3。工作流的 `Run tests` 步骤通过，测试数量如上。
- 工作流构建了 `StatusTrio-2.0.0.dmg`，并将其上传为 `StatusTrio-221` Actions 产物（[下载](https://github.com/lingyired/status-trio/actions/runs/36844103043/artifacts/11153255565)）。下载后的 DMG 在不启动应用的情况下完成检查：`STTelemetryProduction=true`；两个处理器架构的最低系统版本均为 15.0、SDK 均为 26.0；签名校验通过。
- `publish=false` 按预期跳过了 GitHub Release 创建和 appcast 发布。工作流使用 Ad-hoc 签名；由于没有配置 Developer ID 和公证凭据，本次应用未进行公证。
- 工作流验证的是产品与测试提交 `b7382e8`。后续提交 `9dda76a` 仅在生命周期测试夹具中明确选择关闭统计，并添加本验收文档。夹具调整后，最新代码树另行通过了 `swift test` 和 `swift build -c release`。日志：`/tmp/status-trio-telemetry-v2-swift-test-final.log`、`/tmp/status-trio-telemetry-v2-release-build-final.log`。

## 尚待完成的生产验收

本次未获授权向生产端点发送请求，或检查、写入远程 D1，因此这些操作均未执行。生产环境冒烟测试与正式发布后的验证仍待完成。

Worker / dashboard 部署源码修改，以及与本功能无关的 SwiftUI / XCTest 架构迁移，不属于本次实现范围。
