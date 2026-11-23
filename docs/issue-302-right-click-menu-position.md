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
