# Issue #263 交接文档 — 调音量时 CPU 飙升

> 写给新会话：读完这份就能直接接手，不用重走弯路。
> 生成时间：2026-11-04 18:20。作者：上一会话（lead）。

## 0. 一句话现状

**面板侧三轮修完：状态拆分（§5.1）+ 合并 main 的 `PanelLevelSlider` 并限频回写（§5.2）
+ 滑杆绘制改位图缓存（§5.4）。**
第一轮真机 Release 验收约 15%（此前 30%+）；第三轮在隔离面板探针里把绘制成本
从 15.0% 压到约 10.1%（Release，120Hz 模拟拖动），待真机复核。
分支和 worktree 保留。

## 1. 分支 / worktree / 提交（沿用）

- worktree：`/Users/lingsmbp/Documents/aiwork/status-trio-issue263`
- 分支：`fix/issue-263-volume-cpu`
- 基于：`ddd728ee`（当时等于 `origin/main`）
- **未合并、未推送**，main 干净未动
- 已有提交（按时间）：

| 提交 | 内容 |
| --- | --- |
| `0cc28b30` | Dock 音量重绘降频 `DockVolumeRenderCoalescer`（防御性，实测后证明不是主要矛盾） |
| `757fa1f4` | 文档：Dock 音量拖动采样 |
| `1a713a65` | 文档：音量 CPU 测量结论（第一版，其中「无法复现」的结论**已被后续推翻**） |
| `be42b069` | 修复：设置面板图标预览光栅缓存 `StatusIconPreviewCache`（14.7% → 8.7%） |
| 本次会话新增 | 修复 §5：音量状态拆成 `VolumeControlModel`，音量 tick 不再让整面板失效 |

本次会话在最终树上跑过 `scripts/verify-local.sh full`，exit 0（2469 tests，71 个可见 UI 测试按默认跳过）。
工作树提交后应为干净。

## 2. 问题现象（用户实测）

1. **不开面板**，键盘调音量：图标确实重绘（满格→递减），CPU **≤3%**，很低。
2. **打开面板**，在面板里把音量在 **95%↔100%** 来回拖：图标四个点始终满格、
   **根本不需要重绘**，但 CPU 飙到 **15–20%**，松手回落。

→ 结论：**不是绘图的问题。** 峰值只在面板/设置窗口可见时出现。

## 3. 已确认的测量事实

全部是临时微基准 + `sample`/`top` 实测（测量文件用完即删，未入库）。
机器：ARM64，macOS 27.2 (26B123)。

### 3.1 单次成本

| 测量项 | 每次耗时 |
| --- | --- |
| 菜单栏 template base 整图 @22pt | **0.076–0.078 ms** |
| 菜单栏 template base @32pt | 0.084 ms |
| 菜单栏彩色 overlay | 0.029 ms |
| Dock 整图 512px `DockIconRenderer.image` | **0.505 ms** |
| accessibility `statusItemValue` 构建 | 0.076–0.108 ms |
| accessibility 构建 + 写入 | 0.090 ms |
| CoreAudio `read()` 全设备读取 | 0.43 ms |
| CoreAudio `setVolume()` 写入 | 0.20 ms |
| `AudioPanelMapper.volume(...)` 重建音量面板态 | **0.366 ms** |
| 音量反馈音 `sound.stop(); sound.play()` | **13–21 ms wall / 1.6 ms CPU** |
| `AudioServicesPlaySystemSound`（替代候选） | 0.016 ms（但脱离输出音量跟随） |

**菜单栏整图重绘只要 0.078ms → 分区增量重绘（原「路线 A」）收益是零头，已明确否决。**

### 3.2 真实进程 CPU

- 空闲基线：0.6–0.7%
- 外部改系统音量、无窗口：最高 1.6–1.8%
- 设置窗口打开 + 改音量：**13–15%（Release 构建）**
- 面板打开 + 拖音量：**15–20%**

### 3.3 采样热点

**设置窗口打开时**（对 PID 42506 采样）：

```text
NSHostingView.layout()
  → ImageLayer.update(image:)
    → NSCustomImageRep draw
      → StatusIconRenderer.image(...)      ← 每次绘制整张重渲染
        → drawOfficialSymbol → CoreUI/CoreSVG 解析 SF Symbol 矢量路径
```

**面板打开拖动时**（更早一次采样）：主线程 4412 个样本中约 **951 个**（21%）
落在 `layoutIfNeeded` / `_layoutViewTree`（窗口布局），图标渲染 **0 次**。

## 4. 已修复的两处

### 4.1 `StatusIconPreviewCache`（提交 `be42b069`）

**根因**：`StatusIconRenderer.image(...)` 返回的是**带绘制闭包的惰性 NSImage**
（`StatusIconRenderer.swift:967` 附近，源码注释自己写了
"keeping an NSImage drawing handler so automatic appearances resolve again on every draw"）。
**每一次合成都会重跑整个 Core Graphics 渲染**，包括 SF Symbol 矢量路径解析。

而设置面板把这条渲染直接写在 SwiftUI `body` 里且无缓存：

- `UI/Settings/SettingsVisualPreviews.swift`（原 92 / 292 行）
- `UI/IconPreviewComponents.swift`（原 127 行）
- `UI/Settings/IconSizePreview.swift`（原 9 行）
- `UI/Settings/MiddleIconSettingsGroup.swift`（原 444 行）

这些视图又 `@ObservedObject` 整个 `SystemStatusStore`，且预览取**实时音量**
（`menuBarPreviewStatus`），所以每个音量 tick 都整张重画。

**修法**：新增 `UI/Icon/StatusIconPreviewCache.swift`
- 用 `StatusIconRenderer.render(...)` 拿 `CGImage`，包 `NSBitmapImageRep` + `NSImage`
  → **立即光栅化**，之后绘制只是 blit；
- 按 `StatusBarRenderKey`（scene/size/scale/appearance/phase）缓存，LRU，24 条 / 2 MiB；
- `StatusBarRenderKey` 改为 `Hashable`；
- 5 个调用点全部改用它；
- `App/PreviewResourceLifecycle.swift` 在无预览表面时与 Dock 预览缓存一起释放。

**实测**：设置窗口打开、连续改音量，峰值 **14.7% → 8.7%**。
采样里 `StatusIconRenderer.image` 栈从大量降到 6 个样本。

### 4.2 `DockVolumeRenderCoalescer`（提交 `0cc28b30`）

Dock 侧音量连续变化的限速/合并（10Hz + arc 微小差值合并 + 尾值精确）。
**实测后确认它不是主要矛盾**（Dock 不在用户场景里），保留即可，别当灵药。

## 5. 面板拖音量 CPU：两轮修法

### 5.1 ✅ 第一轮：把音量状态从 `StatusPanelViewModel` 拆出去

**根因**：面板打开时拖音量，`volume` 原是 `StatusPanelViewModel` 的 `@Published`，
而面板根视图 `@ObservedObject` 观察整个 VM，导致每 tick 整个面板 body 重算 + 整窗布局。

**修法**（本次会话提交）：

- 新增 `Presentation/Panel/VolumeControlModel.swift`：
  `VolumeControlModel: ObservableObject`，持有 `@Published private(set) var volume`，
  `update(_:) -> Bool` 在值未变时不发 `objectWillChange`（挡住重复回退 tick）。
- `StatusPanelViewModel`：
  - `@Published volume` 移除，改成非 `@Published` 的 `let volumeControl: VolumeControlModel`；
  - 新增只读转发 `var volume: VolumePanelState { volumeControl.volume }`，
    供 `StatusBarController:906` 滚轮读档位和测试读取（行为不变）；
  - `publishVolume` 改为 `volumeControl.update(state)`；释放路径同样写模型；
  - 仍只在 VM 内映射/订阅，`listeningModeTaskID`、layout snapshot、设备行骨架逻辑不动。
- `UI/VolumeControlsView.swift`：新增 `VolumeControlsSection` 容器，它是**唯一**
  `@ObservedObject` 观察 `VolumeControlModel` 的视图，内部仍渲染原 `VolumeControlsView`。
- `UI/StatusPopoverView.swift`：音量 section 改用 `VolumeControlsSection`，
  父视图不再读 `panel.volume`，音量 tick 不再让整面板失效。
- 测试：原先读 `panel.$volume` 的几处改为 `panel.volumeControl.$volume`；
  新增 `testLiveVolumePublishesTheVolumeModelWithoutInvalidatingThePanel`
  锁住契约：一次音量 tick 的 `panel.objectWillChange` 发射数必须为 0。

结果：**这一步没有解决峰值**。真机 Release 仍然 30%+。
原因：SwiftUI 的 hosting view 只要有一处子视图失效，就会提交整窗布局 + 显示列表 + CA 合成；
仅缩小「失效范围」并不能消除每次拖动事件的这笔固定成本。

### 5.2 ✅ 第二轮：合并 main 的 `PanelLevelSlider`，并把它的回写限频

最新 `main` 已用 `UI/PanelLevelSlider.swift`（#245）把音量/亮度滑杆统一成
AppKit `NSSlider` 子类自绘（`PanelLevelSliderView` + `PanelLevelSliderCell`）。
合并 `origin/main` 后本分支直接采用它，删掉了自己那版 `NSSlider`。

但 `PanelLevelSlider` 仍在每个拖动事件里 `onValueChanged` → 写 SwiftUI `@Binding`
（音量行的 `VolumeControlInteraction` draft 是 `@State`），于是每个指针事件还是
提交一次 SwiftUI 事务、整窗布局/合成——这正是 §5.3 里 A 组仍然高的原因。

修法（`UI/PanelLevelSlider.swift`）：

- 手势期间把 `onValueChanged` 限频到 30Hz（`minimumReportInterval`），
  待发的最后一个值在 `mouseUp`/`keyDown` 收尾时 flush；
- 原生控件仍然每帧自绘，滑杆跟手性不受影响；
- `updateNSView` 在 `nsView.isTracking` 时不再把 SwiftUI 的旧值写回原生控件，
  避免限频后"回弹"打断手势；
- 键盘调整（单次 keyDown）走同一条 flush 路径。

### 5.3 自测方法与 A/B 数据

用实例级 AX（不抢全局鼠标）或应用内临时压力钩子驱动，再配合 `top`：

- 注意：AX 的 increment/set-value 走的是无障碍非手势路径（`isGestureActive == false`），
  不会经过 30Hz 限频，不能用来验证本修复；要用应用内"模拟手势"的钩子（本轮用完已删）。
- `sample` 默认 1ms 间隔会显著抬高被测进程 CPU，用 `sample <pid> 20 25` 或只信 `top`。
- Release 下用临时启动参数自动开面板时，面板会被系统很快关掉（不影响产品）；
  Debug 测试实例能稳定保持，所以 A/B 在 Debug 下做，Release 交给用户真机。

Debug（120Hz 模拟拖动）A/B：

| 方案 | 峰值 | 平均 |
| --- | --- | --- |
| 不限频（main 原样，逐事件回写 SwiftUI） | 42.3% | 23.1% |
| 限频 30Hz（本分支） | 20.0% | 10.0% |

Release 真机数值待用户复核；预期比 Debug 低不少。

### 5.4 ✅ 第三轮：滑杆绘制改位图缓存

`sample` 与隔离面板探针把残余拆开：Release、120Hz 下整行可见拖动约 15%，
其中空绘制（trivial）只要 5%，滑杆自身每帧的 `NSBezierPath` 填充 + `NSShadow`
旋钮光栅化约 10 个百分点；阴影单项约 2.6。

修法（`PanelLevelSliderView`）：

- 轨道、填充、旋钮（含阴影）各预光栅化成 `NSImage`（按 backing scale 绘制，
  旋钮的 shadow 烘进位图），拖动时只做 `NSImage.draw` 位图搬运；
- 填充用同一张整宽胶囊位图裁左侧 `fillWidth` 绘制，右端方角恰好藏在旋钮下；
- 失效时机：尺寸、`isEnabled`、`fillColor`、effectiveAppearance、backing scale 变化；
- 标签文字仍走原有 `drawLabel`（带标签的滑杆不受影响）。

实测（Release 位图缓存前后，隔离面板探针，120Hz 模拟拖动）：

| 版本 | CPU |
| --- | --- |
| 旧：每帧路径 + 阴影 | 15.0% |
| 新：位图缓存 | 10.1% |

试过但**放弃**的：只重绘拇指移动的小脏区（`setNeedsDisplay(rect)`），实测反而
从 8.1% 升到 9.5%（Debug），说明 CA/图层上传对整层更友好。

第三轮后的成本分解（Release 微基准 + 探针）：

| 项 | 数值 |
| --- | --- |
| 位图缓存后单次 `draw`（固定尺寸，Debug 微基准） | **0.05ms**（120Hz ≈ 0.6% CPU） |
| `NSImage.draw` vs `CGImage` 直绘（微基准） | 0.0104ms vs 0.0039ms/次，但相对每帧提交可忽略，未改 |
| 探针 visible / hidden 差 | ≈5.8 个百分点，主要是驱动循环 + AppKit/CA 每帧提交 |

外观证据：把新（位图缓存）与旧（路径+阴影）实现分别渲染到 400×60 位图，
对比亮/暗、启用/禁用、静音色、0/50/100% 共 7 种状态，**0 个差异像素**
（阈值 8/255 下也是 0），说明绘制改造没有改变外观。

结论：**继续压绘制代码已无收益**；要再降只能限制滑杆重绘帧率（例如 120Hz 屏上
封顶 60Hz，代价是拇指跟手略降）或改 CALayer 分层（提交成本仍在，收益有限），
都属于产品取舍，需要用户拍板。

### 5.5 已知边界

- 残余成本来自原生控件每帧触发的 AppKit 子树布局 + vibrancy + CA 提交
  （`NSViewUpdateVibrancyForSubtree`、`_layoutSubtreeWithOldSize`、`CA::Layer::commit`），
  与 store/设备列表无关；再往下压需要更轻量的自绘轨道（CALayer），本轮没做。
- 设置窗口里也有 `PanelLevelSlider`（亮度/音频输入等），同一限频对它们同样生效。

## 6. 踩过的坑（务必避免重复）

1. **必须测对 PID。** 用户机器上同时跑 5 个开发版实例，一开始只测了自己启动的那个
   （没开窗口 → 0.8%），得出「无法复现」的错误结论。
2. **`ps -o %cpu` 是进程生命周期平均值**，会严重低估瞬时峰值。用
   `top -l N -s 1 -pid <PID> -stats cpu`。
3. **`--background-ui-testing` 只在 `#if DEBUG` 生效**
   （`App/BackgroundUITestingConfiguration.swift`）。Release 包会静默忽略，
   所以 Release dev 包不会自动开设置窗口 → 测不出设置窗口的峰值。
4. **Debug vs Release 性能差很多。** 判断方法：dev 包看
   `STBackgroundUITestingSupported` 是否为 `true`（`scripts/build-app.sh:209` 只在
   debug + dev 包写入）。用户的开发版基本都是 **Release**。
5. **`scripts/verify-local.sh full` 会把 `dist/StatusTrio.app` 重建成 Release**
   （CFBundleName 变成 "Status Trio (Verify Local)"），会覆盖你手动构建的 Debug 包。
6. **部分在跑的实例来自已被删除的 worktree/bundle**（如 `issue-245-level-slider`），
   Info.plist 读不到属正常，不要据此判断配置。
7. **图标整图重绘 = 0.078ms**，不要再用「重绘是元凶」的思路。

## 7. 构建与验证命令

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio-issue263

# 迭代期：只跑相关测试
bash scripts/test.sh 'StatusIconPreviewCacheTests|IconSurfaceIntegrationTests|Issue30WiFiAlignmentTests'

# 交付前：full（渲染/状态/并发 → 必须 full）
bash scripts/verify-local.sh full

# 开发包（第一个参数是配置；Debug 才能用 --background-ui-testing）
bash scripts/build-worktree.sh debug no-open    # → dist/StatusTrio.app
bash scripts/build-worktree.sh release no-open
```

开发版 bundle id：`com.lingsmbp.StatusTrio.dev.fix-issue-263-volume-cpu`

打开并自动开设置窗口（仅 Debug 有效）：

```bash
open -a "$PWD/dist/StatusTrio.app" --args --background-ui-testing
```

## 8. 复现方法

1. `bash scripts/build-worktree.sh debug no-open`
2. `open -a dist/StatusTrio.app --args --background-ui-testing`
3. 打开活动监视器，找到该 PID
4. **场景 A**：不点面板，用键盘调音量 → 预期 ≤3%
5. **场景 B**：点菜单栏图标打开面板，在面板里把音量 95%↔100% 来回拖
   → 预期 15–20%（这就是待修的那项）
6. 同时用 `top -l 8 -s 1 -pid <PID> -stats cpu` 取瞬时值

## 9. 当前分支上已有的相关文档

- `docs/performance/issue-263-volume-cpu-findings.md`（测量结论，**其中「无法复现」
  那段是早期错误结论，以本文档为准**）
- `docs/performance/issue-263-dock-volume-coalescing.md`（Dock coalescer 说明）
- 本文档：`docs/performance/issue-263-handoff.md`

## 10. 项目规则提醒

- 合并前要 `fetch` 并对比最新 `origin/main`，重跑受影响范围的验证。
- 复杂改动先让用户真机验收再合并；**issue #263 不要自行关闭**。
- 不写没有采样支撑的 CPU 收益结论。
