# Issue #259：Wi-Fi 详情页高 CPU — 采样复核与整改方案

## 复核结论

2026-11-04 复核用户提供的 `sample`：Status Trio 1.9.2 (49)，ARM64，macOS 27.2 (26B123)。
热点已定位到面板尺寸更新后的同步显示、布局路径；具体为何反复产生尺寸更新尚需验证。
当前结论支持优先检查面板的 resize 反馈链，不能把所有 Wi-Fi 行为排除，也不能宣称修复已确认。
本次只复核方案并纠正分析文档，未修改应用源码、未启动 GUI、未执行运行时性能验收。

## 对上一版分析的更正

- `406`、`838` 等数字是采样命中次数，不是递归层数或函数调用次数。所谓“递归 400+ 层”“单次产生上百次 setFrame”没有证据。
- 主线程 4155 个采样点中，4114 个位于 `installShowObservers` 的 Combine sink 下；其中3987个经过 `applyContentSize`，约占主线程采样的96%。不能说4155个全部命中该方法，也不能由采样比例直接算CPU百分比。
- 栈出现 AppKit 约束引擎不等于已证明存在两个相互冲突的尺寸约束。没有记录每轮实际 frame，不能断定窗口被约束引擎“改回去”。
- `ProgressView` 高度抖动、跨越0.5pt阈值均未测量，保留为候选，不能作为既定根因。
- hosting view、玻璃容器和背景本来已经使用 autoresizing；“改用 autoresizing”不是有实质内容的整改。
- 栈从 RunLoop 调度后的通知处理进入，不能据此断言是“同一 block 内无限直接递归”。Release优化也会内联/合并函数，闭包编号不宜当成完整调用来源的证明。

## 已验证的证据

用户 sample 的主要调用路径：

```text
RunLoop block → Combine ReceiveOn → Sink
  → AnchoredStatusPanel.installShowObservers 中的闭包
    → AnchoredStatusPanel.applyContentSize
      → NSWindow setFrame
        → displayIfNeeded / layoutIfNeeded
          → _changeWindowFrameFromConstraintsIfNecessary
            → NSWindow setFrame / 视图树布局 / NSHostingView.layout
```

工作线程主要等待，未见 CoreWLAN 扫描或 Wi-Fi XPC事件处理成为本次采样热点。
因此优先治理面板布局路径有依据；扫描是否完成、扫描回调是否已排队并未由 sample 证明。
本地 tag `v1.9.2` 与本分支的两个相关源码文件
`AnchoredStatusPanel.swift`、`StatusPanelScrollArea.swift` 无差异。

## 代码中的具体风险

### 1. resize通知会再次应用旧尺寸

`AnchoredStatusPanel.swift:328` 监听 `didResizeNotification`，调用 `reposition()`；
后者在238–250行先 `applyContentSize(lastContentSize)`，再用当前窗口尺寸定位。
`applyContentSize` 又会 `setFrame(display: true)`。
由此存在 `resize → 通知 → 重新设尺寸 → resize` 的反馈路径。
原先监听resize的目的包含保持Dock锚定边，整改须保留这一行为。

### 2. 判重对象与实际设置对象不同

`applyContentSize` 在214–224行先对内容高度封顶、ceil取整，
把当前frame尺寸与该中间结果比较，随后才调用 `placementFrame(for:)`。
`StatusPanelPlacement.frame` 会在81–90行再次限制宽度、高度。

算术例：上限200.25、内容高度400、当前窗口高度200.25：

```text
capped = 200.25
rounded = 201
旧guard：abs(200.25 - 201) >= 0.5 → 要求setFrame
placement最终高度 = min(201, 200.25) = 200.25 → 实际已经到位
```

相同问题也可能出现在宽度被屏幕限幅时。
这个例子证明判重不可靠，不证明现场使用此上限，也不证明相同frame写入必然继续发resize通知。

### 3. 内容测量与窗口尺寸缓存语义不清

`lastContentSize` 注释称其为自然内容高度，但SwiftUI根视图包含已限高的滚动视口，
`sizeThatFits` 不一定返回未封顶的文档高度。
屏幕预算缩小后再扩大时，必须验证内容能恢复，而非盲目复用旧的限高测量。

### 4. 滚动偏移会在布局更新期间写入SwiftUI状态

`PanelScrollBridge.updateNSView/layout → attach → bind → publish` 可同步写 `offset.wrappedValue`。
通知回调虽用了Task，首次attach和重复bind仍同步publish。
这属于需要修正的状态更新时机问题，但尚未证明它就是本次卡死的触发源。

## 建议采用的整改顺序

1. **先建立收敛复现。** 在隔离实例中用有界诊断记录更新来源、内容测量、上限、当前frame、最终目标frame和resize/frame写入次数；不记录SSID。诊断需有限时/限条数及关闭路径。区分整数/小数预算、限宽、扫描中/结束、三种面板背景。
2. **最终frame判重与职责拆分。** 统一取整和限幅顺序，先计算最终placement frame，再判断是否需要写窗口。内容更新负责请求新尺寸；自身resize通知只校正位置，不重放旧内容尺寸；屏幕/Space变化负责重算预算并触发必要的重新测量。三条路径复用同一frame写入入口。
3. **解除同步布局中的窗口写入。** hosting布局回调仅交付尺寸请求，以单个待处理任务合并并取最新值；窗口更新用 `display:false` 交由正常显示周期绘制。关闭、换内容时取消或作废旧任务。不得每个事件新建一个Task，也不得用“每轮只执行一次”代替真正收敛。
4. **单独验证滚动桥接。** 将所有offset写回移出view update/layout，同一实例只保留一个待发布任务，detach后不得再写旧Binding。若窗口侧修正后仍有高度振荡，再据测量决定是否调整ScrollArea的测量方式；暂不重写整个滚动容器、不固定ProgressView高度、不改Wi-Fi扫描策略。

`display:false` 是减少同步重入的辅助手段，不是单独的根治证明。
不建议只缓存“上一次请求尺寸”后永久忽略相同请求，否则真实屏幕变化或内容恢复可能被屏蔽。

## 验证与交付门槛

- 小数高度上限、屏幕限宽后，重复同一输入不得继续写frame。
- 连续resize通知后，窗口写入应停止；真实内容变化仍能触发新的尺寸更新。
- 合并期间保留最新请求；关闭/换内容后旧任务不再写窗口或Binding。
- 预算缩小再恢复时，同一内容能恢复正确高度；summary/Wi-Fi/其他详情切换后尺寸正确。
- 主菜单栏与Dock锚定边、长内容滚动、footer固定、三种背景均保留。
- 现有 `StatusPanelContentResizeTests` 将独立metrics交给根视图，新增集成用例应使用 `panel.layoutMetrics`，覆盖真实的窗口—内容预算反馈。
- 聚焦运行 `StatusPanelPlacementTests`、`StatusPanelHeightCapTests`、`StatusPanelScrollAreaTests`、`WiFiNetworkList*`。需要真实窗口的resize用例遵守现有Visible UI边界，默认跳过必须单列。
- 实现后交付前运行 `bash scripts/verify-local.sh full`。另在隔离实例打开Wi-Fi页10分钟，对比CPU、frame写入是否停止、主线程是否恢复处理事件，并重新sample。静态检查和单测不能替代此项运行时验收。
- 用户验收后再合并/推送；保留当前分支和worktree，issue随正式发布统一核对关闭。

## 修复实施记录（2026-11-04，分支 `fix/issue-259-wifi-cpu-hang`）

按 [实施计划](superpowers/plans/2026-11-04-issue-259-wifi-panel-hang.md) 完成四个任务，源码改动如下：

1. **最终 frame 判重**（`StatusPanelPlacement.contentFrameUpdate`）：先算放置后的最终 frame，再与当前 frame 比较尺寸（≥0.5pt）与原点；小数高度上限、屏幕限宽不再重复写同一 frame。
2. **事件职责拆分 + 合并**（`StatusPanelLayoutCoordinator` + `StatusPanelLayoutUpdateScheduler`）：内容测量、自身 resize、屏幕/Space/Dock 变化各自入队，单个待处理操作保留最新值；resize 只校正位置，不再重放旧内容尺寸；预算变化丢弃旧测量并请求重新测量；窗口写入统一 `display: false`；关闭/换内容使在途操作失效。
3. **滚动偏移延后发布**（`PanelScrollBridge.Coordinator`）：绑定写入移出布局周期，合并为一次；`detach` 与绑定替换使旧写回失效。
4. **回归与观测**：面板新增 `#if DEBUG` 的 frame 写入计数（release 不含）；`StatusPanelContentResizeTests` 改为共享 `panel.layoutMetrics`，新增“静止后 100 次 resize 不再写 frame、真实内容变化仍会写”的可见 UI 回归；`StatusPanelHeightCapTests` 新增同一实例预算 `300 → 200 → 300` 恢复用例。

### 自动化证据

- 新增/更新测试：`StatusPanelFrameUpdateTests`（7）、`StatusPanelLayoutUpdateSchedulerTests`（4）、`StatusPanelLayoutCoordinatorTests`（8）、`StatusPanelScrollBridgeTests`（6）、`StatusPanelHeightCapTests` 新增 1 例。
- 聚焦验证通过：`StatusPanelFrameUpdateTests|...|WiFiNetwork|StatusMenuBuilderTests`，39 个 XCTest + 36 个 Swift Testing 用例 0 失败。
- 滚动桥接做过变异验证：把发布改回同步会让 4 个时机/生命周期用例失败，说明新测试能抓住回归。
- `StatusPanelContentResizeTests` 的 2 个用例属 Visible UI，默认跳过；`bash scripts/verify-local.sh full` 结果另行记录。

### 验证结论

- **真机验收：用户于 2026-11-04 自测确认修复版可用**（打开 Wi-Fi 详情页不再卡死）。本会话没有收集修复前后的 CPU / `sample` 对比数据，因此这里没有量化性能结论；定位依据是原 sample 栈与自动化测试。
- 修复已合并到 `main`（合并提交 `a1d2f526`）。
- 另构建了 1.9.3 (50) 的 Developer ID 签名 + 公证 DMG 供外部测试（App/DMG 均 Accepted、已装订）；它不属于正式发布物。
- 修复前后的真实 CPU 对比数据：NOT RUN（没有做现场基线，不伪造对比）。
- macOS 13 真机、正式发布签名/公证流程：NOT RUN，仍按 release 流程另行验证。

### 独立审查跟进（提交 `ba0f9c48`）

独立审查指出三处缺口，已修复并补测：

1. **同步重测的更新不能被丢弃**：`needsRemeasure` 分支在清空旧测量后强制 host 重新布局；若重测在同一回合同步报告新尺寸，直接应用，不再等到下一回合。新增协调器用例（单轮 drain 验证“同一回合”）。
2. **换内容后旧 host 失效**：新增 `contentHost` 身份校验，旧 hosting controller 的延迟布局不再进入测量队列；新增用例覆盖替换后旧 host 不再被接受。
3. **Release 测试编译**：convergence 用例整体包在 `#if DEBUG` 中，只有 DEBUG 才有 frame 写入计数。补充事实：`swift build -c release --build-tests` 在干净 main 上本就因模块解析失败，不是本分支引入；Release 应用构建通过。

修复后聚焦用例 52 个 XCTest + 45 个 Swift Testing 0 失败，`quick` 档通过，Release 构建通过。
