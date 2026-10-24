# Swift 工具链 CI 兼容性与失败记录

本文记录 Status Trio 在 GitHub Actions 上发布时遇到的工具链兼容问题，以及后续开发和发布必须遵守的规则。

## 结论

正式发布工具链已迁移到 `xcode-27` runner / Xcode 27 / 匹配 SDK。本机当前也是
Xcode 27 / Swift 6.4，但本机工具链、release runner 和 GitHub Actions 的实际
安装仍须分别核验，不能只用本机 `swift test` 证明 release workflow 可发布。

下文 2026-09-19 之后、迁移前的记录发生在 `macos-26` / Xcode 26.6 /
Swift 6.3.3 上；它们保留为历史兼容证据，不代表当前 release runner。
2026-09-19 之前的记录则发生在更旧的 `macos-15` / Xcode 16.4 /
Swift 6.1.2 上。

`isolated deinit`、`weak let`、`Bundle.module` 资源布局、IRGen 崩溃这些具体
症状属于旧编译器，而由它们归纳出的规则至今有效。

## 1.7.1 非发布预检：系统符号与测试采样（2026-10-23）

预检 [`39809532587`](https://github.com/lingyired/status-trio/actions/runs/39809532587)
在测试阶段失败；加入原始像素诊断后的
[`39817193272`](https://github.com/lingyired/status-trio/actions/runs/39817193272)
与独立符号探针
[`39819697604`](https://github.com/lingyired/status-trio/actions/runs/39819697604)
进一步缩小了原因。这些失败 run 没有生成安装包。

- 电池按钮测试原来跟随屏幕倍率。1x 采样把墨迹中心量化到半点，无法可靠验证
  0.25pt 断言；本机显式改成 1x 后复现 CI 的 `29.5 != 29.0`。测试现在固定
  SwiftUI displayScale 和截图倍率为 2x，保留 0.25pt 精度；临时把齿轮偏移
  0.5pt 会使断言失败。修复后两个后续 CI 的 XCTest 1911 项均无失败。
- 静态图标指纹只在 Wi-Fi 区域有 143 个不同像素，电池环和音量像素完全一致。
  本机与 CI 都是 macOS 27.0.1（26A434）、Xcode 27 / Swift 6.4，但 38pt
  `wifi.slash` 在本机 2x 屏幕上的布局尺寸为 `50x47`，6x 墨迹边界为
  `[24,38,272,252]`、水平补偿 `-0.25`；CI 1x 屏幕分别为 `51x46`、
  `[24,38,277,246]`、`-1/3`。两边的独立 AppKit 探针都与各自生产图标的
  Wi-Fi 像素逐一相同。禁用 NSImage 缓存后两边仍不相同，因此不修改生产缓存
  或绘制路径。旧测试只有 macOS 26 CI 和 macOS 27 本机的基线，缺少新的
  macOS 27 CI 符号变体。
- 指纹现在根据系统版本与独立取得的符号布局尺寸选择唯一精确哈希：macOS 27
  `50x47` 对应 `e08ab4...`，`51x46` 对应 `377721...`；macOS 26 保留
  `9dcba3...`。未知变体直接失败并输出原始像素及符号边界。各环境不再共享一个
  可任选其一的哈希集合，Issue #30 的独立墨迹与完整合成居中断言保持原样。
- 后续 macOS 26.6.2 runner 暴露出同一 26 系统的另一个精确变体：38pt
  `wifi.slash` 布局为 `50x46`，完整图标指纹实测
  `a89b29044ab04205b8c1c12265bc5ad6e22f8384832436ca48a2d3934f17aaa9`。
  基线选择改为按系统版本和独立符号尺寸精确匹配该值；该用例在校验前已明确
  报出原有基线不匹配，未知尺寸仍会失败。
- 双通道 PR 预检 [`40103971193`](https://github.com/lingyired/status-trio/actions/runs/40103971193)
  的 Store 通道通过，Direct 通道在 full 套件退出 1。`PanelActionAlignmentTests`
  测得控件中心 `25.5`，而同一行的 slider 内容中心为 `27.0/27.5`：该测试仍
  跟随 headless runner 的 1x 捕获，未使用相邻 Battery 布局测试已有的固定 2x
  采样；现在同时固定 `displayScale` 和 bitmap 倍率。2x 离屏 bitmap 的最外
  一像素列/行是未绘制边缘，扫描会把它误判为横贯整行的墨迹；探测现在排除该
  边缘，并只从 Input 行选择窄 action glyph，避免下方无设备行遮盖按钮。
- 同一 Direct 运行的
  `processExecutorKillsAChildThatIgnoresTermination` 在 2.595 秒后失败。断言把
  Task 排队时间算进了“期限后 1 秒内完成”的上界；该测试从 PID 文件出现时开始
  计上界，同时保留原先至少 1.2 秒的下界，证明 1 秒 deadline 与 kill grace
  确实经过，而非提前结束。
- 下一次 Direct 预检 [`40105290055`](https://github.com/lingyired/status-trio/actions/runs/40105290055)
  的 Store 通道通过，Direct 仍在同一个 volume 行失败。固定 2x 后，断言的 Mute
  读数实际来自 `minimumX: 200` 截出的 `40%` 文本，而 `controlRowCenterY` 又把
  slider 轨道和背景并入了行中心，所以它从未比较真正的 Mute/Settings。测试改为
  选取首尾两个 24 pt action glyph，并以 `VolumeControlScrollTarget` 的 AppKit
  frame 中心作为 slider 行中心；生产布局未因该测试缺陷而偏移。
- 本地完整测试另暴露了进程 fixture 的冷 Python 启动可能耗尽就绪期限。改为
  `/bin/sh` 先安装忽略 TERM 的 trap、写 PID，再进入工作循环；取消、超时、
  SIGKILL 和耗时断言保持原样，失败时停止读取不存在的 PID 文件。
- [`39821223609`](https://github.com/lingyired/status-trio/actions/runs/39821223609)
  已通过完整 Swift 测试，但在 `test-mobile-battery-source-cache.sh` 退出 128：
  fixture 把提交推到 `main`，裸仓库的默认 HEAD 却依赖宿主 Git 配置。本机
  默认 `main` 掩盖了问题，默认 `master` 时克隆没有可检出的 HEAD。本地用
  进程级 `init.defaultBranch=master` 复现同一错误；两个临时仓库现在显式以
  `main` 初始化，并在初始化命令中刻意提供相反默认值，持续覆盖这种宿主差异。

随后 [`39822549809`](https://github.com/lingyired/status-trio/actions/runs/39822549809)
通过 Swift 测试和 source-cache 检查，在公证模拟夹具中暴露另一种继承环境：
CI 导出的 `TAG=v1.7.1` 与 fixture 的 `VERSION=1.0` 不匹配，使其在 Sparkle
密钥断言前退出。本地带相同环境可复现；fixture 的 wrapper 调用现在显式传入
`TAG=v1.0`，并始终在父环境注入不匹配的测试 Tag，避免本机空环境再次掩盖问题。
后续本地完整验证同时注入 CI 的版本、Tag、candidate 和默认分支环境。

[`39824152450`](https://github.com/lingyired/status-trio/actions/runs/39824152450)
通过上述检查后，在 clang 版本捕获的旧管道控制实验失败：期望 SIGPIPE 141，
实际退出 1。本地让 Python 保留被忽略的 SIGPIPE 状态再启动脚本，可确定性复现。
非交互 Bash 不能用 `trap - PIPE` 重置启动时已被忽略的信号；模拟 clang
现在使用显式恢复 `SIG_DFL` 的小型 C 生产者。旧管道 141、真实版本探针成功、
生产者失败码 23 与空错误输出等断言均保留，并验证默认和继承忽略两种信号状态。

这些是测试环境和 fixture 修复，不代表签名、公证、Universal 安装包或真实
macOS 13 / Dock 交互验证；交付仍须以最终候选的成功 CI 与安装包核验为准。

## 新子系统的预检证据

首个特权 helper（issue #72 低电量模式）加入了一个新的 SwiftPM executable target
（`StatusTrioPowerHelper`）、一个 LaunchDaemon property list，以及构建变体开关
`PRIVILEGED_HELPER`。非发布预检
[`38067773966`](https://github.com/lingyired/status-trio/actions/runs/38067773966)
（head `4c3daf00`、`version=1.6.0`、`build=25`、`publish=false`、`notarize=false`）在
CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）上全绿，耗时 15m27s：

- `Run tests` 通过（1,439 XCTest、7 skipped、0 failures；554 Swift Testing / 88 suites）。
- `Run native compatibility tests` 通过，含新增的
  `scripts/test-privileged-helper-bundle-contract.sh`（`privileged helper bundle-contract regressions passed`）。
- Universal release 构建产出 `StatusTrioPowerHelper` 的 `x86_64 arm64` 双架构切片，
  `LC_BUILD_VERSION` 为 `minos 13.0 / sdk 26.0`，`Privileged helper bundle verified: x86_64 arm64`。
- 该预检 `publish=false` 且 `notarize=false`，因此走 Ad-hoc 签名，构建打印了预期警告
  （“bundled but Ad-hoc signed”）；Apple 锚定的客户端 requirement 在 Ad-hoc 下无法满足，
  运行时 XPC 往返与真实 `pmset` 写入必须在 Developer ID 签名并安装到 `/Applications` 后手工验证，
  见 [privileged helper](privileged-helper.md)。未创建 GitHub Release，也未更新 appcast。

本机同一 head 上 `swift test` 与 `swift build -c release` 均通过；
`PRIVILEGED_HELPER=0` 变体构建验证了 helper 与 LaunchDaemon plist 被排除且
`STIncludesPrivilegedHelper=false`。

#72 的后续修复（helper 在 app 退出后不退出：daemon 现在自己管生命周期，见
[privileged helper](privileged-helper.md) 的 Idle exit）走了同一条预检路径。非发布预检
[`38328318162`](https://github.com/lingyired/status-trio/actions/runs/38328318162)
（head `85247588`、`version=1.6.0`、`build=26`、`publish=false`、`notarize=false`）在 CI
工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）上全绿，耗时 11m40s：

- `Run tests` 通过（1,471 XCTest、7 skipped、0 failures；563 Swift Testing / 89 suites）。新增的
  测试 target `StatusTrioPowerHelperTests` 在 CI 上正常编译并参与运行：SwiftPM 会把
  executable target 链进测试 bundle，`main.swift` 的顶层代码不会执行，因此 `swift test`
  里 daemon 不会真的启动（本机与 CI 同样的行为，日志可见 `Emitting module
  StatusTrioPowerHelperTests`）。
- `Run native compatibility tests` 通过，含更新后的
  `scripts/test-privileged-helper-bundle-contract.sh`（新增“缺少 `ThrottleInterval` 的 plist
  必须被拒绝”的负例）。
- Universal release 构建产出 `x86_64 arm64` 双架构切片，`Privileged helper bundle verified: x86_64 arm64`；
  新增的 `ThrottleInterval=1` 断言随 `verify-privileged-helper-bundle.sh` 一起通过。
- 该预检 `publish=false` 且 `notarize=false`，仍走 Ad-hoc 签名（构建打印 “the privileged helper is
  bundled but Ad-hoc signed”）。未创建 GitHub Release，也未更新 appcast。

本机同一 head 上 `swift test`（1,461 XCTest、7 skipped、0 failures；563 Swift Testing / 89 suites）
和 `swift build -c release` 均通过。helper 的运行时行为不在 CI：daemon 的退出时序在 macOS 27 上用
等价的 user LaunchAgent 手工测量（`MachServices` job 空闲时 launchd 不会停它，加
`EnableTransactions` 也不会），测量方法与结果记在 [privileged helper](privileged-helper.md)。

## 失败记录

| Run | 失败阶段 | 根因 | 修复方式 |
| --- | --- | --- | --- |
| [`37816211317`](https://github.com/lingyired/status-trio/actions/runs/37816211317)（head `5c4e6fc`，`1.5.1` / build 23，`publish=false`） | `Run tests` | `ForbiddenPatternGuardTests.testSourcesContainNoActorIsolatedMethodReferences` 把 `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift:390` 的 `using: read` 转发闭包参数误报为方法引用；该源文件未在失败提交中改动。`is_forwarded_closure` 使用 `sed | grep -qE`，命中后 `grep -q` 提前退出，在 `set -o pipefail` 下可能让仍在输出大文件的 `sed` 收到 SIGPIPE（141），使真实声明查找返回假阴性。| 将 `grep -qE` 改成会完整消费输入的 `grep -E … >/dev/null`，保留 `pipefail` 和原匹配语义；`--self-test` 新增超过 2 MB 的早期匹配 forwarded-closure fixture，验证其仍为 `external`。本地红测在修复前稳定误报；修复后 `bash scripts/check-forbidden-patterns.sh --self-test`、正常扫描及 `swift test --filter ForbiddenPatternGuardTests` 均通过（2 tests、0 failures）。后续非发布预检 [`37819064891`](https://github.com/lingyired/status-trio/actions/runs/37819064891)（head `7bc0aa9`、`version=1.5.1`、`build=23`、`publish=false`、`notarize=false`）全绿：测试、原生兼容性检查、Universal release 构建、Ad-hoc 签名、DMG 打包与 artifact 上传全部通过。未创建 GitHub Release，也未更新 appcast。 |
| [`37768863227`](https://github.com/lingyired/status-trio/actions/runs/37768863227)（job `113283127466`，main `25555649a76dd6e3138c0548556eeae95a87577e`） | `Build, sign, notarize, and publish`，exit `141`（SIGPIPE） | **CI 观察（2026-10-08）：** early signing smoke 与全部测试通过；最后日志是 arm64 libimobiledevice `make install` 成功，之后没有 helper package 或 `LC_BUILD_VERSION` 消息，build/sign stage 以 `141` 退出，而非 identity error。**本地确定性证据：** `scripts/build-mobile-battery-helper.sh` 在每个 architecture iteration 的 build-key probe 中用 `clang --version \| head -n 1`；Bash 3.2 的 `set -euo pipefail` 下，synthetic clang 输出超过 pipe capacity 的多行文本，稳定使原 production probe 因 reader 提前关闭而以 `141` 退出。该测试证明此代码有 SIGPIPE 缺陷；CI 没有逐命令 trace，不能断言本次退出一定发生在第二个 architecture 的该行。 | 仅将 version probe 改为完整捕获 producer stdout，再用 shell parameter expansion 提取首行；不关闭 pipefail，不用 `\|\| true`，保留真实 compiler failure。新增 `scripts/test-mobile-battery-clang-version.sh`：原 probe red exit `141`，修复后保留首行并成功，producer exit `23` 仍传播。early smoke 成功只证明 disposable binary 可签署，**不证明 actual bundled component 签署、notarization 或 artifact 产出成功**。后续 runner 验证仍需经人工批准的 `publish=false, notarize=true` run；本次未触发 CI。 |
| [`37765619584`](https://github.com/lingyired/status-trio/actions/runs/37765619584)（job `113272443035`，`codex/ci-notarized-test-build`） | `Build, sign, notarize, and publish`，首次签署 bundled component | **CI 观察：** 测试、native helper、universal build 均通过；Developer ID signing 配置从显式临时 keychain 找到 identity，Apple notarization 配置也成功；首次 bundled component 签署时报 `Developer ID Application: …: no identity found`。本次证据不能单独证明缺少 user search-list registration 就是该错误的根因。**有依据的排查假设：** workflow 创建并导入临时 keychain，但此前未将它加入 user search list；`codesign --keychain` 指定 identity lookup keychain，并不替代证书链查找所需的 search-list 配置。GitHub 的 [Xcode signing 指南](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)也显式将临时 keychain 加入该列表。 | workflow 保存原 user search list，将临时 keychain 加到首位并保留原 entries；build 前复制 `/usr/bin/true` 到 runner temp，用默认 search-list 路径执行 codesign 与 verify，失败即停止。always-run cleanup 独立尝试还原原列表与删除临时 keychain，即使还原失败也不会跳过删除。新增 fixture 覆盖列表保留、smoke sign 顺序/失败关闭、凭据日志脱敏及 restore 失败时仍删除。`scripts/test-release-notarization.sh` 本地通过；修复是否解决 CI 签署错误仍待新的 `publish=false, notarize=true` runner 验证，未触发该 run。 |
| [`37760229583`](https://github.com/lingyired/status-trio/actions/runs/37760229583) attempt 1（`codex/ci-notarized-test-build`，head `387ac294198ea0c5729e10982c2d2d86443c3977`） | `Run tests` | **CI 观察：** Swift Testing 570 tests、1 issue：`AppIconControllerTests.sliderBurstRepaintsTheDockIconOnce` 在原第 309 行读到 `renderCount == 1`，期望 `0`；Developer ID signing / Apple notarization 配置步骤成功跳过。**本地确定性证据：** 测试用 ring-style 变更预热 coalescer 后只清空日志，隐含假定 threshold 循环耗时小于 50 ms；coalescer 使用真实 `Date()`，超过间隔时按设计立即重绘。在 threshold 35 前加入 60 ms 同步暂停可稳定复现同一断言，未改变生产逻辑。CI 没有该循环的耗时日志，因此不声称已量出本次 CI 的具体调度时序。原 workflow 提交未改动 `Sources` 或 `Tests`，这一事实本身不证明 flaky。 | `AppIconController` 仅增加可选 coalescer 注入，默认仍使用原实现；该测试使用固定时钟和受控 sleeper，保留 release 前 `0`、release 后恰好 `1` 及 final critical scene 断言，并要求确实调度了尾部重绘。本地 red/green 日志见下文；完整本地测试与 release build 已通过（见下文）；CI 验证仍待进行。没有再重跑 CI，不声称 CI 已修复或已发布。 |
| [`37760229583`](https://github.com/lingyired/status-trio/actions/runs/37760229583) attempt 2（job `113258378754`，同一 head `387ac294198ea0c5729e10982c2d2d86443c3977`） | `Run tests` | **CI 观察：** XCTest 1,382 tests、7 skipped、1 failure：`MobileBatteryControllerTests.testMissingWatchRetryBudgetSurvivesRepublishedDemandAndBackgroundToggle` 原第 416 行 `configuredRefreshRequests` 实际 `0`、期望 `1`；Swift Testing 570 tests 全通过，含 attempt 1 的 Dock 测试。**本地确定性证据：** 测试用真实时钟却只匹配 `.seconds(600)`，实际 scheduler 从 full-refresh deadline 扣除已经过去的时间。注入可控时钟并推进 1 秒，可复现 600 秒请求计数 `0`，同时断言实际 599 秒请求计数为 `1`；这不只是轮询不够久。三个 controlled-sleeper wait helpers 原本在 1,000 次 yield 后无条件返回，缺失请求的回归测试确定性产生三个失败，证实其隐藏了同步失败。CI 未记录具体 requested duration，因此不能断言该次 CI 恰好请求 599 秒。 | retry-budget 测试固定时钟，保留原精确计数；新增推进 1 秒的 599 秒 deadline 场景，同样覆盖 retry cap、背景开关及重新授权。仅该测试文件的三个 sleeper waits 改为有 5 秒 deadline 的条件等待并在超时抛错，调用处用 `try await`；不更改 MobileBatteryController 或 scheduler 生产行为。本地 red/green 日志见下文；完整本地测试与 release build 已通过（见下文）；CI 验证仍待进行。没有盲目重跑 CI。 |
| [`37416172832`](https://github.com/lingyired/status-trio/actions/runs/37416172832)（PR #93，head `27cc07cadbcae8a969b1140508a6899d7a06fbde`） | `Run tests` | `DDCVolumePresentationTests.testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately` 在 `VolumeMonitor.topologyChanged()` 后读取异步 `MonitorStream` 的下一项时，仍观察到先前已确认的 DDC 音量 `0.75`：scalar、current-device volume、canSetVolume 与 current output-device row volume 四项断言失败。run 中 1,158 个 XCTest 有 4 failures、6 skipped；其余 519 个 Swift Testing tests passed。版本/appcast、Xcode 26.6/macOS 26.6.2 runner setup 均通过；后续 build/sign/package 因 tests step 失败而跳过。此为产品/测试时序行为，不是编译、签名或 runner 环境失败。 | 本失败 run 的 head 上未实施修复，故不声称该 SHA 已修复。后续 head `db2bdb4` 的完整本机 `swift test`（1,164 XCTest、6 skipped、0 failures；540 Swift Testing / 88 suites）通过；PR #93 非发布预检 [`37490195329`](https://github.com/lingyired/status-trio/actions/runs/37490195329) 在相同 DDC 测试上通过 `Run tests`，并完成 macOS 26/Xcode 26.6 build/sign/DMG 与 artifact upload。该预检 `publish=false`，Release/appcast 发布跳过。父会话安排的独立只读 review 仍作为 merge 前 review gate；本次未更改产品代码。 |
| `34753548674` | `Run tests` | `isolated deinit` 在 Swift 6.1.2 需要实验开关，默认不可用 | 移除 `isolated deinit`，改为普通 `deinit` 和显式清理 |
| `34753630833` | `Run tests` | 尝试启用 `IsolatedDeinit`，生产编译器不允许 | 不依赖该实验特性，直接改写生命周期清理 |
| `34753843803` | `Run tests` | 测试中的 `weak let` 在 Swift 6.1.2 非法 | 改为 `weak var` |
| `34753912541`、`34754021368`、`34754087160` | `Run tests` | `Bundle.module` 在 CI 中的 `lproj` 资源布局/大小写与本地不同 | 使用路径查找并同时尝试标准名和小写名 |
| `34758026894` | `Run tests` | Swift 6.1.2 IRGen 在处理 `Binding.set: localization.setPreference` 方法引用时崩溃 | 改写为显式闭包，避免触发 thunk 代码生成 |
| `34758129632` | 全部通过 | 1.0.1 / build 2 发布成功 | 保留上述兼容性修复 |
| `35293247382` | `Run tests` | 测试用 `drainMainActorTasks()` 假定 `AsyncStream` 消费任务一定已完成；CI 调度较慢时仍读到更新前的 `currentDevice` | 测试改为有超时上限地等待目标状态，不再依赖单次主线程排空；后续预检 `35293533279` 全部通过 |
| `35307956823` | `Upload release artifacts` | runner 向 GitHub artifact 服务建 artifact 的请求超时（`Failed to CreateArtifact: Unable to make request: ETIMEDOUT`），发生在编译、测试、打包全部成功之后 | 与代码和工具链无关，无代码改动；重跑同一 run 的失败 job 后全部阶段通过 |
| `35316867111` | `Run tests` | 新增的图标合并重绘测试在断言前固定 `Task.sleep(200ms)`；Swift Testing 会同时启动整轮测试，CI 上主 actor 被排满的时间超过该固定等待，coalescer 的尾部重绘还没执行 | 测试改为轮询目标状态（5 秒上限，命中即返回），不再依赖固定睡眠；后续预检 `35317347672` 全部通过 |
| `35375443023`（fork 非发布预检） | `Build, sign, notarize, and publish` | 使用 `version=1.2.1`，但仓库没有 `release-notes/1.2.1`；前置校验允许非发布时跳过，`scripts/release.sh` 仍要求该目录存在。Swift 6.1.2 测试已通过，尚未进入 release 构建 | 保持音频代码提交 `55983e2` 不变，改用已有说明的 `version=1.2.0`、递增的 `build=10`、`publish=false`；后续预检 `35375769964` 的测试、通用 release 构建、DMG 打包和 artifact 上传全部通过 |
| `35447073294` | `Run tests` | `SettingsRowHitAreaTests.testPreferenceCheckboxRowUsesFullRowHitArea` 失败（`got [14.0]`）。该测试把 `NSHostingView.subviews` 当作命中区代理；macOS 26 SDK 把 `.checkbox` 样式的 `Toggle` 画成 14×14 的 AppKit `Checkbox` 加一个 SwiftUI 标签，脱离窗口时不存在任何全宽子视图。旧工具链（Xcode 16.4）与本机 macOS 27 都会生成全宽 `_FocusRingView`，所以失效的是探针的假设，不是产品行为 | `interactiveSubViewSizes` 改为先把行放进已 `makeKeyAndOrderFront` 的 `NSWindow` 再测量：窗口的 key-view proxy 在 macOS 26 上正好是 300 pt 宽；后续预检 `35448004467` 通过 |
| `35447273818` | `Run tests` | 同一根因的诊断复现（临时 dump 视图树以取得 macOS 26 上的实测尺寸与类名） | 同上 |
| `35447521372` | `Run tests` | `AppIconControllerTests.visibleDockRendersStatusChanges`（Swift Testing）偶发失败：`renderCount → 0`，期望 `1`。上一版修复在探针里调用了进程级的 `NSApplication.shared.setActivationPolicy(.accessory)`，改变了其他测试判断 Dock 是否可见的前提 | 从 `interactiveSubViewSizes` 移除该调用，只保留窗口，并在 `defer` 里 `orderOut` 加清空 `contentView`；后续预检 `35448004467` 通过 |
| （本轮，非失败记录） | `swift build --build-tests` | 本机 Xcode 27 / Swift 6.4 对四处测试里的 `weak var weakMonitor` 报 `weak variable ... was never mutated; consider changing to 'let' constant`。编译器的建议是 `weak let`，但 `AGENTS.md` 明令禁止该写法，且没有证据表明 CI 的 Swift 6.3.3 接受它 | 不采用 `weak let`。把这四处改成 `Tests/StatusTrioCoreTests/DeinitProbe.swift` 里的 `DeinitProbe.track(_:)`，弱引用以 `weak var` 存储属性保存（写法仍满足规则），断言内容与顺序不变 |
| `35614298374` | `Run tests` | 新增的 `BluetoothSummaryTests.testDevicesWithoutALevelKeepTheirNameOnly` 断言了 `机灵的耳机` 与 `MX Keys` 拼接后的先后。摘要行按系统 collation 排序，而 ICU collation 与语言有关：CI runner（英文）把 `MX Keys` 排在前，开发机（中文）把中文名排在前。本地 `swift test` 与 `swift build -c release` 全绿，所以失效的是断言（对混合脚本排序的假设），不是产品缺陷 | 把排序规则改成「AirPods 无条件最前、其余按名称」（`BluetoothDevicePresentation.grouped`），断言不再依赖 collation；后续预检 `35615262052`（`build=24`）全绿 |
| `35718713396`（1.3.0 正式发布，`build=13`） | `Build, sign, notarize, and publish` 末尾的 appcast 发布回读（`scripts/release.sh`） | 测试、构建、签名、DMG、Release 上传、appcast 提交（`8519984`）全部成功后，PUT 完成仅 2 秒即用 Contents API 回读 `appcast.xml?ref=main`，撞上 GitHub Contents API 的最终一致性窗口，读到旧 blob 而误报 `published appcast does not contain build 13`。与工具链、代码、说明文件无关 | 回读改为带退避的重试（最多 6 次、间隔 5 秒），重试全部用尽才失败；已手动回读远端 appcast 确认 build 13 条目完整（12 titles + 12 descriptions、en 首位、edSignature 与 DMG 长度 4244534 一致），1.3.0 发布四项核验通过；重试逻辑经桩测（stale→stale→fresh 通过、恒 stale 失败并退出 1）验证，详见文末专节 |
| `35876435136` | `Run tests` | `AppIconControllerTests.sliderBurstRepaintsTheDockIconOnce`（Swift Testing）偶发失败：`renderCount → 1` 期望 `0`（`harness.log.batteryOptions.last?.criticalThreshold → 33` 期望 `40`）。该测试模拟把 `batteryCriticalThreshold` 从 25 连续设到 40（滑块拖动），断言合并成一次尾部重绘且携带终值 40。Swift Testing 把整轮测试并行启动，runner 负载高时 `iconAppearancePublisher` 的逐次发射与 `currentAppearance` 更新被排到与存储值不同的时点，合并器的尾部重绘在 `currentAppearance` 还没推进到 40 时就抢先执行，抓到一个中间值。本机 Xcode 27 / Swift 6.4 与 CI 的 Xcode 26.6 / Swift 6.3.3 都跑这套合并逻辑，且本机 `swift test` 769/0 全绿，所以失效的是测试对「同步循环里的 16 次发射一定先于尾部重绘落地」的假设，不是产品缺陷，也与本轮蓝牙改动无关（蓝牙分支未触碰 `AppIconController` / `IconRenderCoalescer` / 电池 publisher） | 重跑同一 `version=1.3.3`、`build=16`、`publish=false` 的非发布预检 [`35877626348`](https://github.com/lingyired/status-trio/actions/runs/35877626348)：`Run tests` / `Build, sign, notarize, and publish` / `Upload release artifacts` 全绿，确认是偶发而非回归。该测试属时序敏感家族（见 `35316867111`、`35447521372`）；若日后还要根治，需让突发写入在 MainActor 上落地后再断言，不要据此误判蓝牙改动 |
| `36332229393` | `Build, sign, notarize, and publish` | 蓝牙图标来源预检用 `version=1.4.0`，但仓库没有 `release-notes/1.4.0`：`scripts/validate-appcast-notes.sh` 在非发布时允许目录缺失并跳过校验（日志里只有一条 `::notice::`），`scripts/release.sh` 却在第 144 行硬性要求该目录存在，于是直接 `exit 1`。这是 `35375443023` 的同一模式复发，不是代码或工具链问题——Swift 6.3.3 的 `Run tests` 已通过，尚未进入 release 构建 | 不改动蓝牙代码（`0651799`），改用已有说明文件的 `version=1.3.3`、递增的 `build=17`、`publish=false` 重跑预检 [`36332507137`](https://github.com/lingyired/status-trio/actions/runs/36332507137)：`Run tests`、通用 release 构建/签名、`Upload release artifacts` 全绿（4m43s）。**发布 1.4.0 前必须先补 `release-notes/1.4.0/`（`publish=true` 需要全部 12 种语言）**，否则预检会以同一方式失败 |
| [`39286678415`](https://github.com/lingyired/status-trio/actions/runs/39286678415)（head `44b3e06`，Dock 充电动效预检） | `Build, sign, notarize, and publish` | 使用 `version=1.6.2`，但仓库没有 `release-notes/1.6.2`。`Run tests`（XCTest 1,657 / 7 skipped / 0 failures，Swift Testing 647 / 99 suites）与 `Run native compatibility tests` 已通过；`scripts/release.sh` 在版本解析后直接报 `release notes directory does not exist`，尚未进入 release 构建。与 `35375443023` / `36332229393` 是同一门槛 | 不改产品代码，改用已有说明目录的 `version=1.6.1`、递增的 `build=2026102001`、`publish=false` 重跑预检 [`39287740763`](https://github.com/lingyired/status-trio/actions/runs/39287740763)：`Run tests`、原生兼容性测试、Universal release 构建/签名、DMG 打包与 artifact 上传全绿（13m53s），未创建 tag、Release 或 appcast 更新 |
| （本地，非失败记录） | 本机 `swift test` | 新加的 `VolumeFeedbackTests.preferenceTreatsAMissingKeyAsEnabled` 想用 suites 断言「键不存在时按开启处理」，而 `UserDefaults(suiteName:)` 的搜索链在 suite 域之后仍会落到 `NSGlobalDomain`：全新 suite 读到的是本机 `com.apple.sound.beep.feedback`。开发机把这个开关关成 `0`（0 = 关）之后该测试即失败，CI runner 上（该键缺失）却一直是绿的——失效的是测试对「suite 隔离」的假设，不是产品行为 | 把判断拆成纯函数 `SystemVolumeFeedbackPreference.isEnabled(storedValue:)`，「缺失按开启」由它覆盖，suite 只留给显式写值的用例；顺带给两个未注入 feedback 播放器的既有 store 测试补上假播放器，免得在开关打开的机器上跑测试时真的出声。后续预检 `35851597428` 全绿 |
| `36396172842` | `Run tests` | #30 的 Wi-Fi 居中修复把 SF Symbol 的锚点从 `canvas.midX`（60.0）改为 `artworkCenterX`（59.5），`ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint` 记录的静态像素基线随之改变。该用例的 `staticSnapshot` 是 `wifi.state = .off`，走 `drawOfficialSymbol(name: "wifi.slash")` 的默认 `center: wifiSymbolCenter` 分支，因此像素必然变化。本机 macOS 27 的实测新指纹为 `0ef6d48…`，但 macOS 26 CI runner 的对应值无法在本地推导，预检如实报出 `9f0c892…` | 按平台分别把基线更新为实测值：macOS 26 CI 用 `9f0c892e2602f4d4f9c541be1d93963e14d46e76f3ef24b46cd2dfbc25a22d1d`，macOS 27 本地用 `0ef6d483e344f6056fa3799f9f33bac0092246e3dbfbb3619a4666d7e9e9c190`（**替换**而非追加旧值，否则旧缺陷像素仍会被接受，守卫失效）。该失败是修复的预期效果，不是回归；同一次 run 中 380 个用例里只有这一项失败，说明新的 #30 断言在 CI 工具链上全部通过 |
| `37936045929` | `Run tests` | #30 在 2026-10-09 于 v1.5.1 复发：此前只把 SF Symbol 的锚点从 `canvas.midX`（60.0）改到 `artworkCenterX`（59.5），但对齐的是 `NSImage.size` 的布局框。`wifi` 的可见墨迹并不在布局框中心，默认 60.8pt 时墨迹 bbox 中心比框中心左偏约 0.344pt；框居中后墨迹仍落在约 59.16，用户看到的还是偏左。修复改为测量并补偿符号墨迹的横向 side bearing，`ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint` 的静态像素随之变化。本机 macOS 27 实测新指纹为 `1930db1…`，macOS 26 CI runner 的对应值无法在本地推导，预检如实报出 `9dcba31…` | 按平台分别替换静态基线：macOS 26 CI 用 `9dcba3184f0953f8c173cc2f846977f01b84510a8505166bd6a8048f44d8fd97`，macOS 27 本地用 `1930db19c8a2f14400b25cf8f9228320b3d2bb9eb3f3360f93cc1e9ae8b1bf52`；旧值不能追加保留，否则修复前的偏左像素仍会被接受。该失败是预期像素变化，不是回归。同一次 run 的其他用例全绿；随后以同分支 head `4b255e5`、`version=1.5.1`、`build=25`、`publish=false` 重跑预检 [`37936688902`](https://github.com/lingyired/status-trio/actions/runs/37936688902)：`Run tests`、`Run native compatibility tests`、`Build, sign, notarize, and publish`（`publish=false`，未创建 GitHub Release、未更新 appcast）与 `Upload release artifacts` 全绿，耗时 14m48s；本机同 head `swift test` 为 583 tests / 91 suites 通过、`swift build -c release` 通过（见 `docs/issue-30-wifi-centering-analysis.md`） |
| `36649829624`（#79 听音模式非发布预检） | `Run tests` | `OutputDeviceListeningModeRowTests.testInFlightCapsuleDrawsASpinnerNormally` 断言 `("0") != ("1")`：它数 `NSHostingView` 里的 `NSProgressIndicator`，期望被点选、正在写入的那颗胶囊画出转圈。`BluetoothListeningModeControl.busyMark` 读 `@Environment(\.accessibilityReduceMotion)`——开启时画静态 `Circle`（无 `NSProgressIndicator`），关闭时才是 `ProgressView`。该环境键只读，测试 harness 无法注入，只能继承宿主设置：CI runner 默认开着 Reduce Motion（0 个 spinner），开发机没开（1 个），于是本地 `swift test` 397/0 全绿而 CI 失败。失效的是断言对宿主无障碍设置的依赖，不是产品行为 | 让断言与无障碍设置无关：用例改名 `testInFlightCapsuleRemainsItsOwnButton`，去掉 `row.spinners == 1` 这条环境相关断言，只保留「正在写入的胶囊仍是一个独立按钮」`row.controls.count == 4`；Reduce Motion 分支改由代码审查保证（同 `.accessibilityReduceMotion` 只读、无注入修饰符的既有约定）。同一次 run 其余用例全绿，无产品回归。后续以 `version=1.3.3`、递增 `build=18`、`publish=false` 重跑非发布预检验证 |
| `36681666541`、`36687697162`（#78 iPhone 电量非发布预检） | `Run tests` | 两次都是 `BluetoothListeningModeControllerLifecycleTests` 里等 `.failed` 的用例失败：第一次只有 `testFailedWriteRollsBackThroughAReRead`（2 秒期限，`BluetoothListeningModeControllerLifecycleTests.swift:117`），把期限放宽到 5 秒后第二次反而多了一个 `testUnconfirmedWriteRollsBackToObservedMode`（`…Tests.swift:125`，两条 `XCTAssertTrue(isFailed(...))` 也一并失败）。两次失败与期限长短无关，因为失效的从来不是等待时间，而是**能看见该状态的窗口**：`.failed` 会按 `failureClearDelay` 自动清除，而这个测试 helper 把它从产品默认的 2 秒压到 30 毫秒，`waitUntil` 却每 5 毫秒才轮询一次——runner 的主 actor 只要一次延迟超过 30 毫秒，整段 `.failed` 就被跳过，5 秒期限再长也等不到。`testUnconfirmedWriteRollsBackToObservedMode` 完全不涉及 OS 错误（后端接受写入、回读仍停在 NC），纯 Swift 逻辑必然发布过 `.failed`，所以只可能是没被观察到，不是产品行为改变。第一次的「期限不够」结论由此被推翻 | 把测试 helper 的 `failureClearDelay` 改成产品默认的 2 秒（新增 `Self.failureClearDelay`），使「状态存活多久」与「轮询多久看一次」不再互相错位；`waitUntil` 的 5 秒期限保留，但注释改回真实原因（它只是卡死写入的上界）。`swift test --filter BluetoothListeningModeControllerLifecycleTests` 13 项通过（2.24 秒，两条失败用例各等满 2 秒 linger）。后续以 `version=1.3.4`、`build=21`、`publish=false` 重跑非发布预检验证 |

| `36727668293`（#78 iPad 横版图标非发布预检） | `Run tests` | `AppIconControllerTests.sliderBurstRepaintsTheDockIconOnce` 再次偶发失败：`harness.log.renderCount → 1` 期望 `0`，且 `harness.log.batteryOptions.last?.criticalThreshold → 38` 期望 `40`。同一 run 里 1124 个 XCTest（6 跳过）与其余 438 个 Swift Testing 用例全绿，只此一项失败。与 `35876435136` 同根同症：该用例用同步循环连续发射 16 次阈值，假设尾部重绘必然读到终值 40，而 runner 负载高时尾部重绘会先于 `currentAppearance` 落地，抓到中间值 38。失效的是断言对发射顺序的假设，不是产品行为——失败提交 `5075e85` 只改 iPad 横版图标，不触碰 `AppIconController` / `IconRenderCoalescer` / 电池 publisher | 不改产品代码：该提交随后并入 `8a8157f`，同一工作流非发布预检 [`36728153620`](https://github.com/lingyired/status-trio/actions/runs/36728153620) 全绿。该用例属时序敏感家族（另见 `35316867111`、`35447521372`、`35876435136`），至此已在四个不同提交上偶发；若日后根治，需让突发写入在 MainActor 上落地后再断言，不要据此误判蓝牙改动 |
| [`39427610464`](https://github.com/lingyired/status-trio/actions/runs/39427610464)（head `d299548`，蓝牙 radio 开关非发布预检） | `Run tests` | `AppIconControllerTests.visibleDockRendersStatusChanges` 偶发失败：`renderCount → 0` 期望 `1`，5 秒内没有等到合并后的 Dock 重绘。此前 XCTest 与其余 Swift Testing 用例均通过；失败提交只改蓝牙 radio 开关，不触碰 `AppIconController`、`IconPresentationViewModel` 或 `IconRenderCoalescer`。该用例和 `35447521372` 同属依赖真实 `Task.sleep` 与主 actor 排程的时序敏感家族，不能据此判定蓝牙回归 | 不改产品代码；测试改用 `ManualIconPresentationScheduler` 明确推进快照 debounce，再调用 `flushPendingPresentationForTesting()` 排空 render coalescer，断言仍为“一次可见 Dock 重绘”；定向 `swift test --filter AppIconControllerTests.visibleDockRendersStatusChanges` 通过（0.096s）。随后重跑完整本地测试、release 构建与同一非发布预检，未创建 Release 或更新 appcast |
| [`39449643901`](https://github.com/lingyired/status-trio/actions/runs/39449643901)（head `ce8be20`，蓝牙 Quick Actions UI 非发布预检） | `Run tests` | 697 个 Swift Testing 用例中 18 个失败，集中在 `AppIconControllerTests`、`IconSurfaceIntegrationTests`、`DockChargingEnvironmentTests`、`SystemIconAppearanceMonitorTests` 和 `ChargingEffectControllerTests`；失败都是既有 2–5 秒时序等待超时，例如 `visibleDockRendersStatusChanges` 的 `scheduler.hasPendingAction`、`IconSurfaceIntegrationTests` 的 “surface update did not arrive”、`invokesPollHandlerUntilStopped` 的轮询次数不足。所有失败在约同一 5 秒窗口内集中记录，且失败提交只改蓝牙标题行与设置项，不触碰这些测试或其生产路径。本地同一 head 的 697 个测试、Release 构建及定向 `visibleDockRendersStatusChanges` 均通过，因此这是已知主 actor/并行测试调度家族的再次发生，不是蓝牙回归 | 本 UI PR 不扩大范围修改图标测试架构；先把该 run 记录为时序敏感失败，并以同一 Swift 代码 head `ce8be20`、`version=1.6.1`、`build=2026102004`、`publish=false` 重跑预检验证。若复发，后续需单独把仍在用真实 `Task.sleep`/`TestTaskIconPresentationScheduler` 的图标断言迁到手动时钟与显式排空，而不是继续放宽超时 |
| [`39451283618`](https://github.com/lingyired/status-trio/actions/runs/39451283618)（head `f2209af2`，蓝牙 Quick Actions UI 非发布预检） | `Run tests` | 同一组并行调度失败复发：12 个 issue，分别来自 `AppIconControllerTests`（3 个等待超时）、`IconSurfaceIntegrationTests`（6 个 surface 更新超时）、`DockChargingEnvironmentTests`（2 个 restore/scene 等待失败）和 `ChargingEffectControllerTests`（1 个 store 更新超时）；没有任何蓝牙断言失败。两次 run 的失败都集中在同一批 `@MainActor` 图标套件，说明继续重跑或放宽单测期限不能消除根因 | 在这 5 个共享主 actor、依赖 2–5 秒轮询的 Swift Testing 套件上添加 `@Suite(.serialized)`，让套件内测试顺序执行，避免 CI 同时启动大量主 actor 任务耗尽等待窗口；不改生产代码、不隐藏断言。修复后本机定向 72 个测试（5 个套件）用 4.72 秒全部通过，完整 `swift test` 的 697 个 Swift Testing 用例与 `swift build -c release` 均通过。后续非发布预检 [`39453350816`](https://github.com/lingyired/status-trio/actions/runs/39453350816)（head `065a678`、`version=1.6.1`、`build=2026102005`、`publish=false`）在 16m21s 内全绿：1,746 XCTest（7 skipped）、697 Swift Testing / 103 suites、native compatibility、Universal Release 构建、签名校验、DMG 打包与 artifact 上传均通过；未创建 GitHub Release，也未更新 appcast |
| [`39457652321`](https://github.com/lingyired/status-trio/actions/runs/39457652321)（head `be93f4de`，PR #124 HUAWEI 非发布预检） | `Run tests` | 4 个 Swift Testing 图标用例失败：`ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork`、`AppIconControllerTests.visibleDockRendersStatusChanges`、`AppIconControllerTests.ringStrokeStyleSurvivesOtherOptionChanges`、`AppIconControllerTests.connectionOptionChangeKeepsConfiguredWiFiSymbolScale`。同一 run 的 XCTest 1,769 项、7 skipped、0 failure，Swift Testing 697 项 / 103 suites 中为这 4 issues。旧测试依赖主 actor 上的真实调度和统一 5 秒 wall-clock deadline；runner 负载下快照 debounce、coalescer 尾部重绘或推进后的静态 artwork 未在期限内落地，不能判定 HUAWEI 传输逻辑回归 | 合并 main 的 #129 修复，在测试注入 `ManualIconPresentationScheduler`、`ManualEventSleeper` 和受控 charging clock，显式推进并排空待处理重绘；断言强度未降低，产品节流与 HUAWEI 写入/read-back 逻辑未修改。当前 head 本地 `swift test` 全绿（XCTest 1,759、7 skipped、0 failure；Swift Testing 697 / 103 suites），图标定向测试 66 项、`HuaweiTransportLifecycleTests` 15 项及 `Issue30WiFiAlignmentTests` 6 项均通过，`swift build -c release` 通过；仍需本节 head 的 `macos-26` / Xcode 26.6 / Swift 6.3.3 非发布预检验证 |
| （1.4.0 正式发布，`build=17`） | — | 非失败记录。发布前先补 `release-notes/1.4.0/` 全部 12 种语言（即 `36332229393` 的缺失目录门槛），本地 `scripts/validate-appcast-notes.sh` 在 `publish=false` 与 `publish=true` 下均通过（12 titles / 12 descriptions，en 首位） | 发布工作流 [`36739480903`](https://github.com/lingyired/status-trio/actions/runs/36739480903)（`version=1.4.0`、`build=17`、`publish=true`，head `2137675`）全绿：`Validate appcast notes`、`Run tests`（1124 个 XCTest（6 跳过，0 失败）与 438 个 Swift Testing / 72 suites 全绿）、`Build, sign, notarize, and publish`、`Upload release artifacts`。Release `v1.4.0`、tag `v1.4.0`、资产 `StatusTrio-1.4.0.dmg`（5520444 字节）与远端 appcast 的 build 17 条目（12 titles + 12 descriptions、en 首位、edSignature 与 DMG 长度一致）均已核验。本仓库仍无 Developer ID 证书与公证密钥，实际为 Ad-hoc 签名 |

> **本轮结束时构建不是零警告：** 上面的修复只清掉了 `weak var` 那 4 条 `WeakMutability` 和 Task 1 的 1 条 `String(cString:)`，共 5 条；剩下 **2 条**警告是 `WiFiPasswordStore.swift` 的 `kSecUseAuthenticationUIFail` / `kSecUseAuthenticationUIAllow` 弃用，属于 R-12（Keychain 加固）计划，class B，尚未开始。不要把本轮记录读成「构建已经干净」。

## 37760229583：本地同步回归验证（2026-10-08）

上述两次 CI 尝试的失败事实来自 run 报告；以下是同一 worktree 的本地控制变量验证，不替代 `macos-26` / Xcode 26.6 / Swift 6.3.3 CI 验证。本机 Swift 为 6.4。没有提交、推送、再次派发 CI、合并或发布。

- `/tmp/status-trio-sync-20261008/red-clock.log`：在原断言保留的情况下，Mobile 时钟推进 1 秒后 600 秒计数 `0 != 1`（同时 599 秒计数 `1` 的断言通过）；Dock 在 threshold 35 前同步暂停 60 ms 后 `renderCount` 为 `1 != 0`。临时暂停已移除。
- `/tmp/status-trio-sync-20261008/red-sleeper.log`：旧 wait 实现对三个未发生的条件都静默返回，新增 timeout 回归测试产生 3 个失败。改用 deadline + 抛错后，该测试通过。
- `/tmp/status-trio-sync-20261008/targeted-green.log`：`swift test --filter 'AppIconControllerTests|MobileBatteryControllerTests|IconRenderCoalescerTests'` 通过：36 XCTest tests、0 failures；28 Swift Testing tests、0 issues。包含 600 秒固定时钟和推进 1 秒后 599 秒的两个 retry-budget 场景。
- `/tmp/status-trio-sync-20261008/full-test.log`：完整 `swift test` 通过：1,384 XCTest tests、7 skipped、0 failures；570 Swift Testing tests / 90 suites 全通过。没有新增 skip 或删除断言。
- `/tmp/status-trio-sync-20261008/release-build.log`：`swift build -c release` 通过，30.50 秒。仅编译验证，不是 DMG 打包、签名、公证或正式发布；上述本地结果不证明 CI 已通过。

## 35375443023：非发布预检缺少下一版本说明

上述音频预检在 `hhh2210/status-trio` fork 执行，使用与上游相同的
macOS 15 / Xcode 16.4 / Swift 6.1.2 workflow：
[失败记录](https://github.com/hhh2210/status-trio/actions/runs/35375443023)、
[同一代码提交的通过记录](https://github.com/hhh2210/status-trio/actions/runs/35375769964)。
两次均未发布 Release 或更新 appcast。

合并前又在上游仓库以同一 workflow 复跑了一次非发布预检
[`35418503401`](https://github.com/lingyired/status-trio/actions/runs/35418503401)
（`version=1.2.0`、递增的 `build=10`、`publish=false`）：574 个 XCTest（3 跳过）、
146 个 Swift Testing 全部通过，通用 release 构建、`StatusTrio-1.2.0.dmg` 打包和
artifact 上传成功，未发布 Release 或更新 appcast。该次预检验证的是 Swift 代码提交
`e22cd13`；其后只有记录 CI 历史的 Markdown 提交。

同一个门槛在 2026-09-23 又踩了一次，这次是触发后才发现的：预检
[`35837434234`](https://github.com/lingyired/status-trio/actions/runs/35837434234)
用 `version=1.3.2` 派发，而仓库当时还没有 `release-notes/1.3.2/`。前置的
`Validate appcast notes` 会打印「目录不存在，跳过校验」并成功，真正拦人的是稍后的
`scripts/release.sh`——它检查 `release-notes/$VERSION` 目录的那段在 `PUBLISH` 判断之外，
所以非发布预检照样要过这一关。该 run 在测试跑完前取消，取消不产生 Release、tag 或
appcast 改动。

现在的做法：预检一个还没发布过的版本时，先把 `release-notes/<version>/` 的 `en.md` 与
`zh-Hans.md` 一起提交上（`publish=false` 只警告缺少其余 10 种语言，`publish=true` 才要求齐全）。
补上文案后复跑 [`35837523924`](https://github.com/lingyired/status-trio/actions/runs/35837523924)
（`version=1.3.2`、`build=15`、`publish=false`）：760 个 XCTest（6 跳过）、
247 个 Swift Testing 全部通过，通用 release 构建、`StatusTrio-1.3.2.dmg` 打包和 artifact
上传成功，appcast 校验通过（2 titles and 2 descriptions, en first），未发布 Release 或
更新 appcast。该次预检验证的是 Swift 代码提交 `23a3d9f`。

1.3.3 的非发布预检 [`35851597428`](https://github.com/lingyired/status-trio/actions/runs/35851597428)
（`version=1.3.3`、`build=16`、`publish=false`）在推送 `feat/volume-feedback-sound`
分支后派发，一次通过：762 个 XCTest（6 跳过）、255 个 Swift Testing（36 个 suite）
全部通过，通用 release 构建、`StatusTrio-1.3.3.dmg` 打包和 artifact 上传成功。
该次预检验证的是 Swift 代码提交 `734fc3a`（音量反馈音的实现、测试清理和 1.3.3 文案），
未发布 Release、未创建 tag、appcast 未更新。派发前先在本地跑通了 `swift test` 与
`swift build -c release`，并把 `release-notes/1.3.3/` 的 `en.md` 与 `zh-Hans.md`
随分支一起提交，所以这次没有再撞上上一节那个 notes 目录门槛。

## 失败记录规则

每次正式发布或经批准的诊断 GitHub Actions 失败都应追加到上表，至少包含：

- workflow run ID
- 失败阶段或 job
- 可复现的直接根因
- 修复方式
- 后续 CI 预检验证结果

不能只记录“重跑后通过”。同一根因造成的重复 run 关联到已有记录，不复制长报告。
日常本机验证失败不需要在本文建档；如果暴露了发布工具链兼容问题，再记录。

## 35293247382：测试同步竞态

这次非发布预检在 `SystemStatusStoreTests` 失败：

- `testSetVolumePreservesCurrentOutputDevice` 在 CI 中读到 `currentDevice == nil`
- 同一测试在本机和后续定向运行中通过
- 失败测试使用 `await drainMainActorTasks()` 推进主线程，但该方法只排空一次
  MainActor，不能保证 `AsyncStream` 的消费任务已经执行

修复方式是等待明确的业务状态，而不是等待调度时序：

```swift
await waitUntil { store.liveVolume.currentDevice == currentDevice }
```

`waitUntil` 使用 1 秒上限并在超时后让测试失败。`testSetVolumeUpdatesVisibleVolumeImmediately`
也使用同样方式等待初始音量，避免同类竞态。

修复后的非发布预检 `35293533279` 已完整通过，包括 `Run tests`、release 构建、
签名、产出上传和 workflow 收尾阶段。

## 当前这次是否和编码有关

有关系，但不是业务逻辑错误。

`set: localization.setPreference` 在 Swift 6.4 中合法，在语义上也没有问题；问题出在 Swift 6.1.2 的 IRGen 对“带 actor isolation 的方法引用转换为函数值”的代码生成存在编译器缺陷。显式闭包没有改变行为，只是避免了触发该编译路径：

```swift
// 不要这样写：会在 Swift 6.1.2 触发 IRGen 崩溃
set: localization.setPreference

// 这样写：行为相同，但不生成触发 crash 的转换
set: { newPreference in
    localization.setPreference(newPreference)
}
```

所以结论是：**代码写法是当前崩溃的触发条件，但根因是 CI 与本地 Swift 工具链不一致。** 后续开发需要同时处理这两件事。

## 35307956823：artifact 上传超时

这次非发布预检（`version=1.1.1`、`build=9`、`publish=false`，分支 `fix/dock-icon-after-update-check`）在最后一步失败：

- `Run tests`、`Build, sign, notarize, and publish` 均通过，说明 Xcode 16.4 / Swift 6.1.2 下编译、测试、打包都正常
- 只有 `Upload release artifacts` 失败，报错是 `Failed to CreateArtifact: Unable to make request: ETIMEDOUT`
- 该步骤带 `if: always()`，失败原因是 runner 与 GitHub artifact 服务之间的请求超时，属于基础设施抖动

因为失败点在所有编译与测试阶段之后，且报错不包含任何编译或测试诊断，这次失败与代码无关，没有对应的代码修复。处理方式是重跑失败 job，重跑后 `Set up job` 到 `Complete job` 全部通过（包括 artifact 上传）。

判断同类失败的标准：失败的必须是最后一个上传/清理步骤，并且日志里没有任何 Swift 编译、链接或测试输出。如果失败出现在 `Run tests` 或 `Build, sign, notarize, and publish`，必须按上面的规则排查代码。

## 35331580264：蓝牙电量读取的所有权竞态

这次非发布预检在 `BluetoothBatteryLevelHandoffTests` 失败：

- `testDetailPageKeepsReadingLevelsAfterLeavingTheSummary` 在最后一行
  `XCTAssertFalse` 失败，即从详情页返回摘要后电量读取没有被重新打开
- 同一测试在本机通过，因此不能按抖动处理

直接根因不是工具链问题，而是一个真实的顺序竞态：摘要行和详情页**共用一个布尔
标记**来决定是否读取电量。SwiftUI 在切换子树时，离开方与进入方的生命周期回调
顺序并不固定，实测两种情况都会出现：

```
去详情页：summary.task → detail.appear → summary.disappear
返回摘要：detail.disappear → summary.task → summary.appear
```

于是“最后写入者获胜”：离开摘要时会把详情页刚申请的电量读取关掉，详情页每个
设备都显示“不可用”；返回摘要时又会因为标记被关掉而不再重开。

修复方式是让结果与顺序无关，而不是再去猜顺序：控制器改为按 token 记录**申领
计数**，只要还有任一界面持有申领就继续读取，最后一个释放时停止。

```swift
func requestBatteryLevels(_ token: String)
func releaseBatteryLevels(_ token: String)
```

摘要在“开关打开且连了 AirPods”时申领，详情页仅按开关申领，关闭 popover 时清空
全部申领。新增控制器级测试直接覆盖两种顺序、重复申领和关闭场景，不再依赖
SwiftUI 的时序。

修复后的非发布预检 `35332232060` 的 `Run tests`、release 构建、签名和产出上传
全部通过。

## 开发与发布验证

日常开发不强制运行 GitHub Actions。按风险使用
`bash scripts/verify-local.sh quick <filter>` 或
`bash scripts/verify-local.sh full`；前者只证明定向范围，后者证明完整本机
Swift 测试、Release 编译和原生契约，不证明 DMG、签名、公证或运行时兼容性。

正式发布前必须在同一冻结 SHA 上完成一次完整 CI。非发布的诊断 run 只用于
维护者明确批准的高风险专项验证，不是每个 PR 或合并前的必选项。

### 1. 发布工具链

发布环境的实际 runner 与 Xcode 版本以
`.github/workflows/release.yml` 为准，并在 workflow 日志中输出
`xcodebuild -version`、`swift --version` 和 macOS SDK 版本。本机通过结果只能
作为开发证据，不能替代正式发布 CI。

### 2. 禁止使用仅在新工具链可用的写法

- 不使用 `isolated deinit`
- 不启用 `IsolatedDeinit` 或其他实验性编译器特性来绕过发布问题
- 不把 actor-isolated 方法直接当作闭包/函数值传递
- 不使用 `weak let`，weak 绑定必须是 `var`
  - 如果编译器因此报 `weak variable ... was never mutated`，不要照它的建议改成 `weak let`。用测试目标里的 `DeinitProbe.track(_:)`，把弱引用放进 `weak var` 存储属性。
- 要推翻这条规则，必须提供正式发布工具链接受 `weak let` 的运行记录，然后才改 `AGENTS.md`。
- 不假设本地和 CI 的 `Bundle.module` 资源目录大小写或布局一致

### 3. 遇到编译器崩溃时的处理方式

以下症状表示应该缩小或改写触发表达式，而不是重试或改变发布参数：

- `error: compile command failed due to signal 6`
- `IRGenRequest`
- `SmallVector unable to grow`
- `fatal error encountered during compilation`

处理顺序：

1. 从堆栈中的 `While evaluating request IRGenRequest` 找到源文件。
2. 检查该文件最近新增的方法引用、闭包转换、actor isolation 和复杂泛型表达式。
3. 用显式闭包或拆分局部变量改写最小表达式。
4. 重新运行受影响的本地验证。
5. 正式发布前在冻结 SHA 上重新运行完整 CI。

## 发布检查清单

- [ ] 版本号已明确，构建号大于线上 appcast 的最大构建号。
- [ ] `bash scripts/verify-local.sh full` 通过，或记录了未运行项。
- [ ] 完整 Release CI 在冻结的候选 SHA 上通过，并保存该 SHA。
- [ ] package 与 publish 使用同一个 artifact，未重新构建、签名或 DMG。
- [ ] Tag、manifest、DMG SHA-256 和 GitHub Release 均指向同一 SHA。
- [ ] `publish=true` 的发布 workflow 成功，且人工批准边界生效。
- [ ] GitHub Release 有 DMG 和 `.sha256` 文件。
- [ ] 线上 `appcast.xml` 的版本、构建号、长度和 EdDSA 签名已更新。
- [ ] 未配置 Developer ID / notarization 时，明确说明 Ad-hoc 签名和首次安装限制。

## 工具链迁移记录

日期：2026-09-19。

issue [#40](https://github.com/lingyired/status-trio/issues/40) 的根因不是缺代码，而是**构建 SDK 太旧**。
`scripts/build-app.sh` 从 `b728e6c`（2026-09-13）起就带有用 `vtool` 改写 `LC_BUILD_VERSION.sdk`
的修补，但 CI 一直是 `macos-15` + Xcode 16.4（SDK 15.5），`if SDK >= 26` 从未成立，
这段修补在任何一次发布里都**没有生效过**——线上 app 的 `sdk 15.5` 就是证据。macOS 依据
`sdk` 字段判断 app 是否采纳当前设计语言，所以菜单栏面板一直停在 Tahoe 之前的磨砂观感。

迁移把 CI 换成 `macos-26` + Xcode 26.6（Swift 6.3.3）来激活它，并补上三道护栏：

- `scripts/build-app.sh` 在 **`swift build` 之前**就以退出码 2 失败（SDK < 26），不再静默跳过。
  放在编译前是有意的：放在后面会先花掉一次完整编译，并留下一个能运行、观感却是旧的 bundle，
  正是这次要消灭的那种「构建成功、观感悄悄回退」。
- `minos` 从产物读回后原样写回，不再硬编码 `15.0`；**并且**与 `Support/Info.plist` 的
  `LSMinimumSystemVersion` 交叉比对，不一致就失败。只把产物里的值读回来再写回去是不够的——
  那样断言只是自我比较，`Package.swift` 抬高 `platforms` 时仍会静默产出 macOS 15 用户
  无法启动的包。
- `scripts/verify-platform-version.sh` 逐架构断言 `minos` 与 `sdk`，期望值取
  `LSMinimumSystemVersion`（一份独立声明，而不是产物自身的值），由构建脚本自动调用，
  本地构建与 CI 预检都会执行。

非发布预检 [`35452394846`](https://github.com/lingyired/status-trio/actions/runs/35452394846)
（`version=1.3.0`、`build=11`、`publish=false`）通过：608 个 XCTest（3 跳过）与 146 个
Swift Testing 全绿；通用 release 构建的两个切片都是 `minos 15.0 / sdk 26.0`，
`LC_BUILD_VERSION check passed`；DMG 打包与 artifact 上传成功，未发布 Release 或更新 appcast。
这次预检跑的是加了下面那几道护栏、并且页脚显示运行版本的代码，也就是说 `minos` 与
`LSMinimumSystemVersion` 的交叉比对在 CI 上确实执行并通过了。

同一条分支上更早两次通过的预检是 `35449290621`（`build=10`，护栏加强后的代码）与
`35448004467`（`build=10`，护栏加强之前）。

本次迁移过程中修掉的三个失败 run 见上面的失败记录表：`35447073294`、`35447273818`、`35447521372`。

### 复审后追加的护栏（2026-09-19）

整条分支复审时发现上面第二道护栏原本不成立：`build-app.sh` 把产物里的 `minos` 原样回传给
断言脚本，断言等于拿产物的值和它自己比，`Package.swift` 抬高 `platforms` 时必然通过。
现在是产物值 vs `LSMinimumSystemVersion` 的交叉比对，任一侧改动而另一侧没跟上都会失败。

同一次复审还改了两处：

- `SettingsRowHitAreaTests` 的探针原本固定等 50 ms；这个仓库已经因为固定睡眠吃过两次
  CI 失败（见上表 `35293247382`、`35316867111`），现在改为 2 秒上限的轮询。
- `release-notes/1.3.0/` 的 12 个文件原本写「macOS 15 及以上不受影响」，与同一条目的标题
  「macOS 26 及以上的原生 Liquid Glass」自相矛盾——受影响的正包括 macOS 26+。现改为
  「macOS 15–25 的观感保持不变」。`README.md` / `README.zh-CN.md` 的系统要求也补上了
  「构建需要 macOS 26 SDK」。

### 之后的跟进改动（2026-09-19）

- `Support/Info.plist` 的构建号由 10 提到 **11**。原因：开发机本地可能装着比线上 appcast 更超前的
  构建（例如 1.2.1/10），而 Sparkle 比较的是**已安装 app** 的 `CFBundleVersion`，`1.3.0 (10)`
  不会推送到这类机器。构建号的最终取值仍在发布时决定，判断基准是**已发布的 appcast**（当时为 9），
  不是本地已安装的版本。
- 弹窗页脚在「设置」按钮右侧、⋯ 菜单左侧显示运行版本（如 `1.3.0 (11)`）；开发构建仍在按钮文字里
  保留「开发版 · <代号>」。对比不同构建或排障时不必再打开「设置 → 关于」。

### issue #48 的预检（2026-09-20）

菜单栏面板在全屏 Space 下不弹出（[#48](https://github.com/lingyired/status-trio/issues/48)）的修复
新增了 `NSWindow` 扩展，属于 §2 的 `@MainActor` 范围，因此在分支
`fix/issue-48-fullscreen-popover` 上跑了一次非发布预检
[`35456441704`](https://github.com/lingyired/status-trio/actions/runs/35456441704)
（`version=1.3.0`、**`build=12`**、`publish=false`）：608 个 XCTest（3 跳过）与 149 个
Swift Testing 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，DMG 与 artifact 上传成功，未发布。
`build=12` 大于线上 appcast 的最大构建号 9，也大于 `Support/Info.plist` 当前记录的 11。
根因与工程细节见 [fullscreen-popover-investigation.md](fullscreen-popover-investigation.md)。

### 方法引用改写的预检（2026-09-20）

`StatusBarController` 的 8 个弹窗回调、`SettingsDisclosureRow` 的 `toggle`、以及
`WiFiNetworkListView` 的两处 `dismiss.callAsFunction` 原本以方法引用（而非显式闭包）的形式
作为函数值传递，这正是 §2 的 `@MainActor` 范围，也是 `34758026894` 崩溃的同一类代码形状。
本次在分支 `fix/class-a-hardening`（计划 `docs/superpowers/plans/2026-09-20-toolchain-method-reference-compliance.md`）
上跑了一次非发布预检
[`35495412938`](https://github.com/lingyired/status-trio/actions/runs/35495412938)
（`version=1.3.0`、**`build=13`**、`publish=false`）：

- `Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、
  `Upload release artifacts` 全部成功；`Validate Sparkle signing secret` 与 `Prepare release notes`
  按 `publish=false` 跳过——即未发布 Release、未改动 appcast。
- `Run tests`：**624 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿。
- 两个切片均为 `minos 15.0 / sdk 26.0`，即 macOS 26 SDK 断言成立。
- `build=13` 大于线上 appcast 的最大构建号 9，也大于 `Support/Info.plist` 当前记录的 11。

这次预检同时验证了新增的强制门禁：`Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift`
在 `swift test` 内运行 `scripts/check-forbidden-patterns.sh` 及其 `--self-test`，因此**在守卫的覆盖范围内**
重新出现的方法引用会让 `Run tests` 失败，无需改动任何 workflow 文件。守卫当前的覆盖范围与非目标
（脚本头部列有同一份清单）是：

- 会扫描的函数值位置：参数标签 `action:`/`get:`/`set:`/`using:`/`block:`/`perform:`、
  `request*:` 与 `open*:` 两个回调族、`on[A-Z]…:` 回调族（锚定在词边界上，因此
  `connectionOptions:`、`iconSize:` 不会误判成 `on…:`），以及
  `.map`/`.compactMap`/`.filter`/`.forEach`/`.sink`/`.assign` 与 `.callAsFunction`。
- 判定规则：带接收者的**点号成员引用**（`receiver.method`）只要 `Sources/` 下存在同名 `func`
  声明，不论参数个数都算违规——这正是 `34758026894` 的崩溃形状
  `Binding(get: { 0 }, set: loc.setPreference)`；**裸标识符**仍要求 `Sources/` 下存在零参数
  `func <name>()`，唯一的例外是 `on[A-Z]…:` 回调族（该族期望的闭包本身带参数，例如
  `Slider(onEditingChanged: (Bool) -> Void)`，所以 `onEditingChanged: handleVolumeEditing`
  算违规）。其余非目标见脚本头部。
- **不覆盖**：`Tests/` 下的任何代码。扫描只遍历 `$ROOT/Sources`，所以守卫通过并不代表测试目标里
  没有方法引用；编译层面的最终判据仍然是本预检
  （`swift test` + `swift build -c release` + 非发布 release workflow）。

#### 加宽后的复核（`build=14`）

终审发现守卫的覆盖范围小于分支的声明：`StatusPopoverView` 的三个 `store.*` 回调
（`onVolumeChange`/`onToggleMute`/`onSelectOutputDevice`）、`VolumeControlsView` 的
`onEditingChanged` 与 `perform: synchronizeVolume`、`IconGuideView` 的 `perform: restartPulse`
共六处仍是方法引用，而 `34758026894` 的原始崩溃形状（`Binding.set: … setPreference`，**带一个
参数**）当时被判为 `external` 而漏检。这六处已改为显式闭包，并按上一节所述的规则加宽守卫
（点号成员引用不再受零参数规则限制，新增 `perform:` 与 `on[A-Z]…:`），`--self-test` 由
6/6 + 7/7 变为 **10/10 + 7/7**。

改完之后重跑非发布预检
[`35496776064`](https://github.com/lingyired/status-trio/actions/runs/35496776064)
（`version=1.3.0`、**`build=14`**、`publish=false`）：`Validate appcast notes`、`Run tests`、
`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，624 个 XCTest
（6 跳过，0 失败）与 163 个 Swift Testing / 27 个 suite 全绿，两个切片仍为
`minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。
**两次预检对应加宽前后的两个 HEAD，合并时应以 `35496776064` 为准。**

守卫仍有两个已知的、当前不触发的假阳性路径，作为残留项记录而非继续扩大改动范围：一是点号分支
先于「转发闭包」豁免判断，因此 `Button(action: self.openSettings)` 这类**点号**转发闭包，在
`Sources/` 下恰好存在同名 `func openSettings()` 时会被误判为违规；二是转发的声明形状要求写成
`label name: … ->`，因此省略外部标签的闭包参数（`func f(read: (…) -> …)`）不再被豁免。两者在
当前代码树上都不产生任何输出（守卫退出 0），一旦出现按脚本头部的 `ALLOWED` 名单逐条标注即可。

### 状态轮询调度的预检（2026-09-20）

`SystemStatusStore` 的兜底轮询原本每 5 秒无条件唤醒一次，且 `Task.sleep` 没有
`tolerance`，无论 popover 是否打开、显示器是否睡眠都照跑。本次在分支
`fix/class-a-polling`（计划 `docs/superpowers/plans/2026-09-20-status-poll-scheduling.md`）
上做的改动是：给兜底 sleep 加 `interval / 5` 的 tolerance；把默认间隔由 5 秒提到 15 秒
（可调范围仍是 5...60 秒，用户选过的值仍然优先）；无可见界面时只刷新电池，Wi-Fi 与音量
改到每第 4 个 tick；显示器睡眠时整个 tick 跳过，任一唤醒通知都会清掉该标志并先
`recoverAll()` 再 `refreshAll()`；`applyVolume` 在值未变化时不再重复发布 `liveVolume`。

> **补齐（预检 `35513133152` 之后）：** 显示器睡眠的跳过当时没有上限，而「显示器单独睡眠」
> （屏保、显示器休眠定时器、系统不睡眠）只有 `screensDidWakeNotification` 一个清除入口。
> 该通知一旦丢失，`batteryMonitor.refresh()` 会在整场会话里停摆，画进菜单栏图标的电量
> 就此冻结。现补上 `maximumDisplayAsleepSkips`：连续跳过 20 个 tick（默认间隔 15 秒即
> 5 分钟）后强行刷新一次并清零计数，任一唤醒通知也会清零。因此丢一次通知最多只会让
> 每个上限损失一次刷新，而不是让轮询停摆整场会话。

这一步牵涉 `@MainActor` 状态与 `deinit`（新增两个 observer token，仅由 `deinit` 与 `stop()`
移除），因此按规则跑了非发布预检
[`35513133152`](https://github.com/lingyired/status-trio/actions/runs/35513133152)
（`version=1.3.0`、**`build=15`**、`publish=false`）：`Validate appcast notes`、
`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**636 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿，
两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

`build=15` 是因为 `12`（issue #48 全屏修复的预检，见上）、`13`、`14` 都已被更早的预检
占用；它仍大于线上 appcast 的最大构建号 9 与 `Support/Info.plist` 记录的 11。
本轮的用户可见影响是有界的：状态面板与设置窗口都关闭时，Wi-Fi 与音量的读数最多滞后
4 个 tick（默认间隔下 60 秒），这段滞后正常由推送通道覆盖；电池每个 tick 都刷新，
想恢复旧节奏的用户也可以在设置里选 5 秒。

> **⚠️ 构建身份不一致（必读）：** 现有的「改动前」基线取自**线上安装的 1.2.1 / build 10**，
> 不是本分支（工作树为 1.3.0）的构建。两者不是同构建对比，该数字只能作为背景参考，
> 不能当作本分支改动前后的对照。

功耗对比只记录了**改动前**的基线（线上安装的 1.2.1/10，空闲采样 20 次：平均 CPU 0.125 %、
RSS 25 MB、累计 idle wakeups 0；另一次在界面打开状态下的采样为平均 CPU 0.225 %、
RSS 134 MB、20 秒累计 240 次 idle wakeups——两次采样条件不同，不能互相比较）。

> **⏳ 改动后采样：发布 1.3.0 之前必须完成（当前仍未完成）。** 发布说明已经宣传了这项节省，
> 因此必须在发布前、在同一台机器上，用本分支自己的 dev bundle 采集，并把改动前后两个
> 数字一起记录到 PR。发布后再补测就没有意义了。命令如下（`scripts/build-worktree.sh`
> 会派生出独立的 dev bundle id，不覆盖已安装的正式版）：
>
> ```bash
> # 先退出已安装的正式版，保证只有一个 StatusTrio 进程（dev bundle 与正式版可同时运行，
> # 两个 PID 会让 top -pid 报 "invalid option or syntax"）
> osascript -e 'tell application id "com.lingsmbp.StatusTrio" to quit'
> bash scripts/build-worktree.sh release no-open
> open dist/StatusTrio.app
> top -l 20 -s 1 -pid "$(pgrep -x StatusTrio)" | tail -5
> ```
>
> 本次预检未执行采样，是为了不在维护者的机器上多出一个菜单栏实例并触发权限弹窗；
> 这个理由只解释了当时的推迟，不能替代发布前必须拿到的证据。

### 有界自愈的第三次预检（`build=16`）

终审指出上一版的「显示器睡眠」标志只由两个唤醒通知清除：显示器单独睡眠时若那一条
`screensDidWakeNotification` 丢失，电池刷新会在整个会话里停住，而电池百分比是画进菜单栏
图标的——正是本计划禁止的「轮询永久停止 / 已绘制值变陈旧」。修复方式是给跳过加一个上限：
连续跳过 20 个 tick（默认 15 秒下约 5 分钟）后就照常刷新并清零，任一唤醒通知或任何一次真正
执行的 tick 也会清零。这样丢失一条通知的代价是被上限约束的一次多余刷新，而不是整个会话停摆。

该修复触及 `@MainActor` 状态，因此再次跑了非发布预检
[`35514169366`](https://github.com/lingyired/status-trio/actions/runs/35514169366)
（`version=1.3.0`、**`build=16`**、`publish=false`）：`Validate appcast notes`、`Run tests`、
`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**637 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿，
未发布 Release、未改动 appcast。**本分支合并时应以 `35514169366` 为准**（`35513133152`
对应有界自愈修复之前的 HEAD）。

同一次修复还按终审意见收尾了文档：发布说明改为「默认每 15 秒一次」并去掉了「watchdog /
看门狗」这类开发者词汇、改用 `.lproj` 里的既有术语；`2026-09-12-status-trio-design.md`
标记为 v1 设计快照；`2026-09-14-performance-optimization-design.md` 的间隔描述改为
实际的 15 秒 / 5...60 / 步长 5。

> **⏳ 仍然未完成：改动后的功耗采样（见上一节）。** 它不影响合并，但**必须在发布 1.3.0
> 之前**补上。

### 蓝牙轮询改写的预检（2026-09-20）

`BluetoothDeviceController` 原本每 15 秒 spawn 两次 `/usr/sbin/system_profiler`，且在用户授权并打开过 popover 之后**永不停止**；`deinit` 也不会移除两个 `NotificationCenter` observer、不会停 IOBluetooth 事件监视器和 CoreBluetooth 状态监视器。本次在分支
`fix/class-a-bluetooth`（计划 `docs/superpowers/plans/2026-09-20-bluetooth-polling-and-lifetime.md`）上把蓝牙改成推送驱动：每个刷新周期共用一份 profiler 报告（2 → 1 次 spawn）；单次读锁 + 一次合并的后续刷新；可见性 claim 门控的 30 秒兜底轮询；IOBluetooth 连接/断开通知 + 750 毫秒防抖；完整的 `deinit` 拆卸；以及**读队列退役 + 读看门狗**（两者必须同时存在：只加看门狗时重试会排在挂住的块后面）。

这一步是 `deinit` + `nonisolated(unsafe)` + `@MainActor` hop 的形状，因此按规则跑了两次非发布预检：

- [`35520306448`](https://github.com/lingyired/status-trio/actions/runs/35520306448)（`build=17`）—— 终审修复 wave **之前**的 HEAD。
- [`35521490583`](https://github.com/lingyired/status-trio/actions/runs/35521490583)（**`build=18`**）—— 修复 wave 之后，**合并以这次为准**：`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**668 个 XCTest（6 跳过，0 失败）** 与 **168 个 Swift Testing / 27 个 suite** 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

终审修复 wave 修掉的一个真实缺陷值得记在这里：设备断开时 `BluetoothConnectionEventMonitor` 直接丢弃 `IOBluetoothUserNotification` token 而**没有 `unregister()`**，而 SDK 明确说明 token 在注销前一直有效——于是每一次断开都会在存活的监视器上永久泄漏一个注册，并在下次断开时多触发一次回调（注释还写着相反的话）。现已改为先 `unregister()` 再丢弃（断线与重连两条路径都覆盖），并加了通过计数 token 注销次数、可对旧代码失败（RED `[0, 0, 1, 1]`）的测试。

> **⏳ 仍未完成：改动前后的 spawn 次数实测**（计划 Task 7 Step 1）。它不影响合并，但和 R-03 的功耗采样一样，**必须在发布 1.3.0 之前**由维护者用 dev bundle 采集（`pgrep -x system_profiler` 采样：面板关闭时应为 0 次，蓝牙界面可见时约每 30 秒一次），或在合并记录中明确豁免。计划里没有记录任何推断出来的数字。

### Wi-Fi 扫描节奏的预检（2026-09-20）

Wi-Fi 页面原本在打开期间**每约 5 秒**做一次全信道 `scanForNetworks` 并 spawn 一个 `networksetup`（30 秒的周期循环只是下限，状态 yield 才是真正的驱动），返回摘要页后循环仍在跑；没有 Wi-Fi 网卡的 Mac 还会每 30 秒重建整套 CoreWLAN 事件栈。本次在分支
`fix/class-a-wifi`（计划 `docs/superpowers/plans/2026-09-20-wifi-scan-cadence.md`）上：加入可注入的扫描 worker/时钟/`minimumScanInterval`（30 秒），把 `refresh`（自动、间隔内复用缓存）与 `refreshNow`（显式、总是扫描）分开；三个用户主动路径（刷新按钮、无线开关、连接完成）改走 `refreshNow`；新增 `closeWiFiDetails()` 并在返回时调用，同时修掉一个既有的「扫描中 deactivate 会让 `state` 永久停在 `.scanning`」冻结；把无网卡时的恢复限制为 3 次重建。

这一步触及 `@MainActor` 状态，因此按规则跑了两次非发布预检：

- [`35528142630`](https://github.com/lingyired/status-trio/actions/runs/35528142630)（`build=19`）—— 终审修复 wave **之前**的 HEAD。
- [`35528756095`](https://github.com/lingyired/status-trio/actions/runs/35528756095)（**`build=20`**）—— 修复 wave 之后，**合并以这次为准**：`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**683 个 XCTest（6 跳过，0 失败）** 与 **168 个 Swift Testing / 27 个 suite** 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

终审修复 wave 修掉的缺陷值得记在这里：`recoverIfAllowed` 把 `interfaceAbsentStreak` 的**自增放在 staleness 门控之前**，于是被门控刻意抑制的读也在消耗恢复预算——注释、测试名与测试注释都写着"计数重建次数"，代码却在数读次数，两者只在测试刻意使用的 30.001 秒读间隔下重合。生产中间隔更密（R-03 的 15 秒兜底 tick 加链路质量事件），预算约 45 秒就耗尽，实际只换到 1–2 次重建，而不是文档承诺的 3 次。现已把自增移到门控之后，并新增一条 **5 秒读间隔**的测试独立钉住"计数的是重建"（对旧代码 RED：`streak 3 != 1`、`restartCount 1 != 3`）。

> **⏳ 仍未完成：改动前后的扫描次数实测**（计划 Task 5 Step 5）。与上面两项一样不影响合并，但**必须在发布 1.3.0 之前**由维护者用 dev bundle 采集（`pgrep -x networksetup` 采样：间隔内应为 0 次，页面打开时约每 30 秒一次，返回摘要后应为 0 次），或在合并记录中明确豁免。

> **记录在案的残留项（已裁定，不在本计划内修）**：无网卡恢复的 3 次上限**无法区分**"这台机器没有 Wi-Fi 硬件"与"有硬件但接口读卡在 nil"。后者在旧代码里会在 30–60 秒内自愈，现在 3 次重建后要等到睡眠/唤醒或连接失效才恢复，期间菜单栏与 Wi-Fi 页显示 `.unavailable`。计划有意收紧这项工作，发布说明也写明"尝试有限次数后等待唤醒或网络变化"；若要恢复慢速自愈，需要一个更慢的（例如每几分钟一次）上限后兜底，属后续改动的设计决定。

### 编译警告清理的预检（2026-09-21）

本计划清掉 7 处告警中的 5 处：把 `AudioOutputDeviceIcon.swift` 里废弃的 `String(cString:)` 换成 `String(decoding:as:)` 并把 `hw.model` 解析抽成纯函数以便测试；把三处测试文件里的 4 个 `weak variable … was never mutated` 改为通过新的 `Tests/StatusTrioCoreTests/DeinitProbe.swift` 以 `weak var` 存储属性观察释放——**没有**采用编译器建议的 `weak let`（`AGENTS.md` 禁止，且 CI run `34753843803` 记录旧工具链不接受该写法）。规则与决策已写入上表与 §3，并在 `AGENTS.md` 第 45 行加了指向 `DeinitProbe` 的括号说明（规则本身未放松）。

分支 `fix/class-a-icons`（计划 `docs/superpowers/plans/2026-09-20-compiler-warning-cleanup.md`）的非发布预检
[`35565582217`](https://github.com/lingyired/status-trio/actions/runs/35565582217)（`version=1.3.0`、**`build=21`**、`publish=false`）：
`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**683 个 XCTest（6 跳过，0 失败）** 与 **170 个 Swift Testing / 27 个 suite** 全绿，未发布 Release、未改动 appcast。
终审修复 wave 之后只改了注释、测试名、一个泛型参数（`Unicode.ASCII` → `Unicode.UTF8`，用来恢复旧 `String(cString:)` 的解码契约）与计划文本，没有触及 actor isolation / `@MainActor` / `deinit` 形状，因此按既定规则**没有再跑一次预检**。

> **本计划结束时构建仍**有 2 处告警，都是 `WiFiPasswordStore.swift:108`、`:131` 的 `kSecUseAuthenticationUI*` 废弃提示，属于 **R-12（Keychain 加固，class B，尚未开始）**。上表已在"本轮，非失败记录"一行记录该决策与证据门槛：要推翻 `weak let` 规则，必须提供 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）接受该写法的运行记录。

> **终审发现的测试诚实性问题也已修正**：新增的"shrinking buffer"测试曾以系统调用重采样路径命名并声称其在缩容时返回 `""`，但它只调用纯解析函数，而实测缩容时得到的是缩短后的型号（`Mac15,9`）而非空串——即套件曾声称覆盖一个它并不覆盖的可见回退。现已改名为 `modelIdentifierParserHandlesEmptyAndUnterminatedBuffers`，删掉错误注释，并在计划的风险行里明确写出 **sysctl 失败路径未被测覆盖**。

## 35614298374：排序断言依赖了 locale（蓝牙电量默认开启，第 2 轮）

分支 `fix/bluetooth-battery-level-default`（设计 `docs/superpowers/specs/2026-09-20-bluetooth-battery-level-default-design.md`）的第二次非发布预检
[`35614298374`](https://github.com/lingyired/status-trio/actions/runs/35614298374)（`build=23`）在 `Run tests` 失败，唯一失败用例是新增的
`BluetoothSummaryTests.testDevicesWithoutALevelKeepTheirNameOnly`：

```
XCTAssertEqual failed: ("Optional("MX Keys、机灵的耳机 · L 93%")") is not equal to ("Optional("机灵的耳机 · L 93%、MX Keys")")
```

摘要行把已连接设备交给 `BluetoothDevicePresentation.grouped` 排序，那里用的是 `name.localizedCaseInsensitiveCompare`，即 ICU collation —— 与语言有关：CI runner（英文）把 `MX Keys` 排在 `机灵的耳机` 之前，开发机（中文）相反。本机 `swift test` 与 `swift build -c release` 都是绿的，因此这是**断言**的问题，不是产品缺陷；前面那次预检 `35610292554`（`build=22`）也不含这条用例。

不过它顺带暴露了一个真实取舍：AirPods 的多路电量是这一行的头条信息，不该因为名字的 collation 被挤到后面。修复把排序规则改成 **AirPods 无条件最前、其余按名称**（Connected / Not connected 两组内一致），`BluetoothDevice.isAirPods` 因此恢复，但用途只剩排序（产品 ID 命中或名字含 "airpods"；电量认领已不依赖它）。断言现在由规则决定顺序，`testAirPodsLeadTheRowRegardlessOfName` 用一个 collation 最靠后的名字钉住这条规则。

验证：[`35615262052`](https://github.com/lingyired/status-trio/actions/runs/35615262052)（`build=24`）`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**690 个 XCTest（6 跳过，0 失败）** 与 **180 个 Swift Testing / 28 个 suite** 全绿，未发布 Release、未改动 appcast。

## 35718713396：appcast 发布回读撞上 Contents API 最终一致性（1.3.0 正式发布）

1.3.0 正式发布 run [`35718713396`](https://github.com/lingyired/status-trio/actions/runs/35718713396)
（`version=1.3.0`、`build=13`、`publish=true`）在 `Build, sign, notarize, and publish`
的**最后一步**失败，错误来自 `scripts/release.sh` 的发布后回读校验：

```
Error: published appcast does not contain build 13.
```

时间线（取自该 step 日志）：

- 11:01:16 `Build complete!`，`LC_BUILD_VERSION` 检查通过（两架构 `minos 15.0, sdk 26.0`），
  `codesign` 校验通过；
- 11:01:43–47 `gh release create v1.3.0` 成功，DMG 与 sha256 随即上传为 Release 资产；
- 11:01:47 appcast 经 Contents API `PUT` 成功提交（main 上的 `8519984`）；
- 11:01:49 **仅 2 秒后**回读 `appcast.xml?ref=main` 做校验，读到旧内容，`exit 1`，整个 run 标红。

根因：GitHub Contents API 在写入成功后存在短暂的最终一致性窗口，紧接 `PUT` 的读取
可能拿到旧 blob。本次发布与 Swift 工具链、产品代码、说明文件均无关；除这条回读外，
发布的每一个环节都已实际完成。该路径只在 `publish=true` 时执行（`release.sh` 在
`PUBLISH=false` 时于第 238 行提前退出），且 `Release` 已存在时不允许复跑（第 243 行），
所以无法通过重跑同一发布来复现或验证。

修复：`scripts/release.sh` 的回读改为带退避的重试——最多 6 次、间隔 5 秒，期间读到
含目标 build 即视为成功，重试全部用尽才保留原错误信息并失败。错误文案未变，
`docs/superpowers/plans/2026-09-20-preflight-validator-and-appcast-sync.md` 中引用它的
测试断言不受影响。

验证：

- **发布四项核验（该 run 实际结果）**：`Run tests` 成功；DMG `StatusTrio-1.3.0.dmg`
  （4 244 534 字节）与 sha256 已在 Release 上；Release
  [v1.3.0](https://github.com/lingyired/status-trio/releases/tag/v1.3.0) 已发布，正文为规定的
  `# Version 1.3.0 （English + 中文， 中文在下方）` 双语格式并附首次安装命令；
  appcast 提交 `8519984` 已在 main，Sparkle 源已含 build 13。
- **远端 appcast 条目**：12 titles + 12 descriptions、`en` 首位、真实 `sparkle:edSignature`、
  `length=4244534` 与 Release 资产一致、无残留 `%VERSION%/%BUILD%` 占位符。
- **重试逻辑桩测**：用桩 `gh`（前 2 次返回旧内容、第 3 次返回含 build 13 的内容）执行
  release.sh 中的同一段回读代码，得到 `appcast_verified=true` 且仅调用 3 次；桩恒返回旧内容时，
  6 次用尽后打印原错误信息并以 1 退出。`bash -n scripts/release.sh` 语法检查通过。
- 本次改动只有 shell 与 Markdown，未触碰 Swift 代码，按规则无需新的工具链预检；
  下一次正式发布将真实行使这段重试。

## 35740301886：30 秒回读窗口仍不足，判据改到 git 层（1.3.1 正式发布）

1.3.1 正式发布 run [`35740301886`](https://github.com/lingyired/status-trio/actions/runs/35740301886)
（`version=1.3.1`、`build=14`、`publish=true`）在 `Build, sign, notarize, and publish`
的最后一步再次失败，用的正是上一条记录留下的重试窗口：

```
Published appcast read-back missed build 14 (attempt 1/6); retrying in 5s...
Published appcast read-back missed build 14 (attempt 5/6); retrying in 5s...
Error: published appcast does not contain build 14.
```

时间线（取自该 step 日志）：

- 14:30:20 `Build complete!`；14:30:31 `LC_BUILD_VERSION` 与 `codesign` 校验通过（两架构 `minos 15.0, sdk 26.0`）；
- 14:30:52 `gh release create v1.3.1` 成功，DMG `StatusTrio-1.3.1.dmg`（4 243 505 字节）与 sha256 随即成为 Release 资产；
- 14:30:52 appcast 经 Contents API `PUT` 成功提交（main 上的 `3979dc4`）；
- 14:30:55–14:31:24 回读 `appcast.xml?ref=main` 连续 6 次（间隔 5 秒，约 30 秒）仍读到旧内容，`exit 1`，整个 run 标红。

根因：**判据选错了实体，而这个滞后没有可测上界。** 上一条记录把窗口定为 6×5 秒，
依据只是"2 秒不够"这一个数据点；本次实测把上界推高了一个量级——写入后 30 秒仍读到旧 blob，
而此刻 `git/ref/heads/main` 已经是 `3979dc4`，约 5 分钟后 `contents` 读取才一致。所以再猜一个
更长的秒数并不能消除假失败。写入本身是同步的：`PUT` 的响应里就带着它创建的那个 commit，
而当时那行命令把响应丢给了 `/dev/null`。

修复：`scripts/release.sh` 的回读不再丢弃 `PUT` 响应，取其中的 `commit.sha`，判据改为
**git 层求证**——`git/ref/heads/<branch>` 指向该 commit 即视为已发布；`contents` 读取降级为
二次确认（仅在 `PUT` 未报告 commit 时依赖它），窗口放宽到 24×10 秒。错误文案未变，
`docs/superpowers/plans/2026-09-20-preflight-validator-and-appcast-sync.md` 中引用它的断言不受影响。

验证：

- **发布四项核验（该 run 实际结果）**：`Run tests` 成功；DMG `StatusTrio-1.3.1.dmg`（4 243 505 字节）
  与 sha256 已在 Release 上；Release [v1.3.1](https://github.com/lingyired/status-trio/releases/tag/v1.3.1)
  已发布且非 draft/prerelease，tag 指向 `568ac50`；appcast 提交 `3979dc4` 已在 main，Sparkle 源已含 build 14。
- **远端 appcast 条目**：12 titles + 12 descriptions、`en` 首位、阿拉伯语带 `div dir="rtl"`、
  真实 `sparkle:edSignature`、`length` 与 Release 资产一致、无残留 `%VERSION%/%BUILD%` 占位符。
- **桩测**（真实代码块 + 桩 `gh`）：用 `awk` 从 `scripts/release.sh` 逐字抽出回读段执行，
  三种场景全绿——① `git/ref` 首次即指向 `PUT` 的 commit：退出 0，且**完全不读 contents**；
  ② `git/ref` 滞留、contents 第 3 次追上：退出 0，读 3 次；③ 两者都滞留：读 3 次后打印原错误
  信息并以 1 退出。
- **`--input -` 与 `--jq` 共存**：本次新引入的组合在 gh 2.96.0 上实测可用（对 `POST /markdown`
  传 body 并用 `--jq` 处理响应，jq 报的是响应解析错误而非参数冲突），该接口零副作用。
- `bash -n scripts/release.sh` 通过。本次改动只有 shell 与 Markdown，未触碰 Swift 代码，按规则
  无需新的工具链预检。**同一 tag 不允许复跑**（`release.sh` 在 Release 已存在时拒绝），所以新判据
  只能由下一次正式发布行使。

## 35842269867：1.3.2 正式发布，新回读判据首次即命中（兑现上一条的留话）

上一条结尾那句「新判据只能由下一次正式发布行使」在 1.3.2 兑现了。run
[`35842269867`](https://github.com/lingyired/status-trio/actions/runs/35842269867)
（`version=1.3.2`、`build=15`、`publish=true`、`ref=main`）5m6s 全绿：

- `Validate appcast notes`：12/12 语言、`12 titles and 12 descriptions, en first`；
- `Run tests`：XCTest **760 个（6 skipped）、0 failures**，swift-testing **247 个 / 35 suites**，0 failures；
- `Build, sign, notarize, and publish`：`LC_BUILD_VERSION check passed`（两架构 `minos 15.0, sdk 26.0`），
  `codesign` 报 `valid on disk` / `satisfies its Designated Requirement`；
- **回读判据首次即命中 git 层**：`Creating GitHub Release v1.3.2...`（09:24:41）到
  `Published …StatusTrio-1.3.2.dmg`（09:24:46）只隔 5 秒，日志里**没有任何 `retrying in` 行**——
  即上一条设计的桩测场景①（`git/ref` 首次就指向 `PUT` 的 commit，完全不读 `contents`）在真实发布上成立，
  1.3.1 那种「写入成功却判失败」的假失败没有复现。

发布四项核验：Release [v1.3.2](https://github.com/lingyired/status-trio/releases/tag/v1.3.2)
已发布且非 draft/prerelease，tag 指向 `2055908`；DMG 4 317 802 字节与 sha256 均已附加；appcast
提交 `5cd8c7e` 已在 main，Sparkle 源条目为 12 titles + 12 descriptions、`en` 首位、阿拉伯语带
`div dir="rtl"`、真实 `edSignature`（88 字符）、`length` 与 Release 资产一致、无残留占位符。

一处读路径滞后值得记住：`gh api repos/…/releases/tags/v1.3.2` 的 `assets` 字段在发布后数分钟内仍返回
空数组（`/releases/tags/…/assets` 甚至 404），而同一时刻 Release 页面的 `expanded_assets` 已列出两个
资产、`releases/download/v1.3.2/StatusTrio-1.3.2.dmg` 直链返回 200。**核对资产不要只看 `assets` 字段**，
用页面或直链交叉验证。

## 35997423299：macOS 26 预检中的状态更新测试超时

Release workflow run [`35997423299`](https://github.com/lingyired/status-trio/actions/runs/35997423299)
（`version=1.3.3`、`build=16`、`publish=false`）在 `Run tests` 阶段失败；工具链显示步骤、版本解析及
12 语言 appcast 校验均通过，后续 build/publish 步骤因此未运行。

失败项：

- `AppIconControllerTests.visibleDockRendersStatusChanges`：在原有 900 ms 固定等待后仍为 0 次渲染。
- `ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork`：原有 1 秒轮询期限到达时，渲染仍为初始值，最后电量仍为 60%。

根因：这两项测试依赖电池监视器的 `AsyncStream` 消费与 `AppIconController` 的 500 ms Combine debounce；Swift Testing 会并发启动测试，macOS CI 忙时事件调度超过了 900 ms / 1 秒测试期限。失败只发生在等待事件的断言前，其他新预览测试均通过。专项本机重跑的可见 Dock 更新在 580 ms 完成，符合调度变慢而非渲染键失效的表现。

修复：可见 Dock 测试改为轮询至渲染条件满足（最多 5 秒，沿用该测试套件已有 helper）；隐藏 Dock 测试等待 2 秒后再确认没有渲染；静态 Dock 电池测试的轮询期限从 1 秒延长到 5 秒。只调整测试等待，不改变产品更新延迟或渲染行为。

验证：`swift test --filter AppIconControllerTests`（28 项）与 `swift test --filter ChargingEffectControllerTests`（2 项）本机通过；全量 `swift test` 通过（349 项 / 59 suites）；`swift build -c release` 通过；`git diff --check` 通过。第二次预检发现另一项独立的像素基准问题，见下节。

## 35998205381：静态图标哈希只覆盖了本机 CoreGraphics 输出

第二次 `publish=false` 预检 run [`35998205381`](https://github.com/lingyired/status-trio/actions/runs/35998205381)
（`version=1.3.3`、`build=16`）通过版本与 appcast 检查，但 `Run tests` 因
`ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint` 失败：测试的本机预期值是
`224850873cf3d786d2fe246a1b1f15c092e34297dfb944832284b2fbf671bd74`，CI 同一静态渲染得到
`4d795d40269a978007765c4d4d20922982b140207d34d7ddcaeb25368c9a5591`。全量测试中的其他 348 项通过。

根因：该测试把 macOS 27 本地 CoreGraphics 的完整 40×40 像素哈希当作跨平台唯一基准；macOS 26/Xcode 26.6
对相同的 `StatusIconRenderer` 输入，在抗锯齿边缘产生不同字节。预览改动不修改 `StatusIconRenderer`，但此前没有 macOS 26 的该测试基准。

修复：测试允许两个已观测的静态哈希（macOS 26 CI 与 macOS 27 本机），其他输出仍须精确匹配其中一个基准；这样保留像素回归检测，同时避免跨 OS 抗锯齿差异造成假失败。

验证：修改后的 `swift test --filter ChargingEffectRenderingTests`（7 项）通过；全量 `swift test` 通过（349 项 / 59 suites）；`swift build -c release` 通过。第三次预检结果见下节。

## 35998888434：内存优化变更通过 macOS 26 发布预检

第三次 `publish=false` workflow run [`35998888434`](https://github.com/lingyired/status-trio/actions/runs/35998888434)
（`version=1.3.3`、`build=16`）于 2026-09-24 全绿，耗时 5m2s。该预检覆盖前两次 CI 失败的修复：
状态更新测试使用有界轮询，静态图标像素基准允许 macOS 26 与 macOS 27 两个已观测哈希。

- `Validate appcast notes`：12/12 语言，12 titles + 12 descriptions，`en` 首位。
- `Run tests`：成功；swift-testing 全量 349 项 / 59 suites 通过。
- `Build, sign, notarize, and publish`：成功（`publish=false`，没有创建 Release 或发布 appcast）；
  `LC_BUILD_VERSION` 检查通过，x86_64 与 arm64 均为 `minos 15.0, sdk 26.0`，`codesign` 验证为
  `valid on disk` 且满足 Designated Requirement。
- `Upload release artifacts`：成功。

根因与修复记录分别见上面两节；此次全绿完成对这两项修复的 CI 验证。工作流只构建并上传预检产物，没有发布正式版本。

## 36332507137：蓝牙设备图标替代网络图标通过 macOS 26 发布预检

蓝牙图标来源变更（提交 `0651799`，5 个提交的功能分支）在 `version=1.3.3`、`build=17`、
`publish=false` 的预检 [`36332507137`](https://github.com/lingyired/status-trio/actions/runs/36332507137)
上于 2026-09-27 全绿，耗时 4m43s。整轮 4 次 dispatch 中只有第一次因缺发布说明失败（见上表
`36332229393`），代码本身没有出现过 CI 编译、测试或签名失败。

- `Validate appcast notes`：沿用 1.3.3 的 12/12 语言说明，12 titles + 12 descriptions，`en` 首位。
- `Run tests`：成功；本机同一提交 `swift test` 为 XCTest 944 项 + swift-testing 367 项全绿。
- `Build, sign, notarize, and publish`：成功（`publish=false`，没有创建 Release 或发布 appcast）；
  `LC_BUILD_VERSION` 检查通过，`minos 15.0` / `sdk 26.0`，`codesign` 为 `valid on disk` 且满足
  Designated Requirement。
- `Upload release artifacts`：成功。

该预检覆盖的是引入 `Picker` 绑定、`BluetoothAudioIconOptions` 新字段与 12 个 `.lproj` 资源改动的
提交 `0651799`。

合入 main 前远端已经前进：`origin/main` 并入了 PR #73（nearby BLE battery，12 个提交），**同样改动蓝牙
子系统**（设置键、蓝牙设置面板、12 个 `.lproj`）。整合只在
`Tests/StatusTrioCoreTests/SettingsStoreTests.swift` 产生冲突——两边在同一位置各自新增了互不相关的测试
方法，两边都保留——其余文件自动合并。整合后的 head 是 `5f3f8ea`，本机在其上跑出 XCTest 963 项 +
swift-testing 380 项 0 失败、`swift build -c release` 通过。

因为整合后的树包含了另一个 PR 的蓝牙改动与手工冲突解决，**新 head 又跑了一次预检**
[`36333074090`](https://github.com/lingyired/status-trio/actions/runs/36333074090)
（`version=1.3.3`、`build=17`、`publish=false`，head `5f3f8ea`），5m39s 全绿：
`Run tests`、通用 release 构建/签名、`Upload release artifacts` 全部成功。这才是随 main 一起落地的验证；
两轮预检都只构建并上传预检产物，没有发布正式版本。

## 37641006582：个人热点分组预检因缺少 1.4.1 发布说明中止

个人热点分组提交 `e62db3b` 的首次非发布预检
[`37641006582`](https://github.com/lingyired/status-trio/actions/runs/37641006582)
使用 `version=1.4.1`、`build=18`、`publish=false`，在
`Build, sign, notarize, and publish` 阶段失败。

- **根因**：仓库缺少 `release-notes/1.4.1/`。前置 `Validate appcast notes` 允许非发布预检在目录不存在时跳过校验，但 `scripts/release.sh` 的目录检查仍要求该目录存在，因此在进入 release 构建、签名和 DMG 打包之前中止。此次失败不涉及 Swift 代码或工具链兼容性。
- **修复**：新增 `release-notes/1.4.1/en.md` 与 `release-notes/1.4.1/zh-Hans.md`，标题均包含 `%VERSION%` 与 `%BUILD%` 占位符；说明仅描述已连接且被识别的个人热点分组，未连接网络的发现与分组保持不变。不修改产品代码、工作流或应用版本元数据。
- **首轮验证结果**：该 run 的 `Run tests` 全部通过；打包阶段因上述发布说明目录缺失而停止，尚未完成 release 构建、签名、DMG 打包和预检产物上传验证。
- **后续验证**：修复后的非发布预检 [`37642150046`](https://github.com/lingyired/status-trio/actions/runs/37642150046)（head `eb8f644`，`version=1.4.1`、`build=18`、`publish=false`）全绿，耗时 15m6s：说明校验、全量测试、arm64/x86_64 通用 release 构建、Ad-hoc 签名验证、`LC_BUILD_VERSION` 检查、`StatusTrio-1.4.1.dmg` 打包与 artifact 上传全部通过。本次没有创建 GitHub Release 或更新 appcast；后续提交仅补充本条验证记录，不改变已验证的产品代码。

## 37794017981：蓝牙电量排序预检因缺少 1.5.1 发布说明中止

蓝牙电量优先排序（4 个提交的功能分支，合入 main 后的 head `c46df7b`）的首次非发布预检
[`37794017981`](https://github.com/lingyired/status-trio/actions/runs/37794017981)
使用 `version=1.5.1`、`build=19`、`publish=false`，在
`Build, sign, notarize, and publish` 阶段失败。

- **根因**：仓库缺少 `release-notes/1.5.1/`。前置 `Validate appcast notes` 允许非发布预检在目录不存在时跳过校验，但 `scripts/release.sh` 的目录检查仍要求该目录存在，因此在进入 release 构建、签名和 DMG 打包之前中止。此次失败不涉及 Swift 代码或工具链兼容性。
- **修复**：改用已有 12/12 语言发布说明的 `version=1.5.0`、`build=19` 重新调度预检；不修改产品代码、工作流或应用版本元数据。
- **首轮验证结果**：该 run 的 `Run tests` 全部通过；打包阶段因上述发布说明目录缺失而停止，尚未完成 release 构建、签名、DMG 打包和预检产物上传验证。
- **后续验证**：改用 `version=1.5.0` 的非发布预检 [`37794632312`](https://github.com/lingyired/status-trio/actions/runs/37794632312) 全绿，耗时 15m29s：说明校验、全量测试、通用 release 构建、签名验证、`LC_BUILD_VERSION` 检查、DMG 打包与 artifact 上传全部通过。同时本机同一 head 上 `swift test` 为 571 项 0 失败、`swift build -c release` 通过。本次没有创建 GitHub Release 或更新 appcast。

## 37757549323：macOS 13 兼容性首次预检在产物路径检查处失败

macOS 13 兼容性分支 `codex/macos13-compatibility` 的首次 non-publishing 预检
[`37757549323`](https://github.com/lingyired/status-trio/actions/runs/37757549323)
（`version=1.5.1`、`build=19`、`publish=false`、head `ec1dd4b`）在
`Verify Ventura binary metadata` 阶段失败，`Run tests` 与 `Run native compatibility tests` 已通过。

- **根因**：新增的 metadata step 使用了错误的硬编码产物路径 `dist/Status Trio.app`。`scripts/build-app.sh`
  实际输出 `dist/StatusTrio.app`（bundle 显示名仍为 `Status Trio`），因此 `verify-platform-version.sh`
  在读取 `Contents/MacOS/StatusTrio` 前以“no such file”退出。此次失败不涉及产品代码、二进制元数据或工具链兼容性。
- **修复**：工作流改为读取 `dist/StatusTrio.app`；计划文档同步修正该路径记录。
- **后续验证**：修复后的非发布预检
  [`37758928359`](https://github.com/lingyired/status-trio/actions/runs/37758928359)
  （`version=1.5.1`、`build=19`、`publish=false`、head `8ee4b6d`）全绿，耗时 11m4s：
  `Run tests`、`Run native compatibility tests`、Universal release 构建、Ad-hoc 签名、`StatusTrio-1.5.1.dmg`
  打包、`Verify Ventura binary metadata` 和 artifact 上传全部通过；`publish=false` 未创建 GitHub Release，
  也未更新 appcast。

## 37763140072 / 37763923306 / 37765173557：macOS 13 review-fix 预检在既有 Watch 重试测试上失败

macOS 13 review-fix 分支的三个 `publish=false` 预检
[`37763140072`](https://github.com/lingyired/status-trio/actions/runs/37763140072)（head `29bad4e`）、
[`37763923306`](https://github.com/lingyired/status-trio/actions/runs/37763923306)（head `97323cf`）和
[`37765173557`](https://github.com/lingyired/status-trio/actions/runs/37765173557)（head `88848ff`）
都在 `Run tests` 阶段失败，均为 `MobileBatteryControllerTests.testMissingWatchRetryBudgetSurvivesRepublishedDemandAndBackgroundToggle` 的第 416 行断言：`configuredRefreshRequests` 为 `0`，期望 `1`。其余步骤未执行。

- **失败阶段**：`Run tests`。
- **根因**：测试用精确 `Duration == .seconds(600)` 匹配调度请求；控制器把剩余刷新时间换算为毫秒并向上取整，CI 调度延迟会把它变成 `599.999s` 一类的近似值。测试等待和计数因此看不到目标请求，随后读取到 `0`。这是测试等待逻辑的时间精度问题，不是 `MobileBatteryController` 的 API/行为回归。
- **修复**：测试辅助 actor 的 duration 等待、活跃请求和计数改为 10ms 容差，并保留有界 `ContinuousClock` deadline；只修改测试 helper，不改生产调度代码。
- **后续验证**：第四个 `publish=false` 预检 [`37765927373`](https://github.com/lingyired/status-trio/actions/runs/37765927373)
  （head `c2ea2cc`、`version=1.5.1`、`build=19`、`publish=false`）全绿，耗时 14m23s。
  `Run tests` 通过（1390 XCTest、7 skipped、0 failures；570 Swift Testing / 90 suites），
  `Run native compatibility tests` 通过，Universal release 构建、Ad-hoc 签名、DMG 打包与 artifact 上传通过；
  `Build, sign, notarize, and publish` 在 `publish=false` 下只生成 `StatusTrio-1.5.1.dmg`，未创建 GitHub Release，
  也未更新 appcast。二进制检查显示主程序 x86_64/arm64 均为 `minos 13.0 / sdk 26.0`，Helper 与 dylib 均为
  `minos 13.0`，Sparkle 5 个 Mach-O 文件均满足 Ventura 最低版本，MobileBattery bundle 验证通过。

### 合并 main 后的测试辅助 actor

合并 `codex/macos13-compatibility` 到 main 时，这条 10ms 容差修复与 main 上更晚的
`e9ab294`（retry-budget 测试注入固定时钟、三个 wait helper 改为带 5 秒 deadline 的
`async throws` 条件等待、超时抛 `WaitTimeout`）落在同一个 helper 上。两边都保留：

- 保留 main 的 throwing/deadline 设计，因为它是唯一能让「缺失调度事件」确定性失败的路径；
- 保留本条的 10ms 容差，因为它覆盖的是 main 未覆盖的那半边——仍使用真实时钟的用例
  （`waitForDuration(.seconds(120))`、`.seconds(1_200)` 等）。调度器把剩余时间换算成
  整毫秒并向上取整，真实时钟上超过 1ms 的调度延迟就会让记录值变成 `119.998s` 一类，
  精确 `==` 匹配不到。容差取 0.01s，相邻的整秒区间（599s 与 600s）相距 1s，不会互相别名。
- `fire(duration:)` 仍是精确匹配：它要唤醒的是某个具体 waiter，近似匹配可能唤醒错误的那个。

合入 main 的 head `da6f5c9` 已用非发布预检
[`37808512388`](https://github.com/lingyired/status-trio/actions/runs/37808512388)
（`version=1.5.1`、`build=22`、`publish=false`、`notarize=false`）验证，耗时 12m14s 全绿：
`Run tests`、`Run native compatibility tests`、Universal release 构建、Ad-hoc 签名、
DMG 打包与 artifact 上传全部通过；`publish=false` 未创建 GitHub Release，也未更新 appcast。
本机同一 head 上 `swift test` 为 573 Swift Testing / 90 suites 通过、`swift build -c release` 通过。
这条记录本身的提交只补充验证说明，不改变已通过预检的产品代码。

## 38262423399 / 38278475902 / 38279498535：低电量模式控制器测试的时间竞态

`LowPowerModeControllerTests.testDisablingClearsErrorAndStopsContact` 在 CI 上间歇失败。主干预检
[`38262423399`](https://github.com/lingyired/status-trio/actions/runs/38262423399)
（head 为 `test/72-103-combined`）与 issue #110 分支的首次非发布预检
[`38278475902`](https://github.com/lingyired/status-trio/actions/runs/38278475902)
（head `14b050e3`、`version=1.6.0`、`build=25`、`publish=false`、`notarize=false`）
都停在 `Run tests` 阶段、第 95 行 `XCTAssertNotNil(controller.lastError)`，同一行号，其余步骤未执行。
#110 的改动只涉及 Wi-Fi，与低电量模式无关。

- **失败阶段**：`Run tests`（XCTest；同一次 run 的 563 项 Swift Testing 已全部通过）。
- **根因**：该断言靠 `settle()` 里固定 10 次 `Task.yield()` 等控制器写路径完成。写路径在 nonisolated 的
  `await client.setLowPowerMode(...)` 上挂起后再回到 main actor，这个跨执行器的往返不是 yield 计数能保证的；
  CI 负载高时十次 yield 覆盖不到，`lastError` 尚未写入即断言。这是测试等待逻辑的缺陷，不是
  `LowPowerModeController` 的行为回归。
- **修复**：只改测试 helper。新增带 5 秒 deadline 的 `waitUntil { ... }` 条件等待（与 main 上 `e9ab294`
  已确立的 throwing/deadline 约定一致），把依赖异步完成的断言改为等待具体条件；只在“断言没有异步工作发生”的
  用例保留一个有时限的 `settle()` 排空。生产代码不变。
- **后续验证**：修复后 head `907624ad` 的非发布预检
  [`38279498535`](https://github.com/lingyired/status-trio/actions/runs/38279498535)
  （`version=1.6.0`、`build=25`、`publish=false`、`notarize=false`）全绿，耗时 15m6s：
  `Run tests` 通过（1,461 XCTest、7 skipped、0 failures；563 Swift Testing / 89 suites），
  `Run native compatibility tests` 通过，appcast 说明 12/12 语言校验通过，Universal release 构建产出
  `StatusTrio-1.6.0.dmg`（`LC_BUILD_VERSION` 检查对主程序、两个 helper 与 MobileBattery 动态库全部通过），
  Ad-hoc 签名与 artifact 上传通过；`publish=false` 未创建 GitHub Release，也未更新 appcast。本机同一 head 上
  `swift test` 563 项、`swift build -c release` 均通过，且 `LowPowerModeControllerTests` 单独连续三次运行 0 失败。
  本条记录本身的提交只补充说明，不改变已验证的产品代码。

## 38558727357：输入音频恢复测试匹配到旧状态

helper 生命周期分支的非发布预检
[`38558727357`](https://github.com/lingyired/status-trio/actions/runs/38558727357)
（head `5757b420`、`version=1.6.0`、`build=29`、`publish=false`）在 `Run tests` 失败。

- **失败位置**：`AudioInputMonitorTests.testRecoverRefreshesAndStoppedObservationCallbackIsIgnored`
  第 289 行；`fullReadCount` 为 `1`，期望 `2`。
- **根因**：恢复等待只匹配 `defaultDeviceID == 11`。`recover()` 先发布仍携带旧设备 ID 的
  `isRefreshing` 状态，新的硬件读取尚未完成就能满足该等待，导致提前断言。这不是 helper
  生命周期改动或 Swift 编译失败。
- **修复**：仅调整该测试。初次读取等待终态；恢复前把假硬件的默认设备改为 `22`，等待
  `defaultDeviceID == 22 && !isRefreshing`，让旧状态无法满足恢复期望。保留读取次数和停用后
  回调无效的断言，不延长超时，也不改生产音频代码。
- **本机验证**：修复后 `swift test` 通过 1502 项 XCTest（7 项跳过）与 587 项
  Swift Testing，0 失败；`swift build -c release` 通过。修复后的非发布预检
  [`38560578171`](https://github.com/lingyired/status-trio/actions/runs/38560578171)
  （head `03c424d1`、`version=1.6.0`、`build=29`、`publish=false`）全部通过。
  该 CI 结果不代表系统审批切换的实机验证通过：同一构建的手动复测仍出现 native
  待批准与实际 XPC 可用不一致，后续就绪判定改动需另行验证。

## 38541853330：helper 审批恢复预检中的 Dock 测试失败

非发布预检 [`38541853330`](https://github.com/lingyired/status-trio/actions/runs/38541853330)
（head `5fd71618`、`version=1.6.0`、`build=27`、`publish=false`）在 `Run tests` 阶段失败。

- **失败位置**：`ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork`，
  第 48 行；等待 5 秒后 `renderCount` 仍为 `1`，未超过初始值 `1`。helper 测试通过。
- **根因状态**：尚未确认。该用例已经使用有界条件等待，不能归因于固定 `Task.yield()` 次数，
  也没有 Swift 编译错误的证据。本机完整测试通过；单次 CI 失败不足以证明这是偶发调度问题。
- **处理**：保留原测试与断言，不增加超时或绕过用例。先核对后续预检的同一测试结果；
  若再次失败，继续检查电池更新、presentation 调度和 Dock 重绘之间的路径。
- **验证**：包含最后一项审批错误修复的 head `2135e0eb` 本机 `swift test` 通过
  （1497 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites），
  `swift build -c release` 通过。后续非发布预检
  [`38542541814`](https://github.com/lingyired/status-trio/actions/runs/38542541814)
  （同一产品代码 head `2135e0eb`、`version=1.6.0`、`build=28`、`publish=false`）全绿：
  `Run tests`、原生兼容检查、Universal release 构建、DMG 打包和 artifact 上传全部通过。
  原 Dock 测试未修改，后续运行通过，但首次失败的具体根因仍未确认。
  CI 使用 Ad-hoc 签名；本机安装版单独通过 Developer ID 签名、公证与 stapler 验证。
  用户按“系统关闭 → App 开启 → 系统开启”的流程确认等待提示自动消失、绿叶可用，
  本机日志也记录自动 `register()` 返回成功、状态从 `2` 转为 `1`。没有发布 Release 或修改 appcast。

## 38741027089：预检用了还没写发布说明的版本号

输入法中间图标分支的第一个非发布预检
[`38741027089`](https://github.com/lingyired/status-trio/actions/runs/38741027089)
（head `2b693eb3`、`version=1.6.1`、`build=38`、`publish=false`）在 `Build, sign, notarize, and publish`
阶段失败：

```
Error: release notes directory does not exist: …/release-notes/1.6.1
```

- **失败位置**：`bash scripts/release.sh` 第 163 行的发布说明目录检查，测试与原生兼容检查已经在
  这一步之前通过。
- **根因**：`publish=false` 只跳过 appcast 发布，不跳过发布说明；`scripts/release.sh` 要求
  `release-notes/<version>/` 存在。预检不是发布，随便挑一个「下一个」版本号就会在这一步中止。
- **修复**：改用已有发布说明的 `version=1.6.0` 重跑，代码未改动。
- **验证**：同一 head 的非发布预检
  [`38741878250`](https://github.com/lingyired/status-trio/actions/runs/38741878250)
  （`version=1.6.0`、`build=38`、`publish=false`、`notarize=false`）在 CI 工具链
  （`macos-26` / Xcode 26.6 / Swift 6.3.3）上全绿：`Run tests`、`Run native compatibility tests`、
  Universal release 构建、DMG 打包和 artifact 上传全部通过。该次预检走 Ad-hoc 签名，
  未创建 GitHub Release，也未修改 appcast。

**规则**：新子系统的非发布预检要复用当前版本号（`release-notes/<version>/` 已存在），
除非同一次改动里已经写好新版本的发布说明。`scripts/validate-appcast-notes.sh` 在
`publish=false` 时会对缺失目录只发 `::notice::`，而 `scripts/release.sh` 会直接报错，
这个差异正是这次失败的位置。

## 38741878250：输入法中间图标加入新子系统的预检

非发布预检 [`38741878250`](https://github.com/lingyired/status-trio/actions/runs/38741878250)
（head `2b693eb3`、`version=1.6.0`、`build=38`、`publish=false`）在 CI 工具链上全绿，
耗时约 17 分钟：

- `Run tests` 通过（1,595 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites 也通过）。
  本机的 1,585 与 CI 的 1,595 差 10 个用例，全部是 `#available(macOS 26/27)` 门控的用例：
  CI 运行在 macOS 26 上，本机是 macOS 27。输入法相关的新用例在两个版本上都运行。
- `Run native compatibility tests` 通过，含 macOS 13 bundle/Sparkle 契约检查。
- Universal release 构建产出 `x86_64 arm64` 双架构切片，`LC_BUILD_VERSION` 为
  `minos 13.0 / sdk 26.0`；`StatusTrioPowerHelper` 与 MobileBattery 框架的签名与
  designated requirement 校验通过。
- 该预检 `publish=false` 且 `notarize=false`，因此走 Ad-hoc 签名。未创建 GitHub Release，
  也未更新 appcast。

本机同一 head（Xcode 27.0 / Swift 6.4）上 `swift test`（1,585 tests、7 skipped、0 failures）、
`swift build -c release` 和 `swift test --filter Issue30WiFiAlignmentTests`（5/5）均通过。
`@MainActor` / SwiftUI / `Bundle.module` 相关改动的 CI 编译兼容性由此确认；
真实前台输入切换、候选框行为与 macOS 13/15/26 设备验证不在 CI 覆盖范围，
见 [输入法中间图标](input-source-center-slot.md)。

## 38754577081：输入法图标尺寸与面板行改动的预检

第二轮输入法反馈（中间图标跟随 Wi-Fi 图标大小、状态面板改为行 + 切换列表、
行列图标的单色处理）的非发布预检
[`38754577081`](https://github.com/lingyired/status-trio/actions/runs/38754577081)
（head `60c8db89`、`version=1.6.0`、`build=38`、`publish=false`、`notarize=false`）
在 CI 工具链上全绿，耗时约 20 分钟：

- `Run tests` 通过（1,603 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites 也通过）。
  本机 1,593 与 CI 1,603 的差仍是 `#available(macOS 26/27)` 门控的用例。
  本轮新增的 `InputSourceIconMaskTests`、`InputSourcePanelLayoutTests` 和缓存用例在两个
  macOS 版本上都运行。
- `Run native compatibility tests` 通过，含 macOS 13 bundle/Sparkle 契约检查。
- Universal release 构建、DMG 打包与 artifact 上传通过；该次预检 `publish=false` 且
  `notarize=false`，走 Ad-hoc 签名，未创建 GitHub Release，也未更新 appcast。

本机同一 head（Xcode 27.0 / Swift 6.4）上 `swift test`（1,593 tests、7 skipped、0 failures）、
`swift build -c release` 和 `swift test --filter Issue30WiFiAlignmentTests`（5/5）均通过；
面板行、图标掩膜与菜单栏尺寸条通过测试内渲染的截图人工核对。真实前台输入切换、
候选框行为与 macOS 13/15/26 设备验证仍不在 CI 覆盖范围。

## 38770589762：中间槽文字锚点修复的预检

用户第二轮反馈的第三个问题（160% 的输入法短标签 `A` 压到外环充电闪电）修好后，
非发布预检
[`38770589762`](https://github.com/lingyired/status-trio/actions/runs/38770589762)
（head `7bef0428`、`version=1.6.0`、`build=38`、`publish=false`、`notarize=false`）
在 CI 工具链上全绿，耗时约 13 分钟：

- `Run tests` 通过（1,604 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites 也通过）。
  本机 1,594 与 CI 1,604 的差仍是 `#available(macOS 26/27)` 门控的用例。
  本轮新增的 `Issue30WiFiAlignmentTests.testInputSourceLabelInkKeepsTheSlotCentreAtEveryScale`
  在两个 macOS 版本上都运行，并且在旧算法下会失败（160% 实测 21.6，期望 64.25），
  证明它确实守住了这次的缺陷。
- `Run native compatibility tests` 通过，含 macOS 13 bundle/Sparkle 契约检查。
- Universal release 构建、DMG 打包与 artifact 上传通过；该次预检 `publish=false` 且
  `notarize=false`，走 Ad-hoc 签名，未创建 GitHub Release，也未更新 appcast。

本机同一 head（Xcode 27.0 / Swift 6.4）上 `swift test`（1,594 tests、7 skipped、0 failures）、
`swift build -c release` 和 `swift test --filter Issue30WiFiAlignmentTests`（6/6）均通过；
修复前后的菜单栏条带、以及"槽内电量百分比"受同一路径影响的对比条，都通过测试内渲染截图人工核对。
真实前台输入切换、候选框行为与 macOS 13/15/26 设备验证仍不在 CI 覆盖范围。

## 38867314730 与 38868054372：Issue #115 DDC 匹配的预检

Issue #115（当前默认音频输出 → 唯一 DDC Service 匹配）新增了一个泛型函数
（`DDCTargetResolver.openResolvedTarget<Handle, Opened>`）和 IOKit 侧的 resolve 改写，
因此按规则走非发布预检。

第一次派发
[`38867314730`](https://github.com/lingyired/status-trio/actions/runs/38867314730)
（head `107d5493`、`version=1.6.1`、`build=38`、`publish=false`）**失败**，失败阶段是
`Build, sign, notarize, and publish`，根因是 `version=1.6.1` 没有对应的
`release-notes/1.6.1` 目录，`scripts/release.sh` 在打包前直接报
`release notes directory does not exist` 并退出 1——不是工具链或代码编译问题
（同一 run 的 `Run tests`、`Run native compatibility tests` 都已通过）。

修复方式是改用已存在的版本号并只抬高 build：重新派发
[`38868054372`](https://github.com/lingyired/status-trio/actions/runs/38868054372)
（head `107d5493`、`version=1.6.0`、`build=38`、`publish=false`、`notarize=false`），
在 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）上全绿，耗时约 15 分钟：

- `Run tests` 通过（1,627 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites）。
  本机 1,620 与 CI 1,627 的差仍是 `#available(macOS 26/27)` 门控的用例；
  两边的 skipped 数（本机 10 / CI 7）同样只反映这些平台门控。
- `Run native compatibility tests` 通过，含 macOS 13 bundle/Sparkle 契约检查与
  `privileged helper bundle-contract regressions passed`。
- Universal release 构建产出 `StatusTrio-1.6.0.dmg`，输出 `Built … without publishing.`；
  该次预检 `publish=false` 且 `notarize=false`，走 Ad-hoc 签名，未创建 GitHub Release，
  也未更新 appcast。

本机同一 head（Xcode 27.0 / Swift 6.4）上 `swift test`（1,620 XCTest、10 skipped、
0 failures；587 Swift Testing / 91 suites）与 `swift build -c release` 均通过。
DDC 只有单台 XV272U 实机证据；双外接屏分别作为默认输出的场景未在真机验证，
见 [issue-115-ddc-targeting](verification/issue-115-ddc-targeting.md)。

## 38885873584 与 38885964515：Issue #115 DDC 读协议预检与测试 DMG

第二轮（Get VCP 校验和显式化 + 受控只读 profile 探测 + `ddc.*` 诊断）同样按规则
走非发布预检，并额外产出一次可供报障用户安装的测试 DMG。

第一次派发
[`38885873584`](https://github.com/lingyired/status-trio/actions/runs/38885873584)
（head `fbf8baf7`、`version=1.6.0`、`build=39`、`publish=false`、`notarize=true`）
**失败**，失败阶段是 job `release` 本身（2 秒内结束，没有任何步骤运行），根因是
`distribution` environment 的 protection rule：

```
Branch "codex/issue-115-ddc-output-matching" is not allowed to deploy to
distribution due to environment protection rules.
```

这不是证书/密钥缺失，也不是代码或编译失败——该 environment 只允许受保护分支部署。
修复方式是按 Plan 的降级路径改用 Ad-hoc：
[`38885964515`](https://github.com/lingyired/status-trio/actions/runs/38885964515)
（head `fbf8baf7`、`version=1.6.0`、`build=39`、`publish=false`、`notarize=false`）
在 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）上全绿，耗时约 15 分钟：

- `Run tests` 通过（1,653 XCTest、7 skipped、0 failures；587 Swift Testing / 91 suites）。
- `Run native compatibility tests` 通过，含 macOS 13 bundle/Sparkle 契约与
  `privileged helper bundle-contract regressions passed`。
- `Built …/StatusTrio-1.6.0.dmg without publishing.`；artifact 名为
  `StatusTrio-306`，内含 `StatusTrio-1.6.0.dmg`、`StatusTrio-1.6.0.dmg.sha256`、
  `release.env`。挂载后确认 `CFBundleShortVersionString=1.6.0`、
  `CFBundleVersion=39`、签名为 Ad-hoc；未创建 GitHub Release，也未更新 appcast。
- 该 artifact 的 `release.env` 中 `DMG_URL` 指向
  `releases/download/v1.6.0/...`，`publish=false` 下**并不存在**，不能当作下载地址。

本机同一 head（Xcode 27.0 / Swift 6.4）上 `swift test` 1,646 XCTest（10 skipped、
0 failures；587 Swift Testing / 91 suites）与 `swift build -c release` 均通过；
另外用真实 XV272U 跑了一次只读探针，确认 P1（standard `82 01 62 DE`）可读出当前值，
且 `ddc.resolve` / `ddc.probe` / `ddc.selectedProfile` 能被
`log show --info` 取出。BenQ 真机与 P3/P4 回退路径仍未验证。

## 38893936661 与 38893992336：1.6.1 测试 DMG

同一分支改用 `version=1.6.1` 重新出包时，`release.sh` 需要
`release-notes/1.6.1/` 存在，因此先补了 `en.md`、`zh-Hans.md`
（`publish=false` 只要求目录存在；`publish=true` 仍要求全部 12 种语言）。

- [`38893936661`](https://github.com/lingyired/status-trio/actions/runs/38893936661)
  （head `ca3b832f`、`version=1.6.1`、`build=40`、`publish=false`、`notarize=true`）
  **失败**，仍是 `distribution` environment 的 protection rule：
  `Branch "codex/issue-115-ddc-output-matching" is not allowed to deploy to distribution`。
  与 `38885873584` 同因，说明该 environment 的分支限制没有变化，不是证书或代码问题。
- [`38893992336`](https://github.com/lingyired/status-trio/actions/runs/38893992336)
  （同 head、`notarize=false`）在 CI 工具链上全绿，耗时约 15 分钟：
  `Run tests` 1,653 XCTest（7 skipped、0 failures）+ 587 Swift Testing / 91 suites；
  native compatibility tests 通过；`Built …/StatusTrio-1.6.1.dmg without publishing.`。
  artifact `StatusTrio-308` 内含 `StatusTrio-1.6.1.dmg`（`CFBundleVersion=40`、
  Ad-hoc 签名、无公证 ticket）与 `.sha256`；未创建 Release、未更新 appcast。

要在该分支拿到**公证版**，需要把 `distribution` environment 的 deployment branch
规则放开（或改由受保护分支/标签触发）；管理该设置属于仓库权限变更，未擅自执行。

## 39376165822：内存优化预检中的测试调度依赖

- 运行：[39376165822](https://github.com/lingyired/status-trio/actions/runs/39376165822)，
  head `04206b5`，`version=1.6.1`、`build=38`、`publish=false`，
  CI 为 Xcode 26.6 / Swift 6.3.3；失败阶段为 `Run tests`。
- CI XCTest 1727 项（7 skipped）通过；Swift Testing 697 项中出现 3 个 issue：
  `StatusBarControllerVisibilityTests.testSwitchAnimatesTheMenuBarWhileTheRealBatteryIsUnplugged`
  的两个保留动画断言，以及
  `ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork` 的重绘计数断言。
- 菜单栏根因：测试先关闭合成充电输入，再开启注入的绘图失败开关；
  超过 50 ms coalescing interval 时，设置发布会立即重绘，已成功回到静态图。
  原测试却仍假设失败发生在该重绘之前。为测试插入 75 ms quiet interval 后，
  本地稳定重现相同的两个失败；将失败开关移到设置发布前并显式 drain 后，
  同样的 quiet interval 下两项 visibility 测试通过。正式测试移除了复现用 sleep。
- Dock 测试将 AsyncStream → store → 500 ms presentation debounce → 50 ms
  redraw coalescer 的整条链路当作 5 秒内应自动完成的操作，仅轮询最终 renderCount。
  失败日志没有分阶段观测，不能确定这次 CI 延迟具体落在哪一级；同一轮中
  `visibleDockRendersStatusChanges` 通过，未获得产品绘制逻辑回归的证据。修复改为
  注入既有 ManualIconPresentationScheduler，先验证电量进入 store 与 pending debounce，
  显式执行 debounce，确认 scene 为 61%，再 flush redraw。保留重绘断言，
  不延长 timeout、不修改产品节流逻辑。
- 复验：本地菜单栏定向测试 2 项通过；修复后全量 1717 XCTest（7 skipped）和
  697 Swift Testing / 103 suites 全部通过，Release 构建通过（33.35 秒）。
- [39377387434](https://github.com/lingyired/status-trio/actions/runs/39377387434)
  对修复后 head `8728003` 全部通过：CI 1727 XCTest（7 skipped）+
  697 Swift Testing / 103 suites；native compatibility tests、双架构 Release、
  两种 helper bundle 校验、DMG 创建及 artifact 上传均通过。仍为
  `version=1.6.1 build=38 publish=false notarize=false`，未发版。

## 39422907935：PR #123 定位权限缓存预检

- 运行：[39422907935](https://github.com/lingyired/status-trio/actions/runs/39422907935)，
  第一次 attempt，head `a1fcd448`，临时分支 `codex/preflight-pr-123`，
  `version=1.6.0`、`build=38`、`publish=false`、`notarize=false`；
  失败阶段为 `Run tests`，后续兼容性检查和打包未运行。
- XCTest 1729 项（7 skipped、0 failures）全部通过，包含新增的 Wi-Fi 授权缓存测试；
  Swift Testing 697 项 / 103 suites 报告 11 个 issue，集中在
  `AppIconControllerTests`（4）、`IconSurfaceIntegrationTests`（6）和
  `DockChargingEnvironmentTests`（1）。前两组主要是 5 秒内未观察到合并重绘，
  后一组是开发充电预览尚未观察到 steady phase。
- 根因调查：这些测试依赖主 actor 上的异步状态传播、重绘 coalescer 或真实动画时钟；
  首次失败日志只有最终等待超时或断言，缺少各阶段观测，尚不能确定阻塞在哪一级，
  也不能据此归因于本次 Wi-Fi 缓存改动。相关等待逻辑在 PR 中未改动。
- 修复及验证：未修改产品代码或放宽断言；同一 head 的本地完整测试通过
  （Xcode 27 / Swift 6.4：1719 XCTest、7 skipped、0 failures；
  697 Swift Testing / 103 suites），相关三个测试组均通过。
  第二次 CI attempt 全部通过：1729 XCTest（7 skipped、0 failures）、
  697 Swift Testing / 103 suites、native compatibility tests、双架构 Release、
  mobile battery / privileged helper bundle 校验、DMG 创建和 artifact 上传。
  产物为 `StatusTrio-324`，包含 `StatusTrio-1.6.0.dmg`；日志确认
  `Built … without publishing.`，使用 Ad-hoc 签名，未进行 Apple 公证，
  未创建 Release 或更新 appcast。
  运行间结果有差异，但仍未获得首次失败的精确阶段根因；
  不把首次失败解释为编译器问题，也不以复验通过抹去首次失败。

## 39441930496 至 39447874014：异步图标测试与部署契约假通过

同一 SHA 的结果差异把测试稳定性问题与工具链兼容性区分开了：

- [`39441930496`](https://github.com/lingyired/status-trio/actions/runs/39441930496)
  成功；
  [`39441995782`](https://github.com/lingyired/status-trio/actions/runs/39441995782)
  对同一 head `c8c49315` 失败，失败阶段均为 `Run tests`。
- 后续
  [`39443852308`](https://github.com/lingyired/status-trio/actions/runs/39443852308)
  （head `68282826`）、
  [`39444905968`](https://github.com/lingyired/status-trio/actions/runs/39444905968)
  （head `099baec0`）和
  [`39447874014`](https://github.com/lingyired/status-trio/actions/runs/39447874014)
  （head `d8a3b97c`）连续失败，Swift Testing 分别在约 6.44、6.85、6.30 秒
  汇总失败；XCTest 已完成。失败集中在
  `AppIconControllerTests.visibleDockRendersStatusChanges`、
  `IconSurfaceIntegrationTests` 的多条 surface 等待、
  `ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork`
  和 `DockChargingEnvironmentTests` 的 restore/steady-phase 断言。
- 根因不是编译器或产品渲染差异。原测试把 500 ms presentation debounce、
  50 ms render coalescer、20 Hz charging clock 和 AsyncStream 消费绑定成一个
  5 秒 wall-clock 等待；整套 Swift Testing 在主 actor 上并发启动时，固定窗口内
  实际到达哪一级并不确定。失败 Run 的日志也显示多个 suite 在同一时刻启动并
  在一个 5 秒窗口后一起报错。
- 修复只为测试注入既有的 `ManualIconPresentationScheduler`、`IconRenderCoalescer`、
  `ManualEventSleeper` 和受控 charging clock，先等待 store/debounce 等确定事件，
  再显式执行 debounce、coalescer drain 和时钟帧。没有延长 timeout、删除断言、
  skip 测试或修改产品节流逻辑；超时现在抛出包含 snapshot、store 场景、
  pending debounce、render count 和最后渲染 scene 的错误。
- 定向验证：最终清理后
  `swift test --filter 'AppIconControllerTests|IconSurfaceIntegrationTests|ChargingEffectControllerTests|DockChargingEnvironmentTests'`
  通过 66 tests / 4 suites；默认调度 10/10 轮、四个 suite 分别单独执行 3/3 轮、
  `--parallel` 10/10 轮均通过。第一次默认 10 轮在第 8 轮捕获到
  `mappedSettingsStayInParityAcrossMenuBarAndDock` 的真实竞态：充电场景已到
  model，但菜单栏与 Dock 的异步交付尚未同时收敛，测试立即断言失败。修复后
  先等待两个 surface 都交付同一 scene，再保留严格相等断言；随后 10/10 通过。
  最终 `swift test` 连续 3 轮通过：每轮 XCTest 1719（7 skipped、0 failures）
  和 Swift Testing 697 tests / 103 suites；`swift build -c release` 通过。

同时修复了 `scripts/test-macos13-deployment-contract.sh` 的已证实假阳性：
旧脚本在缺少 `rg` 时让 `if rg ...` 进入 false 分支，然后无条件打印
`macOS 13 deployment contract passed` 并退出 0。用受控 fixture 在
`PATH` 中没有 `rg`、但存在 `grep` 的环境复现了这一行为
（旧脚本 `rg: command not found` 后仍退出 0）。新实现优先用 `rg`，不可用时
自动回退到 `grep -E -R`，并把扫描器的 0（找到禁止常量）、1（未找到）与
其他退出码严格区分；工具缺失和执行错误都会 fail closed。新增
`scripts/test-macos13-deployment-contract-regressions.sh` 覆盖正常 13.0、
禁止 15.0、显式 grep、自动 grep fallback、工具缺失和 scanner exit 2，
并接入 release workflow 的 native compatibility step。

## PR #124：华为传输发现、连接所有权与充电图层并发

- DeepSeek 子任务基于 `group/auto-deepseek-v4-1-flash` 完成了独立功能审查。审查确认
  HUAWEI 噪声控制已接入实时设备、面板行、写入与 read-back；同时发现首次状态读取失败后
  不会重试，以及 transport 打开的 Bluetooth 连接在部分失败路径未释放。后续审查还发现
  明确的非 HUAWEI vendor ID 会被 `FreeBuds` 名称兜底错误识别，以及取消发生在 RFCOMM
  通道打开后时只关闭连接而未关闭通道。
- 修复保持原有功能断言：首次无已确认状态时最多使用 150 ms、450 ms 两次有界重试；
  已有确认模式的后续读取失败继续保留该模式。Transport 只关闭自己成功打开的设备连接，
  并覆盖连接超时、SDP、RFCOMM、读写、取消、过期连接、`closeAll()` 与会话关闭路径；
  预存连接保持原所有者。明确 vendor ID 优先于名称兜底。
- 定向验证通过：华为协议、控制器、首用并发启动和生命周期共 30 项；
  `Issue30WiFiAlignmentTests`、输出设备听音控制行、面板 task ID 与 Dock 充电恢复
  定向测试也通过，且 `git diff --check` 通过。
- 本轮全量 `swift test` 暴露 4 个 issue，集中在既有
  `StatusBarChargingAnimationTickTests.steadyTicksReuseTheTemplateBaseAndThePreRenderedFrames`：
  测试快照前观察到基础层被处理两次，从而连带有 4 个计数/对象身份断言失败。6 项充电
  tick suite 再次运行时有 1 个同类 issue，随后单独复跑通过，说明该测试的初始呈现
  handoff 仍与实际 `Task.sleep` 调度竞争。重试的 39 个 HUAWEI 定向测试全部通过，
  证明本次华为代码没有引入这些计数失败。按本条记录的测试调度原则，后续以已有可控
  presentation 调度器替换固定 sleep，保留“静止呈现只栅格化一次、稳态 tick 不重建基础层”
  的全部计数与对象身份断言，再运行完整本地测试和非发布 CI 预检。
