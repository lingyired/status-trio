# Issue #263 交接文档 — 调音量时 CPU 飙升

> 写给新会话：读完这份就能直接接手，不用重走弯路。
> 生成时间：2026-11-04 18:20。作者：上一会话（lead）。

## 0. 一句话现状

**面板侧两轮修完：状态拆分（§5.1）+ AppKit 滑杆（§5.2）。**
只拆观察粒度不够——真正的大头是「每个拖动事件都让 SwiftUI 提交一次整窗布局/绘制」，
换成 AppKit `NSSlider` 后按 120Hz 模拟拖动，Release 峰值从 30%+ 降到约 19%、
平均约 10%（残余是面板每帧原生合成/vibrancy）。真机手感与最终数值待用户复核。
分支和 worktree 直接沿用，不要重建。

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

### 5.2 ✅ 第二轮：音量滑杆换成 AppKit `NSSlider`

- `UI/VolumeControlsView.swift`：`VolumeSliderRow` 里原来直接用 SwiftUI `Slider`，
  它的 binding 每个指针事件都会写 `@State`，于是每个事件都触发一次 SwiftUI 事务。
  现改为 `NSViewRepresentable` + 原生 `NSSlider`：
  - 拖动由 AppKit 自己跟踪并重绘，SwiftUI 不再逐事件失效；
  - 只在原生 `mouseDown`→`mouseUp` 之间把动作交给现有 `VolumeControlInteraction`
    （`beginEditing`/`setSliderValue`/`endEditing`），语义与旧滑杆一致；
  - 外部音量变化仍通过 `updateNSView` 同步，拖动期间不覆盖用户手势；
  - 百分比文字改用合并后的 `state.scalar`（~10Hz），不再依赖逐事件 draft；
  - 保留静音红色轨道（`trackFillColor`）与 AX 标签/值。
- 同时保留第一轮的「纯音量变化 10Hz 合并」（`VolumeStatus.changesOnlyLevel` +
  `receiveLiveVolume`/`pendingLevelVolumeStatus`），结构性变化（静音/设备/可用性）
  仍然立即发布。

### 5.3 自测方法（没有真实鼠标也能 A/B）

用 AX（实例级，不抢全局输入）打开面板并驱动滑杆，再配合 `top`：

- 打开面板（临时 DEBUG 参数或脚本 `AXExtrasMenuBar` + `AXPress` 都试过；
  最终用临时启动参数打开，已在提交前移除）；
- 用 `AXUIElementSetAttributeValue(slider, kAXValueAttribute, …)` 或
  `AXIncrementAction`/`AXDecrementAction` 以 ~120/s 驱动；
- `top -l 30 -s 1 -pid <PID> -stats cpu` 读峰值；注意 `sample` 默认 1ms 会显著抬高被测
  进程 CPU，用 `sample <pid> 20 25` 这种低扰动间隔，或只信 `top`。

实测（Release，面板打开，95%↔100%）：

| 方案 | 驱动方式 | 峰值 | 平均 |
| --- | --- | --- | --- |
| 旧：SwiftUI Slider | AX 设值 ~54/s | 32% | 32% |
| 新：NSSlider | 应用内 120Hz 模拟拖动 | 19.3% | 10.1% |
| 新：NSSlider | 只用原生滑块、不写 store | 19.5% | 10.4% |
| 新：NSSlider | 原生滑块 30Hz | 10.6% | 5.1% |

结论：残余成本是原生控件每帧触发的 AppKit 子树布局 + vibrancy + CA 提交
（`NSViewUpdateVibrancyForSubtree`、`_layoutSubtreeWithOldSize`、`CA::Layer::commit`），
与 store/设备列表无关。继续压需要更轻量的自绘滑杆（CALayer 轨道+旋钮），
本轮没做。

**仍待真机验证**：真实拖动手感、百分比跟手、静音色/无障碍，以及最终 Release 峰值。

### 注意

- `VolumeControlInteraction` 已有本地 draft 值，滑杆跟手性不依赖 store 的发布频率；
  节流/隔离不会让手感变差，但**必须真机验证**。
- 面板里还有 `store.$popupSnapshot` → `refreshPopupPanels(...)`（`:910`）会重映射所有区，
  也值得检查：音量 tick 会触发 `schedulePopupSnapshot` 的去抖发布（500ms 去抖，
  持续拖动时不会落地，松手后才可能触发一次）。
- 设置面板还有十来个视图 `@ObservedObject var statusStore: SystemStatusStore`
  （`SettingsView`、`AudioSectionView`、`BatterySectionView`、`NetworkSectionView`、
  `StatusIconPreviewCard`、`MiddleIconSettingsGroup` 等），是剩余 8.7% 的来源，
  收窄观察粒度可进一步下降。

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
