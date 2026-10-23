# Issue #115：BenQ 外部音量案例证据表

本文汇总**其它用户、其它型号**的公开报告，用来界定“DDC 音量不可用”可能出现在哪一层，
以及它对我们代码的指导。

> **边界声明**：下表全部是第三方报告，不是 Status Trio 的实测结果，也不代表
> Issue #115 报障用户的 BenQ 型号/连接方式与其相同。文中任何结论都不能表述为
> “BenQ 已支持”或“BenQ 已修复”。链接与标题在 2026-10-18 用
> `gh issue view` 复核过（状态、标题、URL），对话细节未逐条复核。

## 证据表

| 设备 / 讨论 | 公开现象 | 对 Status Trio 的指导 |
| --- | --- | --- |
| [BenQ PD2725U · MonitorControl #574](https://github.com/MonitorControl/MonitorControl/issues/574)（[Discussion #576](https://github.com/MonitorControl/MonitorControl/discussions/576)） | 亮度可用，但 m1ddc / Lunar 的音量控制失败；厂商对该型号的音量 VCP 能力给出否定回复 | DDC 亮度可用**不能**推出音量可用；软件音量是另一条独立路径 |
| [BenQ PD2705U · BetterDisplay #2836](https://github.com/waydabber/BetterDisplay/issues/2836) | 亮度正常，但音量 GUI 不改变真实声音 | BetterDisplay 并非在所有 BenQ 上都能硬件调音量；第三方 App 存在不代表协议可用 |
| [BenQ EW2780Q · MonitorControl #1260](https://github.com/MonitorControl/MonitorControl/issues/1260) | 音量滑块可移动，实际声音不变 | I²C 写确认 ≠ 可听结果；硬件能力与音频路径要分开验证 |
| [BenQ BL2420PT · MonitorControl #1179](https://github.com/MonitorControl/MonitorControl/issues/1179) | M1 Mac mini 走 HDMI 失败，Thunderbolt→DisplayPort 正常 | 连接路径是诊断维度，不能把所有失败归因到驱动代码 |
| [BenQ EX2780Q · MonitorControl #201](https://github.com/MonitorControl/MonitorControl/issues/201) | `ddcctl` 可写音量，但最大刻度为 50，按键增量异常 | 必须使用设备报告的 maximum，不能假定 100（我们的 `invalidRange` 与 `maximum` 校验覆盖这一点） |
| [BenQ PD2506Q · BetterDisplay #5278](https://github.com/waydabber/BetterDisplay/issues/5278) | BetterDisplay GUI / `ddcctl` 有效，键盘不生效；用户切换 DDC / 原生键盘选项后报告恢复 | 要区分“按键是否被拦截”与“是否真的写入了寄存器”；第三方 OSD 生效不代表系统原生音量路径生效 |
| [BenQ PD3220U · MonitorControl #110](https://github.com/MonitorControl/MonitorControl/issues/110) | DDC 音量失效；有用户改用 Soundflower 作为软件音量替代 | 软件音量是独立可行方向，但需要用户安装额外音频组件（本轮不引入） |
| [BenQ PD2700U · ddccontrol-db #100](https://github.com/ddccontrol/ddccontrol-db/issues/100) | 报告了 `VCP 0x62` 的数值 | 不能把所有 BenQ 统一标记为不支持 `0x62` |

## 从证据推出的、写进代码的规则

1. **不按品牌/型号判定后端。** 选择只依据运行时探测结果（见
   `docs/design/audio-volume-backends.md`）。
2. **分离四件事**：能否读到合法回复、写入是否被 I²C 确认、读回是否与写入一致、
   人耳听到的音量是否变化。我们只能断言前三者中已验证的部分。
3. **读回一致但声音不变**时，可能是显示器固件、显示器音频路径（HDMI/DP 音频回传）
   或软件混音，**单次 DDC 读回无法独立判定**；这类情况不应报成我们的 bug 或修复。
4. **保留连接路径维度。** HDMI 失败 / DP 成功的案例说明失败可能来自链路，
   `ddc.resolve`、`ddc.probe` 的阶段化日志正是为了把这类失败与协议失败分开。
5. **最大刻度必须来自设备。** 不用 100 或本地缓存值替代显示器报告的最大值。

## 仍未验证（Issue #115）

- 报障用户 BenQ 的具体型号、连接方式（HDMI / DP / USB-C / 扩展坞）。
- 其 `DDCTarget` 阶段日志（`ddc.resolve` / `ddc.probe` 的 stage 与 outcome）。
- BetterDisplay 在该机器上实际使用了哪条后端，以及是否改变了可听音量。

在拿到这些之前，本轮工作只声明“修复了我们自身可复现的协议判定缺陷”，
不声明用户问题已解决。
