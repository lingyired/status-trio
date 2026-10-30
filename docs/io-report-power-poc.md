# IOReport SoC 功耗只读 POC 报告（Phase 2 / PR B 可行性验证）

- 状态：**NO-GO**（SoC 总量 + CPU/GPU/ANE/DRAM 细分在 macOS 27.2 / M3 Max 上不可用）
- 日期：2026-10-30
- 执行：独立 POC，不修改产品代码；本 PR 仅提交报告与开发工具（`Tools/ioreport-poc/`），不接入产品 UI
- 依据：`status-trio-battery-details-enhancement-plan.md` B1–B5 与「建议执行步骤」
- POC 源码：`Tools/ioreport-poc/`（纯开发工具，不在 `Package.swift` 内，不进产物）
- 产物/日志：`/tmp/ioreport-poc/`（`experiments.jsonl`、`all-channels.txt`、`em-list.txt`）

---

## 0. 结论摘要（先说人话）

1. **IOReport 在无 sudo、无 TCC/管理员弹窗、无 daemon/LaunchAgent、无 entitlement 的情况下可以打开并读取**：POC 是 ad-hoc linker-signed、无任何 entitlement 的普通用户进程（uid 501），`dlopen("/usr/lib/libIOReport.dylib")` 成功，17 个所需符号全部解析。
2. **但拿不到目标数据**。本机 `Energy Model` 组共 325 个通道，在 7 组对照实验（空闲、8 线程 CPU 满载、Metal GPU 负载、恢复空闲）里**只有 1 个通道在增长：`GPU Energy`（nJ）**；其余 324 个通道（`CPU Energy`、`ANE0`、`DRAM0`、`DISP0`、`PCIe Port *` 等）**计数器完全冻结在 0**，CPU 满载时也不动。这与 macmon 记录的 macOS 27 行为一致：Energy Model 的 CPU/ANE 计数器在没有 Apple 私有 entitlement 时会冻结。
3. **总功耗交叉验证通过，但正好证明缺口**：SMC `PSTR` 与电池放电（`B0AV×B0AC`）随负载同步变化（空闲 31–40 W，8 线程 CPU 满载 47–51 W，二者相差 0–8%），而 IOReport 能读到的 "SoC" 只有 2.0–3.0 W（仅 GPU），**不随 CPU 负载变化**，覆盖率约 5–8%。也就是说：拿 IOReport 当 "SoC 总功耗" 会低报一个数量级。
4. **CPU / GPU / ANE / DRAM 的"互斥通道"无法在本机验证**：因为 4 个 IP 块里 3 个计数器是死的；`GPU Energy` 虽然会长，但在 Metal 负载把 GPU 打到 53% 利用率时只读到 2–11 W（明显偏低/抖动），无法用任何独立源校准。按计划 B2 的门槛（"无法区分重叠通道 → 仅调查报告，不接入 UI"），这里必须止步。
5. **显示屏、USB 都没有可验证测量源**：Energy Model 的 `DISP0/DISPEXT0` 冻结；DCP/DCPEXT0 的 `power`/`instant_energy` 通道要么整体不推进（DCP 组 "no channel advanced"），要么单位不可换算（`events`）；USB 在 IOReport 里只有中断/时间统计，没有任何功率通道。结论：两条支路一律"隐藏"。
6. **开销可接受但不重要**：订阅建立约 54 ms（一次性）、每次区间采样约 2.9–3.3 ms、SMC 四键读取约 1.2 ms，采样循环自身 CPU 0.75%（单核占比）、6 秒内自身能耗 0.095 J、RSS 9.7 MB。若功能成立，2–5 秒窗口对 app 页面打开完全可接受。
7. **因此本阶段只提交调查报告，不接入产品 UI**。现有 `PSTR`（整机，已可用）+ 电池功率（已可用）足够支撑"功率流向"第一层；不建议为了"SoC 细分"引入私有 IOReport。

---

## 1. 环境（实测）

| 项 | 值 |
|---|---|
| 机型 | MacBook Pro `Mac15,9`（Apple M3 Max，16 核 = 12P + 4E，128 GB） |
| 系统 | macOS 27.2（build 26B123） |
| 工具链 | Xcode 27.0（27A266a），Swift 6.4（swiftlang-6.4.0.34.1），SDK `MacOSX.sdk` |
| 用户 | uid 501（普通用户），全程未使用 sudo |
| 电源状态 | `pmset -g batt`：AC attached、not charging；`PDTR`≈0.19–0.21 W（适配器几乎不供电），电池实际在放电，电池电量 91–97% |
| 背景负载 | loadavg 约 9–13（`BlueStacks`、`WindowServer`、`mediaanalysisd`、DeepSeek Harness 渲染进程等）。**不是静置机器**——这一点对绝对值有影响，局限见第 12 节 |
| POC 二进制 | `/tmp/ioreport-poc/ioreport-poc`，ad-hoc linker-signed，`codesign -d --entitlements -` 为空，`otool -L` 中**没有** IOReport（纯 dlopen） |

### 关键环境变化（影响任何"照抄 Stats"的实现）

- macOS 27.2 上 `/System/Library/PrivateFrameworks/IOReport.framework` **已不存在**：

  ```
  dlopen(/System/Library/PrivateFrameworks/IOReport.framework/IOReport): tried:
    '/System/.../IOReport.framework/IOReport' (no such file),
    '/System/Volumes/Preboot/Cryptexes/OS/...' (no such file),
    '/System/.../IOReport.framework/IOReport' (no such file, not in dyld cache)
  ```

- 实际 dylib 在 dyld shared cache 里，路径为 `/usr/lib/libIOReport.dylib`（`dlopen` 成功）。
- SDK 里仍保留 `usr/lib/libIOReport.tbd`（install-name `/usr/lib/libIOReport.dylib`，导出 60+ 个 `_IOReport*` 符号），所以**链接期**也能用 `-lIOReport`（macmon 就是这样），但那样会在产物里留下 `LC_LOAD_DYLIB /usr/lib/libIOReport.dylib`。POC 选择 dlopen，是为了等价验证"不链接私有库"的隔离方案。

### 实际解析到的符号（dlopen + dlsym，17/17 全部成功）

`IOReportCopyAllChannels`、`IOReportCopyChannelsInGroup`、`IOReportCreateSubscription`、`IOReportCreateSamples`、`IOReportCreateSamplesDelta`、`IOReportChannelGetGroup`、`IOReportChannelGetSubGroup`、`IOReportChannelGetChannelName`、`IOReportChannelGetUnitLabel`、`IOReportChannelGetFormat`、`IOReportSimpleGetIntegerValue`、`IOReportStateGetCount`、`IOReportStateGetNameForIndex`、`IOReportStateGetResidency`、`IOReportMergeChannels`（另有 `IOReportChannelGetDriverID`/`IOReportGetChannelCount` 等在同一 tbd 中，未使用）。

> 权限结论的证据链：进程无 entitlement、非 root、无沙盒例外，dlopen/dlsym 成功，订阅创建成功，采样返回真实变化数据（GPU 通道），**全程无任何 TCC/管理员/钥匙串弹窗**。因此"读 IOReport 需要 root 或 entitlement"这一说法在**打开与订阅**层面不成立；限制体现在**部分计数器是否更新**（见下）。

---

## 2. 方法

POC 单文件 Swift（`Tools/ioreport-poc/ioreport-poc.swift`），无 SPM target，命令：

```
ioreport-poc groups                  # 210 个 group、11292 个 channel 的全景
ioreport-poc list --group "Energy Model"
ioreport-poc sample --group G --window W [--windows N] [--json] [--raw] [--nonzero]
ioreport-poc bench                   # 订阅/采样/SMC 耗时、自身 CPU%、RSS、ri_energy_nj
ioreport-poc selftest                # 基线/回卷/停滞门控的合成用例
bash run-experiments.sh              # 受控对照批次（见第 4 节数据来源）
```

采样模型（与计划 B1 的 `begin/finish` 两阶段一致）：

1. `IOReportCopyChannelsInGroup("Energy Model", nil, 0,0,0)` 取通道字典（325 个）；
2. `IOReportCreateSubscription(nil, dict, &sub, 0, nil)` 建立订阅；
3. 第 1 次绝对采样**只建立基线**，不产出瓦数；
4. 窗口结束后第 2 次绝对采样，**逐通道做整数差** `cur - prev`（不用 `CreateSamplesDelta` 也行，自己减便于检测回卷）；
5. 单位换算按通道自带的 `UnitLabel`：`nJ→1e-9 J`、`uJ→1e-6 J`、`mJ→1e-3 J`，除以实测 `dt` 得 W；
6. 门控（`--selftest` 6/6 PASS）：
   - 首样本 → `baseline`；
   - 任一通道 `cur < prev` → 判定计数器重置/回卷（睡眠唤醒、IP 块掉电、能量计数器翻转），**丢弃整个区间并重建基线**，绝不出负数瓦数；
   - 所有通道都不推进 → 判定 `stale`（遥测停更），**不显示 0 W**；
   - `dt < 0.05 s` 或 `dt > 120 s` → 判定 `invalid`（基线过期）；
   - 中途新出现的通道不参与差值（不会崩、不会造数）。
7. 交叉验证同窗口读取：SMC `PSTR`/`PDTR`/`B0AC`/`B0AV`（80 字节 ABI，直接照抄 `SystemPowerReader` 的只读命令 9/5 与 `flt`/`si16`/`ui16` 解码）、IORegistry `AppleSmartBattery`（`Voltage`/`Amperage`/`InstantAmperage`/`ExternalConnected`/`IsCharging`）；
8. 自身开销：`getrusage`（user+sys）、`proc_pid_rusage(RUSAGE_INFO_V6).ri_energy_nj`、`ru_maxrss`。

---

## 3. Channel 清单（本机实测，2026-10-30）

- IOReport 全景：**210 个 group / 11292 个 channel**。
- `Energy Model`：**325 个通道**，按单位：`mJ` 319 个、`uJ` 5 个、`nJ` 1 个。
- `IOReportChannelGetFormat` 对 Energy Model 通道统一返回 `1`（POC 只把它当作诊断信息打印，取值与换算**不依赖** format，一律用 `IOReportSimpleGetIntegerValue` + `UnitLabel`，与 macmon/matti-power 一致）。

关键通道（节选，完整清单见 `/tmp/ioreport-poc/em-list.txt`）：

| 通道名 | 单位 | 语义（按名字/与参考实现对照） | 实测是否推进 |
|---|---|---|---|
| `CPU Energy` | mJ | 整 CPU 块聚合（M1–M4 的 `CPU Energy`；Ultra 为 `DIE_n_CPU Energy`） | **否（恒 0）** |
| `PACC0_CPU0..5`、`PACC1_CPU0..5` | mJ | P 簇每核 | 否 |
| `EACC_CPU0..3` | mJ | E 簇每核 | 否 |
| `PACC*_CPM`、`EACC_CPM` | mJ | 簇级 CPM | 否 |
| `EACC_CPU*_SRAM`、`PACC*_CPU*_SRAM` | mJ | 每核 SRAM 轨 | 否 |
| `PCPU0DTL00..3c`、`PCPU1DTL*`、`ECPU*DTL*` | mJ | 每核每 P-state 细分 | 否 |
| `GPU Energy` | **nJ** | GPU 精确能量轨（参考实现取此通道，忽略粗糙 `GPU0`） | **是** |
| `GPU0` | mJ | GPU 粗糙聚合 | 否 |
| `GPU CS0`、`GPU SRAM0`、`GPU CS SRAM0` | mJ | GPU 子轨 | 否 |
| `ANE0` | mJ | ANE 能量（M3 Max 命名） | 否 |
| `DRAM0`、`DCS0`、`AMCC0` | mJ | 内存子系统相关轨 | 否 |
| `DISP0`、`DISPEXT0` | mJ | SoC 显示管线（内屏/外接），**不是面板功耗** | 否 |
| `ISP0`、`AVE0`、`MSR0` | mJ | 其它 IP | 否 |
| `PCIe Port 0/1 Energy`、`apciec0..2 Energy` | uJ | PCIe 控制器 | 否 |

推进性统计（全部 7 个对照条件的交集）：**325 个通道里只有 `GPU Energy` 有非零增量**；其余 324 个在空闲、CPU 满载、GPU 负载下**增量恒为 0**。

> 注意：冻结的通道不是"读法错误"——同一套 `IOReportSimpleGetIntegerValue` 读 `GPU Energy` 能读出连续增长的值，说明订阅、采样、单位换算链路是通的；冻结的是**计数器本身**。

---

## 4. 实测数据

数据来源：`bash run-experiments.sh`（每次窗口 5 s；记录当时的 `vm.loadavg`、AC/电池状态）。完整机器可读数据在 `/tmp/ioreport-poc/experiments.jsonl`。

| 条件 | loadavg | SoC（实为 GPU only）W | PSTR W | PDTR W | 电池 SMC `B0AV×B0AC` W | 电池 IORegistry W | dt s | 单次采样 µs |
|---|---|---|---|---|---|---|---|---|
| 空闲-1 | 10.06 | 2.99 | 40.36 | 0.20 | −41.27 | −84.81 | 5.00 | 3293 |
| 空闲-2 | 10.97 | 2.71 | 35.46 | 0.19 | −35.25 | −84.81 | 5.01 | 3142 |
| 8 线程 CPU 满载-1 | 10.59 | 2.73 | 47.37 | 0.21 | −51.22 | −84.81 | 5.01 | 2865 |
| 8 线程 CPU 满载-2 | 11.19 | 2.29 | 48.24 | 0.21 | −47.97 | −46.45 | 5.01 | 3106 |
| Metal GPU 负载-1 | 13.47 | 2.10 | 40.93 | 0.19 | −42.17 | −46.45 | 5.01 | 3073 |
| Metal GPU 负载-2 | 12.94 | 2.23 | 42.37 | 0.20 | −43.53 | −46.45 | 5.01 | 3296 |
| 恢复空闲 | 12.42 | 2.06 | 31.44 | 0.19 | −33.88 | −46.45 | 5.01 | 2828 |

CPU/ANE/DRAM/display 四个分类在所有条件下都是 **0.000 W**（通道无增量，POC 按门控输出 0 而不是伪造值）。

### 4.1 窗口长度对读数的影响（同一时刻连续采样）

| 窗口 | SoC(GPU) W | PSTR W | 电池 SMC W |
|---|---|---|---|
| 1 s ×2 | 2.165 / 2.452 | 31.13 / 33.21 | −29.91 / −30.78 |
| 2 s ×2 | 2.486 / 2.596 | 33.68 / 34.54 | −31.64 / −33.11 |
| 3 s ×2 | 2.711 / 3.915 | 30.45 / 51.63 | −33.32 / −43.91 |
| 5 s ×2 | 4.365 / 2.624 | 33.31 / 34.96 | −31.22 / −34.76 |

结论：`GPU Energy` 计数器更新是**成簇/粗粒度**的（单秒内会看到 2 W→11 W 的跳变），窗口 <2 s 波动大；**≥5 s 才比较稳**。PSTR 在 3 s 那次出现 51.6 W 的离群值，是背景负载（loadavg 10+）造成的，与本功能无关。

补充观察（`GPU Energy` 通道本身的可信度）：在另一次背景 GPU 很重（loadavg≈10，BlueStacks/WindowServer 活跃）的时段，连续 3 次 5 s 采样读到 `GPU Energy` = 17.5 / 27.9 / 28.1 W；而背景 GPU 安静时只有 2–3 W。说明该通道**确实响应真实 GPU 工作**、不是死通道；但在我们合成的 53% 利用率 Metal 负载下又只读到 2–11 W、无法与任何独立源校准，因此**不能作为可交付的 GPU 功耗读数**。

---

## 5. 与 PSTR / 电池放电的交叉验证

| 对比 | 结果 | 解读 |
|---|---|---|
| PSTR vs 电池 SMC 放电 | 空闲 40.36 vs 41.27（+2.3%）、35.46 vs 35.25（−0.6%）；CPU 满载 47.37 vs 51.22（+8.1%）、48.24 vs 47.97（−0.6%） | **量级/边界一致性检查**：两条通道方向随负载同步、差 0–8%。注意本机 PDTR≈0.2 W，PSTR 此时本身就是电池放电，所以这是同一物理量的两种读数，**不是独立校准**。PSTR 仍可信、可继续作为"系统供电"来源 |
| PSTR vs 适配器输入 PDTR | 全程 PDTR 0.19–0.21 W | 本机虽"AC attached"，适配器几乎不供电（电池在实际放电）。所以**不能**把 PDTR 当输入功率参照；也说明为什么本报告用电池放电做交叉验证 |
| PSTR vs IORegistry 电池 | IORegistry 长期停在 −84.81 W，约 30–60 s 才跳一次（−84.81 → −46.45）；SMC 同一时刻已从 −41 变到 −51 | 复现了仓库已记录的"部分机型电池遥测约 1 分钟才更新"；**用 IORegistry 做秒级交叉验证不可行**，用 SMC `B0AV/B0AC` |
| PSTR vs IOReport "SoC 总量" | 空闲 40.36 vs 2.99（7.4%）、35.46 vs 2.71（7.6%）；CPU 满载 47.37 vs 2.73（5.8%）、48.24 vs 2.29（4.7%） | **IOReport 能读到的部分只占整机 5–8%，且 CPU 满载时占比反而下降**——因为 CPU 能量计数冻结。这就是"不能当 SoC 总功耗用"的直接证据 |

交叉验证方法说明：本报告只把多通道读数当作**量级与方向的一致性检查**，不把它当独立传感器校准；因此即使数值吻合，也不能据此把 IOReport 的 GPU-only 读数推广成 SoC 总量。

CPU 满载对照特别关键：`PSTR` +7~13 W、电池放电 +7~16 W，说明 CPU 确实在耗电；而 IOReport 的 `CPU Energy` 以及所有 `PACC*/EACC*` 通道**一个 mJ 都没有增加**。因此不是"CPU 用得太少"，而是计数器被冻结。

---

## 6. 精度与性能（POC 自身开销）

`ioreport-poc bench --window 6`（采样间隔 0.5 s，共 12 次）：

| 项 | 数值 |
|---|---|
| 订阅建立（`CopyChannelsInGroup` + `CreateSubscription`，325 通道） | **54.0 ms**（一次性） |
| 单次区间采样（绝对采样 + 325 通道整数差 + 差值表） | **mean 3.08 ms，p50 3.15 ms，max 3.29 ms** |
| SMC 四键只读（PSTR/PDTR/B0AC/B0AV） | mean **1.16 ms** |
| 采样循环自身 CPU（含 sleep，单核占比） | **0.75%** |
| 自身能耗增量（`ri_energy_nj`） | **0.095 J / 6.1 s ≈ 16 mW** |
| RSS | **9.7 MB** |
| 接受/拒绝样本 | 10 / 2（拒绝均为 `stale`——窗口内有通道整体未推进） |

对 app 的可行性判断（假如数据可用）：页面打开时建立订阅一次性 ~54 ms，之后每 2 s 采样 ~3 ms + SMC ~1.2 ms，摊到 2 s 约 0.2% 单核，**完全可接受**；主要成本是那 54 ms，建议放到后台队列、随功率卡展开时懒加载，页面关闭销毁订阅。**但当前数据不可用，所以不实施。**

---

## 7. macOS 版本 / 机型兼容性

| 目标 | 状态 | 依据 |
|---|---|---|
| macOS 27.2 / M3 Max（Mac15,9） | **实测**：可打开、可订阅；CPU/ANE/DRAM/DISP/PCIe 计数器冻结；仅 `GPU Energy` 推进 | 本报告 |
| macOS 13 (Ventura) | **NOT RUN** | 无可用机器；且私有 API 在旧系统上的通道布局不同 |
| macOS 14 / 15 / 26 | **NOT RUN** | 同上 |
| M1 / M2 | **NOT RUN** | 参考实现显示通道名不同（如 M1 的 `ANE`、M5 的 `GPU`+`GPU Energy` 并存） |
| M4 / M5 / M6 | **NOT RUN** | matti/power 的 SAMPLING-SPEC 在 M5 Pro 上验证过 Energy Model 可用；macmon 声称 macOS 27 起 CPU/ANE 计数器可能冻结 |
| Intel Mac | **不支持**（设计层面排除） | 无 Energy Model/Ane；现有实现依赖 Apple Silicon 通道 |
| Mac 休眠/唤醒后基线 | **NOT RUN（不许休眠）** | 逻辑用合成用例覆盖（`selftest`）：计数器回退 → 丢弃区间并重建基线，下一区间正常；真实唤醒需真机验证 |
| 带 Apple 私有 entitlement 的进程（如 `powermetrics`） | **NOT RUN（进程无法获得该 entitlement）** | macmon 注释指出有 entitlement 时计数器不冻结；我们无法验证，也不应依赖 |
| App Store 审核 | **NOT RUN** | 未提交；私有 API（Guideline 2.5.1）风险高 |

参考来源（外部，仅作对照，未作为本机结论）：
- macmon（`vladkens/macmon`）`src/metrics.rs` 注释：*"On macOS 27 Energy Model CPU/ANE counters can freeze without Apple's entitlement. Prefer readable CLPC counters…"*；其 `src/shared.rs` 过滤器只订阅 `CLPC`（`CLPC/Energy Counters/{CPU Energy,GPU Energy,ANE}`，单位 nJ）、`PMP/Energy Counters/ANE*`、`Energy Model` 的 `GPU Energy`/`*CPU Energy`/`ANE*`/`DRAM*`。
- matti/power `docs/SAMPLING-SPEC.md` + `src/samplers/ioreport.rs`：`/usr/lib/libIOReport.dylib`、无 sudo、单位按 `UnitLabel`（nJ/uJ/mJ）换算、按名字去重（`GPU Energy` 优先于 `GPU`，`*_SRAM`/`*DTL*` 是细分子项）。
- exelban/stats `Modules/GPU/reader.swift`：Swift 侧调用范式（`IOReportCopyChannelsInGroup("Energy Model")` → `IOReportCreateSubscription` → `IOReportCreateSamples` → 遍历 `IOReportChannels` → `IOReportSimpleGetIntegerValue`），ANE 用能量差。

**CLPC 替代路径（未实现、未验证）**：本机存在 `AppleCLPC` IOService（`IOUserClientClass=AppleCLPCUserClient`），且 `IOServiceOpen` 在无 entitlement 下返回 `KERN_SUCCESS`（type 0/1 均可）。macmon 用**按芯片型号 + macOS 版本硬编码的计数器 ID 表** 手工构造 `CLPC/Energy Counters` 通道，理论上能绕开冻结的 Energy Model。但这属于"逆向后按机器打表"的私有接口，跟着芯片/OS 更新就废，且与 App Store 永不相容。本阶段**不尝试**，只记录为"若产品坚持要 SoC 细分的唯一现实路径（高风险）"。

---

## 8. 重叠 / 重复统计风险

即使计数器可用，也需要证明"互斥通道"，本机因为 3/4 的 IP 块冻结，**无法用实测验证**。以下是从通道结构 + 参考实现整理的风险清单（都需要在有数据的机器上重新验证）：

| 风险 | 证据 | 需要的验证 |
|---|---|---|
| `CPU Energy` 与 `PACC*/EACC*`、`*_CPM` 是聚合-细分关系，不能相加 | 参考实现（matti/power）在存在 `CPU Energy` 时跳过 `MCPU*/PCPU*/ECPU*/PACC*/EACC*`；macmon 只取 `*CPU Energy` | 同一窗口比较 `CPU Energy` 与各簇/核之和，确认量级关系 |
| `*_SRAM` 已包含在所属 IP 的轨内 | 参考实现直接丢弃 `_SRAM` | 实测差分 |
| `PCPU*DTL*` 是每核每 P-state 细分 | 名字结构 + 参考实现丢弃 `DTL` | 同上 |
| `GPU Energy`（nJ）与 `GPU0`、`GPU CS0`、`GPU SRAM*`（mJ）重复 | 参考实现只取 `GPU Energy`，丢弃粗糙 `GPU` | 实测；注意本机 `GPU Energy` 在 Metal 53% 利用率下只报 2–11 W，**可信度存疑** |
| `DRAM0` vs `DCS0` vs `AMCC0` | 都在 Energy Model 组，名字不同，语义未公开；可能分别是 DRAM、片内缓存控制器、内存控制器的一部分 | 实测求和/相关；否则只能取其一 |
| `DISP0`/`DISPEXT0` 是 SoC 显示管线，**不是**面板功耗 | 参考实现把 `DISP*` 归为 SoC 侧"other"，不是显示屏 | 需要独立显示功耗传感器才能叫"显示屏 W" |
| "SoC 总量" 若用全部通道求和，会把 panel/PCIe 等整机部件算进 SoC | Energy Model 组同时含 `DISP*`、`PCIe*`、`ISP*`、`AVE*` | 必须先定义"哪些算 SoC"，且与 `PSTR` 的边界对齐 |

**结论**：在冻结的机器上，既不能验证细分，也不能验证互斥；计划 B1 要求的"确认 channel 定义后才汇总"无法满足。**不做"整机 − SoC = 其他负载"的估算**，因为 SoC 覆盖率只有 5–8%，减法结果会变成一个巨大的、无意义的数字。

---

## 9. 显示屏 / USB 结论

### 显示屏：**隐藏**（无可验证测量源）

- `Energy Model/DISP0`、`DISPEXT0`（mJ）：**冻结**（325 通道里除 GPU 外全 0）。
- `DCP` 组（内屏显示控制器，含 `display stats/power`、`instant_energy`）：`sample --group DCP` 直接返回 **"no channel advanced"**，整组计数器不推进。
- `DCPEXT0`（外接显示）组能推进的只有 `red/green/blue/frame_count/apl_*` 等 `events` 单位计数器，**没有可换算为瓦的功率/能量通道**；`power`/`instant_energy` 未出现在推进列表里。
- 因此：**不展示"显示屏 W"**。亮度、`system − soc` 余项都不能替代屏幕功率（计划 B1 已明确禁止）。

### USB：**隐藏**（IOReport 里没有功率源）

- 全量 11292 通道中，USB 相关只有 `dart-usb*` 的中断计数/时间（`First/Second Level Interrupt Handler Count/Time`），**没有任何功率/电流/能量通道**。
- 系统侧只有设备申报值（`system_profiler SPUSBDataType` 的 *Current Required* / IORegistry `bMaxPower`）和额定上限，**不是实时消耗**（计划 B1 同样禁止用它顶替）。
- 因此：**不展示"USB W"**。

---

## 10. App Store / 实验接口隔离方案（不实现产品代码，仅方案）

现状核实：
- `Package.swift` 只有两个 product：`StatusTrio`、`StatusTrioPowerHelper`；target 为 `StatusTrioCore`、`StatusTrio`、`StatusTrioPowerHelper`、`PowerHelperProtocol`、`DDCPrivateAPI`、`PowerUIPrivateAPI` 与两个测试 target。**没有 App Store/MAS 变体**。
- `scripts/build-app.sh` 只有 `CONFIGURATION` 与 `UNIVERSAL_BUILD`/`TELEMETRY_PRODUCTION`/`PRIVILEGED_HELPER` 等开关，**没有 App Store 分支**；发行路径是 Developer ID + Sparkle（GitHub）。
- 结论：当前不存在"从 App Store 构建中排除"的既有机制，需要新增；同时因为本项目不打算上架 MAS，这里的隔离更多是"**保证私有接口不进入任何会被签名/公证的产物** + 为将来可能的 MAS 变体留出干净的开关"。

推荐方案（若将来 GO，再实施）：

1. **独立 target + 独立目录**：新增 `Sources/SoCPowerExperimental/` 与 SPM target `SoCPowerExperimental`，只包含 IOReport FFI（dlopen/dlsym）、通道枚举、区间差、聚合、去重规则。`StatusTrioCore` 通过一个公开协议（如计划 B1 的 `SoCPowerSampling`）依赖它，但**核心 target 不出现任何 `IOReport` 符号/字符串**。
2. **条件编译总开关**：实现文件整体包在 `#if SOC_POWER_EXPERIMENT` 内；关闭时该 target 只编译一个返回 `nil` 的空实现。这样 MAS/默认构建的二进制里**根本不含** `IOReport`、`dlopen` 私有路径等字符串（避免静态扫描命中 Guideline 2.5.1）。
3. **构建脚本开关 + 断言**：`scripts/build-app.sh` 增加 `SOC_POWER_EXPERIMENT=0|1`（沿用现有 `UNIVERSAL_BUILD` 的 `case` 校验风格），为 1 时给 `swift build` 传 `-Xswiftc -DSOC_POWER_EXPERIMENT`；`scripts/verify-platform-version.sh` 或新增校验脚本断言：
   - 默认/MAS 产物 `otool -L` 不含 `libIOReport`；
   - `strings` 不含 `IOReport`/`libIOReport`/私有通道名；
   - 只有实验构建允许出现。
4. **禁止把私有库链接进产物**：即使 SDK 有 `libIOReport.tbd`，也**不要** `-lIOReport`（否则 `LC_LOAD_DYLIB` 会写进二进制，App Store 必拒、公证也难看）。只允许运行时 `dlopen("/usr/lib/libIOReport.dylib")`，并且失败即降级。
5. **运行时兜底**：dlopen/符号缺失、订阅失败、窗口内无通道推进（`stale`）、计数器回退（`reset`）→ 一律返回 `nil`，UI 整块隐藏，绝不显示 0 W 或估算值。设置项默认关闭，文案必须写明"非公开接口、部分系统/机型不可用"。
6. **检查脚本**：在 `scripts/check-forbidden-patterns.sh` 增加规则，除 `Sources/SoCPowerExperimental/` 外禁止 `IOReport`/`dlopen` 私有框架字符串，防止误扩散。

---

## 11. GO / NO-GO

### **NO-GO**

拒绝理由（按计划 B2 的门槛逐条对照）：

| 门槛 | 本机实测 | 判定 |
|---|---|---|
| 不运行 sudo / 不弹权限 / 不装 daemon | 满足：无 entitlement、无 root、无弹窗 | ✅ 可行 |
| 能识别通道、比例、单位 | 满足：325 通道、单位 mJ/uJ/nJ 明确 | ✅ 可行 |
| CPU/GPU/ANE/DRAM 细分可用 | **不满足**：CPU/ANE/DRAM 计数器在 macOS 27.2 冻结，仅 GPU 推进 | ❌ |
| SoC 总量可信 | **不满足**：读数只覆盖整机 5–8%，CPU 负载时不变 | ❌ |
| 与 PSTR 方向/量级可比 | 方向不可比（CPU 负载时 PSTR 上升、IOReport 不动） | ❌ |
| 能区分/证明互斥通道 | **不能**（没有可用数据验证重叠） | ❌ |
| 开销可接受 | 满足：setup 54 ms、采样 3 ms、0.75% CPU | ✅ 但无意义 |

结论：**本阶段只提交调查报告，不接入产品 UI**（符合计划 B2 的"出现无法区分重叠通道/无数据 → 仅报告"）。

### 若产品仍坚持"SoC 细分"，只有三条路（均不建议在本期做）

1. **CLPC 计数表逆向**（macmon 路线）：本机 `AppleCLPC` 用户客户端可打开，理论上可读 CPU/GPU/ANE 的 nJ 计数；但需要按芯片+系统版本维护硬编码 ID 表，任何系统更新都可能失效，且必然是私有接口。需单独立项 spike，**不适合作为产品功能**。
2. **等待 Apple 修复/开放**：不可作为交付计划依赖。
3. **只展示 GPU 能耗**：数据本身未校准（Metal 53% 利用率只读 2–11 W），展示会误导，不做。

### 如果将来 GO：接入接口设计要点（草案，勿直接抄）

- 两阶段协议，不用单次 `sample() -> snapshot`：

  ```swift
  protocol SoCPowerSampling: Sendable {
      func begin() throws            // 建立订阅 + 绝对基线（一次性 54 ms，放后台）
      func finish() -> SoCPowerDelta? // 区间差 + 单位换算 + 门控；nil 表示基线/重置/停更
      func cancel()                  // 页面关闭即销毁订阅
  }
  ```

- `SoCPowerDelta` 必须携带 `Dt`、`source`、`coverage`（哪些通道被计入）、`rejectedReason`；UI 只能展示"测量/估算"标签，不显示未知值为 0。
- 聚合必须"先按名字分类、再去重、最后求和"，并把"参与求和的通道清单"写进日志/diagnostics，便于跨机型排查。
- 首样本只建基线；页面打开时异步建立基线，约 2–5 s 后才出第一份数据（不显示 0 W）。
- 失败路径：dlopen 失败、订阅失败、`stale`、`reset`、`coverage` 不足（例如 CPU 通道缺失）→ 隐藏整个细分卡，而不是只隐藏一项。
- 生命周期：只在功率卡展开时持有订阅；关闭即销毁；不引入常驻轮询（遵守 performance 规则）。
- 风险：私有 API 随时失效；不同芯片通道名不同；App Store 需完全编译排除；公证/静态扫描对 `dlopen` 私有框架字符串敏感。

---

## 12. 复现步骤

```bash
cd Tools/ioreport-poc

# 1) 编译（无 sudo、无签名要求）
bash run.sh groups
bash run.sh list --group "Energy Model"

# 2) 单次区间采样（PSTR/电池交叉验证 + 自身开销）
bash run.sh sample --window 5
bash run.sh sample --window 5 --json

# 3) 受控对照批次（空闲 / 8 线程 CPU 满载 / Metal GPU 负载），日志在 /tmp/ioreport-poc
bash run.sh experiments
cat /tmp/ioreport-poc/experiments.jsonl

# 4) 开销
bash run.sh bench --window 6

# 5) 基线/回卷/停更门控的合成用例
bash run.sh selftest
```

关键产物：
- `/tmp/ioreport-poc/ioreport-poc`（ad-hoc，无 entitlement）
- `/tmp/ioreport-poc/experiments.jsonl`（本报告第 4 节原始数据）
- `/tmp/ioreport-poc/em-list.txt`（Energy Model 325 通道清单）
- `/tmp/ioreport-poc/all-channels.txt`（11292 通道全景）

### 测量局限（如实记录）

- 测试时机器**不是静置的**（loadavg 9–13，`BlueStacks`/`WindowServer` 等占用 GPU），绝对值会浮动；因此本报告用"同一时段并列对比 PSTR/电池"和"空闲 vs CPU 满载对照"来下结论，而不是单点读数。
- 无法在本机获得"无背景负载"的基准，也无法获得带 Apple 私有 entitlement 的对照（`powermetrics` 需要 root，且本阶段禁止运行）。
- 未做真实休眠/唤醒（禁止让机器休眠）；该路径仅有逻辑级合成验证。
- 电池 IORegistry 读数更新粒度约 30–60 s，本报告以 SMC `B0AV/B0AC` 为准。

---

## 13. 参考

- `status-trio-battery-details-enhancement-plan.md`（B1–B5、建议执行步骤）
- 仓库：`docs/battery-power-flow.md`、`Sources/StatusTrioCore/Monitoring/SystemPowerReader.swift`、`BatteryDetailsReader.swift`
- [vladkens/macmon](https://github.com/vladkens/macmon)（`src/metrics.rs`、`src/shared.rs`、`src/sources.rs`；macOS 27 冻结说明与 CLPC 路径）
- [matti/power](https://github.com/matti/power)（`docs/SAMPLING-SPEC.md`、`src/samplers/ioreport.rs`、`examples/dump_channels.rs`）
- [exelban/stats](https://github.com/exelban/stats)（`Modules/GPU/reader.swift`、`Modules/CPU/readers.swift`）
- 本机 SDK：`/Applications/Xcode.app/.../MacOSX.sdk/usr/lib/libIOReport.tbd`
