# macOS 功耗上游证据档案

检索时间：2026 年 10 月 30 日晚（Asia/Shanghai）。研究对象：macmon、macpow、Stats；用途：为 Mac15,9 / M3 Max / macOS 27.2 (26B123) 的本机研究提供可追溯依据。**本文的上游报告不能替代本机测量。**本研究没有运行负载、SMC 功率采样、提权、安装软件、commit 或 push。只进行网络读取、源码阅读和极轻量 ioreg 读取；传感器实测请以 sensor-harness / load-lab 的记录为准。

## 1. 结论与边界

1. **旧路径是累积能量计数器的差分，不是直接读取瓦数，也不是根据 CPU 使用率猜功率。**Energy Model 的 `CPU Energy` / `GPU Energy` / `ANE*` 等通道由 `IOReportCreateSamplesDelta` 得到 ΔE，再按 mJ/uJ/nJ 转成 J，除以真实采样间隔秒数得到 W。
2. **macOS 27 的核心问题是部分计数器可见但不刷新。**所以 ΔE=0 不能解释为 CPU/DRAM/ANE 真正消耗 0 W；偶发批量刷新又可能产生几千 W 的假尖峰。GPU 的 AGX/nJ 通道经常继续刷新。
3. **macmon 已在 v0.9.0（2026-10-07）发布 rootless AppleCLPC workaround。**CPU/GPU/ANE 使用按驱动 bundle+report ID 定位、按 nJ 假设换算的隐藏能量报告，仍通过 IOReport subscription/delta API 读取。并非正常枚举出来的已命名 CLPC 通道；`CLPC / Energy Counters / CPU Energy` 等名字是应用构造 descriptor 时赋予的名字。
4. **当前 macmon 明确说 Energy Model 刷新需要 `com.apple.private.pmgr.nrg.reporting` entitlement；sudo 不赋予该权限。**CLPC workaround 不要求 root；是否在本机每个计数器都可用，仍必须由本机读取证明。
5. **macpow 0.1.19 的 SoC 是多个 Energy Model 分项相加。**CPU/DRAM/ANE/fabric 等冻结后，只剩 GPU 活动量时 SoC 可小于 1 W；这不是整机输入功率。其 PR #21 只新增冻结警告和文档 workaround，未替换功率来源，也尚未合并。
6. **SMC 键名不能跨代照抄语义。**PHPC 有 Asahi 源码称为 SoC 散热估算/Heatpipe Power，不能称 CPU-only；PZC0/PHPS 有包含 GPU 响应的社区测量；PP0b/PPbb/PP7b 的 CPU 组合只在特定基础款上被测量。M3 Max 的分项边界未从这些证据证实。
7. `PowerOutDetails.Watts/PDPowermW` 的 `/1000` 仅有第三方实现支持；**实际输出、协商值还是预算值 UNKNOWN**。`AdapterEfficiencyLoss`、`WallEnergyEstimate` 的单位、时间窗、能量/功率边界均 UNKNOWN。

## 2. 冻结的上游版本及本地材料

所有路径相对 `/tmp/soc-power-research/upstream/`。三个仓库均已 `git clone --depth 1`；macmon 随后补取最多 80 深度以核对修复历史；Stats 额外取 v3.0.23 tag，不切换 checkout。

| 项目 | 审阅 SHA / 版本 | git 日期与版本证据 |
|---|---|---|
| macmon | `39e98aa73e49256e6281b2a228f6ef3499ae3209`；Cargo 0.10.0，main/dev 快照 | HEAD 2026-10-21 18:12:10 +0300，`ci: build the release archive through rust-build targets (#109)`；`repos/macmon/Cargo.toml:3`。正式 v0.10.0=`5df67a54e082e0b30a0aa2b48b7c7f78a36f1795`，2026-10-15；v0.9.0=`7df49f55d9a1b9072e31fc8ba991abda84593563`，2026-10-07；v0.8.2=`6919d7781b6c55a6e3bedff83a210435837e1dfe`，2026-08-04。 |
| macpow | `696de22d87acb62fbdd306827fb72ea4a375e537` = tag v0.1.19 | 2026-05-11 22:57:20 +0400，`Bump version to 0.1.19`，`git ls-remote --tags` 与本地 tag 一致。 |
| Stats | `032f4a5e4cb9c11bc537c70a9487dfd904f2011d`（checkout main） | 2026-10-29 17:34:02 +0100；`feat: updated speeds formatter to always show two decimal places with fixed units (#3376)`。最新已核验 release tag v3.0.23=`5cf09a8cb0561ff24c28be4e5374d579d0601818`，2026-10-25 12:10:36 +0100；checkout 不是该 tag。 |

永久链接前缀：

- macmon：<https://github.com/vladkens/macmon/tree/39e98aa73e49256e6281b2a228f6ef3499ae3209>
- macpow：<https://github.com/k06a/macpow/tree/696de22d87acb62fbdd306827fb72ea4a375e537>
- Stats：<https://github.com/exelban/stats/tree/032f4a5e4cb9c11bc537c70a9487dfd904f2011d>

历史 v0.8.2 `src_lib/metrics.rs`、`src_lib/sources.rs` 已归档为 `macmon-082-metrics.rs`、`macmon-082-sources.rs`。注意旧版叫 `src_lib`，当前重组到 `src`；当前 checkout 没有独立 `src/sampler.rs` / `src/ffi.rs`，对应实现合在 `src/metrics.rs` 和 `src/sources.rs`。**不能用旧文件名配当前行号。**

## 3. macmon：读哪里、单位、公式、权限

### 3.1 旧版与当前的 Energy Model 分项

v0.8.2：`src_lib/metrics.rs:515-523`，永久链接：<https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/metrics.rs#L515-L523>

```rust
if x.group == "Energy Model" {
  match x.channel.as_str() {
    "GPU Energy" => rs.gpu_power += cfio_watts(x.item, &x.unit, dt)?,
    c if c.ends_with("CPU Energy") => rs.cpu_power += cfio_watts(x.item, &x.unit, dt)?,
    c if c.starts_with("ANE") => rs.ane_power += cfio_watts(x.item, &x.unit, dt)?,
    c if c.starts_with("DRAM") => rs.ram_power += cfio_watts(x.item, &x.unit, dt)?,
    c if c.starts_with("GPU SRAM") => rs.gpu_ram_power += cfio_watts(x.item, &x.unit, dt)?,
```

同文件注释明确 `CPU Energy` 为 Basic/Max，`DIE_{}_CPU Energy` 为 Ultra；`ANE` 为 Basic、`ANE0` 为 Max、`ANE0_{}` 为 Ultra。当前同逻辑见 `repos/macmon/src/metrics.rs:684-697`，过滤见 `src/shared.rs:39-44`。当前多路来源优先级：CLPC > Energy Model > PMP ANE；`src/metrics.rs:26-53`：

```rust
// On macOS 27 Energy Model CPU/ANE counters can freeze without Apple's
// entitlement. Prefer readable CLPC counters, including valid idle zeroes.
Some(self.clpc.or(self.energy_model).unwrap_or(self.pmp))
```

CLPC 有限、非负值（含合法 idle zero）才接受；负数含 IOReport invalid sentinel / reset，见 `src/metrics.rs:32-37`。`Sampler::with_clpc()` 不允许 fallback，缺 CPU/GPU/ANE 任一项会报 unavailable，见 `src/metrics.rs:565-570,716-724`。默认 fallback 仍可能在不支持配置上返回冻结 0；不能把默认成功解释成有效数据。

### 3.2 差分、积分、采样间隔

`repos/macmon/src/sources.rs:243-255`：<https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/sources.rs#L243-L255>

```rust
let val = unsafe { IOReportSimpleGetIntegerValue(item, 0) } as f64;
// watts_from_energy:
let val = val / duration.as_secs_f64();
match unit {
  "mJ" => Ok((val / 1e3) as f32),
  "uJ" => Ok((val / 1e6) as f32),
  "nJ" => Ok((val / 1e9) as f32),
  _ => Err(format!("Invalid energy unit: {}", unit).into()),
}
```

`src/sources.rs:1218-1241` 用 `Instant` 给两个 `IOReportCreateSamples` 记时、调用 `IOReportCreateSamplesDelta(prev,next)`，使用 `next.1.duration_since(prev.1).max(Duration::from_nanos(1))`。`src/metrics.rs:750-756` 把实际 elapsed 而非单纯请求 interval 传入计算。CLI 默认 1000 ms，可 `-i` 设置：`readme.md:96-102`；UI 默认配置 `src/app/config.rs:65-67`。

公式（Δt 用秒）：

- `P_W = (E₂ - E₁) × k / Δt_s`，k=mJ→10⁻³、uJ→10⁻⁶、nJ→10⁻⁹；差分由 IOReport 库执行。
- 对有效区间积分：`E_J = Σ P_i × Δt_i`。冻结期间按 0 积分会少算；长时间批量刷新量用一个短 interval 除会产生尖峰，不能把该尖峰当瞬时功率。
- Energy Model 按原通道标签解读；**CLPC 是应用按 nJ（纳焦耳）假设解读，尚需独立标定**。不是 “J/ns 计数”，也不是直接 mW。`P_mW=P_W×1000` 只用于最终功率换单位。

`src/metrics.rs:647-649` 读取 SMC `PSTR`；`778-780` 为 `sys_power = PSTR.max(all_power)`。因此 `sys_power` 并非始终是未加工 PSTR；错误能量尖峰可能污染它。CPU/GPU/ANE 合计也不等于含 DRAM/显示/USB 的整机输入。

### 3.3 AppleCLPC 隐藏报告：M3 Max 的精确 ID

`repos/macmon/src/clpc.rs:19,53-58,127-142`：<https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/clpc.rs#L19>

```rust
const INDICES_27: ClpcIndices = ClpcIndices { cpu: 16, gpu: 25, ane: 24 };
// com.apple.driver.AppleT6031CLPC:
cpu: 0xd81e_0084,
gpu: 0x1085_f98b,
ane: 0x313a_3be1,
// report_id:
((index as u64) << 32) | key as u64
```

| 本机匹配 bundle | 项 | 完整 report ID |
|---|---|---|
| `com.apple.driver.AppleT6031CLPC` | CPU | `0x00000010d81e0084` |
| 同上 | GPU | `0x000000191085f98b` |
| 同上 | ANE | `0x00000018313a3be1` |

`energy_channels` 只在 `os_version.split('.').next() == Some("27")` 时返回映射；未知 bundle / 26.x / 28.x 返回 None。它只按 major 判断，**并没有证明 27.2 固件 ID 必然不变**。该表来源为 27.0 (26A428) / 27.0.1 (26A434)，见文件头。`docs/clpc-discovery.md:3,21-37,53-60` 说明从 Apple IPSW kernelcache 静态扫描 descriptor、生产者链及 aggregate（Ultra 含两 die）归属；未知必须报告 unresolved。

`src/sources.rs:997-1019` 构造 descriptor：

```rust
// IOReportTypes.h: simple integer, power category, one element; energy in nJ.
let channel_type = 1i64 | (2 << 16) | (1 << 32);
let unit = (3i64 << 56) | (118 << 32);
// DriverID = IORegistryEntryGetRegistryEntryID(...)
// DriverName="AppleCLPC", IOReportGroupName="CLPC"
// IOReportSubGroupName="Energy Counters", LegendChannel=[id,channel_type,name]
```

`src/sources.rs:1022-1046`：`IOServiceIterator::new("AppleCLPC")`，读 `CFBundleIdentifier` 与 registry entry ID，按 bundle 取 ID；`src/sources.rs:1090-1097` 将人工 descriptor 添加到 selected array；`src/shared.rs:21-24` 只接受 `CLPC/Energy Counters/{CPU Energy,GPU Energy,ANE}/nJ`。同一 IOReport subscription 可合并通常枚举的组与人工 descriptor。**无法用 “IOReportCopyChannelsInGroup("CLPC") 为空” 否定可读性。**

单位的独立 Apple 源码交叉：<https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/IOReportTypes.h#L214-L283>，本地 `IOReportTypes.h:214-217,233-235,257-259,279-280`：

```c
#define __IOR_MAKEUNIT(quantity, scale) (((IOReportUnit)quantity << 56) | (uint64_t)scale)
kIOReportQuantityEnergy = 3, // Joules
#define kIOReportExpBase        (-127)
#define kIOReportExpZeroOffset  -(kIOReportExpBase)
#define kIOReportScaleNano ((-9LL + kIOReportExpZeroOffset) << kIOReportScaleSIShift)
```

所以 `3<<56` 是能量，`118=127-9` 是 nano 尺度，raw unit=`216173289042345984`。这是 descriptor 编码和库标签的独立解释；**AppleCLPC 真实硬件计数缩放的最终标定仍需与本机有效计量对照**，不能仅凭应用自造标签证明准确度。

### 3.3.1 nJ 假设、覆盖范围与发布版核对（必须保留的限制）

`repos/macmon/src/app/find_clpc.rs:219` 原文：

```rust
// nJ is a hypothesis until matched to independent energy measurements.
```

永久链接：<https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/app/find_clpc.rs#L219>。这直接限制了前述 descriptor/unit 编码的证据强度：Apple 的 unit 常量只能证明应用写入的 nJ 标签是什么意思，**不能证明隐藏 report 原生缩放已被独立标定**。

`docs/clpc-discovery.md:60` 还明确：

> “Static tracing proves producer provenance, not the full physical coverage of Apple's power model.”

即静态追踪证明 CPU/GPU/ANE 生产者来源，不证明其完整物理覆盖范围。不能将 CLPC 称为已校准电功率、比 SMC 更准确或完整 SoC 总功率。

已用 `git show 7df49f55:<path>` 直接核对 **v0.9.0**：`src/clpc.rs`、`src/shared.rs`、`src/app/find_clpc.rs` 与 main 当前版本逐字相同（git diff exit 0）。v0.9.0 已有 T6031 的上述映射，也已有 nJ hypothesis 注释；descriptor 在 v0.9.0 的 `src/sources.rs:834-855`，`channel_type` :836 / `unit` :837 与当前 :999/:1000 相同。其余 `sources.rs` / `metrics.rs` 后来有变化，本文当前行号引用仍指 main SHA，**不宣称所有 current 行为都在 v0.9.0**。v0.9.0 三份归档为 `macmon-090-clpc.rs`、`macmon-090-sources.rs`、`macmon-090-find_clpc.rs`。

### 3.4 权限与 macOS 26/27 记录

README（已完整阅读；当前没有独立 FAQ 文件或 FAQ section）`readme.md:201-209`：

> “refreshing them now requires the private `com.apple.private.pmgr.nrg.reporting` entitlement”
>
> “Running macmon with `sudo` does not grant the same access.”
>
> “The working rootless workaround we found is to read hidden energy reports from the AppleCLPC driver through IOReport.”

这说明权限变化属于 **Energy Model 的刷新路径**，不能转述成 AppleCLPC 需要同一 entitlement。AppleCLPC 的查询/订阅源码不含提权流程；README 和 issue 有普通用户使用反馈，但本机可用性仍交由 harness 报告。

核验的相关 git 历史：

- `a266042800e02262bd8c34748426253fa2326bb3`，2026-10-05：`fix: read CPU, GPU and ANE power via AppleCLPC`，<https://github.com/vladkens/macmon/commit/a266042800e02262bd8c34748426253fa2326bb3>。
- `f32e8ae287294a2b31f8664f44710cc3c9a48770`，2026-10-05：`feat: extract CLPC keys from firmware and expand macOS 27 support`。
- `64cd23417afb7df7bc76f7fa10b94929a6db578b`，2026-10-05：`feat: add find-clpc command for power counter discovery`。
- `8683dea034bf186f67e49e38a53fc860a9acf400`，2026-10-05：ANE stress / PMP fallback。
- `40f4e46408c20e63cd51b1b3416c170ac8f447ea`，2026-07-23：powermetrics sampling research。

`docs/powermetrics-sampling.md:84-112,119-139` 在 M2、macOS **26.5.2 (25F84)** 追踪到 powermetrics 订阅 `Energy Model`，每周期调用 energy sample/delta。因此 issue #76 最初正文“powermetrics 不用 CPU Energy、只用 DVFS 曲线”的说法，不能当结论；后来特权刷新实验和当前维护者文档更有针对性。此次 bounded history 未找到另一个明确 Tahoe/macOS26 功耗故障结论，**NOT FOUND，不等于全历史无相关 issue**。涉及文档的 Frida/SIP/boot-args 实验没有在本机执行。

## 4. macmon issue #76：现象与最终处理

URL：<https://github.com/vladkens/macmon/issues/76>。2026-09-05 创建，检索时 closed，9 条评论；正文与9条评论全部归档 `issue76.json`、`issue76c.json`；可读全文 `issue76-readable.md`（182行）。API `?per_page=100` 一次取得9条，与 issue.comments=9 相符，无遗漏分页需求。

- 原作者 roely15mol：macmon 0.8.2，**M3 Max Mac15,10（10P+4E）**、macOS **27.0 beta 26A5425a**；CPU=0，GPU/频率/温度/PSTR 正常。报告 AppleT6031PMGR `CPU Energy` 原始 timestamp/counter 字节连续相同，GPU 来自 AGXAcceleratorG15X 仍增长。原文：“`consecutive samples contain identical timestamps and counter bytes`”。这是用户诊断，非 Apple 官方根因文档。
- M1 Pro 用户也报告同类问题。2026-10-03 talkstream 补充 **M3 Pro Mac15,6/T6030、27.0 (26A428)、27.0.1 (26A434)** 正式版仍有：所有 mJ CPU/DRAM 类通道为0，GPU nJ 活动。300个2秒样本中299次CPU=0，一次 **3564.0W**，DRAM同次1011.9W；支持间歇批量刷新解释。[原评论](https://github.com/vladkens/macmon/issues/76#issuecomment-5969767570)。
- 维护者 vladkens 2026-10-07：[评论](https://github.com/vladkens/macmon/issues/76#issuecomment-6046222854)：“`v0.9.0 is out with a rootless workaround ... using AppleCLPC counters`”。
- 10-08 M1 Pro（27.0/26A428）：“`CPU, GPU and ANE readings are all normal.`”；M3 Max 原作者：“`Works on m3 max as well thanks!`”。
- 结论：macmon 对支持映射的机器有已发布 workaround；**不是 Apple 已修复 Energy Model，也不是已证实 macOS27.2 所有机型都恢复**。

## 5. Stats：当前实现与 issue #3621 全部评论

### 5.1 源码机制

`repos/stats/Modules/Sensors/readers.swift:532-624`：<https://github.com/exelban/stats/blob/032f4a5e4cb9c11bc537c70a9487dfd904f2011d/Modules/Sensors/readers.swift#L532-L624>

- `getChannels` 只订阅 `Energy Model`，538行用 `IOReportCopyChannelsInGroup`。
- `IOSensors` 582行取**累积样本**；597行 `Double(IOReportSimpleGetIntegerValue(item, 0))`；599-608按 suffix CPU Energy/GPU Energy，prefix ANE/DRAM/PCI求和。
- 611行 defer 保存上次值和时间；616行用 `lastIOSensorsRead == 0` 标识初次，而非用 prevCPU 是否为0。

```swift
let elapsed = CFAbsoluteTimeGetCurrent() - self.lastIOSensorsRead
let cpuResult = (cpu - self.prevCPU) / elapsed
// GPU/ANE/RAM/PCI 同理
return (cpuResult, gpuResult, aneResult, ramResult, pciResult)
```

它自己做差分，未用 `IOReportCreateSamplesDelta`。单位转换在 `Kit/extensions.swift:350-360`：mJ `/1e3`、uJ `/1e6`、nJ `/1e9`。`Double.power(unit)` 名字虽叫 power，此处先把累积量换成 J，之后才除秒得到 W。

GPU模块的 ANE 显示也订阅 Energy Model，`Modules/GPU/reader.swift:314-368` 按 `ANE*` 累计、差分，再 `/elapsed`；**这不是 GPU 功率本身的另一套 SMC fallback**。Sensors表另有传统 SMC `PCPC` CPU Package、`PG0R` GPU、`PSTR` System Total 等标签（`Modules/Sensors/values.swift:604-631`），不等于 Apple Silicon 上自动拿这些替代冻结的 computed CPU Power。

当前已检视路径内未找到通过提权 powermetrics helper 获取 Apple Silicon CPU/GPU 功耗；不能把 Stats 的风扇/helper 子系统与本功耗来源混为一谈。已确认移除旧 `prevCPU != 0` 首样本门禁，**但 Energy Model 冻结仍未被当前路径解决**。

### 5.2 issue #3621（检索时仍 open）

URL：<https://github.com/exelban/stats/issues/3621>，2026-09-16 创建。**正文+全部14条评论已完整阅读**：`stats3621.json`、`stats3621c.json`，可读归档 `stats3621-readable.md`（426行）。API `comments?per_page=100` 得14条，与 issue.comments=14 相符。

1. 正文：**MacBook Air M5、macOS27、Stats3.0.16**，CPU Power=0.00W。
2. 维护者 exelban 9-16：“`not a Stats-specific problem`”；“`macOS does not report this value (or report incorrectly)`”；“`not only ... CPU Power ... almost all powers ... IOReport`”；当时“不知道 workaround”，保留 open 防重复。[评论](https://github.com/exelban/stats/issues/3621#issuecomment-5702465324)。
3. homm 9-24，**M4 Pro、macOS27**：同一非特权 IOReport CPU Energy 在另一个签名 `sudo /usr/bin/powermetrics --samplers cpu_power -i 200` 运行时产生增量，停止后冻结；更新节奏跟随 powermetrics；gpu_power sampler 也能触发，tasks/ane_power 不行。exelban 回应“`its sudo. And its banned here`”。这不是建议普通应用自动运行 sudo。
4. tianchengchi04 9-26，**base M4 Mac16,12、27.0 26A428、Stats3.0.17**：PZC0 无root，idle≈1W、负载≈24W，提交限 base M4 的 patch（该用户称CPU package）。**其标签不能跨机型，也不能忽略后续GPU反例。**[patch](https://github.com/tianchengchi04/stats/commit/e6a9dbe8bbb0eb7bda588f5ab8ae0109f88f4bd8)。
5. STRML 9-27：PMP0/Energy CPU power histogram 是另一条无root路径，驻留时间×功率档位求加权均值，最低非零 bin 按0处理；称 M5 Ultra GPU直方图62.2W对GPU Energy63.5W，M5 Max CPU14.36W对Energy Model13.76W，+4.3%。**属于模型/量化估算，不是同一类累积能量计数。**[分支比较](https://github.com/exelban/stats/compare/master...STRML:osx-stats:fix/m5-ultra-power)。
6. Igradi 10-10，**base M5 Mac17,3、27.0.1 26A434、Stats3.0.20**：histogram在裸组 `PMP` 而非 PMP0..7；PZC0 tracks PHPS、包含GPU；GPU-only时PZC0=20.0W、GPU Energy=18.0W，不能叫CPU-only。
7. 权限诊断补充：homm 9-24 的[后续评论](https://github.com/exelban/stats/issues/3621#issuecomment-5816975542)展示系统 powermetrics entitlement，称 ad-hoc 重签后即使sudo也0、停止激活别的reader；自行添加 entitlement 会被系统kill。作者特别指出：重签也改变platform signing状态，**尚不能单独证明这一entitlement就是唯一gate**。维护者同日表示会继续调查，未宣布最终修复。
8. Flowershangfromthebranches 10-13：**MacBook Air base M3、27.2 (26B5086k)、Stats3.0.21（评论未给hw.model）**，PP0b(P)、PPbb(E)、PP7b(CPU SRAM)；PZC0随GPU也升，估计SoC。1800秒 frozen counter两次刷新间对照：CPU Energy均值1.577W，三轨之和1.666W(+5.6%)，PZC0=2.885W(+82.9%)；明确“`Not tested: M3 Pro / Max / Ultra`”。[评论](https://github.com/exelban/stats/issues/3621#issuecomment-6146808425)。
9. Igradi 10-13 base M5对照同三轨成立；GPU PP1b 17.98W对GPU Energy18.02W；PZC0/PHPS 包含GPU。[评论](https://github.com/exelban/stats/issues/3621#issuecomment-6155722895)。
10. linq0016 10-19：**M5 Mac17,2、27.0.1、Stats3.0.22**，旧prevCPU gate已不存在但CPU仍0，PMP裸组可用；不是官方Stats采用了其独立读数。[评论](https://github.com/exelban/stats/issues/3621#issuecomment-6260973785)。
11. sillygru 10-25：**Air M2、27.0.1**，CPU/DRAM/ANE/PCIe mJ原值跨idle/CPU/memory均不动，GPU nJ更新；RAM PP4b/PP9b仅本机负载相关性，不能通用。[评论](https://github.com/exelban/stats/issues/3621#issuecomment-6396476381)。

上述按主题归纳14条评论，并非声称只有11条。维护者没有在本帖宣布合并统一修复；本地checkout也仍用Energy Model。**状态：部分fork workaround；上游问题仍open。**

## 6. macpow 0.1.19 与 PR #21

README完整阅读。来源表 `repos/macpow/README.md:120-171` 标称CPU/GPU/ANE/DRAM均来自IOReport直接能量差分；源码比“direct hardware”宣传更具体。

### 6.1 采样与 SoC 计算

- `src/ioreport.rs:458-474` 订阅 `Energy Model` + CPU/GPU Stats + backlight；未订阅AppleCLPC，也无macOS27专用fallback。
- `src/ioreport.rs:530-538` `IOReportCreateSamples` 后记`Instant::now()`；`573-584`：`dt_ms=cur.ts.duration_since(prev.ts).as_millis()` + `IOReportCreateSamplesDelta`。
- `src/ioreport.rs:77-92`：

```rust
let dt_s = dt_ms.max(1) as f32 / 1000.0;
let per_sec = val as f32 / dt_s;
match unit {
  "mJ" => per_sec / 1e3,
  "uJ" => per_sec / 1e6,
  "nJ" => per_sec / 1e9,
  _ => 0.0,
}
```

- `src/ioreport.rs:698-746` 仅Energy Model：`ends_with("CPU Energy")`、`"GPU Energy"`、`starts_with("ANE")`、`DRAM`、`GPU SRAM`、ISP、DISP、PCI、AVE/MSR、AMCC/DCS/FAB/AFR分别累加。
- 默认250ms：`src/main.rs:23-25`；采样线程 `src/metrics.rs:1108-1126`，请求下限100ms。
- SoC不是另一个传感器；`src/types.rs:79-91` 原文：

```rust
self.total_w = self.cpu_w + self.gpu_w + self.ane_w + self.dram_w
    + self.gpu_sram_w + self.isp_w + self.display_soc_w
    + self.display_ext_w + self.pcie_w + self.media_w + self.fabric_w;
```

- `src/ioreport.rs:885`执行compute_total；SMC `PSTR`为整机，`src/smc.rs:597-600`；`src/metrics.rs:1188-1192`另存`sys_power_w=max(PSTR, soc.total_w)`。

所以当CPU/DRAM/ANE/fabric等冻结只留下GPU时，SoC≈GPU并可<1W。该结果是**缺失分项的和**，不是CPU真的0、DRAM真的0，更不是整机仅耗<1W。采样更快不自动修复计数器冻结。

### 6.2 PR #21：只警告，没有恢复数据源

URL：<https://github.com/k06a/macpow/pull/21>。作者apurvamarya，2026-10-16创建，检索时 **open、merged=false**；head=`1f47a41de82089a8b3248d3791cf0c07dae3a33f`、base=`696de22d87acb62fbdd306827fb72ea4a375e537`。正文保存在`pr21.json`，完整diff `pr21.diff`（185行）。

环境：**M5 Pro Mac17,9、macOS27 build26A434**。原文：

> “CPU, DRAM, ANE and fabric are not refreshed unless a privileged sampler such as powermetrics is running.”
>
> “GPU Energy keeps updating, so the GPU row still looks plausible.”
>
> “stay constant ... with and without sudo.”

其测试称powermetrics激活后CPU约330–570mW，对powermetrics打印约410mW；停止则冻结。**这是PR作者报告，不是本机实测。**

diff精读：

- `pr21.diff:77-98`：metrics新增`StallDetector`，每次IOReport power更新后调用`stall.update(&soc, dt.as_millis() as u64)`，暴露`energy_counters_stalled` JSON。
- `pr21.diff:115-145`：CPU/DRAM/fabric均`<=0.0`且累计4秒判stalled；任何一项>0立刻clear。**启发式，不检测raw timestamp，也不单独看ANE；不能当准确缺失判定器。**
- `pr21.diff:9-22`：新增troubleshooting让用户另开`sudo powermetrics --samplers cpu_power -i 1000`；本研究没有执行。
- 其他变化是footer文案和3个detector测试。**没有改IOReport计量公式，没有CLPC fallback。**

讨论完整性：issue conversation comments=0、review comments/threads=0（hasNextPage=false）、reviews=0；已用GitHub MCP核验。未发现维护者回应或已合并修复。REST后续遇到403 rate limit，转MCP及patch-diff归档，未用限流失败冒充无评论。

## 7. SMC 键语义表：源码事实与社区推断分开

强度定义：**strong**=至少两条独立实现/研究支持相同一般语义，仍非Apple官方硬件规格；**medium**=可追溯源码标签或有负载/对照数据，但机型或计量边界受限；**weak**=单次相关性/社区猜测，或模型不匹配。有源码的标签也可能只是社区逆向注释，不能升级为官方定义。

交叉来源至少包含：Asahi Linux driver/DTS、Chromium、macmon/macpow实现、Stats issue中的独立用户测量。**未能给每个键都找到两个独立、适用M3 Max的来源；下表逐一明确缺口，不凑证据。**

| 键 | 据称含义与原文 | 强度及本机边界 | 证据URL / 本地行号 |
|---|---|---|---|
| PHPC | Asahi驱动：“`an estimate of the heat energy being dissipated by the SoC`”；DTS label=`Heatpipe Power`。base M3社区表将PZC0/PHPC并列，GPU-only时约14W。 | medium；Asahi源码与独立base M3负载报告一致反对CPU-only，但未确认M3 Max的GPU包含比例/滤波时间窗。SoC热估计不能精确等同所有电轨之和。 | [driver](https://raw.githubusercontent.com/AsahiLinux/linux/master/drivers/hwmon/macsmc-hwmon.c)，本地`macsmc-hwmon.c:3-9`；[DTS](https://raw.githubusercontent.com/AsahiLinux/linux/master/arch/arm64/boot/dts/apple/hwmon-laptop.dtsi)，`hwmon-laptop.dtsi:9-12`；[base M3负载表](https://github.com/exelban/stats/issues/3621#issuecomment-6146808425)，`stats3621-readable.md:293`。 |
| PZC0 | 早期Stats#1712社区仅称ANE活动相关但idle约1.5W；base M4用户称CPU package；base M3/M5后续GPU-only也明显增加，称whole SoC。 | weak（M3 Max语义）；base M3/M5“非CPU-only”有medium负载证据。**不能采用CPU-only/ANE-only通用标签**。 | [#1712 ANE相关猜测](https://github.com/exelban/stats/issues/1712)；[base M4 patch说明](https://github.com/exelban/stats/issues/3621#issuecomment-5845048378)；[base M3反例](https://github.com/exelban/stats/issues/3621#issuecomment-6146808425)；[base M5 GPU反例](https://github.com/exelban/stats/issues/3621#issuecomment-6155722895)。归档`stats3621-readable.md:149,277-304,341-347`。 |
| PHPS | base M5报告PZC0“tracks PHPS”；GPU-only负载同时升，后续表将两者并列称whole SoC incl GPU（未证明逐bit恒等）。 | weak；仅base M5单一研究者，未找到独立源码定义，M3 Max UNKNOWN。 | [M5首报](https://github.com/exelban/stats/issues/3621#issuecomment-6101687692)、[同作者后续](https://github.com/exelban/stats/issues/3621#issuecomment-6155722895)；`stats3621-readable.md:219-240,347`。 |
| PSTR | Asahi `Total System Power`；Chromium `System Total Rail (watts)`；macmon和macpow直接作为整机W。 | strong（系统总功率一般语义）；不证明是墙端AC输入，是否含充电/外设输出、刷新/滤波窗口本机待定。 | [Asahi common](https://raw.githubusercontent.com/AsahiLinux/linux/master/arch/arm64/boot/dts/apple/hwmon-common.dtsi)，`hwmon-common.dtsi:9-12`；[Chromium](https://chromium.googlesource.com/chromium/src/+/refs/tags/122.0.6250.0/components/power_metrics/smc_internal_types_mac.h#17)，`chromium-smc.h:17`；macmon`src/metrics.rs:647-649`；macpow`src/smc.rs:597-600`。 |
| PDTR | Asahi `AC Input Power`；macpow `Power adapter`，读取后直接用W。 | strong（adapter输入一般语义）；**不是已证实墙插侧AC有功功率**，转换损耗边界未知。 | [Asahi](https://raw.githubusercontent.com/AsahiLinux/linux/master/arch/arm64/boot/dts/apple/hwmon-common.dtsi)，`hwmon-common.dtsi:13-16`；[macpow README](https://github.com/k06a/macpow/blob/696de22d87acb62fbdd306827fb72ea4a375e537/README.md#L154)，源码`src/metrics.rs:1179`。 |
| PDBR | macpow称M1–M4 XDR display/backlight rail；注释“Power Delivery Brightness”。PBwo失败时回退PDBR。Stats独立表也标签Power Delivery Brightness，但平台仅m1Gen+m4Gen。 | medium（社区源码标签两项目）；未找到Apple/独立标定证据，尤其Stats表未覆盖M3，M3 Max随亮度响应及是否含SoC display controller待测。 | [macpow源码](https://github.com/k06a/macpow/blob/696de22d87acb62fbdd306827fb72ea4a375e537/src/metrics.rs#L1172-L1178)，`README.md:131,152`；[Stats values](https://github.com/exelban/stats/blob/032f4a5e4cb9c11bc537c70a9487dfd904f2011d/Modules/Sensors/values.swift#L635)，本地`values.swift:635`。 |
| PP0b | base M3/M5用户：P-cluster rail；base M2也随CPU负载升。M5 Pro Mac17,8另一源码将它与PP4b列为Super cluster组合。 | medium（特定机型），M3 Max UNKNOWN。跨机型不是固定“完整CPU”。 | [base M3](https://github.com/exelban/stats/issues/3621#issuecomment-6146808425)、[独立base M5](https://github.com/exelban/stats/issues/3621#issuecomment-6155722895)、[base M2](https://github.com/exelban/stats/issues/3621#issuecomment-6396476381)；[siltop源码](https://github.com/CLoaKY233/siltop/blob/c2dab6b584389587417a63121e7a7a174bb43da6/crates/siltop-metrics/src/smc_keys.rs#L210-L223)，本地`siltop-smc_keys.rs:218-223`。 |
| PPbb | base M3和独立base M5负载对照称E-cluster；base M2报告一致相关性。 | medium（base M3/M5）；M3 Max键是否存在/哪条rail UNKNOWN。不能把base三轨sum直接移植。 | 同上base M3/M5/M2评论；`stats3621-readable.md:282,343-345,415-418`。有fork方案，当前Stats源码没有通用定义。 |
| PP7b | base M3/M5用户称CPU SRAM，随P负载；siltop仅Mac17,8将PP1b+PP7b组合为一个Performance cluster。 | medium（机型内组合），具体芯片电路语义来自逆向，不是Apple官方。M3 Max UNKNOWN。 | base M3/M5评论同上；[siltop exact-model table](https://github.com/CLoaKY233/siltop/blob/c2dab6b584389587417a63121e7a7a174bb43da6/crates/siltop-metrics/src/smc_keys.rs#L210-L232)。 |

SMC**数据类型**与**物理单位**是两回事。macmon `src/sources.rs:1593-1627` 先keyinfo，再selector2结构调用，读取command5，要求size4/type`flt `并用`f32::from_le_bytes`；这只确定float编码。各P键的W解释依赖以上语义证据/本机核对，不能仅凭flt断言是W。具体源代码：<https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/sources.rs#L1593-L1627>。

## 8. Lead补查：USB输出与 AppleSmartBattery 电池遥测

### 8.1 PowerOutDetails.Watts / PDPowermW

macpow源码 `src/battery.rs:155-201`：<https://github.com/k06a/macpow/blob/696de22d87acb62fbdd306827fb72ea4a375e537/src/battery.rs#L155-L201>

```rust
let watts_mw = cf_utils::cfdict_get_i64(d, "Watts").unwrap_or(0);
let pd_mw = cf_utils::cfdict_get_i64(d, "PDPowermW").unwrap_or(0);
let power_mw = if watts_mw > 0 { watts_mw } else { pd_mw };
let watts = power_mw as f32 / 1000.0;
```

README:171称“Per-port power measurement (Watts/PDPowermW)”。独立社区gist [robzr, 2024-02-19](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48)同样用 `.PowerOutDetails[].Watts/1000`，同时显示AdapterVoltage/1000和Current/1000。该gist**没有校准、字段合同或driver溯源**，也没有证明PDPowermW可替代Watts。

另外[whatcable#95](https://github.com/darrylmorley/whatcable/issues/95)把它描述为per-port live telemetry，并征集多代机器dump，称有活跃端口也可能缺失。属于第三方研究描述，没有拿到Apple驱动层定义。

**结论：mW解释有两个第三方实现支持，强度medium；Watts实际输出/平均值/请求功率/预算，以及PDPowermW的协商或测量性质均UNKNOWN。不得在Status Trio产品里先称“实际USB输出功率”。本机缺键应显示unavailable，不能0。**更不能把`AdapterDetails.Watts`等同该字段：macpow `battery.rs:135`读AdapterDetails.Watts时没有/1000，显然是另一上下文。

### 8.2 PowerTelemetryData

唯一检索到解释单位的独立资料：[Apple StackExchange 455157](https://apple.stackexchange.com/questions/455157/looking-for-a-way-to-read-out-battery-and-poweradapter-information-via-ioreg)，2023-02-20问答。原文自称“`for almost all values you might assume the prefix of milli`”；以`SystemInputVoltage`、`SystemInputCurrent`乘积/1000近似`SystemPowerIn`解释mV/mA/mW，并称AccumulatedSystemEnergyConsumed是J，后者未给Apple源码依据。

另[ireg Rust crate字段结构](https://docs.rs/crate/ioreg/latest/source/src/apple_smart_bettery.rs)只列u64字段，没有物理单位或时间窗，不能算单位证据。

- `SystemPowerIn ≈ SystemVoltageIn × SystemCurrentIn / 1000` 的mW判断：**可作为本机算术交叉验证断言**，不是公开API合同。字段名旧文为SystemInputVoltage/Current、本机可为SystemVoltageIn/Current，不应混淆。
- `SystemLoad`边界是否排除充电/USB输出、`BatteryPower`符号和合计关系：UNKNOWN。
- `AdapterEfficiencyLoss` 是mW损耗、某区间能量还是估算项：UNKNOWN。
- `WallEnergyEstimate` 是否mJ、J或其他积分窗口：UNKNOWN。不能因为名字含Energy就按J，更不能直接W。
- Accumulated字段自何时复位、每次累积单位、AccumulatorCount与实际周期关系：UNKNOWN。
- Lead已观测约60秒刷新：作为**Lead本机观察**可记录，不由社区资料推导，也不代表每台Mac固定60秒。需要value-age/重复值标识，不能拿它做1秒瞬时分解。

## 9. 交给本机实验的断言清单

1. **CLPC ID对27.2仍正确？**本机bundle、DriverID、三个report ID、descriptor type/unit、订阅返回码、raw counter与driver timestamp分别记录；不要把人工标签当原生枚举结果。
2. **CLPC是否真动态？**CPU/GPU/ANE分别看raw counter变化、变化节奏与有效Δt；ANE空闲不变只能记“未观察到增长”，不能说不支持。读者不提权与普通用户权限状态要留证据。
3. **Energy Model冻结范围？**按driver、channel、unit、timestamp、raw counter列出CPU Energy、E/P各核/集群、DRAM、ANE、GPU(mJ/nJ分别)、GPU SRAM、其他已发现通道。区分不存在、读取失败、零计数、计数冻结、合法零增量。
4. **Δt与批量刷新？**同一通道时间戳长时间不变后跳变，是否跟能量一起跳？按本机观察验证能量是否能用publication-to-publication长窗计算；不能把全部能量落入一个短interval。
5. **CLPC缩放与边界？**负载实验验证CPU/GPU分离响应；CLPC GPU能量与仍有效AGX GPU Energy对照；CPU与SMC只能交叉看趋势，未经参考校准不要断言绝对误差。
6. **PHPC是否含GPU？**单CPU、单GPU、混合与恢复对照；是SoC热功率估计还是电功率，时间常数是否显著？源码只给一般标签。
7. **PZC0/PHPS是否相同、含GPU/ANE/其他？**基础款评论不适用本机M3 Max；比较同周期raw float及负载相应，不以键名直接命名CPU。
8. **PP0b/PPbb/PP7b是哪些rail？**固定候选键存在性与type先检查，不扫描全表；PPbb缺失应记unavailable。若只有部分rail，禁止把部分和叫CPU total。
9. **PSTR/PDTR边界？**电池、AC、充电、USB输出情形由Lead安排可控对照；是否充电含在PSTR、是否PDTR输入DC端、是否各有滤波和刷新差异，均待证。不能用max(PSTR,SoC)掩盖两个测量边界。
10. **PDBR亮度响应？**恒定负载改变亮度后测差，是否仅背光，是否受HDR影响，是否独立于Energy Model DISP；不把两个来源重复求和。
11. **USB字段若出现？**同时记录Watts/PDPowermW/Current/AdapterVoltage/PortIndex；实测电压×电流是否匹配、协商不变而负载变时是否变化。未测前实际vs协商保持UNKNOWN。
12. **PowerTelemetryData更新周期/边界？**对SystemPowerIn与V×I/1000做近似检查；用单调时钟记录何时变值及AccumulatorCount增长，重复读不得视为新样本。AdapterEfficiencyLoss/WallEnergyEstimate没有证实单位前保持raw，不参与W合计。
13. 温度只能作热状态参考：Stats `Modules/Sensors/values.swift:429-451` M3表明确 `Te05`=ECPU1、`Tf04`=PCPU1、`Tf14`=GPU1，可固定少量候选，不扫描。温度相关性不是功率绝对校准。

## 10. UNKNOWN / NOT FOUND 与研究限制

- Apple官方关于所有9个SMC键的硬件/计量边界规范：NOT FOUND。PHPS未满足两个独立定义来源；PHPC有源码与base M3社区负载报告但M3 Max边界不明；PDBR虽有两项目社区标签，仍没有适用M3 Max的计量标定。
- Mac15,9 M3 Max CPU-only SMC精确rail集合、PHPC的GPU比例、PHPS/PZC0物理边界：UNKNOWN。
- AppleCLPC mapping跨27.2固件是否稳定、真实硬件缩放误差、ANE是否有效：需本机证据。本档案只证明当前上游实现、Apple unit编码和公开反馈。
- `~pkg-power-split-cpu/gpu/ane-fraction` 的算法、定点比例、能否用于按PHPC拆分：UNKNOWN。轻量ioreg读到CPU/GPU=29491、ANE=6553，不足以把这些常量当实时占比，本文不提出乘法模型。
- Stats官方统一macOS27修复：当前代码/issue未找到；macpow PR21未合并；不能以有fork patch宣称上游已修复。
- macOS27.2 Apple是否修复Energy Model：base M3的27.2 beta (26B5086k)仍有冻结报告；本机27.2 (26B123)是否如此，UNKNOWN，由本机实验决定。
- powermetrics精确内部模型和私有entitlement协议：README为维护者结论，旧26.5.2trace可证明IOReport订阅，但本研究没有反汇编本机powermetrics或验证Apple授权合同。
- 当前macmon README无独立FAQ；已完整读README及issue76全文；没有虚构“FAQ维护者说”。
- GitHub REST后段403限流，代码用raw、git、MCP或patch-diff补读。issue76九条、Stats3621十四条评论已在限流前完整归档；PR21讨论用MCP核验为空。搜索覆盖不等于全GitHub穷举。
- 网络Asahi材料按取得内容归档，raw master为可变URL；Chromium用固定tag，siltop用固定SHA，三个主要项目用固定SHA。本机没有运行上游工具的load命令或文档中的sudo/SIP操作。

## 11. 原始资料索引

- `repos/macmon/`、`repos/macpow/`、`repos/stats/`：源码checkout。
- `issue76.json`、`issue76c.json`、`issue76-readable.md`：macmon issue正文+9评论。
- `stats3621.json`、`stats3621c.json`、`stats3621-readable.md`：Stats正文+14评论。
- `pr21.json`、`pr21.diff`：macpow PR正文与完整diff。
- `macmon-082-metrics.rs`、`macmon-082-sources.rs`：旧版本raw源码。
- `IOReportTypes.h`：Apple XNU单位定义；`macsmc-hwmon.c`、`hwmon-laptop.dtsi`、`hwmon-common.dtsi`：Asahi语义；`chromium-smc.h`：独立PSTR W标签；`siltop-power.rs`、`siltop-smc_keys.rs`：固定SHA机型表。

操作纠正记录：最初并行clone的shell工作目录作用域使一份**干净的、此次新建的**macpow clone落在工作区根目录；核实remote/status/绝对路径后已整体移至本研究 `/tmp/.../repos/macpow-extra-clone`，未改任何原有仓库文件。此后所有持久材料均在/tmp。该额外clone不是另一版本，不作为独立证据。
