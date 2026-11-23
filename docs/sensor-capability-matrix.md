# 传感器能力矩阵（跨型号温度与背光功耗）

> 基线：`origin/main` @ `1382d64efebd935ef82035337b97b2e7e626ac0b`（2026-11-23）
> 分支：`feat/sensor-capability-matrix`
> 适用范围：macOS 13+，Intel Mac 与 Apple Silicon M1～M6 实际发布 SKU，以及 A18 Pro。

这份文档记录 `SensorCapabilityCatalog` 的依据，不把“Key 能读出数字”当成“物理语义已验证”。代码只对 `measured` / `communityMapped` 的 Key 做常规聚合；`candidate` 只作为候选，缺少实测的型号不会在发布说明里写成“已实机认证”。

## 1. 证据等级

| 等级 | 含义 | 处理方式 |
| --- | --- | --- |
| `measured` | 真实设备在空载/负载对比或回放数据中得到合理读数，并确认了物理位置 | 可作为主路径 |
| `communityMapped` | 多个独立项目（Stats / iSMC / macmon）对同一 Key 语义一致 | 可作为主路径，但保留 fallback |
| `candidate` | 只出现在静态 Key 表里，或只读到过数字，未验证语义 | 只作为候选/兜底，UI 不据此宣称已验证 |
| `unsupported` | 未知芯片或 Key 集合不可用 | 不读取，不猜测 |

同一核心的多个探针在 `SensorTemperatureGroup` 内先求平均，再按 group 求 CPU/GPU 平均；不会把同一物理位置的 A/B/max 探针当成多个核心。

## 2. 各代际与 SKU 的最终策略

| 芯片 / SKU | CPU 温度策略 | GPU 温度策略 | 证据 | 说明 |
| --- | --- | --- | --- | --- |
| Intel | 保留 `TC0C…TCFC`（大小写两组），无核心读数时回退 `TCAD/TC0D/TC0E/TC0F` | `TCGC/TG0D/TGDD` | `communityMapped` | 保持现有行为；不同 GPU 类型独立探测，不假定统一 Key |
| M1 Base | `Tp09/Tp0T/Tp01/Tp05/Tp0D/Tp0H/Tp0L/Tp0P/Tp0X/Tp0b` | `Tg05/Tg0D/Tg0L/Tg0T` | `communityMapped` | Base M1 的 HID 回退保持只在确认 SMC 失败后启用 |
| M1 Pro/Max/Ultra | 同上 | 同上 | `communityMapped` | Ultra die-2 Key 未纳入，避免把另一 die 的探针混入平均 |
| M2 Base/Pro/Max/Ultra | 保留现有 12 个 `Tp*` | `Tg0f/Tg0j` | `candidate` | 现有生产表未改动，避免回归；base 与 Pro/Max 布局差异仍需负载 dump 才能定论 |
| M3 Base（Mac15,12/13） | 保留现有 CPU 表，Mac15,12 已确认 `Te05` 可读 | **12 个 `Tg*`，按六对分组**：`Tg0O/P`、`Tg0C/D`、`Tg0W/X`、`Tg0a/b`、`Tg0i/j`、`Tg0u/v` | `communityMapped`（GPU Key 可读性实测，pair 代表值未负载验证） / `candidate`（CPU） | 原 `Tf14/Tf18/Tf19/Tf1A/Tf24/Tf28/Tf29/Tf2A` 在 Mac15,12 全部 `KEY_INFO_FAILED`，已不再探测；六对中每个 pair 作为一个 GPU 区，避免 12 个探针被当成 12 个核心 |
| M3 Pro/Max/Ultra | 现有 M3 CPU 表 | 优先 `Tf14/Tf18/Tf19/Tf1A/Tf24/Tf28/Tf29/Tf2A`；无读数时回退 iSMC 的 `Tg*` 对 | `communityMapped`（Mac15,9 实测 `Tf04/Tf14`） | 不直接套用 M3 Base；Tf* 仍是工作路径，Tg* 仅作 fallback |
| M4 Base/Pro/Max | 保留现有 12 个 CPU Key | 保留现有 12 个 GPU Key | `candidate` | 不改动已工作的型号；Pro 14 核的 Tp00-scheme 语义仍待负载验证 |
| M5 Base | 4 个 Super 核 `Tp00/Tp04/Tp0C/Tp0G` + 4 个 E 核 `Te04/Te08/Te0C/Te0R` | `Tg04/Tg0G/Tg0K/Tg0m/Tg0p/Tg1A/Tg1g/Tg1s` | `communityMapped`（CPU）/ `candidate`（GPU） | iSMC 的 MacBook Air/Pro 负载显示 `Tp0O…Tp1E` 跟随 GPU 负载，不是 CPU 核心，已从 CPU 平均中移除 |
| M5 Pro/Max | 6 组 Super 三探针（`Tp00…Tp0y`）+ 2 个 P-cluster（`Tm*` 子集） | `Tg08/Tg0C/Tg0O/Tg0R/Tg0U/Tg0X/Tg0a/Tg0d` | `candidate` | `Tp1E…1g` 是 P-cluster 聚合值，不作为 Super 核心；`Tm*` 的 probe→core 关系未解，按 cluster 聚合 |
| M6（2S+4P+6E） | 2 组 Super 对 + 4 组 Performance 对 + 1 个 E-cluster（`Te07/08/09`） | 18 个 `Tg*` 单键槽位 | `candidate` / `communityMapped` | `Te0c/0e/0f/0h/0i`、`Ts00–08` 是 SoC die 探针，不是 E 核，已排除；GPU 是槽位不是 18 个核心 |
| A18 Pro | 2 个 P 三探针 + 4 个 E 三探针 | 4 对 `Tg*` | `communityMapped` / `candidate` | 新增芯片识别；未知 A 系列（A17/A19）不会继承 A18 的映射 |
| 未知芯片 | 空计划 | 空计划 | `unsupported` | 不猜测、不套用邻近型号 |

## 3. 数据来源

- Stats：<https://github.com/exelban/stats>，`Modules/Sensors/values.swift` 的 CPU/GPU Key 表，作为 `communityMapped` 交叉参考。
- iSMC：<https://github.com/dkorunic/iSMC>，`src/temp.txt` 的分组/探针语义与 M3/M5/M6/A18 段；本仓库只根据其事实重新编写实现，未复制 GPL 代码。
- macmon：<https://github.com/vladkens/macmon>，动态能力发现与按需读取思路。
- macos-smc：<https://github.com/sebhildebrandt/macos-smc>，SMC 数据类型与解码交叉参考。
- macpow：<https://github.com/k06a/macpow>，`AppleARMBacklight` 的 `BrightnessMicroAmps` / `backlight-calibration-parameters` 与约 6 V 估算方法。
- 本仓库实测/回放：`docs/research/data/m3-max-macos27/`（Mac15,9）与用户提供的 Mac15,12 M3 Air 诊断数据。

## 4. 尚需真实设备验证的型号与风险

以下型号没有本机实测，只能标记为 `candidate`，发布说明不得写“全型号已验证”：

- M2 Base 与 M2 Pro/Max/Ultra：base 与 Pro/Max 的 `Tp*` 布局不同，现有表未按 SKU 拆分。
- M4 Pro 14 核：`Tp00`-scheme 与 M4 base 的 Tp 表不同。
- M5 Pro/Max：`Tm*` probe→core 未解，当前按两个 P-cluster 聚合；GPU 8 个槽位不代表全部 GPU 分区。
- M6 全系：`Tp*` 的 probe→core 配对来自单个保存的负载运行，仍需更多 SKU 验证。
- A18 Pro：只有 iSMC/静态表依据，没有本机设备。
- Intel 各 GPU 类型：`TCGC/TG0D/TGDD` 只作为独立候选，不保证每个 Intel SKU 都有对应 Key。
- M3 Base CPU 的完整 P-core 布局：Mac15,12 只确认了 `Te05`，未把 iSMC 的 16 个 P 三探针加入主路径。

## 5. 性能与生命周期

- 只在菜单栏/状态面板/详情页实际依赖某项指标时读取；需求消失后由现有 `HardwareMetricsService` 停止循环并释放资源。
- `SensorCapabilityCache` 首次探测有限候选 Key，之后只重读可读 Key；失败 Key 按 30/120/600/1800/3600 秒退避，唤醒或 `HardwareSampler.reset()` 清空负缓存。
- 没有新增常驻 timer、线程、Helper、`sudo` 或生产 `ioreg` 子进程；背光估算只在电池详情页请求 breakdown 时读取 `AppleARMBacklight`，详情页关闭即释放 service/calibration 缓存。
- 同一 refresh 的 SMC 读取次数上限为“可读 Key 数”，不再每个 2 秒 tick 重试全部不可读 Key；回放测试 `testCapabilityCacheStopsProbingMissingKeysOnLaterTicks` 覆盖了这条行为。

## 6. Issue #374 背光功耗回退

优先级：**SMC 实测（PBwo → PDBR → PBLR）→ AppleARMBacklight 估算 → 不可用**。

- M3 Air（Mac15,12）`PDBR` 不存在、`PBLR` 恒为 0：0 不再作为有效背光分支发布，改为尝试 `AppleARMBacklight` 估算。
- 估算值 = `BrightnessMicroAmps.value / max × current-for-max-backlight ÷ 1000 × 6.0 V`；6 V 是 macpow 的明确假设，不是实测电压，UI 以 `≈` 和 “Estimated” 标注。
- 缺少有效电流或校准数据时返回 `nil`，不伪造功耗；估算导致 residual 超出容差时丢弃估算分支，而不是发布异常负 residual。
- `DISP/DISPEXT` 不作为背光功率；它们只代表 SoC 显示控制器。
- 显示器、USB 汇总、逐端口低于 `BatteryPowerFlowState.minimumVisibleWatts`（0.05 W）的 0 分支不绘制。

## 7. 其他相关 SMC Key 审计（本次未改变语义）

| 类别 | Key / 路径 | 结论 |
| --- | --- | --- |
| 风扇 | `FNum`、`F<n>Ac/Mn/Mx/ID`（索引按十六进制字符） | 保持现有行为：`FNum` 必须是 0–9 的整数；RPM 限制 0–30,000；瞬时 0 会二次确认；`F0ID` 只取最长可打印片段。无风扇 `FNum=0` 仍是明确的 fanless。 |
| 电池温度 | `TB0T/TB1T/TB2T` | 保持 `BatteryHealthParser` 的类型解码与独立电池详情路径；系统聚合只读存在的 Key，不重复查询。 |
| 电池功率 | `B0AC`×`B0AV` | 保持 Apple Silicon 小端 mA/mV 专用 ABI 与放电符号处理；只在正向充电时显示“充入电池”。 |
| 系统总功耗 | `PSTR` | 仅用于旧的整机功耗节点；流向图的“系统”仍是 residual，不改为 `PSTR`。 |
| 充电输入 | `PDTR` | 保持 `PDTR` 作为适配器输入；`PSTR` 不替代预算源。 |
| USB 输出 | `DnJV`×`DnJI`，无应答时回退 `PowerOutDetails` | 保持逐口读取与回退；0 W 分支在 UI 隐藏，但底层仍区分“可读 0”“无应答”“不可解码”。 |
| SoC 估算 | `PHPC` | 仍只作诊断，不作为全部 SoC 实测功耗，也不与流向图相加。 |

这些 Key 的读取频率仍由现有 `PowerSamplingService` / `BatteryDetailsController` 的 2 秒需求驱动；本次没有新增常驻定时器。
