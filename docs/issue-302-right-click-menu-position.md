# Issue #302：右键菜单偶尔位置偏移，没有贴着菜单栏图标

## 现象

右键点击菜单栏图标弹出的菜单偶尔会偏离图标（截图里偏向图标左侧/下方），
1.9.4 版本报告。用户未提供复现条件，属于偶发问题。

## 代码里真实存在的问题

`StatusBarController.showMenu()`（右键 `.contextMenu` 路径）直接用状态按钮的
本地坐标定位菜单：

```swift
menu.popUp(
    positioning: nil,
    at: NSPoint(x: 0, y: button.bounds.maxY + 4),
    in: button
)
```

菜单本身的定位公式没问题；问题在于它**完全信任按钮当下的 `bounds` / 窗口坐标**。
AppKit 在状态项或菜单栏生命周期抖动（重建、切换分辨率/显示器、菜单栏显示隐藏、
图标刷新）时会短暂报告一个「看起来合理但其实是错的」矩形，导致 `in: button`
把菜单弹到错误位置。

左键面板走的 `presentPopoverFromShortcut → visibleMenuBarAnchor()` 早就有这层防护：
`StatusPanelShortcutPresentationPolicy.isUsableMenuBarRect` 会拒绝两种明确的错误矩形，
注释写得很直白：

> Reject a stale bottom-left frame and the whole menu-bar window that AppKit briefly
> reports during lifecycle churn; both produce a plausible but wrong keyboard anchor.

右键菜单路径没有复用这套校验，于是偶发偏移。

## 修复

- 新增 `StatusMenuPresentationPolicy`（`Sources/StatusTrioCore/UI/StatusMenuPresentation.swift`），
  复用 `isUsableMenuBarRect` 校验状态项屏幕矩形：
  - 矩形有效 → `.present`，立即弹菜单；
  - 矩形缺失或无效 → `.retry`，下一轮 run loop 再试（最多 `maximumRetries = 2` 次，
    正常路径无感知延迟）；
  - 重试预算用尽仍无效 → `.present` 兜底，保证右键不会「点了没反应」。
- `showMenu()` 改为先校验 `visibleMenuBarAnchor()?.screenRect` 再决定是否弹。
  菜单定位公式保持 `in: button` 不变，正常场景行为与之前完全一致，只把
  「几何还没准备好」的时刻从「弹到错误位置」改成「等一帧再弹」。
- 左键面板路径不受影响（仅把 `isUsableMenuBarRect` 从 `private` 改为 `internal`
  以便复用，行为不变）。

## 验收要点

- 单屏、多屏、切换分辨率/显示器、菜单栏自动隐藏、全屏与不同桌面下，右键菜单都
  贴着图标下方展开。
- 同一场景连续右键多次位置稳定。
- 左键打开面板的锚点行为不变。

## 测试

- `StatusMenuPresentationPolicyTests`：有效矩形立即展示、缺失/隐藏/整条菜单栏矩形/
  脱离菜单栏的矩形/屏幕外矩形/零尺寸矩形都先重试、重试预算后兜底展示。
- `StatusPanelShortcutPresentationPolicyTests`：原有 8 个用例全部通过，校验逻辑未被改坏。

注：真实菜单弹出位置属于可见 UI 行为，需人工在多显示器 / 菜单栏自动隐藏等场景验收，
本地单测只覆盖校验与重试决策。

## 后续修复（macOS 15：版本号首行被裁切，菜单变成可滚动）

现象（macOS 15）：右键菜单顶部出现一个向上箭头（滚动指示），版本号那一行被顶到
可视区外，鼠标移上去才滚动出来，同时整张菜单向下展开。截图见本机复现（2026-11-26）。

根因：旧代码用
`menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)`，
把菜单顶边锚在状态按钮自身坐标里。状态项是**垂直居中**在菜单栏中的，它的下边缘离菜单栏
下沿只有几 pt，`+4pt` 后菜单顶边仍落在菜单栏这条 38pt（带刘海）的条带里；于是第一行
（版本号）被菜单栏压住、裁掉，AppKit 把菜单变成可滚动并显示向上箭头，悬停滚动后整张菜单
下移。macOS 26/27 的菜单栏几何不同，同一偏移刚好落在栏下，所以之前没暴露。
（曾怀疑是 `NSStatusBarButton.isFlipped` 版本差异，实测这台 15.8.3 上它也是 `true`，已排除。）

修复：新增 `StatusMenuPresentationPolicy.anchorPoint(for:gap:menuBarBottom:)`，用状态项的
**屏幕坐标**算菜单左上角 `(x: rect.minX, y: rect.minY - 4)`（图标下边缘留 4pt），并把它
**钳到菜单栏下沿**（`min(计算值, visibleFrame.maxY)`）——因为状态项是垂直居中在菜单栏里的，
它的下边缘可能只比菜单栏下沿高几 pt，"下边缘 + 4pt"仍可能落进菜单栏；钳住后菜单一定从
菜单栏下方开始。`popUp` 改用 `in: nil`（屏幕坐标），不再依赖按钮坐标方向。
`StatusMenuPresentationPolicyTests` 增加锚点计算用例（含负 gap 夹紧与菜单栏下沿钳制）。

补充（实测 macOS 15.8.3）：菜单栏高 38pt、顶部安全区 32pt（刘海）。状态项下边缘离菜单栏
下沿很近，旧锚点因此把菜单顶边压进菜单栏；macOS 26/27 的菜单栏几何不同（更高/安全区不同），
同一偏移刚好落在栏下，所以之前没暴露。
