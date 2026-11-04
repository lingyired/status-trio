# Issue #263 — 调音量时 CPU 飙升：根因与修复

日期：2026-11-04。机器：ARM64，macOS 27.2 (26B123)。

## 修正：之前的测量对象是错的

第一轮排查只盯了自己启动的 Release 开发版（没开任何窗口，CPU 0.8%），
因此错误地得出「无法复现」。用户机器上同时跑着 5 个开发版实例，用 `top`
按 PID 抓瞬时 CPU，真正飙升的是开着**设置窗口**的两个：

| PID | 开发版 | 调音量时 CPU |
| --- | --- | --- |
| 42506 | `issue-245-level-slider`（`--background-ui-testing`） | **14.7%** |
| 79348 | `issue-187-235-246-power-helper` | **13.4%** |
| 18638 | 自己的 issue-263 版（无窗口） | 0.8% |

`--background-ui-testing` 只在 `#if DEBUG` 生效，Release 包会忽略它——
所以之前那个 Release 实例根本没开设置窗口，自然测不出来。

## 根因

对 PID 42506 采样，主线程热点：

```text
NSHostingView.layout()                     ← SwiftUI 整窗布局
  → ImageLayer.update(image:size:)
    → NSCustomImageRep draw
      → StatusIconRenderer.image(...)      ← 每次绘制都整张重新渲染
        → drawOfficialSymbol → CoreUI/CoreSVG 解析 SF Symbol 矢量路径
```

两件事叠加：

1. **`StatusIconRenderer.image(...)` 返回的是「带绘制闭包的惰性 NSImage」**
   （`StatusIconRenderer.swift:967`，注释写明「keeping an NSImage drawing handler
   so automatic appearances resolve again on every draw」）。**每一次合成都会重新
   执行整个 Core Graphics 渲染**，包括 SF Symbol 矢量路径解析。
2. **设置面板里的预览把这条渲染直接写在 SwiftUI `body` 里，且没有缓存**：
   `SettingsVisualPreviews.swift:92/292`、`IconPreviewComponents.swift:127`、
   `IconSizePreview.swift:9`、`MiddleIconSettingsGroup.swift:444`。
   这些视图又用 `@ObservedObject var statusStore: SystemStatusStore` 观察整个 store，
   而 `menuBarPreviewStatus` 取的是**实时音量**。

结果：**每次音量变化 → store 发布 → 预览重渲染 → 整张图标重新光栅化**。
这就是用户说的「为什么要整张重绘」。

## 修复

新增 `StatusIconPreviewCache`（`Sources/StatusTrioCore/UI/Icon/`）：

- **立即光栅化**：用 `StatusIconRenderer.render(...)` 得到 `CGImage`，包成
  `NSBitmapImageRep` + `NSImage`，之后绘制只是一次 blit，不再进入绘制闭包。
- **按 `StatusBarRenderKey` 缓存**（scene / size / scale / appearance / phase），
  LRU 有界（24 条 / 2 MiB）。
- 5 个预览调用点全部改用它；`PreviewResourceLifecycle` 在无预览表面可见时
  与 Dock 预览缓存一起释放。
- `StatusBarRenderKey` 改为 `Hashable` 以作字典键。

## 实测效果

设置窗口打开、连续改变音量时的瞬时 CPU 峰值：

- 修复前：**14.7%**
- 修复后：**8.7%**

采样复核：`StatusIconRenderer.image` 栈从大量降到 6 个样本，`NSCustomImageRep draw`
降到 4 个；SF Symbol 矢量解析（`CUINamedVectorGlyph`）明显下降。

## 仍然存在的问题（后续）

剩余 8.7% 主要是**设置面板整体 SwiftUI 重渲染**：`SettingsView`、`AudioSectionView`、
`BatterySectionView`、`NetworkSectionView`、`StatusIconPreviewCard`、`MiddleIconSettingsGroup`
等大量视图都用 `@ObservedObject var statusStore: SystemStatusStore` 观察整个 store，
而 `SystemStatusStore.setVolume` 每次都会 `publish(snapshot.replacingVolume(...))`
触发 `objectWillChange`。图标光栅已消除，但 view body 重算仍在。

要彻底压平，需要把设置面板的观察粒度收窄（例如订阅去重后的派生值，
或让音量变化不触发这些视图的 `objectWillChange`）。这是独立改造，未包含在本次修复内。

另：关闭设置窗口后，调音量的 CPU 本来就在 0.8% 左右——**峰值只在设置窗口
（或面板）可见时出现**，这一点与「面板可见时窗口布局是主线程大头」的采样一致。
