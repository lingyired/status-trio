# 红米 / 小米耳塞聆听模式接入（交付说明）

日期：2026-11-09
分支：`codex/redmi-listening-mode`（worktree：`.agents/worktrees/codex/redmi-listening-mode`，基于 `main`）

## 结论先行

把朋友给的红米「聆听模式」app（`RedmiBudsMac 0.2.0`，源码在
`/Users/lingsmbp/Documents/RedmiBudsMac-0.2.0-交付包-20261106-095354/`）的
**降噪 / 通透 / 关闭三模式切换**协议，提取并接进了 status-trio 现有的聆听模式面板，
作为**第三种设备族**（前两种是 AirPods 的 CoreAudio、华为 FreeBuds 的 SPP）。

红米和华为是同一类东西：都是蓝牙耳塞，通过 IOBluetooth 的 RFCOMM 厂商通道读写噪声模式，
只切换耳塞自带的三种模式。

**注意：这台 Mac 上没有红米耳机，无法做真机联调。** 协议层、设备识别、面板接入、
状态机都已用单元测试覆盖并通过；真机连接与切换需要你明天用红米耳机实测。

## 移植了什么

红米参考 app 的功能里，status-trio 已经有等价能力的（系统音量滑条、左右耳/充电盒电量）
不再重复实现——status-trio 本身就有全设备电量与音量控制。真正需要「提取兼容」的是
**耳塞三模式聆听控制**：

| 组成 | 文件 | 说明 |
| --- | --- | --- |
| 协议引擎 | `Sources/StatusTrioCore/Audio/RedmiListeningModeProtocol.swift` | 帧编解码（`FE DC BA … EF`）、状态机、TLV 解析、认证算法（移植自 Apechi/XiaomayEarbudsWin `bt/auth.rs`，MIT） |
| 控制会话 | `Sources/StatusTrioCore/Audio/RedmiControlSession.swift` | 把 IOBluetooth 事件回调桥接成一次性的 `async` 结果：SDP 找 `FD2D` 服务 → 开 RFCOMM → 挑战握手 → 读/写模式 → 关通道 |
| 传输层 | `Sources/StatusTrioCore/Audio/RedmiListeningModeTransport.swift` | 实现与华为对称的 `state/setMode/closeAll` 接口；设备查找、错误类型、模式映射 |
| 设备识别 | `Models/WiFiNetworkModels.swift` 的 `isRedmiAudio` | Xiaomi 公司 ID `0x2717` 为主，名称（redmi/xiaomi/buds 8）兜底，失败即不显示控制 |
| 面板接入 | `Audio/BluetoothListeningModeController.swift` | 新增 `refreshRedmi` / `setRedmiMode` / `redmiAddresses` / `stop()` 清理，写法照华为分支；红米也做 CoreAudio 输出端点解析，从而在新版 UI 上像华为一样内联显示在音量行 |
| UI | `UI/BluetoothDeviceRow.swift`、`UI/BluetoothDeviceList.swift`、`Presentation/Panel/StatusPanelViewModel.swift` | 红米复用新版胶囊聆听控件（`BluetoothListeningModeControl`）；有输出端点时显示在音量行，无端点时回退到蓝牙设备行；并参与刷新触发 |

## 与新版聆听 UI 的兼容

`main` 已经把聆听模式控件重做成**胶囊式**，并且 AirPods 在音量（输出）行内联展开。红米这次对着新 UI 做了对齐：

- 红米复用同一套胶囊控件 `BluetoothListeningModeControl`，不再有旧样式。
- 增加 CoreAudio 输出端点解析（复用与华为同一个按地址/名称匹配的解析器）。当红米耳机正作为系统输出时，控制**内联显示在音量行**（和新 UI 一致）；解析不到端点时回退到蓝牙设备行。
- 端点解析到后，音量行独占该控制，蓝牙行不再重复显示（与华为语义一致）。
- `supportsAirPodsSystemControls` 只对真正的 AirPods 机型为真，红米不会误走到 AirPods 专属的空间音频/对话感知分支，只显示三模式胶囊。

## 协议要点（与红米源码一致）

- 控制通道：SDP 服务 UUID `0xFD2D`，非标准 SPP（华为用的是 `0x1101`）。
- 帧格式：`FE DC BA | type | opcode | len(2, BE) | [status] | seq | payload | EF`，
  `type` 的 `0x40` 位区分请求/响应。
- 认证：`0x50` 随机挑战 → 响应 `0x51 [1,0]` → 认证完成；之后设备还会下发 `0xC4`
  类型的 `0x50` 挑战，需要用 `auth.rs` 算法应答。
- 模式：写 `0x08 [2,4,mode]`，读 `0x09 [255,255,255,255]`；
  模式值 `off=0 / 降噪=1 / 通透=2`；状态从 `0x02/0x09/0x0E/0xF4` 报文的 TLV 里解析。
- 成功判定：只认「设备回报的模式 == 请求模式」，写成功本身不当作确认（和华为、AirPods 一致）。

## 验证

已通过（本机、无红米耳机）：
- 红米协议与认证单测 **21 项全通过**，含：
  - 上游 `auth.rs` 的 4 组认证对照向量；
  - 帧编解码、每个分片点的分片重组、噪声/坏帧重新同步、载荷内帧头；
  - 完整认证握手序列（含认证后 `C4` 挑战）；
  - 三种模式命令、电量 TLV、失败响应忽略、截断 TLV；
  - 2000 段固定种子异常输入不崩溃、不挂起；
  - `isRedmiAudio` 识别（公司 ID / 名称兜底 / 非音频设备 / 不误判华为）；
  - Controller 集成：红米控制出现在蓝牙行、setMode 走 transport 并确认、写入失败回滚、
    transport 失败即不显示控制、stop 清理并关闭 transport。
- 既有聆听模式 / AirPods / 华为相关测试 **90 项全通过**（确认没破坏现有设备族）。

待你验收（需要真机）：
- 红米耳机实际连接、认证握手、三模式实际切换、回读确认；
- 耳机长按等外部操作后状态是否同步；
- 其他固件 / 型号的兼容性。

## 明天怎么测

1. 在「系统设置 → 蓝牙」里连上红米耳机（名称含 Redmi / Xiaomi）。
2. 用这个 worktree 构建开发版：`bash scripts/build-worktree.sh`（会生成带分支开发标识的独立 bundle）。
3. 打开蓝牙面板，红米耳机那一行下面应出现「降噪 / 通透 / 关闭」三个胶囊。
4. 点一下切换，胶囊应显示确认后再落在目标模式；若耳机没回报，会回滚。
5. 如果没出现胶囊，多半是 SDP 没查到 `FD2D` 服务——可先关掉手机上的小米耳机 App / 手机蓝牙，
   只让耳机连 Mac 后重试（红米源码的验证记录里也是这个经验）。

## 已知边界

- **采用持久长连接**（对齐红米参考实现）：首次读/写时打开 `FD2D` 控制通道并完成一次认证，之后
  保持连接、持续接收耳机状态通知并回复 ACK，后续读/写复用同一会话；断线后下次请求自动重连。
  这样在手机连上耳机时仍能握住控制通道、不被手机抢走控制权。
- **连接作用域**：按你的选择，连接在「耳机仍连着这台 Mac」期间持续保持——关闭状态面板不会断开，
  因此在面板之间仍持有控制权。释放时机：关闭聆听总开关、应用退出、或耳机断开（其会话在下次刷新时回收）。
  注意这会在面板关闭后仍占用一条蓝牙控制通道，属于明确选择的产品行为（已记录）。
- 只做三模式切换，不做降噪/通透档位、均衡器、手势等（和红米参考版一致）。
- 未提交、未合并；等你验收通过后再合并。
