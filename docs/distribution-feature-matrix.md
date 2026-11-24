# Status Trio 双渠道功能矩阵（Phase A）

日期：2026-10-23。基线：`b9b7961f7eb34ed555ca791f5769883cbf3b1b78`。

图例：`Both (planned)` 表示目标是共享编译，但 Phase A 尚无 Store target 证明；
`Direct only` 表示 Store 源码与成品必须排除；`Store candidate` 表示只能经公开 API、
沙盒和真机实测后决定。`Direct 当前路径` 只说明现有代码，不代表本轮硬件 PASS。

| 功能 | Direct 当前路径 | Store 编译政策 | Store 实测 | 验收步骤 |
| --- | --- | --- | --- | --- |
| 菜单栏图标与面板 | `StatusBarController` + 共享 `IconPresentationViewModel` | Both (planned) | NOT RUN | Store build 后核对与 Dock 同一 scene source；截图与交互回归 |
| Dock 图标与激活 | `AppIconController`、`AppDockMenu` | Both (planned) | NOT RUN | 测静态/充电图标、Dock 点击、Settings 路由和两渠道同装 |
| Dock 可见性探测 | `DockVisibilityMonitor` 公开 CGWindow metadata，受限时 fail-open | Store candidate | NOT RUN | sandbox 中比较显示/隐藏/自动隐藏 Dock；不得新增屏幕录制权限 |
| 基础电池/充电/适配器 | `BatteryMonitor`、`BatteryDetailsController` | Store candidate | NOT RUN | sandbox 内读取电池、充电、适配器；无电池 Mac 降级 |
| Wi-Fi 状态/信号/频段 | `CoreWLANWiFiSystemReader`、`WiFiMonitor` | Store candidate | NOT RUN | 有网/断网/关闭 Wi-Fi；权限拒绝与恢复 |
| Wi-Fi SSID | CoreWLAN SSID + CoreLocation 授权路径 | Store candidate | NOT RUN | location allow/deny/revoke；关联网络与未知名称 |
| Wi-Fi 附近扫描 | `WiFiNetworkController` / CoreWLAN | Store candidate | NOT RUN | 打开详情时扫描；权限、空结果、离屏停止 |
| Wi-Fi 电源控制 | `WiFiMonitor` setPower 路径 | Store candidate | NOT RUN | 单独测 sandbox `setPower`；失败显示原因并深链设置 |
| 已知 Wi-Fi 网络 | 现有 Wi-Fi network list 路径 | Store candidate | NOT RUN | 沙盒内列表读取、重复项、权限和系统版本差异 |
| Internet Sharing detector | `SystemInternetSharingDetector` 读取 `com.apple.nat` | Store evaluate or exclude | NOT RUN | 独立验证未文档化 key；不能据此删除公开 CoreWLAN 读取 |
| 蓝牙枚举/连接/断开 | `BluetoothDeviceController`、公开 IOBluetooth 事件 | Store candidate | NOT RUN | sandbox 枚举、连接、断开、设备移除与权限撤销 |
| 蓝牙总电源 | `IOBluetoothRadioPowerBackend` 的 `dlopen/dlsym` 私有符号 | Direct only | NOT RUN | source/symbol/dynamic-string audit 证明 Store 闭包不含该路径 |
| BLE 附近设备 | `CoreBluetoothLEBatteryScanner` | Store candidate | NOT RUN | Bluetooth entitlement；未授权、授权、撤销和离屏停止 |
| HID/AirPods 电量 | 设备报告、`PmsetAccessoryBatteryWorker`、battery notify | Store candidate after boundary split | NOT RUN | HID、AirPods 左右耳/盒、睡眠恢复；子进程可用性单独记录 |
| Apple AirPods 监听模式 | `BluetoothListeningModeHAL` 的 `iaap`/`lstm`/`lsms` | Direct only | NOT RUN | 源码、数值 ABI、link/symbol audit；Store 不编译私有 HAL |
| Huawei 监听模式 | `HuaweiRFCOMMTransport` 公开 IOBluetooth RFCOMM/SPP + 厂商协议 | Store candidate | NOT RUN | 独立 sandbox/设备试验；不与 Apple 私有 HAL 合并判断 |
| CoreAudio 音量/输入输出 | `CoreAudioOutputController`、`AudioInputMonitor` 等公开 AudioObject API | Store candidate | NOT RUN | sandbox 设备枚举、默认设备、音量/mute、热插拔 |
| 外接显示器 DDC | `DDCDisplayTransport` + `DDCPrivateAPI` | Direct only | NOT RUN | source/link/Mach-O audit 排除 `IOAVService*` 与私有 I2C |
| AppleSMC 功率 | `SystemPowerReader` 的 `AppleSMC` ABI | Direct only | NOT RUN | 排除后仍验证公开电池/适配器能力；不得删除全部 IOKit |
| powerd 充电上限 | `SystemChargeLimitReader` 私有 plist/归档 | Direct only | NOT RUN | 成品审计不含该 reader；Store UI 不展示不可用控件 |
| 低电量模式读取 | 当前主要经 `LowPowerModeController` / Helper XPC | Store candidate after public split | NOT RUN | 先实现 Store-safe 公开读取；授权/未注册/拒绝分开显示 |
| 低电量模式写入 | root Helper + XPC | Direct only | NOT RUN | Store 不注册 daemon、不执行特权写；Direct lifecycle 回归 |
| iPhone/iPad 电量 helper | bundle 内 `StatusTrioMobileBatteryHelper` + usbmuxd 依赖 | Store candidate after audit | NOT RUN | 签名、sandbox、usbmuxd、动态库、许可、审核与真机分别证据化 |
| VPN/有线/本地 IP | SystemConfiguration / Network 路径 | Store candidate | NOT RUN | sandbox 中 VPN、有线、断网、本地网络权限与 IPv4/IPv6 |
| 输入法切换 | Carbon TIS public API | Store candidate | NOT RUN | sandbox 读取、切换、失败反馈 |
| 全局快捷键 | Carbon HotKey public API | Store candidate | NOT RUN | 注册、冲突、禁用、重启和 sandbox |
| 登录启动 | `LaunchAtLoginManager` / `SMAppService` | Store candidate | NOT RUN | signed Store bundle 注册、批准、拒绝、撤销和同装 |
| 更新 | Direct `UpdaterManager` + Sparkle | Direct only | NOT RUN | B1 接入系统更新 adapter；Store 不含 Sparkle/appcast/下载器 |
| 匿名遥测 | Direct eligibility + 既有 consent；Store 固定 false | Store excluded eligibility | NOT RUN | A3 单测通过；Store 发送/网络请求仍无运行时证据 |
| 设置与单实例锁 | 共享 settings schema；Foundation home URL + Bundle ID 锁名 | Store candidate | NOT RUN | 两渠道不同 defaults/container/lock 并发；不能只看锁名不同 |

## 后续必做验收

1. 每个 permission/entitlement 记录 allow、deny、revoke 和恢复，不止首次授权。
2. 分开记录 macOS 13 Ventura 与当前 macOS，不用新版构建代替旧版运行。
3. 测 sleep/wake、设备移除、显示器重连、蓝牙断开、Wi-Fi 切换。
4. 测两渠道同装、同时启动、不同 defaults suite、container 和锁文件。
5. 测低电量/性能驻留，以及 Menu Bar/Dock 场景和图标表现对齐。

以上 Store 项全部为 `NOT RUN`；Direct 行只记录现有实现路径，本轮不产生新的
真机 PASS。
