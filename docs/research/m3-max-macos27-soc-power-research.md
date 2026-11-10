# M3 Max / macOS 27 SoC 功耗测量研究

研究日期：2026-10-30（Asia/Shanghai）

## 1. 结论先行

**本机短期建议采用 E + A：保留 `PHPC`，将显示明确改称“SoC 功率估算”或“芯片散热功率估算”，并将 AppleCLPC 作为独立诊断和未来 CPU/GPU/ANE 分项来源。后续采用 D：按系统、驱动和实际计数健康状况选择来源。暂不把 CLPC CPU+GPU+ANE 改名为整颗 SoC 功率，也不采用未经验证的 SMC 三轨汇总。流向图已由五分支改为“充入电池（仅充电时）/ 显示器 / USB / 系统”四支路，“系统”是算出来的差额，不再单列 SoC 和“其他”（见 §8.1，本轮已实施；系统文案定为“系统”，不加 PHPC 参考行）。** 本轮只提出方案，未实施产品修改。

- **本机实测**：`PHPC` 对 CPU、GPU 和内存带宽负载均有明显响应。未主动加压基线约 28.65 W，CPU 2/6 线程约 35.59/39.08 W，GPU compute 约 58.84 W。它显然不是只测 CPU 的传感器。
- **上游源码证据**：Asahi SMC hwmon 驱动将 `PHPC` 描述为“an estimate of the heat energy being dissipated by the SoC”。这是 SoC 散热估算的证据，不是 Apple 公开的整颗 SoC 电功率定义，也不能据此确定包含哪些内存、显示和外围电源域。
- **10–20 W 合理吗？** 作为轻负载下的 SoC 相关估算，其量级并不反常；本机只读预采样确实出现约 15–30 W，正式不同阶段也在变化。但本轮没有复现一个干净、稳定的 10–20 W 空闲环境，也没有独立电表，所以不能将用户此前的 10–20 W 认证为准确的整颗 SoC 电功率。
- **AppleCLPC 可用**：普通用户可读取 T6031 的 CPU/GPU/ANE 累计计数，三项都在更新。它解决了传统 Energy Model 冻结后显示假 0 W 的问题；**尚未证明它比 PHPC 更准确，更没有证明其三项之和覆盖完整 SoC**。
- **不再单列“其他”或“SoC”**：原始 `PDTR − PDBR − PHPC` 在本次未充电、无可用 USB 输出读数的条件下最低约 −15.22 W。正残差、新鲜时间戳、一次短连接均不能证明统计边界互斥和同步。建议把 `PHPC` 与“其他”合并为一条“系统（其余，含 SoC）”差额支路，明确标注为估算，保留原始负差额用于诊断，不为闭合而调整读数。

面向用户建议文案：

> SoC 功率估算来自 Mac 的 SMC 芯片相关传感器，会随 CPU、GPU 等负载变化。它并非 Apple 公布的完整芯片电功率测量，可能与 CPU/GPU 分项、整机输入存在覆盖和更新时间差异，因此各项不一定相加。

## 2. 实机、系统与研究状态

| 项目 | 实际检测结果 |
| --- | --- |
| macOS / Build | 27.2 / 26B123（`sw_vers`） |
| 内核 | Darwin 27.2.0，arm64，RELEASE_ARM64_T6031 |
| 机型 / 芯片 | Mac15,9 / Apple M3 Max，16 核（12P + 4E） |
| 内存 | 137438953472 bytes = 128 GiB |
| 内建屏 | Liquid Retina XDR，3456×2234，在线且为主屏 |
| 电源 | AC；电池 80%，`AC attached; not charging` |
| 适配器 | Apple 140W USB-C Power Adapter；登记能力 28000 mV / 4990 mA；不是实时功耗 |
| 虚拟化标记 | `kern.hv_vmm_present = 0` |
| 工具链 | Xcode 27.0 (27A266a)，Apple clang 21，Swift 6.4，macOS 27.0 SDK |
| 研究 worktree | `.worktrees/battery-power-breakdown`，`feat/battery-power-breakdown` |
| 研究起点 HEAD | `364b3c3381a5b44c40b1640e182e687d1e1c3043` |
| fetch 后 origin/main | `4a0409eb448a41de1b43fd66dd9e91917f82f5a3` |
| 与 origin/main 的共同基点 | `7903d044a763b6232c8ed4c513d7890a675ebc47`；没有合并或重置分支 |

未在报告正文抄入机器序列号、Hardware UUID 或 provisioning UDID。采样器保存原始 AppleSmartBattery 字段，研究原始记录可能含适配器标识，不建议未经审阅直接对外发布数据目录。

测试期间已有 Stats.app、Stats SMC Helper、macpow、Activity Monitor，以及 Edge、WindowServer、BlueStacks、DeepSeek Harness 等应用运行。早期还观察到约一核 CPU 的 python 负载。**没有关闭或杀死这些应用**。因此 idle 表示“不施加研究负载”，不表示机器真正静止；不能把阶段均值差当严格受控的因果分解。

## 3. 已阅读的项目实现及问题

审查文件：

- [SystemPowerReader.swift](../../Sources/StatusTrioCore/Monitoring/SystemPowerReader.swift)：一次短连接读固定 SMC 键；`readAt` 是读操作开始时间，不是传感器内部计数时刻。`PHPC` 被存入 `soc`，注释称 chip package/heatpipe power；该名称强于当前已知物理边界。
- [BatteryPowerBreakdown.swift](../../Sources/StatusTrioCore/Monitoring/BatteryPowerBreakdown.swift)：用 `PDTR` 减充电、`PDBR`、`PHPC`、USB；缺失 display/USB 按 0 参与；残差 −0.75…0 W 裁为 0。检查“非负 + 新鲜”不能证明同边界、同硬件时窗或互不覆盖。
- [BatteryDetailsReader.swift](../../Sources/StatusTrioCore/Monitoring/BatteryDetailsReader.swift)：充电用 `max(0, battery.watts)`；若电池在接电状态仍短时向系统补电，负电流被截去，输入边界不再满足简单的输入减充电公式。上一拆分可保留 6 秒，这能减少跳动，但不能增强测量可信度。
- [USBOutputReader.swift](../../Sources/StatusTrioCore/Monitoring/USBOutputReader.swift)：`Watts`/`PDPowermW` 均除以 1000，注释认定“实际输出”。**本次接 USB 扩展坞已实测**：`Watts=2461 mW` 与端口 `Current×AdapterVoltage`（470 mA × 5228 mV = 2457 mW）一致，`FilteredPower=2117 mW`，说明 `Watts` 是实际输出；而 `PDPowermW=15000 mW` 是 5V×3A 的 PD 协商上限/预算，不是实测。原代码用 `Watts`，缺失时回退 `PDPowermW`（本口会虚高约 6 倍）。**本轮已按实测与开源实现移除该兜底**：只取 `Watts`，缺失即跳过该端口，并加了“仅 PDPowermW 不算测量”的测试。开源对照：WhatCable 把 `PDPowermW` 注为 “PD contract negotiated power”，battery-monitor 只读 `Watts` 并明确排除 `PDPowermW`/`FilteredPower`/`Configured*`；macpow 的 `Watts > 0 ? Watts : PDPowermW` 正是被避开的写法。
- [BatteryPowerFlowState.swift](../../Sources/StatusTrioCore/Presentation/Panel/BatteryPowerFlowState.swift)：按统一比例尺呈现独立读数，允许合计不吻合是正确方向；但数据的 `soc`/`other` 名称仍须表达估算与质量。
- [现有功率流向说明](../battery-power-flow.md)：此前“PDBR 只随亮度变化”“PHPC 已包含 DISP/DISPEXT”“各分项同边界”“PSTR 始终是上一 PDTR”应收窄。前三项缺少充分验证；最后一项只在本次接电未充电条件验证，不能推广到电池放电/充电/别的机型。
- [已有 PoC](../../scripts/poc/battery-power-rails-readonly.m)：可复现固定键只读；本轮未使用它的 dim 路径。其表格残差没有充电/USB 校正，只适用于相应实验前提。

**结论：主要问题是测量口径和命名过强，而非已经证明解码算法错误。** 现有短连接不会令 SMC 内部采样同步；软件时间戳相同也不能证明硬件同窗。

## 4. 上游源码与 Issue 证据

完整 SHA、行号、关键原文、Issue 全部评论、PR diff 和证据强度见 [上游证据档案](data/m3-max-macos27/evidence/upstream-evidence.md) 及同目录归档。审阅快照：macmon `39e98aa73e49256e6281b2a228f6ef3499ae3209`；macpow v0.1.19 `696de22d87acb62fbdd306827fb72ea4a375e537`；Stats `032f4a5e4cb9c11bc537c70a9487dfd904f2011d`。

### 4.1 Energy Model 为什么变成假 0 W

传统路径读取累积能量：`P = (E₂ − E₁) × unitScale / (t₂ − t₁)`；mJ/uJ/nJ 分别乘 `10⁻³/10⁻⁶/10⁻⁹` 转成 J。计数不变只能得出“该窗口未观测到计数增量”。当 CPU 实际活动而计数长期不变时应标记 frozen/unavailable，不能当真实 0 W。

[macmon Issue #76](https://github.com/vladkens/macmon/issues/76) 报告 M3 Max/macOS 27 beta 的 `CPU Energy` 冻结，AGX 提供的 GPU 通道仍增长，后续还有 M1 Pro/M3 Pro 等报告和偶发集中补计。其正文关于 powermetrics 的具体推导属于报告者解释，本研究没有独立确认 Apple 内部算法。

[Stats Issue #3621](https://github.com/exelban/stats/issues/3621) 在检索时仍 open；已读正文与 14 条评论，含 macOS 27.2 beta (26B5086k) 基础 M3 的冻结报告，没有可泛化的官方修复。本机 27.2 (26B123) 也实际复现冻结，见下一节。

macmon 源码/讨论将变化关联到 `com.apple.private.pmgr.nrg.reporting` 私有 entitlement；sudo 不会自动授予该权限。平台签名等变量尚未完全排除，因此将它记为上游解释，未宣称已通过本机签名实验证明唯一原因。**本轮没有提权、重签系统工具或伪造 entitlement**。

[macpow](https://github.com/k06a/macpow) 的 SoC 是多个 Energy Model 分项相加；CPU/ANE/DRAM/fabric 冻结后只剩 GPU 就可能小于 1 W。[PR #21](https://github.com/k06a/macpow/pull/21) 只增加冻结警告和文档，不是新功率源，检索时未合并。不能把这个“只剩 GPU 的合计”与 PHPC 作等范围比较。

### 4.2 macmon AppleCLPC 路径

[clpc.rs](https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/clpc.rs#L53) 依据 CLPC driver bundle 和 macOS 版本选 report ID。T6031 / `com.apple.driver.AppleT6031CLPC`：

| 名称（由应用声明） | 完整 report ID |
| --- | --- |
| CPU Energy | `0x00000010d81e0084` |
| GPU Energy | `0x000000191085f98b` |
| ANE | `0x00000018313a3be1` |

macmon v0.9.0（2026-10-07，`7df49f55d9a1b9072e31fc8ba991abda84593563`）已含这套映射。它并不是读取名为“CPU Power”的公开属性；程序构造 IOReport descriptor（名称、格式、nJ 单位等）并订阅隐藏 report ID，取累计值差除真实秒数。

**重要限制**：[find_clpc.rs](https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/app/find_clpc.rs#L219) 明写 `nJ is a hypothesis until matched to independent energy measurements.`；[发现方法](https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/docs/clpc-discovery.md#L60) 说明生产者追踪不证明完整物理覆盖。因此 `IOReportChannelGetUnitLabel` 对人工 descriptor 返回 nJ，不是系统独立证实单位。本次使用这套假设换算，并通过动态响应和另一 GPU 通道检查量级；没有完成绝对校准。

AppleCLPC registry 的 `~pkg-power-split-cpu/gpu/ane-fraction` 为 29491/29491/6553。若按 Q16 看约 45%/45%/10%，但其名字和固定值不能证明是实时功率，**没有把它们拿来分摊 PHPC**。

## 5. 只读传感器能力与更新时间

完整原始字节、返回码、每通道计数/单位、成功和失败矩阵见 [能力报告](data/m3-max-macos27/evidence/sensor-capabilities.md)。采样器源代码与构建说明见 [研究工具](tools/m3-max-macos27/README.md)。全部普通用户执行，没有 root、SMC 写入、SMC 键表扫描、权限申请或安装。

### 5.1 SMC

| 键 | 结果/原始样例 | 本机可确认内容 / 边界 |
| --- | --- | --- |
| PHPC | `flt ` 4B，`9f652342` → 40.8492 W（按功率键惯例） | 约 1 Hz 更新；SoC 散热估算有 Asahi 源码支持；完整电边界 UNKNOWN |
| PZC0 | `flt ` 4B，`39fdf441` → 30.6236 | 约 1 Hz；CPU/GPU/内存场景变化，具体域 UNKNOWN |
| PHPS | `flt ` 4B，`a34cf541` → 30.6624 | 约 1 Hz；与 PZC0 接近，不能视为独立不重叠域 |
| PSTR | `flt ` 4B，`b16d4742` → 49.8571 | 本次接电未充电条件下等于前一 SMC tick 的 PDTR |
| PDTR | `flt ` 4B，`e1944a42` → 50.6454 | 输入相关功率，随负载变化；墙插 AC 边界未校准 |
| PDBR | `flt ` 4B，`e093de40` → 6.9556 W | 正式场景均值约 6.6–7.2 W；原始 hex/值见能力报告和 JSONL；亮度阶跃本次 NOT TESTED |
| PP0b | `flt ` 4B，可读 | 约 1 Hz；小读数，基础 M3 的 CPU 轨道映射不能迁移 |
| PPbb | **NOT AVAILABLE** | info IO return `0x00000000`，SMC result 132 / `0x84`，没有可用数据 |
| PP7b | `flt ` 4B，可读，部分样本返回 0 | 键含义 UNKNOWN；返回 0 不证明物理功率为 0 |
| Te05 / Tf04 / Tf14 | `flt ` 4B，°C 按 Stats M3 映射 | ECPU1/PCPU1/GPU1 的社区映射，非全芯片最高温；随负载变化 |

10 Hz 连读 25 秒，PHPC/PZC0/PHPS/PSTR/PDTR/PDBR 的数值变化中位间隔约 1 秒；PP0b/PP7b 也是约 1 秒但相位比前者偏移约 0.5 秒。软件以 10 Hz 读取不会得到 10 Hz 的新硬件数据。**值变化间隔只给出观察到的刷新节奏，不等于内部计数器精确采样周期。**

在 10 Hz 窗口，`PSTR[t] == PDTR[t−10 samples]` 240/240 相等；8 个正式场景也表现为约 1 秒延迟。只能确认这次接电未充电状态的行为；可能是同源缓存/转发等，无法据此证明硬件只有一条测量。工程上不能拿 PSTR 与 PDTR 当独立总功率互校。

### 5.2 IOReport / AppleCLPC / 电池属性

| 来源 | 单位/原始计数例 | 更新 / 可用性 |
| --- | --- | --- |
| IOReport 原生全量枚举 | 208 组、11282 descriptor（另次 11285） | 普通用户成功；数量可随驱动状态变化 |
| Energy Model CPU Energy | 原生 mJ；640211452 在窗口首尾相同 | **frozen，不能当 0 W** |
| Energy Model ANE0 / DRAM0 / AMCC0 / DISP0 / DISPEXT0 等 | 原生 mJ；逐通道原始计数见归档 | 60 秒 325 条 Energy Model 中 324 条不变；冻结/不活动需结合负载判断，不能全部断言真实零功率 |
| Energy Model GPU Energy | 原生 nJ；AGX 来源 | 唯一仍增长的原生 Energy Model 通道；60 秒约 3.967 W |
| CLPC CPU/GPU/ANE | 人工声明 nJ；64 位累计值另存 decimal 字符串 | 三项均更新；60 秒约 5.134/3.969/0.186 W；ANE 18/60 间隔增长，不是全窗口冻结 |
| AppleCLPC IOServiceOpen(type 0) | 返回 `0x00000000` | 普通用户成功；未调用未知 external selector，后者 **NOT TESTED** |
| AppleSmartBattery PowerTelemetryData | 原始整数/累加器均保存 | 60 秒仅两个快照，另段 29 秒无变化；不适合快速功率流 |
| SystemPowerIn / SystemLoad | 逐值相等；V×I/1000 与它吻合约 0.02% | 支持 mV/mA/mW 量级的内部一致性；不是独立校准。与 PDTR 比值随不同刷新窗变化，边界仍 UNKNOWN |
| AdapterEfficiencyLoss / WallEnergyEstimate | 可读 | 单位、能量/功率、时间窗和转换损耗边界 **UNKNOWN** |
| PowerOutDetails | 接扩展坞实测：`Watts=2461`、`PDPowermW=15000`、`FilteredPower=2117`、`Current=470`、`AdapterVoltage=5228`（mW/mA/mV） | 无附件时 **NOT AVAILABLE**（键不存在）；有附件时可用，`Watts≈V×I` 为实际输出，`PDPowermW` 为 PD 预算；5 秒内逐值不变，刷新慢于 1 Hz |

默认负载采样器仅订阅必要的 17 个通道（14 原生 + 3 CLPC），1 Hz 自身 CPU 开销约 0.76% 单核、RSS 24.8 MB，调度抖动标准差约 1.7 ms；早期全 Energy Model 10 Hz 探测约 11.2% 单核，不适合产品持续运行。本轮工具均有结束时间和退出路径，没有接入应用后台。

## 6. 受控负载方法与对照数据

原始记录位于 [数据目录说明](data/m3-max-macos27/manifest.md)，8 个连续 JSONL，各自有 `ts_mono`、`ts_wall`、原始 SMC hex/解码、IOReport/CLPC 原始计数与差分、温度、thermalState、电池属性。另有进程快照、GPU 利用率、阶段边界和控制日志。使用实际单调时间间隔，不以名义“1 秒”代替。

CPU 使用 C 忙循环（2/6 线程）；GPU 使用 Metal runtime `makeLibrary(source:)`，不安装软件；混合为 4 CPU 线程 + GPU；内存为 4×256 MiB（总 1 GiB）流式读写。每个负载有截止时间、SIGTERM 路径、thermalState serious/critical 中止看门狗；每阶段含额外 5 秒停载尾部，阶段间 10 秒缓冲。额外负载总时长约 255 秒。没有因热状态中止，最高 fair；研究压力进程均已结束。

下表为活动窗口均值；CPU/GPU/ANE 用窗口首末累计计数差 / 实际秒数；PHPC 等为对应窗口样本均值。idle/recovery 为无研究负载窗口。CPU/GPU 分量求和只用于比较，**不是已验证的全 SoC 电功率**。完整 mean/median/min/max/n 见 [统计表](data/m3-max-macos27/full-statistics.md)，窗口定义和延迟诊断见 [负载分析](data/m3-max-macos27/load-analysis.md) 与 [诊断](data/m3-max-macos27/diagnostics.md)。负载窗口分别取前 45/60/40/55/55 行；无研究负载的基线和恢复使用全部 35/55/55 行。

| 场景 / 持续 | PHPC W | CLPC CPU W | CLPC GPU W | CLPC ANE W | 原生 EM GPU W | PDTR W | PDBR W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 未加压基线 30s + 尾采样 | 28.65 | 7.25 | 3.96 | 0.059 | 4.05 | 45.30 | 7.10 |
| CPU 2 线程 45s | 35.59 | 11.73 | 4.43 | 0.013 | 4.65 | 53.45 | 6.79 |
| CPU 6 线程 60s | 39.08 | 15.51 | 4.34 | 0.000* | 4.62 | 57.62 | 7.10 |
| 内存带宽 4×256MiB 40s | 57.57 | 25.15 | 3.35 | 0.003 | 3.14 | 80.54 | 7.19 |
| 恢复空闲 50s + 尾采样 | 33.06 | 8.47 | 4.98 | 0.013 | 5.15 | 50.27 | 7.08 |
| GPU compute 55s | 58.84 | 8.88 | 24.66 | 0.008 | 25.59 | 78.76 | 7.18 |
| CPU 4 线程 + GPU 55s | 51.10 | 10.59 | 18.77 | 0.008 | 19.20 | 72.15 | 6.64 |
| 最后恢复 50s + 尾采样（55行） | 25.56 | 5.33 | 4.28 | 0.016 | 2.73 | 39.00 | 7.03 |

\* ANE 在这个窗口无可观测增量，不能据此认证 ANE 实际 0 W；其他窗口计数有增长。没有专门 ANE 负载。

GPU compute 平均 Device Utilization 约 89.3%，91.4% 样本 ≥90%；基线本已约 67.3%。混合阶段功率低于 GPU 单项阶段不代表负载相加后节能：调度、频率、功率管理、背景工作和温度条件不同，没有做相同频率/利用率的严格控制。

### 6.1 CPU/GPU 对 PHPC 的影响与响应延迟（Q1）

- CPU 2/6 线程 PHPC 相对初始基线约 +6.94/+10.43 W，CLPC CPU 由 7.25 W 增至 11.73/15.51 W。**支持 PHPC 响应 CPU 负载**。
- GPU 场景 PHPC 约 +30.19 W，CLPC GPU 约 +20.70 W，CPU 仅小幅变化。**支持 PHPC 也响应 GPU 活动，否定将它命名为 CPU-only 的做法**。不能由此证明覆盖全部 GPU 电源域或精确覆盖比例。
- 内存场景 PHPC−CLPC 三项和约 29.08 W，高于初始基线差值 17.38 W；但 CPU 本身也大幅升高，负载与频率不匹配。**不能据此把多出的约 11.7 W 命名为 DRAM**，更不能确定是 DRAM 芯片、内存控制器、供电损耗还是模型偏差。
- 停载后的首个/数个 1 Hz 样本中可见功率明显下降，温度仍变化。**没有观察到必须等芯片冷却数十秒后 PHPC 才下降的行为**；但 1 Hz 不足以证明“亚秒完成”，也没有拟合热时间常数。
- 温度峰值与 thermalState 不等价：内存阶段 PCPU 候选温度到约 80.1°C 时 thermalState 仍 nominal，之后才到 fair。thermalState 不能代替温度记录。
- **ANE、DRAM、内存控制器、显示控制器是否完整包含：UNKNOWN**。没有隔离 ANE/显示控制器负载，也没有独立 DRAM 轨道校准。

### 6.2 AppleCLPC 与 PHPC 的覆盖差异（Q2）

PHPC 与 CLPC 三项和存在明显差额：基线约 17.38 W、CPU 中载约 19.23 W、GPU 约 25.29 W、内存约 29.08 W。差额可能涉及不同覆盖、时间窗、热估算模型和电源损耗，**本研究不能分配其组成**。数值较小不等于更准确，较大也不等于覆盖完整。

原生 AGX GPU Energy 与 CLPC GPU 在 GPU/混合场景逐秒相关约 r=0.987/0.993，窗口平均 CLPC 低约 3.6%/1.8%，支持 nJ 换算量级；低活动恢复段存在很大相对差异，部分窗口约 56%。两通道可能共享底层估计，未证明是独立物理测量，因此这不是电功率绝对校准。诊断附件保留全部配对数据，不能据高负载接近便让二者任意互换。

`PP0b`、`PP7b` 读到值不代表找到了 M3 Max 的 CPU/GPU 分轨；`PPbb` 不可读，因此基础 M3 社区提出的三轨合计在本机既缺项又无语义证明。`PZC0`/`PHPS` 相近且随负载改变，不能当成互斥分项再加到 PHPC。**绝不计算 PHPC + CLPC CPU/GPU/ANE。**

### 6.3 亮度与 PDBR

内建屏在线。用户同时禁止修改系统设置，本轮没有主动调亮度；亮度阶跃场景标 **NOT TESTED**。公开 IODisplay 路径探测返回无服务；已有 PoC 可通过私有 DisplayServices 只读取得约 0.97，但负载采样器没有记录该属性。

在正式实验前单独只读预采样中，PoC 显示亮度一直为四舍五入后的 0.97，而 PDBR 在约 3.44–6.46 W 变化。这只能说明“用户亮度设置不变仍可能有 PDBR 变化”，原因可能包括显示内容、分区背光/系统调节等，**具体归因未验证**。不能使用此前文档的亮度实验替代本轮，也不能说它与 SoC 完全独立。

### 6.4 其余候选 SMC 轨道（同窗口均值，单位按功率键惯例为 W）

| 场景 | PZC0 | PHPS | PP0b | PP7b |
| --- | ---: | ---: | ---: | ---: |
| 基线 | 25.427 | 25.431 | 0.024 | 0.528 |
| CPU 2线程 | 31.589 | 31.593 | 0.023 | 0.660 |
| CPU 6线程 | 34.348 | 34.349 | 0.032 | 0.610 |
| 内存 | 58.440 | 58.429 | 0.026 | 0.985 |
| 恢复 | 28.740 | 28.742 | 0.025 | 0.532 |
| GPU | 49.494 | 49.491 | 0.028 | 0.554 |
| 混合 | 40.263 | 40.263 | 0.026 | 0.282 |
| 最后恢复 | 20.610 | 20.605 | 0.024 | 0.323 |

PZC0/PHPS 均值接近，但逐样本最大差约 0.51 W；它们与 PHPC 的大小关系在内存场景发生变化，不能互相替代。PP0b 在 CPU 加载后并未呈现可支持“完整 CPU 功率”的量级，不能用基础 M3 映射解释本机。

## 7. “其他”能否可靠计算（Q4）

**当前不能将残差认证为其他部件的实际功率。**

1. **PDTR vs PSTR**：本次接电未充电数据逐值表现为延迟一 SMC tick；不能把两者当独立总量。充电、放电、电池补电和别的机型 **NOT TESTED**。
2. **适配器边界**：PDTR 的输入相关语义有第三方源码支持，但没有墙插电表、USB-C 功率计或板级测量，本轮无法确认墙端 AC、整流后 DC、内部转换损耗究竟包含哪些。AdapterDetails 的 140 W 只是额定/协商能力。不能把未知的 AdapterEfficiencyLoss 直接加减。
3. **PHPC 边界**：SoC 散热估算与输入电功率不保证同域、同窗、同标定；所以不能仅因残差为正就批准从 PDTR 直接扣除。
4. **电池方向**：本次 registry 报未充电，电流为 0 或极小；正式工具没有读取 B0AC/B0AV，故不能逐帧复现应用的充电支路。下文残差是“充电近似 0、USB 假设 0”的条件诊断，不能声称完整预算已实测。
5. **USB/显示重叠**：本次接扩展坞实测 `Watts` 为实际输出（2.461 W，≈V×I），`PDPowermW` 为 PD 预算（15 W）；但仍未证明 USB 输出是否已包含在 PDTR 的输入边界内、是否与 `PHPC`/显示控制器重叠。无附件时缺失不证明实际输出为 0。PDBR 与显示控制器是不同候选域，但与 PHPC 的覆盖互斥尚未证明。传统 DISP/DISPEXT 冻结，本轮无法据其差分验证重叠。
6. **时窗**：SMC 各组相位不同，IOReport 是能量差分窗口，电池 registry 慢快照不等于瞬时输入；同一连接与 `Date()` 不会令它们同步。

按不裁剪的原始 `PDTR − PDBR − PHPC`，初始基线最低 −10.10 W，CPU 中载最低 −6.21 W，最后恢复最低 −15.22 W。最后恢复 55 行中 10 行为负。即使大部分均值为正，也不能认证剩余读数为“其他部件”。现实现 −0.75…0 W 按零的容差仅是 UI 策略，不能作为物理校准；后续不应为使图相加而修改原始值。

建议：有完整、经验证的电气边界前，隐藏“其他”；若产品一定展示，叫“未分配差额（估算）”，不作为实体部件流向，不把未知字段默认为已测零，不用裁剪后的值宣称能量守恒。分项图可作为非守恒的独立读数呈现，适配器→系统/电池仍保留不确定性说明。

## 8. A–E 方案评估与推荐（Q3）

| 方案 | 当前证据/准确性 | 权限与兼容性 | 性能/维护/Mac App Store |
| --- | --- | --- | --- |
| A：PHPC 标 SoC 估算 | 本机可用、CPU/GPU 响应已测；热估算、完整电边界未知 | 当前普通用户可读；不能保证所有芯片/系统有键 | 固定少量键开销低；私有 SMC 协议需维护，MAS 可接受性未认证 |
| B：CLPC CPU+GPU+ANE | 动态计数可用；三项覆盖与 nJ 尚非独立校准，不能直接叫全 SoC | 本机无需 root/entitlement；依赖 OS/驱动精确 ID，未知型号不可猜 | 少量订阅约 0.76% 单核（研究工具）；私有 IOReport/隐藏描述符带维护和审核风险 |
| C：SMC 分轨汇总 | M3 Max 映射不足、PPbb 不可用、不重叠未证，当前不推荐 | 不能移植基础 M3 映射 | 表面实现简单但跨机型维护高；MAS 风险仍在 |
| D：按版本/芯片选源 | 长期合理，但必须叠加运行时健康检查 | 不能仅判断“macOS ≥27”，需 driver/build 能力与未知回退 | 白名单、冻结/回绕/补计处理成本较高；需独立兼容矩阵 |
| E：PHPC + 独立诊断 | 当前最稳妥：保留连续估算，收集CLPC差异，不混合求和 | 不新增权限、Helper、持续后台采样 | 诊断只在明确开启的面板/有界会话内运行，有停止路径 |

**推荐：短期 E+A，后续 D；B 用于明确命名的“CPU/GPU/ANE 计算子系统估算”，与 PHPC 分开；C 暂缓。§8.1 的四支路模型已实施：删掉 `PHPC` 支路与 `其他` 支路，差额并入“系统”。** 如果产品必须承诺“整颗 SoC 实际电功率”，当前没有满足证据要求的数据源，应显示不可用而不是选一个看起来接近的和。

Mac App Store 方面，普通用户可执行不等于公开 API 或审核允许。SMC 键协议、IOReport 私有符号、CLPC 隐藏 report ID 均无公开稳定契约；本轮没有沙盒签名、App Review 或商店分发验证，不能承诺 MAS 可行。建议将商店构建使用的功率能力作为单独合规决策，必要时禁用这些细分；**不要申请/伪造 Apple 私有 entitlement，不加 helper 绕过**。

### 8.1 已实施的流向图分支模型（四支路）

把原来的“SoC + 其他”两条不完整分支合并成一条差额分支，右侧最多四条：

| 支路 | 来源 / 计算 | 何时显示 | 性质 |
| --- | --- | --- | --- |
| 充入电池 | `B0AC × B0AV`（正向电流），或现有电池采样 | 仅电池在充电（正向功率）时 | 实测（注意方向） |
| 显示器 | SMC `PDBR` | 键存在时 | 实测背光直流功率；不含外接屏与显示控制器 |
| USB | `PowerOutDetails` 的 `Watts`（实测≈V×I 实际输出；不要用 `PDPowermW`，它是 PD 预算） | 有外设且字段可用时 | 实测；多口/高功率设备与刷新时延未覆盖，缺失即隐藏 |
| 系统（其余，含 SoC） | `PDTR − 充入电池 − 显示器 − USB` | 上式可算且结果合理时 | **差额/估算**，不是单一传感器 |

规则：

1. **“系统”永远由差额算出，不读 `PSTR`**（本机 PSTR 只是延迟一个 SMC tick 的 PDTR）；图上写“系统（其余，含 SoC）”，不写“SoC 功率”。
2. 左端仍是 `PDTR`（适配器直流输入相关功率）。表达式按定义闭合，但这是“定义闭合”，不是“独立测得”；面板说明要写明各支路为估算、可能含转换损耗与未单独测量的负载。
3. **负差额处理**：差额 < −0.75 W 视为传感器相位/刷新不一致，沿用上一帧一致的拆分最多一个刷新周期（约 1–2 秒），仍不一致则本次不发布细分、回落到“输入 → 充入电池 + 系统”的二支路；不得把负数裁成 0 当作正常值。
4. **未知不当零**：显示器/ USB 缺失时只是不显示该支路，不得以 0 参与“系统”计算并对外宣称；若要算“系统”，需说明当前缺哪些支路。
5. **充电方向**：电池向系统补电（负电流）时不能用 `max(0, …)` 截断；此时电池不是“充入电池”支路，`PDTR` 可能为 0，画面应切到“电池 → 系统”的放电形态。
6. 可选：在图下加一行“参考：SoC 散热估算 `PHPC` xW”，明确它不参与合流、不可与支路相加。

## 9. 代码整改 Plan（分支模型已实施，其余待办）

1. **改分支模型（已完成）**：`BatteryPowerBreakdown` 删掉 `soc`/`other`，改为 `display?`/`usb?`/`system`（差额）；`system = input − charging − display − usb`。`BatteryPowerFlowState` 删除 `.soc`/`.other` kind，视图统一用 `.system`；文案定为“系统”。
2. **差额质量规则（已完成）**：差额 < −0.75 W 时沿用上一帧一致拆分 ≤1 个刷新周期（现有 6 秒保留），仍负则不发布细分并回退两支路；保留原始差额（含负值）到诊断，不裁剪、不为闭合改原始读数。
3. **方向与缺失**：正确处理电池负电流（补电/放电）与 `PDTR=0` 的放电形态；`PDBR`/USB 缺失只隐藏支路并说明，不按 0 计入“系统”。USB 已确认 `Watts` 为实测、`PDPowermW` 为协商预算，并已删除兜底；后续补多口/高功率与非 PD 设备验证。
4. **命名与质量状态**：`PHPC` 若出现在界面，只能标“SoC 功率估算/散热估算”，数据结构区分 available/unsupported/frozen/unknown，缺失不填 0；保留 raw 与显示值。
5. **CLPC 只做独立诊断**：driver bundle + OS/build 映射来自可追溯资料，未知映射回退；健康检查计数增长/回绕/批量补计/异常跃变；CPU/GPU/ANE 与 PHPC 独立呈现，绝不相加，也不并入“系统”差额。
6. **生命周期与性能**：只在详情面板或用户发起的限时诊断中订阅；关闭时取消并释放；只订阅必要报告，不做全量轮询/SMC 扫描；测应用实际开销。
7. **验证后再实施**：补 macOS 13 回退、其他芯片/OS、充电/放电/电池补电、ANE隔离、显示控制器/亮度、外接USB、外部功率计校准矩阵；为差额为正/为负/缺支路/放电四类情形加单元测试与快照测试。按仓库规则为正式状态/生命周期修改运行 full；本轮只运行 docs profile，不代表功能或发布验证。

可选人工后续验证（本轮不执行）：在用户自行选择的安静时段停止重负载应用，再重复同样脚本；用外置 USB-C/墙插功率计同步记录；自行运行已有权限允许的 Apple 工具作为附加观测。即使使用管理员版工具，也不能假定它会刷新受 entitlement 约束的 Energy Model。无需交出管理员密码。

## 10. 交付物、复现与未验证项

- [原始实验与控制清单](data/m3-max-macos27/manifest.md)：8 场景说明、温度/thermalState、GPU 利用率、阶段边界、后台应用快照与哈希。逐秒原始 JSONL（约 11 MB）不随仓库提交，保留在本机同一目录（`.gitignore` 已排除）。
- [GPU 通道配对 CSV](data/m3-max-macos27/gpu-crosscheck.csv)。
- [传感器能力报告](data/m3-max-macos27/evidence/sensor-capabilities.md)、[上游证据档案](data/m3-max-macos27/evidence/upstream-evidence.md)。
- [只读采样器源码](tools/m3-max-macos27/power-sampler.m)、[构建及使用](tools/m3-max-macos27/README.md)。源代码不属于任何应用 target。
- [探测原始证据归档](data/m3-max-macos27/evidence/harness-evidence.tar.gz)：含 10Hz tick、60s freeze、30s idle、全量 inventory、逐通道矩阵及构建说明，SHA256 `1758a3c3044711fbf5e401f34f99e6a47b10e621d8f7789c3fb72eea8a577200`。
- [上游原始证据归档](data/m3-max-macos27/evidence/upstream-evidence.tar.gz)：Issue/PR JSON、关键源文件和版本资料，SHA256 `00e7043888d62261ae0c5ff55b39bf7b7748d584f07d5cad538443e4ee732f15`。

复现示例（有界，普通用户）：

```sh
cd docs/research/tools/m3-max-macos27
make
./power-sampler --hz 1 --seconds 30 --label idle --out /tmp/power-idle.jsonl
```

不要把全量枚举或压力生成器放入应用后台。分析应使用 raw_count_decimal 和实际 ts_mono；JSON 数字经过 JavaScript 时需避免 53 位整数精度损失。

**NOT TESTED / UNKNOWN 总表**：全 SoC 电气校准；PHPC 对 ANE/DRAM/内存控制器/显示控制器的完整覆盖；CLPC绝对单位与完整边界；基础 M3 轨道到 Max 的迁移；亮度阶跃；多口/高功率 USB 设备与 USB 刷新时延（本次仅一个约 2.46 W 的扩展坞）；适配器墙端损耗边界；有充电/放电/电池补电场景；Ventura/其他机型；沙盒与 MAS 审核；风扇/卡顿的量化观察；亚秒响应时间。没有用未知值补齐任何测试。

## 11. 最终验证与善后

- `bash scripts/verify-local.sh docs` **PASS（exit 0）**，HEAD `364b3c3381a5b44c40b1640e182e687d1e1c3043`；包括 shell/禁止模式、所选本地化测试和 workflow policy。完整日志见 [docs-verification.log](data/m3-max-macos27/evidence/docs-verification.log)。这是文档范围检查，不代表完整测试、功能运行、签名、发布或 MAS 验证。
- 主报告本地链接均存在；8 个原始 JSONL 共 425 行均能解析且单调时间严格递增。已独立重算阶段功率和 raw hex 样例。最后恢复期按完整 55 行统计，修正了最初文件仍在写入时生成的临时分析。
- 用户复核后追加了两项正式改动：① `USBOutputReader` 去掉 `PDPowermW` 兜底、只取 `Watts`；② 功率流向图由五分支改为四支路（`BatteryPowerBreakdown`/`BatteryDetailsReader`/`SystemPowerReader`/`PanelDetailMapper`/`BatteryPowerFlowState`/`BatteryPowerFlowView`/`LocalizationKey`/12 个语言文案（en、zh-Hans、zh-Hant、de、es、fr、it、ja、ko、pt-BR、ru、ar）/`docs/battery-power-flow.md`/两个测试文件）。`PHPC` 不再读取，也不再出现在流向图。
- 范围检查：`bash scripts/test.sh 'Battery|SystemPowerReader'` **PASS（exit 0，245 tests）**；`bash scripts/verify-local.sh quick 'Battery|SystemPowerReader'` **PASS（exit 0，172 tests）**；本地化改动后 `bash scripts/verify-local.sh docs` **PASS（exit 0）**。未创建提交或 PR。
- `pgrep` 确认研究 cpuload/gpuload/memload/power-sampler 均无残留；电池仍 AC attached、80%、未充电。亮度没有被本轮修改；已有应用保持运行。
- [负载生成器与分析源码包](tools/m3-max-macos27/lab-tools.tar.gz) 保留 Makefile、runtime Metal shader、CPU/内存生成器、编排和分析脚本，无可执行二进制。编排脚本含本次绝对路径，异机复现前应调整输出目录；先看包内 README，勿当常驻任务运行。

**最终判断：本机可继续用 PHPC 表达“SoC 功率估算”，10–20 W 可解释为轻负载时芯片相关散热估算的合理量级，但不能称为已验证的整颗 SoC 电功率。CLPC 已实测可用，适合补充 CPU/GPU/ANE 分项诊断；在范围和校准完成前，不能用其和替代全 SoC，也不能与 PHPC 叠加。“其他”目前缺少可靠测量依据。**
