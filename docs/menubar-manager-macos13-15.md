# MenuBarManager：macOS 13–15 功能总结

> 记录日期：2026-11-14
> 对象：独立的 MenuBarManager 实验工程（SwiftPM，不是 Status Trio 主工程组件）
> 范围：只写实际验证过的内容；未验证的明确标 NOT RUN。

## 1. 功能是什么

一个只管理**自己**的菜单栏小工具：显示一个圆点图标（红/绿/蓝可换色），并尽力保证它在菜单栏
**可见、且排在最右侧**（系统时钟/控制中心左侧）。不发现、不管理其他 App 的状态项。

## 2. 实现方式

1. **可见性检测**：用公开 CGWindowList 找属于自身 PID、kCGWindowLayer == 25 的窗口，出现在 on-screen 列表即视为可见。
2. **满栏挤位**：确认辅助功能权限后，另起短命 helper 子进程（--make-room），用**合成 Cmd＋拖拽**把最左侧的其他状态项逐步往左推，直到自身图标露出。
3. **右移定位**：helper（--move-right / --ensure-right）同样用合成拖拽把自身图标滑到最右槽位。
4. **手动入口**：设置窗口「把图标移到最右边」按钮，每点一次重试一次。
5. **私有检查（仅 14/15）**：MenuBarWindowInspector 用私有 SkyLight/CGS 辅助枚举菜单栏窗口；macOS 13 不构造该对象，走公开窗口信息路径。

拖拽由**独立进程**发起，因为从 App 自身处于前台时发起自拖，在 14/15 上不被系统接受。

## 3. 版本状态

| 版本 | 状态 | 依据 |
| --- | --- | --- |
| macOS 13（13.6 VM） | 通过：可运行、授权后不崩溃、**可移到最右** | 2026-11-14 人工实测（r2 0.1.1） |
| macOS 13 满栏挤位 | **NOT RUN** | 未测 |
| macOS 14 | **NOT RUN** | 代码路径完整（含私有 CGS 检查），无真机记录 |
| macOS 15 | **NOT RUN（我方）** | 交接文档自称 15.6.1 VM 通过，无复现记录 |

macOS 26/27 属另一套机制，不适用本结论。27 实测状态项窗口已不是 layer 25（变为 layer 0 全宽），
可见性检测与拖拽定位均失效。

## 4. 已知问题与修复

- **macOS 13 授权后必崩（已修）**：后台 AX 扫描通过 applicationMenuBounds 查询**本进程**的 Carbon 菜单，
  触发 HIToolbox _dispatch_assert_queue_fail（线程断言 SIGTRAP）。自身菜单范围本就不用于遮挡判定，
  但旧代码先查后忽略。修复：按自身 PID 直接跳过，不进入该查询；新增两条回归测试
  （自身查询零 AX、外部 PID 仍查询）。13 特有，14/15 未暴露。
- **macOS 15 宽度判断错误**：旧代码用 separator.width <= 26 判「已展开」，而 15 上 24pt 状态项实际窗口约 40pt，恒假。
- **自身在前时全部项显示「未知」**：把自身菜单当遮挡。修复：前台为自身时不把自身菜单计入遮挡。
- **扫描 partial 长期为真**：WebKit/后台 XPC helper 的 AX 失败被当成扫描缺口。改为按可验证身份
  （activationPolicy == .prohibited 或内嵌 helper 路径）归为良性；顶层 App 失败仍算 partial。
- **每次切前台闪「未知」**：前台激活也走了 mover.invalidate()。改为轻量防抖重扫。
- **空分隔器仍是灰块**：最终按产品决定彻底移除分隔器与逐项隐藏。

## 5. 使用前提与风险

- 需要**辅助功能**权限，不需要屏幕录制。
- 会**移动真实鼠标**、**改变其他 App 图标的排列顺序**；退出不会自动恢复原顺序。
- 强依赖「窗口层级 25」假设与主屏幕坐标；多屏、刘海、菜单栏自动隐藏均未验证。
- macOS 15 上 NSStatusItem.length 有 10000pt 硬上限。
- 私有 CGS 接口只在 14/15 使用，存在随系统版本失效的风险。

## 6. 结论与建议

macOS 13–15 **可以做，但必须逐版本验收**：

1. 13 已过「能跑、能右移」，缺**满栏挤位**；
2. 14、15 目前只有代码，缺真机证据；
3. 正式支持前，14 和 15 各跑一遍「空栏右移 + 满栏挤位」。

判断成败的日志：

```bash
log show --last 5m --predicate 'subsystem == "com.statusgtrio.menubarmanager"' --info
```

若出现 ownControlVisible=false 但后续 helper 无结果，说明满栏时没认出自身图标（layer 25 假设不成立），
属定位失败而非拖拽被拒。

## 7. 延伸：能否拖拽 / 管理其他 App 的菜单栏图标

### 7.1 现有代码基础

MenuBarCore 里这套机制基本没删，只是产品层把入口和分隔器去掉了：

- MenuBarScanner / AXMenuBarDiscovery：按 App 枚举 kAXExtrasMenuBarAttribute，产出 ManagedMenuBarItem
  （bundleID、pid、frame、windowID、runtimeToken，以及是否 stale/ambiguous）。
- SystemMenuBarMover.move(_:toHidden:)：完整编排——展开隐藏区 → 取新快照 → 校验身份唯一 → 只发一次手势
  → 回读验证几何 → 失败自动展开回滚；连续失败 3 次暂停。
- StandardCommandDragTransport：实际合成 Cmd＋拖拽，带忙检查、指针恢复、单次手势限制。
- MenuBarSectionLayout：分隔器长度数学（展开约 24pt，收起约最宽屏 + 40pt），有单测。
- MenuBarVisibilityManager：读写真实可见状态，失败不伪造、不重试物理手势。
- 测试：MovementFlowTests、ProtectionAndRecoveryTests、VisibilitySafetyTests、SectionLayoutTests。

### 7.2 两条可行路线

| 路线 | 说明 | 现状 |
| --- | --- | --- |
| A. 隐藏 / 展开其他 App 图标 | Ice / Hidden Bar 式：恢复一个分隔器，把目标图标拖到分隔器左侧，再撑长分隔器把它挤出可视区 | 逻辑全在，但 separatorItem = nil，conceal() / expandAndReveal() 已是空壳 guard，需要恢复分隔器与 UI |
| B. 把指定图标拖到指定位置（纯重排） | 不需要分隔器，直接算目标 x 后拖过去 | 底层拖拽、身份校验、回读验证都能复用，缺“指定目标位置”的编排与入口 |

### 7.3 共同前提与风险

- 需要辅助功能权限；A 路线属于自动化移动，必须由用户显式开启兼容模式（原设计要求）。
- 身份必须唯一：identity + pid + runtimeToken + windowID 全部匹配，否则拒绝；同 App 多图标、旧快照一律禁用。
- 扫描有缺口时禁止隐藏（isPartial 或 failedBundleIDs 非空直接拒绝），防止误藏未发现的项目。
- 会移动真实鼠标、改变他人图标顺序；强依赖「窗口层级 25」与主屏幕坐标。
- A 路线固有边界：新出现的状态项默认落在分隔器左边（会被隐藏），需要产品决策。

### 7.4 版本可行性

- macOS 13：13.6 实测自身图标能被识别并右移，说明 layer == 25 在 13 上成立，枚举与拖拽基础成立；
  但移动其他 App 的图标未测。
- macOS 14 / 15：另有私有 SkyLight/CGS 窗口枚举，理论上更稳；仍是 NOT RUN。
- macOS 26 / 27：不适用。27 上状态项窗口已变为 layer 0 全宽，检测与定位均失效。

### 7.5 结论

可以支持，工作量中等：底层已具备，缺的是“分隔器（A）或目标位置编排（B）”加一个入口。
建议顺序：先用 MenuBarProbe 做命令行原型（列图标 / 指定 bundle 隐藏 / 指定 bundle 移到 x），
在 13 与 15 上各验证一次，再把可用路径搬进设置界面。

