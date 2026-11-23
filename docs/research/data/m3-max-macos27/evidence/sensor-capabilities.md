# 只读传感器能力矩阵 — Mac15,9 / M3 Max / macOS 27.2 (26B123)

研究工具能力报告。除特别注明外，所有数字都是本机实测；未测到的写 **NOT TESTED**，不可用的写 **NOT AVAILABLE**，不用推测值填充。

- 采集时间：2026-10-30 22:40–23:00 (+08:00)
- 硬件/系统：Mac15,9，Apple M3 Max，16 核（12P+4E），128GB；Darwin 27.2.0；内建 Liquid Retina XDR 在线，亮度约 0.97
- 电源：AC 供电，电池 80%，`AC attached; not charging`；适配器 `140W USB-C Power Adapter`（AdapterDetails: 28000 mV / 4990 mA / Watts 140）
- 工具链：Xcode 27，Apple clang 21.0.0，SDK `MacOSX27.0.sdk`
- 全程普通用户权限，**未使用 sudo/root**；未写 SMC、未枚举 SMC 键表、未安装、未申请隐私权限、未新增常驻服务、未修改仓库文件（`git status --porcelain` 为空）

## 1. 结论摘要

| 能力 | 状态 | 关键证据 |
| --- | --- | --- |
| SMC 固定键读取（8 个功率键） | **SUCCESS** | 全部 `flt `/4B；样本见 §2 |
| SMC `PPbb` | **NOT AVAILABLE** | info 命令返回 SMC result=132 (0x84)，未读到数据 |
| SMC 固定温度键 3 个 | **SUCCESS** | Stats M3 映射；`Te05/Tf04/Tf14` 均 `flt`/4B |
| IOReport 原生全通道枚举 | **SUCCESS（无特权）** | 208 组、11,282 descriptor（另一次 11,285） |
| 原生 `Energy Model` CPU/ANE/DRAM/DISP 功率 | **NOT AVAILABLE（冻结）** | 60 s 内计数完全不变；不是 0 W |
| 原生 `Energy Model` GPU Energy | **SUCCESS（仍更新）** | nJ，60 s 内 +238,013,828,558 → 3.967 W |
| AppleCLPC IOReport 计数（CPU/GPU/ANE） | **SUCCESS（普通用户）** | 显式 report ID 订阅成功；nJ 累计计数 |
| `IOServiceOpen("AppleCLPC", type=0)` | **SUCCESS** | `kIOReturnSuccess (0x00000000)` |
| CLPC 外部 user-client selector 统计 | **NOT TESTED** | 未调用，避免未知风险 |
| `PowerTelemetryData` 原始字段 | **SUCCESS（读取）**，语义/单位 **NOT CONFIRMED** | 字段齐全；更新极慢，见 §5 |
| `PowerOutDetails` | **NOT AVAILABLE** | 无配件时不存在 |
| 独立功率校准/外部功率计 | **NOT AVAILABLE** | 无设备，未做 |

## 2. A. SMC

### 2.1 方法

使用 IOKit `AppleSMC` 用户客户端，selector 2，命令 **9（读 key info）** 与 **5（读 bytes）**；从不发送写命令 6，不枚举键表。协议与参考 PoC 一致：`scripts/poc/battery-power-rails-readonly.m:33-56`。固定 12 个键：

- 功率键：`PHPC`、`PZC0`、`PHPS`、`PSTR`、`PDTR`、`PDBR`、`PP0b`、`PPbb`、`PP7b`
- 温度键（按 Stats M3 表固定选 3 个代表）：`Te05`、`Tf04`、`Tf14`

温度为 Lead 要求新增；来源与验证见 §2.4。

### 2.2 实测键表（`sample-idle.jsonl` 第 1 行，2026-10-30T14:57Z 左右）

| key | type | size | raw hex | 解码值 | 推断单位 | 读取结果 |
| --- | --- | --- | --- | --- | --- | --- |
| PHPC | `flt ` | 4 | `9f652342` | 40.849 | W | ok |
| PZC0 | `flt ` | 4 | `39fdf441` | 30.624 | W | ok |
| PHPS | `flt ` | 4 | `a34cf541` | 30.662 | W | ok |
| PSTR | `flt ` | 4 | `b16d4742` | 49.857 | W | ok |
| PDTR | `flt ` | 4 | `e1944a42` | 50.645 | W | ok |
| PDBR | `flt ` | 4 | `e093de40` | 6.9556 | W | ok |
| PP0b | `flt ` | 4 | `a95ba93c` | 0.02067 | W（语义未证） | ok |
| PPbb | — | — | — | — | — | **NOT AVAILABLE**：info result=132 (0x84)，status=0，io_return=0x0 |
| PP7b | `flt ` | 4 | `13ff333f` | 0.7031 | W（语义未证） | ok |
| Te05 | `flt ` | 4 | `13468442` | 66.137 | °C | ok |
| Tf04 | `flt ` | 4 | `7bbc6d42` | 59.434 | °C | ok |
| Tf14 | `flt ` | 4 | `14467842` | 62.068 | °C | ok |

说明：

- `flt ` 为 IEEE-754 little-endian float32；`0x42 43 eb 93` 的内存顺序即 `93 eb 43 42` → 48.98。
- `PPbb` 的 132/0x84 是 SMC 返回码，官方语义未证实；可能是该机型无此键或不可读。没有用其它命令重试探测。
- 每个键的 info/read 都返回 `io_return=0x0`、`smc_result=0`（除 PPbb 的 info 132）。
- 12 个键中 8 个功率键 + 3 个温度键可用；`PPbb` 不可用。

### 2.3 单位与语义证据分级

| 键 | 推断单位 | 依据 | 置信度 |
| --- | --- | --- | --- |
| PSTR | W | 上游证据：Asahi `hwmon-common.dtsi` 标为 Total System Power；量级 38–55 W 合理 | 中 |
| PDTR | W | 上游证据：Asahi 标为 AC Input Power；量级 38–55 W | 中 |
| PHPC | W | 上游证据：Asahi `macsmc-hwmon.c` 标为 SoC dissipated heat estimate（**不是 CPU 专属**）；参考 PoC 注释实测随 CPU 负载 15→55 W | 中 |
| PZC0 / PHPS | W | 仅按键名/量级（20–34 W）；语义 **NOT CONFIRMED** | 低 |
| PDBR | W | 参考 PoC 实测：全亮 8.1 W，30% 亮度 0.4 W，随背光而非负载变化（`battery-power-rails-readonly.m:16-20`） | 中高（本机历史实测） |
| PP0b | W | 仅按 `PP` 前缀与数值量级；实测仅 0.016–0.030 W，**语义与量级都不像 package rail** | 低 |
| PP7b | W | 仅按 `PP` 前缀；实测 0–1.48 W，**语义未确认** | 低 |
| Te05 / Tf04 / Tf14 | °C | Stats `Modules/Sensors/values.swift:429,434,447` 的 M3 表，type=.temperature；数值 57–67 °C 合理 | 中高（单点传感器） |

重要限定：

- 上表单位是**推断**，不是独立校准。SMC 没有公开元数据告诉我们这些值一定是 W；不能把推断当测量证明。
- `PP0b` / `PP7b` 具体含义未知，**不要**当 CPU/GPU 功率使用。
- 温度键是单个传感器，不是 die 平均；`thermal_state`（`nominal`）是系统热压等级，**不是温度**，二者不能互替。
- `PSTR` 与 `PDTR` 在每次同刻读取时**不相等**，但 `PSTR[t]` 精确等于一个 SMC tick 之前的 `PDTR`（见 §2.7）。在本次接电、未充电条件下，二者行为上完全等价于“延迟副本”；这不能区分是同源缓存、驱动转发还是两路恰好同值，因此**不能把它们当作独立的总负载校验**。

### 2.4 温度键来源与本机验证

- 来源：`/tmp/soc-power-research/upstream/repos/stats/Modules/Sensors/values.swift:429-451`（M3 家族表，4E+12P+8GPU，正好 M3 Max 规格）。
  - `Te05` = CPU efficiency core 1（:429）
  - `Tf04` = CPU performance core 1（:434）
  - `Tf14` = GPU 1（:447）
- 上游 researcher 交叉核对，Stats 全表不再扫描；只加这 3 个固定键。
- 本机实测：3 键均存在，`flt`/4B，可读。10 Hz 25 s 内各 26 个不同值（≈1 Hz 更新）：
  - Te05 63.57–66.45 °C，中位 64.61
  - Tf04 57.28–63.95 °C，中位 59.81
  - Tf14 59.30–60.39 °C，中位 60.06
- 这些数值只能说明“该键可读且量级像温度”；未与外部温度计比对。

### 2.5 更新节奏（10 Hz，25 s，250 样本）

| 键 | 变化次数（249 个间隔中） | 不同值个数 | 变化间隔中位数 | 判定 |
| --- | --- | --- | --- | --- |
| PHPC | 25 | 26 | 1.0000 s（0.9967–1.0054） | 1 Hz 更新 |
| PZC0 | 25 | 26 | 1.0000 s | 1 Hz 更新 |
| PHPS | 25 | 26 | 1.0000 s | 1 Hz 更新 |
| PSTR | 25 | 26 | 1.0000 s | 1 Hz 更新 |
| PDTR | 25 | 26 | 1.0000 s | 1 Hz 更新 |
| PDBR | 25 | 26 | 1.0000 s | 1 Hz 更新 |
| PP0b | 25 | 23 | 1.0000 s | 1 Hz 更新（有重复值） |
| PPbb | 0 | — | — | NOT AVAILABLE |
| PP7b | 25 | 20 | 1.0000 s | 1 Hz 更新（有重复值） |
| Te05 / Tf04 / Tf14 | 25 | 26 | 1.0000 s | 1 Hz 更新（见 §2.4） |

结论：

- 以 10 Hz 连读 25 s，所有可读键的值**每秒只跳变一次**；两个跳变之间有约 10 次读取返回完全相同的字节。因此 SMC 的有效更新 tick 约为 **1 Hz**。
- 没有“完全不变”型键；`PP7b` 偶发上报 0，但它是持续变化的活键。**上报 0 只表示该键当刻返回 0，不能称为“真实物理功率 0”**；其物理含义未证实。
- 没有“完全不变”型键（除 `PPbb` 不可用）。

### 2.6 SMC 采样时间 ≠ 硬件更新时间

必须区分三个时间：

1. `ts_mono`：我们发起读取的时刻（`CLOCK_MONOTONIC`）。
2. SMC 返回值对应的那一刻：SMC 内部/驱动缓存更新时刻，本机约 1 Hz。
3. 真实硬件计数器/传感器转换时刻：未知，可能更早。

因此在 10 Hz 下，一次跳变被观测到的时刻有最多约 100 ms 的不确定度（跳变其实发生在两次读取之间）；在 1 Hz 下最多约 1 s。`capabilities` 中的“变化间隔 1.000 s”是**观测到的更新周期**，不是硬件传感器采样率，也不是电流/功率的瞬时值。做功率积分时应使用长窗口计数差或明确说明相位误差。

### 2.7 PSTR 与 PDTR 的精确关系

- 10 Hz、250 样本：`PSTR[t] == PDTR[t-10]`，即滞后 **10 个 10 Hz 样本 = 1.000 s**，240/240 对比完全相等（最大差 0.0），相关系数 1.0。
- 1 Hz、30 样本：`PSTR[t] == PDTR[t-1]`，相关系数 1.0，差值中位数 0.0。
- 同刻 `PSTR != PDTR`（例如最终样例 49.857 vs 50.645，差 0.79 W）。
- 结论（限定条件：本次接电、未充电）：`PSTR` 与 `PDTR` 的关系**行为上完全等价于**延迟一个 SMC tick 的副本；这可能是同源缓存/驱动转发，也可能是两路恰好同值。上游文档把二者分别标为 Total System Power / AC Input Power，但本次数据不足以证明“两路独立测量”；反之，也不能直接断言硬件上只有一个计数器。工程上应把 `PSTR` 视为**不能用于独立总负载校验**。

`PHPS` 与 `PZC0` 高度接近但**不逐值相等**（同刻 30.662 vs 30.624），关系未确认。

## 3. B. IOReport

### 3.1 链接与符号

- SDK：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk`
- TBD：`usr/lib/libIOReport.tbd`，install-name `/usr/lib/libIOReport.dylib`
- 使用符号：`IOReportCopyAllChannels`、`IOReportCreateSubscription`、`IOReportCreateSamples`、`IOReportChannelGetGroup/SubGroup/ChannelName/UnitLabel/Unit/Format/ChannelID/DriverID`、`IOReportGetChannelCount`、`IOReportSimpleGetIntegerValue`、`IOReportStateGetCount/NameForIndex/Residency/IDForIndex/InTransitions`。
- 全部通过 `-lIOReport` 正常链接，**不需要 dlsym 兜底**；macOS 27 上普通用户可调用。
- 私有 ABI 签名参考 macmon `src/sources.rs:161-178`（commit `39e98aa73e49256e6281b2a228f6ef3499ae3209`）。

### 3.2 全量枚举结果

- 一次 `--inventory`：原生 descriptor **11,282**，208 个 group；`IOReportCreateSamples` 实际返回 **11,120** 个通道（少 162 个，原因 **NOT TESTED**）。
- 另一次 `--all-channels` 运行：原生 **11,285** + 3 CLPC = 11,288 订阅；说明枚举数量会随系统状态小幅变化（相差 3）。
- 返回样本的格式：`1`（simple）10,237；`2`（state）736；`3`（其他，样本里保留原始字典，未解释）147。
- 组示例：`Energy Model` 325、`CPU Stats` 107、`GPU Stats`、`SoC Stats` 775、`SMC` 77、`DCP`/`DCPEXT*`、`PMP0` 344、`ANE` 1 等。
- 完整 group/通道/当前原始值：`inventory.json`（11 MB，只读产物）。

### 3.3 `Energy Model` 组

- 325 个通道；单位分布：`mJ` 319、`uJ` 5、`nJ` 1。
- 60 s、1 Hz、61 样本的冻结矩阵（`channel-freeze-matrix.csv`）：
  - **324 / 325 冻结**：计数**完全不变**。
  - 只有 1 个变化：`GPU Energy`（nJ）。

| group | channel | unit | format | driver_id | 60 s 起始计数 | 60 s 末计数 | Δ | 判定 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Energy Model | CPU Energy | mJ | 1 | 4294968324 | 640,211,452 | 640,211,452 | 0 | **frozen** |
| Energy Model | ANE0 | mJ | 1 | 4294968324 | 3,754,641 | 3,754,641 | 0 | **frozen** |
| Energy Model | DRAM0 | mJ | 1 | 4294968324 | 469,044,968 | 469,044,968 | 0 | **frozen** |
| Energy Model | DISP0 | mJ | 1 | 4294968324 | 24,299,028 | 24,299,028 | 0 | **frozen** |
| Energy Model | DISPEXT0 | mJ | 1 | 4294968324 | 29,187,873 | 29,187,873 | 0 | **frozen** |
| Energy Model | GPU Energy | nJ | 1 | 4294968371 | 339,735,309,625,305 | 339,973,323,453,863 | +238,013,828,558 | **live，3.967 W** |

- 其余冻结通道包括 `EACC_*`、`PACC*_*`、`PCPU*DTL*`、`GPU0`、`GPU CS0`、`GPU SRAM0`、`ISP0`、`AVE0`、`MSR0`、`DCS0`、`AMCC0`、`PCIe Port 0/1 Energy`、`apciec0/1/2 Energy` 等。
- **冻结 ≠ 0 W**：这些通道表示“计数在本窗口内没有增长”；可能因为 macOS 27 的 Energy Model 刷新需要私有 entitlement（macmon readme `readme.md:203`），也可能因为通道本身停用。绝不能把冻结值当作 0 W。
- **异常**：macmon 文档说 Energy Model 计数“可能可见但停止更新”；本机并非全停 —— `GPU Energy`（属于另一个 driver_id 4294968371，nJ）仍在更新，而同一组里 CPU/ANE/DRAM/DISP（driver 4294968324，mJ/uJ）全冻。这个分化是本机 macOS 27.2 的具体观测，不能外推到其它机型。

### 3.4 功率换算公式与不确定性

对 simple 格式通道：

```text
P_W = Δcount × unit_scale / Δt_mono
unit_scale: nJ=1e-9, uJ=1e-6, mJ=1e-3, J=1.0
```

- 行内 `power_w_estimate` 用**相邻两次成功读取**的计数差与单调时间差计算；冻结/计数回退时输出 `null`。
- 窗口平均功率请用 **首末计数差 / 首末时间差**，不要对“只在变化间隔才有值”的逐段功率求平均。例如 ANE 在 60 s 内只有 18 个间隔增长；逐段均值约 0.62 W，而整窗真实平均是 `11,161,838,279 nJ / 60 s = 0.186 W`。
- 计数器更新可能以 1 s 或更大粒度跳动；`ts_mono` 是读取时刻，不是计数器积分边界。
- 一次采样读取耗时 5–15 ms；同一行内各通道并非严格同一时刻。
- 单位对 CLPC 是**采样器声明**的（见 §4），不是系统独立证明。
- 原生 `mJ` 通道量化 1 mJ；若恢复更新，短窗口分辨率有限。
- 没有外部功率计/校准源；所有 W 值都是“计数×声明单位/单调时间”的换算值。

### 3.5 原生单位 vs 声明单位

CLPC 通道的 `unit`、`channel` 名称来自我们构造的 descriptor（macmon 反推），`IOReportChannelGetUnitLabel` 会回显我们填的值，因此“getter 返回 nJ”**不能**当作系统对该单位的独立确认。JSONL 中已用以下字段区分：

- `descriptor_origin`：`native IOReport descriptor` 或 `macmon explicit known report ID (not native enumeration)`
- `unit_origin`：`native IOReport descriptor` 或 `declared by harness from macmon reverse-engineering; getter echoes descriptor, not independent unit proof`
- `name_origin`：同上

## 4. C. AppleCLPC

### 4.1 IOKit 打开

- `IOServiceGetMatchingService("AppleCLPC")` 找到服务；`CFBundleIdentifier` = `com.apple.driver.AppleT6031CLPC`；`IOUserClientClass` = `AppleCLPCUserClient`。
- `IOServiceOpen(service, mach_task_self(), type=0)` → **`kIOReturnSuccess (0x00000000)`**，普通用户成功，**不需要 root/entitlement**。
- 随后立即 `IOServiceClose`。
- 只调用了 open/close；**没有**调用任何外部 selector（外部 selector 的返回/结构未知，标 **NOT TESTED**）。
- 原始属性：`clpc-ioreg.txt`。

### 4.2 IOReport 读 CLPC 能量计数

- 原生枚举里**没有** `CLPC` 组，也没有可发现的 CPU/GPU/ANE 通道名（`native CLPC = 0`）。
- 按 macmon `src/clpc.rs:19,54-58,127-141` 的 macOS 27 映射，为 M3 Max（`AppleT6031CLPC`）构造 3 个 report ID 并加入订阅：

| 通道（声明名） | 完整 report ID | 组成 | 60 s 起始计数 | 60 s Δ | 整窗平均 |
| --- | --- | --- | --- | --- | --- |
| CPU Energy | `0x10d81e0084` | index 16 << 32 \| 0xd81e0084 | 643,834,898,302,303 | +308,037,480,218 | 5.134 W |
| GPU Energy | `0x191085f98b` | index 25 << 32 \| 0x1085f98b | 371,726,351,047,110 | +238,168,180,382 | 3.969 W |
| ANE | `0x18313a3be1` | index 24 << 32 \| 0x313a3be1 | 3,946,156,596,396 | +11,161,838,279 | 0.186 W |

- 三条都返回 64 位累计计数；unit label 为 `nJ`（**声明值**）。
- ANE 在 61 个 1 Hz 样本中只有 18 个间隔增长（19 个不同值）；其它间隔计数不变。**不变 ≠ 0 W**，只是该秒没有更新。
- 60 s 内 CPU/GPU 每秒都在增长；GPU 与原生 `Energy Model / GPU Energy` 的整窗差：238.168 vs 238.014 J（0.06%）。
- 30 s 默认样例（后台 GPU 活动较高）：CLPC CPU 5.142 W、GPU 7.268 W、ANE 0.020 W（整窗平均）；同窗原生 GPU Energy 6.516 W，两路差 **11.5%**。见 §7 异常 6：两路并非始终等价。

### 4.3 AppleCLPC 属性

`ioreg -r -c AppleCLPC -l` 只读属性（原始值）：

| 属性 | 值 |
| --- | --- |
| `IOPersonalityPublisher` / `CFBundleIdentifier` | `com.apple.driver.AppleT6031CLPC` |
| `IOUserClientClass` | `AppleCLPCUserClient` |
| `#clpc-version` | 2 |
| `#cpu-num-cores` | 16 |
| `#cpu-core-mask-cluster-0` / `-1` / `-2` | 15 / 1008 / 64512 |
| `~pkg-power-split-cpu-fraction` | 29491 |
| `~pkg-power-split-gpu-fraction` | 29491 |
| `~pkg-power-split-ane-fraction` | 6553 |
| `~pkg-avg-max-power` | 12189696 |
| 其它 | 见 `clpc-ioreg.txt` |

- 三个 split 值在 60 s 内**完全不变**，且 29491+29491+6553 = **65535 = 2^16−1**。
- 若是 Q16 定点，则约为 0.4500 / 0.4500 / 0.1000；但这是**假设**，没有文档确认。
- 更像静态分配权重而不是测量结果（整数、恒定、和为 2^16−1），但**不下结论**，只记录证据。
- `~pkg-avg-max-power` = 12189696 未解释。

## 5. 额外必采：AppleSmartBattery `PowerTelemetryData`

采样器每秒读取 `AppleSmartBattery` 的 IORegistry 属性，原样保存 `PowerTelemetryData`、`AdapterDetails`、`ChargerData`、`Voltage`、`InstantAmperage` 等整数，不做单位换算。

### 5.1 字段与 60 s 增量（`freeze-1hz-60s.jsonl`，61 样本，跨度 60.005 s）

| 字段 | 首值 | 末值 | Δ（60 s） | 不同值 |
| --- | --- | --- | --- | --- |
| `SystemPowerIn` | 46,759 | 38,110 | −8,649 | 2 |
| `SystemLoad` | 46,759 | 38,110 | −8,649 | 2 |
| `SystemCurrentIn` | 1,680 | 1,367 | −313 | 2 |
| `SystemVoltageIn` | 27,826 | 27,877 | +51 | 2 |
| `AdapterEfficiencyLoss` | 1,036 | 761 | −275 | 2 |
| `SystemEnergyConsumed` | 12,988 | 10,586 | −2,402 | 2 |
| `WallEnergyEstimate` | 14,024 | 11,347 | −2,677 | 2 |
| `BatteryPower` | 0 | 0 | 0 | 1 |
| `SystemEffectiveTotalLoad` | 0 | 0 | 0 | 1 |
| `AccumSystemEffectiveTotalLoad` | 0 | 0 | 0 | 1 |
| `AccumSystemEffectiveTotalLoadCount` | 0 | 0 | 0 | 1 |
| `AdapterEfficiencyLossAccumulatorCount` | 194,140 | 194,200 | +60 | 2 |
| `SystemLoadAccumulatorCount` | 197,102 | 197,162 | +60 | 2 |
| `SystemPowerInAccumulatorCount` | 195,201 | 195,261 | +60 | 2 |
| `BatteryPowerAccumulatorCount` | 9,362 | 9,362 | 0 | 1 |
| `BatteryDischargeAccumulatorCount` | 16,924 | 16,924 | 0 | 1 |
| `PowerTelemetryErrorCount` | 0 | 0 | 0 | 1 |
| `AccumulatedSystemPowerIn` | 4,208,625,336,362 | 4,208,627,748,894 | +2,412,532 | 2 |
| `AccumulatedSystemLoad` | 3,863,244,730 | 3,865,657,262 | +2,412,532 | 2 |
| `AccumulatedSystemEnergyConsumed` | 1,169,062,512,403 | 1,169,063,182,525 | +670,122 | 2 |
| `AccumulatedWallEnergyEstimate` | 1,112,747,436 | 1,113,467,245 | +719,809 | 2 |
| `AccumulatedAdapterEfficiencyLoss` | 411,737,082,505,756 | 411,737,082,555,443 | +49,687 | 2 |
| `AccumulatedBatteryPower` | 332,837,696 | 332,837,696 | 0 | 1 |
| `AccumulatedBatteryDischarge` | −343,728,848 | −343,728,848 | 0 | 1 |

### 5.2 单位证据（未证实）

- `SystemPowerIn` 与 `SystemLoad` 在全部运行（250 + 61 + 30 次读取）中**逐值完全相等**。
- `SystemVoltageIn × SystemCurrentIn / 1000` 与 `SystemPowerIn` 的比值在全部样本中为 **0.99976–0.99994**（首样本 27,826×1,680/1000 = 46,747.68 vs 46,759）。
- 数值量级与命名一致地暗示 `mV`、`mA`、`mW`；但这是**内部一致性**，不是独立单位证明。保持 `PowerTelemetryData` 原样整数输出。
- `AccumulatedSystemPowerIn` 在 60.005 s 内 +2,412,532；若累计值单位是 mW·s，则窗口平均 40.209 W；同期 `PDTR` 均值 38.509 W（差 +4.4%）。这只能说明“量级/边界可能相关”，不足以证明同一测量边界。
- `SystemPowerInAccumulatorCount` 在 60 s 内 +60（≈1 Hz）；但另一段 29 s 内 +59（≈2 Hz），最终 30 s 样例中 **0 次变化**。**累计计数的时间基准未确认**，不能把它当严格秒数。

### 5.3 更新/陈旧性（关键）

`PowerTelemetryData` 不是 1 Hz 实时源：

| 运行 | 读取次数 / 时长 | PowerTelemetryData 不同快照数 | 累计计数增量 |
| --- | --- | --- | --- |
| freeze 1 Hz | 61 / 60.005 s | 2 | +60 |
| 早期 idle 1 Hz | 30 / 29.004 s | 2 | +59 |
| 最终 idle 1 Hz | 30 / 29.005 s | **1（整段冻结）** | **0** |

- 同一份属性字典可以**连续 29 s 完全不刷新**；期间 `PDTR` 仍在每秒变化。
- 因此不能把 `PowerTelemetryData` 的某一字段与同一行的 `PDTR` 直接相除来判断边界；比值变化主要来自陈旧快照。
- 所有 `pmset_batt` 字段的 `ts_wall` 是**读取时间**，不是它内部测量/刷新时刻。

### 5.4 与 PDTR 的比值（同单位换算后）

把 `SystemPowerIn` 按 mW 解释、`PDTR` 按 W 解释，比值 = `SystemPowerIn/1000/PDTR`：

| 运行 | 比值范围 | 说明 |
| --- | --- | --- |
| freeze 60 s | 1.014–1.119 | 起始 46.759/41.769=1.119；末 38.110/37.566=1.014 |
| 早期 idle 30 s | 0.808–1.173 | 快照陈旧导致跨过 1 的两侧 |
| 最终 idle 30 s | 40.905/44.880≈0.911（整段冻结） | 无动态可比性 |

**结论：比值不稳定（0.81–1.17），不能确认 `SystemPowerIn` 是与 `PDTR` 同边界的独立 DC 输入读数。** 若要用它，必须在它实际刷新的时刻取快照，并明确其积分窗口未知。

### 5.5 AdapterDetails / ChargerData / 电池

- `AdapterDetails`：`Watts=140`、`Current=4990`、`AdapterVoltage=28000`、`Name="140W USB-C Power Adapter"`、`Description="pd charger"`、`IsWireless=false`、`AdapterPowerTier=2`。
  - 这些看起来是适配器额定/协商参数，**不是实测输入功率**；未证实。
  - 该字典还含 `SerialString` 等敏感字段，未写入本报告。
- `ChargerData`：`IsCharging=0`、`NotChargingReason=16777216`。
- 电池：`Voltage=12251`（按惯例 mV）、`InstantAmperage=0`、`CurrentCapacity=80`、`MaxCapacity=100`、`FullyCharged` 存在、`ExternalConnected=true`、`ExternalChargeCapable=true`。
- `PowerOutDetails` **不存在**（无外接配件时）。
- `pmset -g batt`：`AC Power`、`80%; AC attached; not charging`（与 IOKit 一致；采样器不 fork `pmset`，直接读 IOKit 属性）。

## 6. D. 采样器接口（load-lab 用）

### 6.1 路径与命令

```sh
/tmp/soc-power-research/harness/power-sampler --hz 1 --seconds 60 --out /path/file.jsonl [--label name]
```

- `--hz`：1–100；`--seconds`：>0；`--out` 必填。
- `--all-channels`：全量 `Energy Model`（325）+ CLPC 3；默认只订阅 17 个关键通道（14 原生 + 3 CLPC），显著减小文件。
- `--inventory <file>`：一次性导出全量枚举/当前原始值（探测用）。
- 退出：正常结束、`SIGINT`、`SIGTERM` 均刷盘、`CFRelease`、`IOServiceClose` 后返回 0。实测 `SIGINT` 在 2.4 s 时结束，退出码 0，已写 13 行完整 JSON。
- 不 fork `pmset`，电池/温度/热压都在进程内读取。

### 6.2 schema 版本与关键字段

`schema = "soc-power-research/1"`。要点：

- `ts_mono`：`CLOCK_MONOTONIC` 秒；`ts_wall`：UTC ISO8601；`sampling.lateness_s` 相对计划时刻。
- `smc[]`：12 键，含 `type/size/raw_hex/value/unit_inferred/status/info_smc_result/read_smc_result`。
- `ioreport.channels[]`：`group/subgroup/channel/unit/format/channel_id_hex/id`、`raw_count`（64 位整数）、`raw_count_decimal`（十进制字符串，避免 JS >2^53 精度丢失）、`delta_count`、`delta_count_decimal`、`power_w_estimate`、`count_status`。
- `clpc.channels[]`：同上；另有 `clpc.iokit_open`（错误码/状态）与 `clpc.properties`（`~pkg-power-split-*` 等原始属性，每行重读）。
- `pmset_batt`：`PowerTelemetryData`、`AdapterDetails`、`ChargerData`、`Voltage`、`InstantAmperage`、`IsCharging`、`ExternalConnected` 等原样整数。
- `thermal_state`：`nominal/fair/serious/critical`；不是温度。
- `sample_read_duration_s`：该行读取耗时。

### 6.3 自身开销（`/usr/bin/time -l`）

| 配置 | 样本/时长 | user+sys | 占单核 | RSS |
| --- | --- | --- | --- | --- |
| 1 Hz，默认 17 通道 | 30 / 30.11 s | 0.09+0.14=0.23 s | **0.76%** | 24.8 MB |
| 1 Hz，全 328 通道（freeze） | 61 / 60.44 s | 0.45+0.31=0.76 s | **1.26%** | 23.1 MB |
| 10 Hz，全 328 通道 | 250 / 25.45 s | 1.75+1.16=2.91 s | **11.4%** | 23.3 MB |

- 1 Hz 默认配置满足“<2% 自身开销”的要求。
- 10 Hz 全通道达到 11%，**不适合长时间负载实验**；需要高频时用默认通道或将 `--hz` 降到 1。
- 后台一次 `ps` 看到采样器 10 Hz 时 14.1% CPU，与 time 的 11.4% 同量级。

### 6.4 采样抖动

| 配置 | 间隔中位数 | 间隔 pstdev | 最大 lateness |
| --- | --- | --- | --- |
| 1 Hz 默认 | 1.000005 s | 1.7 ms | 5.27 ms |
| 1 Hz 全通道 | 1.000005 s | 2.0 ms | 5.03 ms |
| 10 Hz 全通道 | 100.001 ms | 2.1 ms | 7.88 ms |

- 调度器在 deadline 后采样，所以 `lateness_s` 中位数约 5 ms；不是 busy-wait。
- 单次读取 5–15 ms，读取期间计数器可能被更新，行内存在毫秒级不一致。

## 7. 异常与重要发现

1. **PSTR 行为上等价于 PDTR 的延迟副本**（本次接电未充电条件）：滞后精确 1 个 SMC tick（10 Hz 下 10 个样本）。这可能来自同源缓存/驱动转发，不能据此断言硬件只有一个计数器；但可以确定：**不能用两者做独立总负载交叉校验**，否则会得到虚假的“完全一致”。
2. **原生 Energy Model 分化**：同一 `Energy Model` 组里，CPU/ANE/DRAM/DISP（mJ/uJ）全冻，而 `GPU Energy`（nJ，另一个 driver_id）仍在更新。macmon readme 的“Energy Model 停止更新”在本机只对一部分通道成立。
3. **AppleCLPC 普通用户可开**：`IOServiceOpen` 返回 0；CLPC 计数无需 root/entitlement 即可经 IOReport 读取。
4. **CLPC 权重恒定**：29491/29491/6553，和 65535（2^16−1），60 s 不变；像静态权重，但未下结论。
5. **PowerTelemetryData 可冻结 29 s**：期间 PDTR 每秒变化；因此它不是 1 Hz 遥测源。累计计数的时间基准（60 s 增 60 vs 29 s 增 59 vs 29 s 增 0）不一致。
6. **两路 GPU 计数并非总是一致**：低活动窗口 CLPC GPU 与原生 GPU Energy 差 0.06%–0.33%；后台 GPU 活动较高时（CLPC GPU ≈7.3 W）差 11.5%。二者不能互换，也不能据此校准。
7. **枚举数量漂移**：11,282 → 11,285 个原生 descriptor（相差 3），另一次 11,120 个有样本（少 162）。原因未查。
8. **PPbb 失败码 132/0x84**：SMC info 阶段失败；未做其它命令重试。

## 8. NOT AVAILABLE / NOT TESTED

### NOT AVAILABLE

| 项 | 原因 |
| --- | --- |
| SMC `PPbb` | info result=132 (0x84)，无数据 |
| 原生 Energy Model CPU/ANE/DRAM/DISP 功率 | 60 s 冻结；不是 0 W，无法用 |
| 原生 IOReport `CLPC` 组/命名通道 | 全量枚举中没有；只能显式构造 report ID |
| `PowerOutDetails` | 无配件时属性不存在 |
| 独立功率校准/外部功率计 | 无设备 |
| 干净空闲基线 | 后台 WindowServer/BlueStacks/Edge/macpow 等持续活动；只能说“未主动施加负载” |

### NOT TESTED

| 项 | 说明 |
| --- | --- |
| AppleCLPC 外部 user-client selector | 只 open/close，未调用 selector |
| `powermetrics` / 私有 entitlement 路径 | 未请求、未提权 |
| SMC 全表/其它键 | 按要求不扫描，只读固定 12 键 |
| SMC 写、SMC 键表枚举 | 设计禁止 |
| IOReport 147 个非 simple/非 state 通道 | 只保留原始字典，未解释 |
| 162 个“枚举有 descriptor 但样本缺失”的通道 | 原因未查 |
| 温度 die 平均/多点校准 | 只有 3 个单点传感器 |
| 10 Hz 长时间稳定性/泄漏 | 只跑 25 s |
| 与 root/sudo 的差异 | 全程普通用户 |
| 负载响应/温升 | 不在本任务；由 load-lab 做 |

## 9. 已知不确定性汇总

1. SMC 功率键的单位（W）是按命名/量级/上游 Asahi 注释推断，非校准；`PP0b/PP7b` 语义完全未知。
2. `PZC0/PHPS` 的物理含义未确认，只知道数值接近。
3. `PSTR` 与 `PDTR` 的语义标签与实测的“延迟副本”行为矛盾；在本次接电未充电条件下只能确认行为等价，无法区分同源缓存与独立两路，采用时不得当作独立校验。
4. CLPC 的 nJ 单位、CPU/GPU/ANE 名称是 macmon 反推后由采样器声明；getter 回显不算独立证明。GPU 量级与原生通道部分吻合，但高活动时差 11.5%，说明两者边界/更新机制仍有差异。
5. `PowerTelemetryData` 的字段单位、刷新时刻、累计计数时间基准都未证实；只能作粗粒度参考，不能做逐秒对齐。
6. 所有温度是单点传感器，不代表 die 平均；`thermal_state` 只是系统热压等级。
7. 采样相位误差：1 Hz 下最多约 1 s，10 Hz 下最多约 100 ms。
8. 后台负载使“idle”并非真正空闲；`sample-idle.jsonl` 只保证“本工具未施加负载”。

## 10. 复现与文件

```sh
cd /tmp/soc-power-research/harness
make
./power-sampler --hz 1 --seconds 30 --out sample-idle-new.jsonl --label check
./power-sampler --hz 1 --seconds 60 --out freeze.jsonl --label freeze --all-channels
./power-sampler --hz 10 --seconds 25 --out tick.jsonl --label tick
python3 analyze.py    # 重新生成 analysis-summary.json / channel-freeze-matrix.csv
```

| 文件 | 内容 |
| --- | --- |
| `power-sampler.m` / `power-sampler` / `Makefile` | 采样器源码、二进制、构建 |
| `README.md` | 构建、运行、schema |
| `sample-idle.jsonl` | **30 s 默认 17 通道样例**，label `idle-no-induced-load` |
| `freeze-1hz-60s.jsonl` | 60 s 全通道冻结观察（328 通道） |
| `smc-tick-10hz.jsonl` | 10 Hz 25 s，SMC 更新节奏 |
| `temperature-tick-10hz.jsonl` | 10 Hz 25 s，温度键更新节奏 |
| `inventory.json` | 全量枚举 + 当前原始值 |
| `channel-freeze-matrix.csv` | 每通道首末计数、Δ、冻结判定 |
| `analysis-summary.json` | 全部运行的结构化汇总 |
| `analyze.py` | 汇总脚本（只读输入） |
| `clpc-ioreg.txt` | AppleCLPC 原始属性 |
| `background-load.txt` / `pmset-batt.txt` | 采集时后台负载/电源状态 |
| `*.log` | 构建与运行日志（含 `/usr/bin/time -l`） |

## 11. 来源

- macmon（commit `39e98aa73e49256e6281b2a228f6ef3499ae3209`）：
  - `src/sources.rs:161-178` IOReport FFI 声明
  - `src/sources.rs:997-1020` CLPC 显式 descriptor（nJ、power 类、simple integer）
  - `src/clpc.rs:19` macOS 27 indices（CPU 16 / GPU 25 / ANE 24）
  - `src/clpc.rs:54-58` T6031 三个 key；`:127-141` report ID 组合与命名
  - `readme.md:203-207` macOS 27 Energy Model 需要私有 `com.apple.private.pmgr.nrg.reporting`；sudo 不给；CLPC 可无 root
  - `docs/clpc-discovery.md:42-47` 26→27 index 迁移与“不建立访问权限/精度结论”
- Stats（`/tmp/soc-power-research/upstream/repos/stats`）：
  - `Modules/Sensors/values.swift:429` Te05，`:434` Tf04，`:447` Tf14（M3 家族温度映射）
- 仓库参考 PoC（只读）：
  - `.worktrees/battery-power-breakdown/scripts/poc/battery-power-rails-readonly.m:33-56` AppleSMC 协议
  - 同文件 `:16-20` PDBR 随背光、PHPC 随 CPU 负载的历史实测注释
- 上游证据（由 upstream-researcher 交叉核对 Asahi 源码）：
  - `macsmc-hwmon.c` header：PHPC = SoC dissipated heat estimate（非 CPU 专属）
  - `hwmon-laptop.dtsi:9`：Heatpipe Power
  - `hwmon-common.dtsi`：PSTR Total System Power、PDTR AC Input Power
- SDK：`MacOSX27.0.sdk/usr/lib/libIOReport.tbd`
