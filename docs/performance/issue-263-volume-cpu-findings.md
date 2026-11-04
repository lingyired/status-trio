# Issue #263 — 调音量时 CPU 飙升：实测定位与结论

日期：2026-11-04。机器：ARM64，macOS 27.2 (26B123)，Release 配置。
所有数字来自临时微基准与 `sample`/`top`，测量文件用完即删。

## 结论先行

**「图标整张重绘」不是 CPU 飙升的原因。** 菜单栏整图重绘仅 **0.078 ms**，
Dock 512px 整图 **0.505 ms**；按最激进的 20 Hz 也只有约 0.16% / 1% CPU，
而且实际链路还有 500 ms 快照去抖，拖动期间根本到不了 20 Hz。

**分区增量重绘（原本的「路线 A」）被实测否定**：收益是 0.08 ms 量级，
却要引入跨帧合成画布、区域差异与 template 一致性风险，不划算，不应实施。

## 完整测量表

| 测量项 | 每次耗时 |
| --- | --- |
| 菜单栏 template base @22pt（默认外观） | 0.076 ms |
| 菜单栏 template base @22pt（真实 darkAqua） | 0.078 ms |
| 菜单栏 template base @32pt | 0.084 ms |
| 菜单栏完整 `menuBarImage`（含 template 调整） | 0.075 ms |
| 菜单栏彩色 overlay `menuBarChromaticImage` | 0.029 ms |
| Dock 整图 512px `DockIconRenderer.image` | 0.505 ms |
| accessibility `statusItemValue` 构建 | 0.076 ms |
| accessibility 值构建 + 写入 | 0.090 ms |
| CoreAudio `read()` 完整设备读取 | 0.43 ms |
| CoreAudio `setVolume()` 写入 | 0.20 ms |
| **音量反馈音 `sound.stop(); sound.play()`** | **13–21 ms wall / 1.6 ms CPU** |
| `NSSound` 只 `play()`（已放完） | 0.24 ms，但**返回 false、不重播** |
| `AudioServicesPlaySystemSound` | 0.016 ms，但走系统提示音量、不随输出音量 |

## 关于音量反馈音（唯一毫秒级操作）

`VolumeFeedbackPlayer` 每 0.1 s 最多触发一次，每次 `sound.stop(); sound.play()`：
实测 **13–21 ms wall、1.6 ms CPU**，在主线程同步执行。

为什么必须 `stop()`：`NSSound.play()` 对**已经播完**的实例返回 `false` 且不重播
（探针确认：first play=true，replay-after-finish=false），所以复播只能靠
`stop()` + `play()`，而这一对操作会重启音频引擎，成本就在此。

可行但各有代价的替代：
- 轮转池两个 `NSSound` 实例：0.72 ms，但第二次起 `play()` 返回 `false`（静音），不可用。
- `AudioServicesPlaySystemSound`：0.016 ms，但脱离输出音量跟随，属行为变更。

## 真实进程 CPU（关键限定）

- 空闲基线：**0.6–0.7%**
- 连续改变系统音量 2 秒（20 次）：`ps` 最高 **1.6%**，`top` 瞬时最高 **1.8%**
- 外部改音量期间 `sample` 抓 6 秒：Status Trio 几乎全空闲
  （栈顶全是 `__workq_kernreturn` / `mach_msg2_trap` 等待），
  `renderLatestScene` / `renderLatestDockIcon` 出现 **0 次**
- CoreAudio HAL 属性查询（`AudioObjectGetPropertyData` 等）出现在音频线程，
  但对应的是系统音频栈，不是本进程热点

**在本机无法复现「大幅 CPU 飙升」**，可测到的量级只有 1–2%。

## 早前真实拖动采样里的布局热点

一次面板打开、用户拖滑杆的采样中：主线程 4412 个样本里约 **951 个**落在
`layoutIfNeeded` / `_layoutViewTree`（窗口布局），而图标渲染 **0 次**。
说明**面板可见时，窗口布局是比图标光栅大一个量级的主线程工作**，
但它的触发条件是面板可见，不是「调音量」本身。

## 若要继续，建议的下一步

1. **先在用户机器上取该场景的 `sample`**：确认峰值是主线程布局、
   核心音频写入，还是别的进程（WindowServer / Dock）。
2. 若确认是面板布局：考虑面板可见时降低音量发布频率（滑杆 draft 已本地化，
   有空间做节流）。
3. 若确认是反馈音：把 `stop()+play()` 换成不重启音频引擎的方案（需接受
   音量跟随或系统音效的行为差异），并做真机听感验收。

## 明确不建议

- 图标分区增量重绘（收益 0.08 ms，风险高）。
- 在无采样证据的情况下宣称任何 CPU 改善。
