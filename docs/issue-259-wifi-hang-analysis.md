# Issue #259 — 打开 Wi-Fi 详情页后卡死 / CPU 99%：sample 定位结论

> 排查对象：用户提供的 hang sample（`~` 1ms × 4155 采样的 live task 转储），
> Status Trio 1.9.2 (49)，macOS 27.2，Opening `<Status Trio>` 后 6 分钟无新日志、
> Activity Monitor 99.9% → 强制退出。

## 结论

**卡死与 CoreWLAN / Wi-Fi 扫描无关。** 主线程 100%（4155 / 4155 全部采样点）
都停在同一个**窗口布局回环**里——不是网络代码、不是事件风暴、没有阻塞在
`CoreWiFi`。页面停在「正在扫描网络…」只是因为主线程被布局占满，扫描完成的
回调根本排不上来。

> 🧠 **From Hindsight memory** 无历史定位记录；本结论直接来自对该 sample 的采样栈分析。

## 采样证据

主线程（`Thread_1096913`，com.apple.main-thread）转储：

```
__CFRunLoopRun
  → __CFRunLoopDoBlocks
    → NSRunLoop.schedule 的 block
      → Publishers.ReceiveOn.Inner.receive (Combine)
        → Subscribers.Sink.receive
          → partial apply closure #3 in AnchoredStatusPanel.installShowObservers  [99%]
            → closure #1 in AnchoredStatusPanel.installShowObservers  [97%]
              → AnchoredStatusPanel.applyContentSize(_:)  [96%]
                → -[NSWindow _setFrameCommon:display:fromServer:]  [55%]
                  → -[NSView displayIfNeeded]
                    → -[NSView _layoutAtWindowLevelIfNeeded]
                      → -[NSWindow layoutIfNeeded]
                        → -[NSWindow _changeWindowFrameFromConstraintsIfNecessary]
                          → -[NSWindow _setFrameCommon:display:fromServer:]  (又改 frame!)
                            → _layoutViewTree → layoutSubtreeIfNeeded
                              → _layoutSubtreeWithOldSize:  (递归 400+ 层)
                                → _NSViewLayout → hosting view 重排版
```

同一挂起点的每次 setFrame 之后，Auto Layout 的
`_changeWindowFrameFromConstraintsIfNecessary` 再一次改 frame，
`_layoutSubtreeWithOldSize:` 分层递归到 400+ 层深度，永不收敛。
单次 applyContentSize 就能拉出几十到上百个 setFrame 重入；4414/4155 命中此链。

## 根因

来自 `AnchoredStatusPanel.swift`，三处叠加成死循环：

1. `StatusPanelHostingController.viewDidLayout()`（L358）在每次排版后回调
   `onLayout`（L371），把 `sizeThatFits` 结果抛给窗口。
2. `applyContentSize(_:)`（L214）收到后，只要与新 frame 差 >=0.5pt（L221）
   就 `setFrame(placementFrame(for:), display: true)`（L223，`display:true` 会
   触发 `displayIfNeeded` → 整窗重排）。
3. 窗口级 Auto Layout 约束（contentViewController 与 hosting view 的
   autoresizing/约束）在 frame 改变后，通过
   `_changeWindowFrameFromConstraintsIfNecessary` **反向**再改窗口 frame，
   引起 hosting 视图再次 `layout` → `viewDidLayout` → `onLayout` → `applyContentSize`
   → `setFrame` …

即「窗口手动 setFrame」与「窗口约束引擎改 frame」来回互掐，中间夹着 SwiftUI
hosting view 的 `viewDidLayout` 回调，形成**不可收敛的直接递归**（非事件驱动，
是一个 runloop block 里无限自嵌套）。Wi-Fi 详情页的 `ProgressView`（扫描中）或
某行内容让 fitting height 反复跨越 0.5pt 阈值，充当了触发器。

## 证据细节

- `4114` ~ `4013` 个采样点就在 `installShowObservers` 的 closure 里（closure #3 / #1
  都指向 as sink 的 `reposition` / `applyContentSize` 路径）。
- `3987` 个采样点停在 `applyContentSize` 内。
- 深处 `_layoutSubtreeWithOldSize:` 累计 400+ 层递归嵌套（转储行号 70-79、735-743）。
- 无任何 `CoreWLANStatusReader` / Wi-Fi 扫描帧；此链与网络完全无关。

## 修复建议（待实现，独立于本分析）

目标是让 `viewDidLayout → setFrame` 不再反向喂养 Auto Layout 的窗口约束回环：

1. `applyContentSize` 的 `setFrame(display:true)` 改为 `display:false`，并把
   frame 修改**移出视图排版回调**（不要在 `viewDidLayout` 里直接同步 setFrame；
   可 `Task { @MainActor }` / `DispatchQueue.main.async` 合并到下一次 runloop）。
2. 收敛保护：一次 layout 事件只允许一次 frame 写入，用「当前 request 已处理的
   目标 frame」做去抖，`setFrame` 后若约束引擎又改回，请求侧必须带 toggling guard
   中断递归。
3. 核对 contentViewController / hostingView 的自动布局约束——让 hosting view 用
   autoresizing 跟随窗口而非约束互相约束，消除 `NSISEngine` 参与窗口 frame。
4. 针对 Wi-Fi 详情页 `ProgressView` 的 fittingSize 抖动，判断是否值得单独做
   高度稳定（详见 issue 正文方向 1）。

> 实现前须过 `.agents/rules/network.md`（Wi-Fi 相关）与
> `.agents/rules/performance.md`（低功耗边界），并用 focused
> `StatusPanelContentResizeTests` / `StatusMenuBuilderTests` 验证。

## 需要用户补充（可选，但推荐）

- 若能，给出 `spindump -notarget 1 -o ~/Desktop/StatusTrio.spindump` 可与本
  结论互相印证；非必需，本 sample 已足够。
- mac 具体型号 / 是否外接屏 / 附近 AP 数量（仅判断触发器触发面，不影响主因）。