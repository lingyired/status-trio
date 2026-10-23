# PR #124 HUAWEI 降噪控制修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 本计划交给 DeepSeek 执行；修复后回报验证结果，交回审查，不自动合并或发布。

**Goal:** 修复 PR #124 的四项 P2 问题，保留现有 AirPods 行为及 HUAWEI SPP 读回确认机制。

**Architecture:** 保持 CoreAudio 与 HUAWEI 两条路径独立。输出列表身份使用当前收到的值；端点匹配拒绝相反的地址证据；传输层用同步的任务取消状态和会话代际控制排队工作及启动/关闭顺序。

**Tech Stack:** Swift 6、Combine、SwiftUI、CoreAudio、IOBluetooth、XCTest。

**Spec:** https://github.com/lingyired/status-trio/pull/124 及仓库 `AGENTS.md`。

## 审查基线与结论

- 审查日期：2026-10-20。
- PR：`https://github.com/lingyired/status-trio/pull/124`。
- Base：`99d6fa998187ba2d5beced13377ed9ceee6ca263`。
- Head：`ace36b341d32da004614e4555b95fa341b9b346f`，源仓库 `yunhai-dev/status-trio`，分支 `feat/huawei-noise-control`。
- 结论：暂不合并。下面四项都应修复后复审。

行号均对应上述 Head。执行前重新读取 PR Head；如已更新，先确认问题是否仍在，不要覆盖贡献者的新修改。

## Global Constraints

- CI 验收工具链：`macos-26`、Xcode `26.6`、Swift `6.3.3`；构建 SDK 必须为 macOS 26 或更新。
- 不使用 `isolated deinit`、`IsolatedDeinit` 或 `weak let`；保留既有 actor 隔离规则。
- 不改 AirPods 模式选择、监听订阅、预览行为及 `DeviceOperationToken` 的既有保障。
- HUAWEI 模式写入必须以设备读回状态确认；仅 ACK 或用户请求值均不能当作成功。
- 保留每个传输实例仅启动一个工作线程、串行非重入执行以及 delegate 缓冲区同步。
- 当前主工作区有不相关的未提交文件；从 PR Head 建立隔离工作区，不切换或清理主工作区，不提交那些文件。
- 不改版本号，不打 tag，不创建 Release，不更新线上 appcast。需要非发布 CI 验证。

## 验证证据与边界

原始 PR Head 的 `swift test`：1,733 项 XCTest，跳过 7 项，0 失败；697 项 Swift Testing，0 失败。`swift build -c release` 成功。验证机器使用 Xcode 27.0 / Swift 6.4，不能代替项目 CI 工具链验收。

新增两个审查回归测试均在原始实现上失败，证明任务 1、2 的问题。任务 3、4 是静态执行路径确认的竞态，尚未用可控调度测试运行复现，必须补相应测试。没有使用真实华为耳机验收本次审查；PR 作者的 FreeBuds 6i 实机声明不能当作本次独立验收。

非发布说明校验通过：`VERSION=1.6.1 BUILD=38 PUBLISH=false`，现有 en、zh-Hans 两种语言；发布前仍需满足全部 12 语言要求。本次未启动 GitHub Actions，PR 当前无检查记录。

审查日志保存在主工作区 `output/pr124-review/`；文末提供两个失败回归测试的完整补丁，方便迁移。

## Review Focus

1. 只改变输出设备列表，其他音量字段及蓝牙地址不变，发现任务仍应刷新；任务 1 覆盖。
2. 同名耳机具有不同地址，不能把一台的控制挂到另一台输出行；任务 2 覆盖。
3. 任务取消后，尚未执行的蓝牙写入不得再产生硬件副作用；任务 3 覆盖。
4. 第一次启动与关闭交错时，旧会话不得在关闭后新开通道；任务 4 覆盖。
5. 关闭后重新打开面板应能正常工作，旧回调不能污染新会话，continuation 不得重复恢复；任务 3、4 覆盖。

## Task 1：输出列表身份使用当前收到的 VolumeStatus

**优先级：P2。** `Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift:294`。

**原因与影响：** `store.$liveVolume` 在 `@Published` 的 willSet 时同步调用 `mapVolume(status)`。新行使用传入的 `status`，但 `currentListeningModeTaskID` 重新读取尚未赋值的 `store.liveVolume`。设备列表已是 `[1, 42]`，任务 ID 仍为 `|outputs:1`；`.task(id:)` 不重新发现端点，HUAWEI 控制可能继续缺失或留在错误的行。`SystemStatusStore.applyVolume` 会去重，不能依赖相同的下一次轮询纠正。

**Files:**
- Modify: `Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift`。
- Test: `Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift`。

- [ ] 应用文末 `testReviewPR124OutputListIdentityUsesDeliveredVolume`，运行并确认原实现失败。
- [ ] 把 `currentListeningModeTaskID` 改为接收输出列表的方法；在 `mapVolume(_ status:)` 中传入 `status.outputDevices`，不在这个方法中重新读取 `store.liveVolume`。

```swift
// mapVolume(_ status:) 内：
listeningModeTaskID: listeningModeTaskID(outputDevices: status.outputDevices),

// 将原 computed property 改成方法，原有 connected/preview/synthetic 逻辑保留：
private func listeningModeTaskID(outputDevices: [AudioOutputDevice]) -> String {
    let configuration = ListeningModePreview.Configuration(
        isEnabled: settings.previewsBluetoothListeningMode,
        deviceName: settings.bluetoothListeningModePreviewDeviceName,
        deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
        languageCode: settings.bluetoothListeningModePreviewLanguage
    )
    let connected = BluetoothDevicePresentation.grouped(store.bluetoothDevices.devices).connected
        .filter { $0.isAirPods || $0.isHuaweiAudio }
        .map { BluetoothBatteryReader.normalizedAddress($0.id) }
        .joined(separator: ",")
    let preview = configuration.isEnabled ? "|preview" : ""
    let synthetic = ListeningModePreview.devices(for: configuration)
        .map { BluetoothBatteryReader.normalizedAddress($0.id) }
        .joined(separator: ",")
    let outputs = outputDevices.map { String($0.id) }.joined(separator: ",")
    return connected + preview + (synthetic.isEmpty ? "" : "|\(synthetic)") + "|outputs:\(outputs)"
}
```

- [ ] 将回归扩展到移除端点：`[1, 42] → [1]`，要求同一次映射的行与 ID 均为最新值。保留原有 AirPods、HUAWEI 过滤及 preview 身份断言。
- [ ] 运行 `swift test --filter StatusPanelViewModelTests`，全部通过后再执行下一项。

## Task 2：名称回退不得覆盖冲突的蓝牙地址

**优先级：P2。** `Sources/StatusTrioCore/Audio/HuaweiAudioEndpointResolver.swift:41`。

**原因与影响：** 当设备 A 没有输出端点，而同名设备 B 有端点时，A 的地址未匹配，随后的名称匹配仍接受 UID 明确属于 B 的端点。A 的控制因而出现在 B 的输出行；点击该行却向 A 发送指令。两台设备可能竞争同一个端点映射。

**Files:**
- Modify: `Sources/StatusTrioCore/Audio/HuaweiAudioEndpointResolver.swift`。
- Test: `Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift`。

- [ ] 应用文末 `testReviewPR124ConflictingAddressCannotMatchByName`，确认原实现返回 `9` 而不是 `nil`。
- [ ] 提取 UID 中的地址证据。只有严格符合六组十六进制字节的地址才算有效地址证据，不要把任意 UID 的非空 normalized 字符串当作地址。兼容 `AA-BB-CC-DD-EE-FF:output`，测试冒号分隔地址；从尾部识别 `:output` 后解析地址，不能简单按第一个冒号截断。
- [ ] 保留唯一地址匹配优先及重复地址匹配失败规则。名称回退候选必须满足“UID 不含可识别的蓝牙地址”，并且名称精确折叠匹配；有其他设备地址的候选直接排除。
- [ ] 补充测试矩阵：冲突地址且同名返回 nil；opaque UID 且同名返回唯一端点；两个 opaque 同名端点返回 nil；不同名称但正确地址成功；重复地址保持 nil。
- [ ] 运行 `swift test --filter HuaweiAudioEndpointMatcherTests`，确保新回归与原测试全部通过。

## Task 3：让取消传递到排队的传输操作

**优先级：P2。** `Sources/StatusTrioCore/Audio/HuaweiListeningModeTransport.swift:153`。

**原因与影响：** `perform` 使用 continuation 将闭包排队，没有取消处理。设备查询占用传输线程时，用户的模式写入进入队列；面板关闭或设备断开只取消 Swift Task，排队闭包仍调用 `writeMode`。`closeAll` 也排在这些工作之后，耳机可能在用户关闭面板后才切换模式。

**Files:**
- Modify: `Sources/StatusTrioCore/Audio/HuaweiListeningModeTransport.swift`。
- Test: `Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift`；需要时新增 `Tests/StatusTrioCoreTests/HuaweiTransportLifecycleTests.swift` 专门放可控调度测试。

- [ ] 在现有传输封装内增加最小可注入调度/操作边界，用假通道记录真实写入调用次数；不要依赖真实蓝牙设备或靠 sleep 猜时序。使用 latch 分别控制“第一个操作正在执行”“第二个操作已排队”“允许继续”。
- [ ] 新增 `testCancelledQueuedWriteNeverReachesChannel`：阻塞第一个操作，排入第二个写入，取消第二个任务，再放行；要求第二个任务抛出 `CancellationError`，底层写入计数为 0，continuation 恰好完成一次。在原实现上确认失败。
- [ ] 在 `perform` 外层使用 `withTaskCancellationHandler`；每个操作持有锁保护的取消/执行/完成状态。队列真正开始硬件操作前原子检查取消状态。处理“取消先发生、continuation 尚未注册”的顺序，取消和完成竞争时只允许一个路径恢复 continuation。不能只在 enqueue 之前检查一次 `Task.isCancelled`。
- [ ] 对尚未开始的操作确保零硬件副作用；已发出的写入不能承诺撤销，但后续可取消等待/读回应尽快退出，并防止重复恢复。保留控制器已有 token 发布保护。
- [ ] 覆盖取消发生在排队前、排队后、开始后、完成后四种时序；新增 `testCloseAllSkipsCancelledQueuedWrites`，证明 close 不需要先执行被取消的写入。测试结束时所有 continuation 都必须完成。

## Task 4：启动中的 closeAll 必须生效

**优先级：P2。** `Sources/StatusTrioCore/Audio/HuaweiListeningModeTransport.swift:143`。

**原因与影响：** 第一次调用在协作线程中运行 `ensureRunLoop`。工作线程尚未发布 run loop 时，`closeAll` 读取 nil 后立即返回；启动随后继续，旧请求仍可建立通道，关闭请求已丢失。任务 3 修复单个任务取消后，还必须保证同步 `closeAll` 的会话关闭语义。

**Files:** 与任务 3 相同。

- [ ] 新增 `testCloseDuringStartupInvalidatesOldSession`：通过注入的启动 latch 暂停 run loop 发布；启动首个操作并确认它已进入 startup；调用 `closeAll()`；再恢复 startup。要求旧操作不新开通道，或者已开通道最终被关闭，连接数为 0，旧任务结束。
- [ ] 将启动状态及关闭会话代际放在同步边界内；操作在提交时捕获代际，关闭时使旧代际无效，执行前再次检查。必须覆盖“已取得 run loop 但尚未 append pending”的窗口。不要只把 nil 判断替换成另一个未同步布尔值。
- [ ] `closeAll` 在主线程不得等待实际 RFCOMM 交互或持锁等待依赖同一把锁的工作线程启动；关闭旧代际工作后，在传输线程清理通道。
- [ ] 新增 `testReopenAfterStartupCloseUsesNewSession`：上述关闭完成后重新读取，要求新会话成功，旧回调不能发布或关闭新连接。保留并运行 `testConcurrentFirstUseStartsExactlyOneTransportThread`，仍要求线程数为 1。
- [ ] 使用同样的 latch 明确覆盖正常关闭、重复关闭、启动前关闭后再首次使用；禁止把所有新请求永久置为 cancelled，也不要无理由增加每次打开面板一个新线程。

## Task 5：完整验证及复审交付

- [ ] 运行下面的本地验证，保留退出码和汇总。`BUILD=38` 是本次审查使用的候选值；执行 CI 前重新核实已发布 build，若已达到 38，选择更大值。

```bash
swift test
swift build -c release
VERSION=1.6.1 BUILD=38 PUBLISH=false bash scripts/validate-appcast-notes.sh
git diff --check
```

- [ ] 执行不发布的 CI 预检。源分支来自 fork；需要先由维护者把修复后的准确 Head 推到 `lingyired/status-trio` 的 `codex/pr124-huawei-preflight` 分支，不能对 main 跑预检冒充验证 PR。不得绕过用户的提交/推送授权。确认远端分支 SHA 等于待审 SHA 后运行：

```bash
gh workflow run release.yml --repo lingyired/status-trio --ref codex/pr124-huawei-preflight -f version=1.6.1 -f build=38 -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml --branch codex/pr124-huawei-preflight --limit 5 --json databaseId,headSha,status,conclusion,url
```

从列表中找到 headSha 匹配本次修复提交的运行，用其实际 databaseId 执行 `gh run watch` 的 `--exit-status` 检查，并读取工作流结果中的测试、原生兼容性检查及构建/DMG 结果。若无法取得 CI，不宣称满足合并门槛。

- [ ] 每一个失败的 GitHub Actions run 都按 `AGENTS.md` 记入 `docs/swift-ci-compatibility.md`：实际 run ID、失败阶段、根因、修复、验证结果。
- [ ] 如有 FreeBuds 实机，分别验证有/无输出端点、同名两副耳机、切换中关闭面板、重新打开、AirPods preview 开启时 HUAWEI 仍走真实 SPP。无硬件则明确记录未验收；不要用 fake 测试替代实机结论。音量区域隐藏且已有输出端点时无控件是原 PR 明示的限制，本计划不扩展产品范围。
- [ ] 提交复审报告：修复 SHA、四项对应改动与测试名、本地结果、CI URL 和 headSha、硬件验收边界。停在复审，不自行发布或合并。

## 附录：已验证失败的回归测试补丁

以下仅增加测试，不包含修复。应用于 PR Head 后运行 `swift test --filter testReviewPR124`，原实现应得到 2 项失败。正式修复时可将测试名改为项目惯用命名。

```diff
diff --git a/Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift b/Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift
index 784f9d6a..ac502f6f 100644
--- a/Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift
+++ b/Tests/StatusTrioCoreTests/HuaweiListeningModeTests.swift
@@ -142,6 +142,15 @@ final class HuaweiAudioEndpointMatcherTests: XCTestCase {
         )
     }

+    func testReviewPR124ConflictingAddressCannotMatchByName() {
+        let endpoint = HuaweiAudioEndpoint(id: 9, uid: "11-22-33-44-55-66:output", name: "HUAWEI FreeBuds 6i")
+        XCTAssertNil(HuaweiAudioEndpointMatcher.endpointID(
+            forAddress: address,
+            deviceName: "HUAWEI FreeBuds 6i",
+            in: [endpoint]
+        ), "An endpoint with a different known address must not match by name")
+    }
+
     func testFallsBackToExactNameOnly() {
         let endpoints = [
             HuaweiAudioEndpoint(id: 9, uid: "SomeOtherUID", name: "HUAWEI FreeBuds 6i")
diff --git a/Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift b/Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift
index 30930860..74720e7f 100644
--- a/Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift
+++ b/Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift
@@ -246,6 +246,25 @@ final class StatusPanelViewModelTests: XCTestCase {
         XCTAssertEqual(panel.volume.listeningModeTaskID, "BBCCDDEEFF01|outputs:")
     }

+    func testReviewPR124OutputListIdentityUsesDeliveredVolume() async {
+        let original = AudioOutputDevice(id: 1, name: "Built-in", uid: "builtin", isCurrent: true)
+        let added = AudioOutputDevice(id: 42, name: "FreeBuds", uid: "buds", isCurrent: false)
+        let fixture = PanelStoreFixture(outputDevices: [original])
+        let panel = fixture.makePanel()
+        panel.start()
+        fixture.store.start()
+        defer { panel.stop(); fixture.store.stop() }
+        XCTAssertEqual(panel.volume.listeningModeTaskID, "|outputs:1")
+        fixture.volume.send(VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Desk speakers", currentDevice: original, outputDevices: [original, added]))
+        for _ in 0..<1000 {
+            if fixture.store.liveVolume.outputDevices.count == 2 { break }
+            await Task.yield()
+        }
+        XCTAssertEqual(fixture.store.liveVolume.outputDevices.count, 2)
+        XCTAssertEqual(panel.volume.rows.map { $0.key.id }, [1, 42])
+        XCTAssertEqual(panel.volume.listeningModeTaskID, "|outputs:1,42", "Output-only changes must restart discovery with the delivered output list")
+    }
+
     func testLiveInputUpdatesOnlyTheInputRegion() async throws {
         let fixture = PanelStoreFixture()
         fixture.settings.setPopupSection(.audioInput, enabled: true)
```
