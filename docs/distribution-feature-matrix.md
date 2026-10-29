# Status Trio 双渠道功能矩阵

日期：2026-10-24。基线：`b9b7961f7eb34ed555ca791f5769883cbf3b1b78`。

源码政策与真实可用性分别记录。`共享源码` 表示 Store 独立目标包含该实现；
`公开候选` 表示保留公开 API 路径，实际设备/权限/沙盒行为仍需验证；
`Direct only` 表示 Store 编译与链接排除。测试不代表硬件 PASS。
实际构建、签名及逐阶段证据见 `verification/dual-distribution-progress.md`。

| 功能 | Direct 当前路径 | Store 编译政策 | Store 实测 | 验收步骤 |
| --- | --- | --- | --- | --- |
| 菜单栏图标与面板 | `StatusBarController` + 共享 `IconPresentationViewModel` | 共享源码 | NOT RUN | Store build 后核对与 Dock 同一 scene source；截图与交互回归 |
| Dock 图标与激活 | `AppIconController`、`AppDockMenu` | 共享源码 | NOT RUN | 测静态/充电图标、Dock 点击、Settings 路由和两渠道同装 |
| Dock 可见性探测 | `DockVisibilityMonitor` 公开 CGWindow metadata，受限时 fail-open | 公开候选 | NOT RUN | sandbox 中比较显示/隐藏/自动隐藏 Dock；不得新增屏幕录制权限 |
| 基础电池/充电/适配器 | `BatteryMonitor`、`BatteryDetailsController` | 公开候选 | NOT RUN | sandbox 内读取电池、充电、适配器；无电池 Mac 降级 |
| Wi-Fi 状态/信号/频段 | `CoreWLANWiFiSystemReader`、`WiFiMonitor` | 公开候选 | NOT RUN | 有网/断网/关闭 Wi-Fi；权限拒绝与恢复 |
| Wi-Fi SSID | CoreWLAN SSID + CoreLocation 授权路径 | 公开候选 | NOT RUN | location allow/deny/revoke；关联网络与未知名称 |
| Wi-Fi 附近扫描 | `WiFiNetworkController` / CoreWLAN | 公开候选 | NOT RUN | 打开详情时扫描；权限、空结果、离屏停止 |
| Wi-Fi 电源控制 | `WiFiMonitor` setPower 路径 | 公开候选 | NOT RUN | 单独测 sandbox `setPower`；失败显示原因并深链设置 |
| 已知 Wi-Fi 网络 | Direct networksetup；Store 公开 CWConfiguration/CWNetworkProfile | 公开候选 | NOT RUN | 沙盒内列表读取、重复项、权限和系统版本差异 |
| Internet Sharing detector | `SystemInternetSharingDetector` 读取 `com.apple.nat` | Direct only | NOT RUN | 独立验证未文档化 key；不能据此删除公开 CoreWLAN 读取 |
| 蓝牙枚举/连接/断开 | `BluetoothDeviceController`、公开 IOBluetooth 事件 | 公开候选 | NOT RUN | sandbox 枚举、连接、断开、设备移除与权限撤销 |
| 蓝牙总电源 | `IOBluetoothRadioPowerBackend` 的 `dlopen/dlsym` 私有符号 | Direct only | NOT RUN | source/symbol/dynamic-string audit 证明 Store 闭包不含该路径 |
| BLE 附近设备 | `CoreBluetoothLEBatteryScanner` | 公开候选 | NOT RUN | Bluetooth entitlement；未授权、授权、撤销和离屏停止 |
| HID/AirPods 电量 | Direct 原 profiler/pmset/notify；Store 公开 IOPS 与既有 BLE | 公开 IOPS/BLE 候选 | NOT RUN | HID、AirPods 左右耳/盒、睡眠恢复；子进程可用性单独记录 |
| Apple AirPods 监听模式 | `BluetoothListeningModeHAL` 的 `iaap`/`lstm`/`lsms` | Direct only | NOT RUN | 源码、数值 ABI、link/symbol audit；Store 不编译私有 HAL |
| Huawei 监听模式 | `HuaweiRFCOMMTransport` 公开 IOBluetooth RFCOMM/SPP + 厂商协议 | 公开候选 | NOT RUN | 独立 sandbox/设备试验；不与 Apple 私有 HAL 合并判断 |
| CoreAudio 音量/输入输出 | `CoreAudioOutputController`、`AudioInputMonitor` 等公开 AudioObject API | 公开候选 | NOT RUN | sandbox 设备枚举、默认设备、音量/mute、热插拔 |
| 外接显示器 DDC | `DDCDisplayTransport` + `DDCPrivateAPI` | Direct only | NOT RUN | source/link/Mach-O audit 排除 `IOAVService*` 与私有 I2C |
| AppleSMC 功率 | `SystemPowerReader` 的 `AppleSMC` ABI | Direct only | NOT RUN | 排除后仍验证公开电池/适配器能力；不得删除全部 IOKit |
| powerd 充电上限 | `SystemChargeLimitReader` 私有 plist/归档 | Direct only | NOT RUN | 成品审计不含该 reader；Store UI 不展示不可用控件 |
| 低电量模式读取 | `BatteryMonitor` 的公开 `ProcessInfo.isLowPowerModeEnabled` | 共享公开读取 | NOT RUN | 先实现 Store-safe 公开读取；授权/未注册/拒绝分开显示 |
| 低电量模式写入 | root Helper + XPC | Direct only | NOT RUN | Store 不注册 daemon、不执行特权写；Direct lifecycle 回归 |
| iPhone/iPad 电量 helper | bundle 内 `StatusTrioMobileBatteryHelper` + usbmuxd 依赖 | 本轮不打包，待独立验证 | NOT RUN | 签名、sandbox、usbmuxd、动态库、许可、审核与真机分别证据化 |
| VPN/有线/本地 IP | SystemConfiguration / Network 路径 | 公开候选 | NOT RUN | sandbox 中 VPN、有线、断网、本地网络权限与 IPv4/IPv6 |
| 输入法切换 | Carbon TIS public API | 公开候选 | NOT RUN | sandbox 读取、切换、失败反馈 |
| 全局快捷键 | Carbon HotKey public API | 公开候选 | NOT RUN | 注册、冲突、禁用、重启和 sandbox |
| 登录启动 | `LaunchAtLoginManager` / `SMAppService` | 公开候选 | NOT RUN | signed Store bundle 注册、批准、拒绝、撤销和同装 |
| 更新 | Direct 原 Sparkle；Store 系统管理更新 service | 按渠道注入 | NOT RUN | Direct 回退/展示回归；Store 无 Sparkle/appcast/下载器或自动更新开关 |
| 匿名遥测 | Direct eligibility + 既有 consent；Store 固定 false | Store excluded eligibility | NOT RUN | 资格/同意/生命周期单测通过；Store 发送/网络请求仍无运行时证据 |
| 设置与单实例锁 | Direct 保留旧路径；Store container-aware URL + 实际 Bundle ID | 共享 schema、独立域 | NOT RUN | 14 个离线测试及独立审查通过；真实 container/TCC/同装仍需验收 |

## 后续必做验收

1. 每个 permission/entitlement 记录 allow、deny、revoke 和恢复，不止首次授权。
2. 分开记录 macOS 13 Ventura 与当前 macOS，不用新版构建代替旧版运行。
3. 测 sleep/wake、设备移除、显示器重连、蓝牙断开、Wi-Fi 切换。
4. 测两渠道同装、同时启动、不同 defaults suite、container 和锁文件。
5. 测低电量/性能驻留，以及 Menu Bar/Dock 场景和图标表现对齐。

以上 runtime/hardware 栏仍为 `NOT RUN`；源码隔离、reader fixtures 和锁/defaults
测试有各自独立的通过证据，不能替代真实沙盒、硬件或旧系统运行。Direct 行保留
原实现路径，本轮不凭编译或单测产生新的真机 PASS。

## Store 明确不包含的实现

Sparkle 与其下载/更新回退、DDCPrivateAPI/IOAVService/CoreDisplay、Apple 私有
监听模式 HAL 和蓝牙电源写入、root Helper/PowerHelperProtocol/LaunchDaemon、
AppleSMC/powerd 私有读取、未文档化 Internet Sharing/accessory notify、Direct
子进程 reader 和 MobileBattery helper 不进入 Store 目标。公开 IOBluetooth、
CoreBluetooth、CoreWLAN、CoreAudio、IOKit 以及 Huawei 厂商 transport 保留。

About 使用共享低权重发行说明与开源项目链接；没有付费/完整版 CTA、跨渠道下载器
或自动安装器。Store 遥测固定关闭，独立可用性不依赖安装 Direct。
