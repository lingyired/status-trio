# Issue #263 交接文档 — 调音量时 CPU 飙升

> 写给新会话：读完这份就能直接接手，不用重走弯路。
> 生成时间：2026-11-04 18:20。作者：上一会话（lead）。

## 0. 一句话现状

**根因已定位，两处已修，最关键的第三处（面板整面板重算）还没修。**
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

工作树当前干净。`scripts/verify-local.sh full` 在 `1a713a65` 上通过过；
`be42b069` 之后**也跑过一次 full，exit 0**。

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

## 5. ⚠️ 还没修的关键项（下一会话的主任务）

**面板打开时拖音量，`volume` 是 `StatusPanelViewModel` 的 `@Published`，
而面板根视图观察整个 VM，导致每 tick 整个面板 body 重算 + 整窗布局。**

### 具体落点

| 位置 | 说明 |
| --- | --- |
| `Presentation/Panel/StatusPanelViewModel.swift:52` | `@Published private(set) var volume: VolumePanelState` |
| 同上 `:784`、`:827` | `store.$liveVolume` 订阅 → `mapVolume` → `publishVolume` |
| 同上 `:1100` | `private func publishVolume(_:)` → `volume = state` → 触发整面板重算 |
| `UI/StatusPopoverView.swift:5` | `@ObservedObject var panel: StatusPanelViewModel` ← 观察整个 VM |
| `UI/StatusBarController.swift:906` | `panelViewModel.volume`（滚轮调音量读它，**改动时必须保留**） |

### 建议修法

把音量状态从 `StatusPanelViewModel` 里**独立出去**（例如
`VolumeControlModel: ObservableObject`），只让音量那一行（`VolumeControlsView` 及其容器）
观察它；`StatusPanelViewModel` 保留一个非 `@Published` 的引用供
`StatusBarController` 读档位。

预期：音量 tick 只让音量行重算，面板主体/其他区不动，布局不再每帧触发。

### 注意

- `VolumeControlInteraction` 已有本地 draft 值，滑杆跟手性不依赖 store 的发布频率；
  节流/隔离不会让手感变差，但**必须真机验证**。
- 面板里还有 `store.$popupSnapshot` → `refreshPopupPanels(...)`（`:910`）会重映射所有区，
  也值得检查：音量 tick 会触发 `schedulePopupSnapshot` 的去抖发布。
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
