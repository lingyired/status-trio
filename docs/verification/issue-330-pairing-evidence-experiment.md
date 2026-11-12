# Issue #330 配对状态证据实验：IOBluetooth 只读对照

- 时间：2026-11-12（Asia/Shanghai）
- worktree：`.agents/worktrees/fix/330-bluetooth-unpair-consistency`，基线与 `origin/main` 同为 `a6a7ab01`
- 实验脚本：`scratch/issue330-pairing-probe.swift`（一次性只读脚本，位于 git ignore 的 `scratch/` 下，未纳入版本库；可用 `swift scratch/issue330-pairing-probe.swift` 复跑）
- 关联文档：[issue-330-bluetooth-regression-audit.md](issue-330-bluetooth-regression-audit.md)（Phase 0 历史审计）、[bluetooth-stale-state-investigation.md](bluetooth-stale-state-investigation.md)
- 性质：**只读**可行性实验。未改任何生产代码/测试，未对任何真实设备做取消配对或重新配对。

## 0. 结论先行（TL;DR）

- IOBluetooth 的 `pairedDevices()` + `isPaired()` 在本机（macOS 27.3）**可以正常只读枚举**，速度快（单次约 60–80ms），能在进程外、后台队列上稳定运行；本次运行未见 TCC 弹窗或权限错误，无签名命令行工具即可读。
- 但本次采样**没有复现 #330 的目标形态**（“profiler 仍列出、配对库里已不存在”）：7 个去重设备在 profiler 和 IOBluetooth 两侧**完全一致**，全部 `isPaired() == true`。因此**“IOBluetooth 能可靠识别已删除残留”只得到静态可行性判断，未得到真机实证**。
- 结论：**不建议把 IOBluetooth 结果直接当生产过滤真源**。建议“保留 `system_profiler` 为主来源，IOBluetooth 只做非破坏性诊断证据（先记录/日志，最多在严格门控下做保守过滤）”。理由见 §5。

## 1. 实验方法与运行环境

### 1.1 对比的三个来源

1. **`system_profiler -json SPBluetoothDataType`**：App 现有的配对设备主来源，解析逻辑对照 `BluetoothDeviceController.swift` 的 `BluetoothPairedDeviceReader.parse`（`device_connected` / `device_not_connected` 两段，按规范化地址去重）。
2. **`IOBluetoothDevice.pairedDevices()`**：系统配对数据库枚举。
3. **每个 device 的 `.isPaired()` / `.isConnected()`**：对枚举对象读取；对 profiler 独有地址用 `IOBluetoothDevice(addressString:)` 构造一个**内存对象**再读 `isPaired()`（构造器无 I/O，不连接）。

关联身份一律用**规范化蓝牙地址**（等价于 `BluetoothBatteryReader.normalizedAddress`：只保留十六进制字符并转大写），不以名称作主身份。

### 1.2 只用到的只读 API

- `IOBluetoothDevice.pairedDevices()`
- `IOBluetoothDevice.isPaired()`、`isConnected()`
- `nameOrAddress`、`addressString`、`deviceClassMajor`、`deviceClassMinor`
- `IOBluetoothDevice(addressString:)`（仅构造内存对象）

### 1.3 明确禁用的 API（脚本中未出现）

`pair()`、`removePairing()`、`performSDPQuery`、`openConnection`、任何扫描 / GATT 写入 / 忽略设备 / 修改系统设置的调用。脚本不常驻、不装东西。

### 1.4 运行环境

| 项 | 值 |
|---|---|
| 机型/系统 | macOS 27.3（Build `26C5035r`，`sw_vers`） |
| 运行方式 | `swift scratch/issue330-pairing-probe.swift`（解释执行，退出码 0）；另以 `swiftc -O` 编译运行同样通过 |
| 工具身份 | 无签名命令行工具（非主 App 进程）；本次未见 TCC 弹窗/权限错误 |
| 是否有配对设备 | **有**。profiler 7 条、IOBluetooth 去重后 7 个，全部为已配对设备 |
| 脚本超时保护 | 内置 15s watchdog，超时强制退出；实测整体运行约 0.2–0.4s |

> 地址脱敏：下文所有地址只保留末 4 位十六进制，其余以 `****` 代替；不记录完整地址或序列号。

## 2. 原始对照结果

### 2.1 profiler（`system_profiler -json SPBluetoothDataType`）

| 名称 | 地址(****) | 段 | minorType | services |
|---|---|---|---|---|
| HECATE G3M Pro | `****7473` | device_connected | Mouse | `0x400020 < HID BLE >` |
| MX Keys | `****A32E` | device_connected | Mouse | `0x400020 < HID BLE >` |
| Ling's 13T | `****B9E2` | device_not_connected | Mobile Phone | - |
| Lingsipad | `****1DAD` | device_not_connected | -（缺 `device_minorType`） | - |
| M585/M590 | `****6D02` | device_not_connected | Mouse | - |
| OPPO Enco Air4i | `****CAF0` | device_not_connected | Headset | - |
| 机灵的AirPods | `****9C1F` | device_not_connected | Headphones | - |

### 2.2 IOBluetoothDevice.pairedDevices()（原始 8 条，含 1 条重复地址）

| nameOrAddress | 地址(****) | isPaired | isConnected | class(major/minor) |
|---|---|---|---|---|
| Ling's 13T | `****B9E2` | true | false | 2/3 |
| OPPO Enco Air4i | `****CAF0` | true | false | 4/1 |
| 机灵的AirPods | `****9C1F` | true | false | 4/6 |
| Lingsipad | `****1DAD` | true | false | 0/0 |
| MX Keys | `****A32E` | true | **true** | 0/0 |
| M585/M590 | `****6D02` | true | false | 0/0 |
| HECATE G3M Pro | `****7473` | true | **true** | 0/0 |
| Ling's 13T（重复） | `****B9E2` | true | false | 2/3 |

- 连接状态与 profiler 一致：profiler 标为 connected 的正是 MX Keys 与 HECATE G3M Pro。
- **枚举内出现重复地址**：`****B9E2` 出现 2 次（同一设备两次）。生产若用此来源必须先按规范化地址去重。

### 2.3 三态配对证据对照（按规范化地址关联）

`class` = IOBluetooth `deviceClassMajor/minor`；`0/0` 表示经典设备类未上报（常见于 BLE HID 或未分类条目）。

| 地址(****) | profiler 段/名称 | IOBT paired/conn | 三态证据 | class | 说明 |
|---|---|---|---|---|---|
| `****B9E2` | N / Ling's 13T | T/F | paired | 2/3 | 枚举到且 `isPaired=true` |
| `****1DAD` | N / Lingsipad | T/F | paired | 0/0 | 枚举到且 `isPaired=true`（profiler 无 minorType） |
| `****CAF0` | N / OPPO Enco Air4i | T/F | paired | 4/1 | 一致 |
| `****9C1F` | N / 机灵的AirPods | T/F | paired | 4/6 | 一致 |
| `****A32E` | C / MX Keys | T/T | paired | 0/0 | 一致；BLE HID |
| `****7473` | C / HECATE G3M Pro | T/T | paired | 0/0 | 一致；BLE HID |
| `****6D02` | N / M585/M590 | T/F | paired | 0/0 | 一致 |

**构造式只读查询 vs 枚举**：对上述 7 个 profiler 地址逐个构造 `IOBluetoothDevice(addressString:)` 再读 `isPaired()`，与枚举结果的 `isPaired` **7/7 全部一致**（0 处不一致）。

## 3. 三态判定覆盖率

| 指标 | 数值 |
|---|---|
| profiler 去重地址数 | 7 |
| IOBluetooth 去重地址数 | 7 |
| 两侧交集 | 7 |
| profiler 独有（仅有 profiler、IOBluetooth 未枚举） | **0** |
| IOBluetooth 独有 | 0 |
| 三态：`paired` | **7** |
| 三态：`unpaired-evidence`（未枚举 + 二次查找 `isPaired=false`） | **0** |
| 三态：`unknown`（构造失败/异常） | **0** |

- 覆盖率：本次 7/7 设备都能**可靠判定为 paired**；因为没有未配对/残留样本，`unpaired-evidence` 与 `unknown` 分支**只验证了代码路径可达**，没有真实样本。
- 三态定义：
  - `paired`：IOBluetooth 枚举到且 `isPaired=true`。
  - `unpaired-evidence`：未枚举到，且只读二次查找 `isPaired=false`。这是 #330 想要的“配对库里已没有”的证据形态。
  - `unknown`：构造失败或调用异常，无法判断。
- **#330 目标形态未复现**：本次没有任何“profiler 列出、IOBluetooth 配对库未枚举”的设备。“系统设置删除后 profiler 仍短暂/持续列出”这一现象在采样期间不存在，故无法用真实删除场景验证 IOBluetooth 的识别能力。

## 4. 关键观察

1. **经典 vs BLE HID 的差异**
   - 2 个 BLE HID 设备（MX Keys、HECATE G3M Pro，profiler `services` 为 `HID BLE`）**确实出现在** `pairedDevices()` 中且 `isPaired=true`，但它们的 `deviceClassMajor/minor` 都是 `0/0`——IOBluetooth 的经典设备类字段对 BLE HID 无意义。也就是说：**BLE HID 的配对状态本身可读，但不能靠 `deviceClass` 判类型**；类型应继续用 profiler 的 `device_minorType`。
   - 本机没有“经典 BR/EDR HID”样本（纯经典 HID 条目数 0），无法在本次数据里对比经典 HID 与 BLE HID 的枚举差异。
2. **枚举重复**：`pairedDevices()` 返回了重复地址（`****B9E2` 两次），生产使用需去重。
3. **`profiler 无分类` ≠ `未配对`**：`Lingsipad` 在 profiler 中既无 `device_minorType` 也无 `device_minorClassOfDevice_string`，按现有 `isGhost(properties:)` 会判为 ghost（`isGhost=true`）；但 IOBluetooth 明确 `isPaired=true`。现有 `filteredDevices` 会**无条件**丢弃这类 `isGhost` 条目（见 Phase 0 审计）。这可能是有意的（iPad 由 Apple/iCloud 来源另行呈现），**不必然是 bug**，但它证明“profiler 没有分类字段”不能推出“没有配对”。反过来说，这是 IOBluetooth 交叉验证的一个**正面用例**：能区分“未分类但已配对”和“真·未配对残留”。是否误伤需与现有 ghost 过滤策略一起核对。
   - 另需注意 Phase 0 审计的关键结论：**曾配对后在系统设置删除**的设备通常仍带 `device_minorType`，`isUnpairedGhost == false`，因此**不会**被 ghost 过滤——这才是 #330 的缺口形态。理论上 IOBluetooth 的“未枚举 + `isPaired=false`”信号正好能覆盖这种“有分类但已不在配对库”的情形；但本次没有真实删除样本，**该覆盖能力仍是静态推断，未证实**。
4. **枚举与 profiler 的 freshness 无法在本实验区分**：两者在采样时点完全一致；#330 中究竟是 profiler 陈旧还是配对库陈旧，只有真实“删除设备再看两侧”才能定论，而该操作属破坏性，未执行（见 §7）。

## 5. 明确结论与生产建议

**能否用于生产过滤：不能直接把 IOBluetooth 结果当硬过滤真源；建议保留 `system_profiler` 为主来源，IOBluetooth 只做非破坏性诊断证据。**

理由：

1. **BLE / 经典配对模型差异**：IOBluetooth 面向经典设备模型。本次 macOS 27.3 上 BLE HID 能被枚举，但**更老的 macOS（项目最低 13）或不同芯片/驱动下 BLE-only 绑定是否稳定出现，未验证**。一旦某个已配对 BLE 设备不被 IOBluetooth 枚举，就会被误判成 `unpaired-evidence` → 误删正常设备行。这是硬过滤的最大风险。
2. **系统已连接/已信任设备可能枚举不全**：第三方 USB/PCIe 蓝牙适配器、Continuity/Handoff、多控制器等场景，`pairedDevices()` 是否覆盖全部已配对设备没有证据；本次只有一台内置控制器（`BCM_4388`）样本。
3. **权限与运行条件不可控（未验证）**：本次是无签名 CLI，运行时未见 TCC 弹窗或权限错误即可读（不等于已授权/未授权，仅代表本次可读）；但 App 内（蓝牙 TCC 被拒/未决）、**蓝牙关闭**、未来若启用 App Sandbox 时 `pairedDevices()` 的行为**未验证**。若蓝牙关闭或权限被拒时它返回空数组，会把**所有** profiler 设备判成 `unpaired-evidence`——用作硬过滤会瞬间清空列表。**这是必须门控的条件**。
4. **“删除即消失”的语义未证实**：删除配对记录理应让 `pairedDevices()` 不再列出，但本次没有真实删除样本；“profiler 陈旧 vs 配对库也陈旧”无法排除。静态度看合理，实证缺失。
5. **枚举会出现重复与 `0/0` 类信息**：需按规范化地址去重；`deviceClass` 对 BLE HID 不可靠，不能替代 profiler 的类型字段。
6. **新增框架依赖**：当前工程（`Sources/`）**未导入 `IOBluetooth`**，引入即新增一个系统框架依赖与相应验证面（最低 macOS 13 兼容、Release 构建链接）。

**若后续确要用于生产，最低限度门控（建议先只记录、不隐藏）**：

- 仅在 CoreBluetooth 状态为 `poweredOn` 且已授权时采信 IOBluetooth 结果；否则一律 `unknown`，不参与过滤。
- `pairedDevices()` 返回空时视为“不可用”，不当“全部未配对”。
- 只对 profiler 判为**纯经典**（`services` 含 HID 但不含 BLE）的设备把“未枚举”当作弱证据；BLE/BLE HID 设备一律降级为 `unknown`。
- 先按地址去重；`isPaired` 与枚举缺失分开记录，日志先行、观察一段再决定是否隐藏。
- 与现有 `isGhost` 过滤、缓存成功读替换、120s 兜底轮询的约束一起评审，别让新路径绕过 `refresh()` 的合并/看门狗/token 守卫。

**替代/补充建议**：对 #330，先修“成功读覆盖缓存 + `.failed` 保留旧列表的边界提示 + 删除后事件驱动的立即重读（复用 `refresh()`）”，这些是确定性行为；IOBluetooth 只作为诊断旁证（例如设置里的“诊断信息”或开发日志），不承担“判定是否配对”的对外承诺。

## 6. 性能 / 资源评估

| 指标 | 实测 |
|---|---|
| `system_profiler -json SPBluetoothDataType` 单次 | 约 **0.13–0.23s**（多次采样） |
| `IOBluetoothDevice.pairedDevices()` 单次 | 约 **0.058–0.079s**（多次采样） |
| 20 次连续枚举（后台 `DispatchQueue` qos=.utility） | 最差单次 **0.0689s**，计数稳定 8，无卡死/超时 |
| 脚本整体（含解析、二次查询、打印） | 约 **0.2–0.4s** |

- 单次枚举与一次 `system_profiler` 同量级（甚至更快），**在既有读取周期内加做一次 IOBluetooth 枚举在时间上可承受**。
- 后台队列调用正常，未观察到必须主线程/主 RunLoop；对主线程阻塞风险低（仍建议放在现有 utility 队列 worker 内，且带超时）。
- IOBluetooth API 本身**不提供超时参数**，阻塞时间不可控是理论风险；本次 20 次均 < 70ms，未见异常。作为诊断路径可接受；作为同步硬过滤需自带超时/降级。
- 注：上表“20 次连续枚举”为另做的独立小探针（同一 `pairedDevices()` 代码路径、后台 `DispatchQueue`），不在交付脚本内；交付脚本本身每次只跑一次枚举。

## 7. 未执行 / 未验证项（如实标注）

- **未执行**任何 `pair()` / `removePairing()` / 取消配对 / 重新配对 / 忽略设备 / 扫描 / GATT 写入 / 改系统设置的操作。**破坏性验证不在本次只读实验范围**，因此“IOBluetooth 能否识别真实删除后的 profiler 残留”只有静态可行性判断，无真机实证。
- 未验证：蓝牙**关闭**时 `pairedDevices()` 的行为；蓝牙 TCC 被拒/未决时的行为；App Sandbox（当前主 App 无 `app-sandbox` entitlement）下的行为。
- 未验证：macOS 13/14/15/26 等其他版本；第三方蓝牙适配器；多控制器；纯经典 HID 设备。
- 未验证：`pairedDevices()` 是否覆盖所有已配对设备（如 Continuity/iCloud 关联设备是否被计入）。

## 附录 A：脚本输出摘录（地址已脱敏）

```
===== 1. 运行环境 =====
macOS: 27.3.0  (ProcessInfo)
sw_vers: ProductName:  macOS | ProductVersion: 27.3 | BuildVersion: 26C5035r
进程是否为主 App 以外的无签名命令行工具: 是（swift 解释/编译产物）

===== 2. system_profiler -json SPBluetoothDataType =====
耗时: 0.141s  字节数: 2471
解析: OK，条目数: 7
（7 条设备见 §2.1）

===== 3. IOBluetoothDevice.pairedDevices() =====
耗时: 0.0612s  枚举条目数: 8
（8 条含 1 条重复地址见 §2.2）
IOBluetooth 枚举内重复地址数: 1
  ****B9E2 出现 2 次

===== 4. 三态配对证据对照 =====
（见 §2.3，7 个去重地址全部 paired）

===== 4b. 只读二次查找控制组 =====
合成地址 ****0001  nameOrAddress=02-00-00-00-00-01  isPaired=false  isConnected=false
（该地址不对应任何真实设备，仅确认 unpaired-evidence 分支的只读路径可达）

===== 5. 覆盖率与一致性统计 =====
profiler 去重地址数: 7
IOBluetooth 去重地址数: 7
两者交集: 7  profiler 独有: 0  IOBT 独有: 0
三态覆盖: paired=7  unpaired-evidence=0  unknown=0
本次采样中未发现「profiler 列出、IOBluetooth 未枚举」的设备（#330 目标形态未复现）。
profiler 称 connected 但 IOBluetooth 不能确认 paired 的设备数: 0
profiler 侧 BLE HID 条目数: 2  纯经典 HID 条目数: 0

===== 6. 性能评估 =====
system_profiler 单次耗时: 0.141s
IOBluetoothDevice.pairedDevices() 单次耗时: 0.0612s
脚本整体（含编译外运行）: 0.314s
```

> 说明：报告中的耗时来自多次运行采样，单条数值为其中一次代表值；范围见 §6。
