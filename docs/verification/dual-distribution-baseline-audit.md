# Status Trio 双渠道发行架构（Phase A 基线审计）

日期：2026-10-23。本文是 Phase A 的冻结基线审计，保留当时的 Direct 依赖图、
入口与待拆分边界。A–F 的最终实现和验证结果见
`2026-10-24-dual-distribution-final.md`；不要用本文的“尚无 Store target”
历史结论描述当前实现。
设计约束见 `docs/superpowers/specs/2026-10-23-dual-distribution-design.md`。

## 冻结基线

| 项目 | 值 |
| --- | --- |
| branch | `codex/dual-distribution-foundation` |
| HEAD / `origin/main` | `b9b7961f7eb34ed555ca791f5769883cbf3b1b78` |
| worktree | `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio` |
| Xcode / Swift | Xcode 27.0 (27A266a) / Swift 6.4 |
| macOS SDK | 27.0 |
| `Support/Info.plist` | `1.7.0 (38)` |
| latest main commit title | `Release v1.7.2 appcast` |

版本 plist 与提交标题不同，不据此推断当前公开版本；Phase A 不修改版本。

## 当前依赖图

```text
StatusTrio executable
  -> StatusTrioCore
       -> Sparkle
       -> DDCPrivateAPI
       -> PowerHelperProtocol
       -> AppKit / SwiftUI / IOKit / Carbon / CoreWLAN / CoreLocation
       -> CoreAudio / CoreDisplay / CoreBluetooth / IOBluetooth
       -> Network / Security / ServiceManagement / SystemConfiguration

StatusTrioPowerHelper
  -> PowerHelperProtocol
```

这是当前唯一可构建的产品图。`Package.swift` 没有 Store target；
`STATUS_TRIO_APP_STORE` 只选择编译期身份，不改变超集依赖、链接框架或源码闭包。
Phase A 没有把完整 Direct Core 伪装成 Store package。

## 启动与默认构造回流

1. `AppDelegate.applicationDidFinishLaunching` 先获取 `SingleInstanceGuard` 锁，
   再调用 `AppEnvironment.live()`，并直接启动 `UpdaterManager.shared`。
2. `AppEnvironment.live()` 创建 Direct 的电池、Wi-Fi、网络、VPN、音量、输入、
   状态栏、Dock、输入法和快捷键对象；启动阶段还直接引用
   `PrivilegedHelperManager.shared`。
3. `AppEnvironment.makeStore()` 只允许主要 monitor 注入；其
   `BluetoothDeviceController` 仍固定构造 `PmsetAccessoryBatteryWorker`、
   `IOBluetoothConnectionEventMonitor`、`AccessoryPowerNotifyEventMonitor` 和
   `CoreBluetoothLEBatteryScanner`。
4. `SystemStatusStore.init` 的默认参数继续创建
   `BatteryDetailsController`、`WiFiNetworkController`、`PrimaryLinkController`、
   `LocalIPController`、`BluetoothDeviceController`、`BluetoothRadioPowerController`、
   `MobileBatteryController`、`AppleDeviceDiscoveryController`、
   `BluetoothListeningModeController` 和 `LowPowerModeController`。
5. `StatusBarController`、`StatusPanelViewModel`、`SettingsWindowController` 和
   `InputSourceLivePreview` 仍存在创建或读取 singleton 的路径；这些路径必须在
   composition root 迁移时逐个覆盖，不能只替换 `live()`。
6. `scripts/build-app.sh` 总是构建并嵌入 Sparkle 与 MobileBattery helper；
   `PRIVILEGED_HELPER=0` 只排除 root Helper 和 LaunchDaemon plist，不是 Store
   source closure 或 sandbox 开关。

## A1 代码审计分类

### 已有协议，但仍默认回流到具体实现

| 边界 | 当前接口 | 默认实现 / 回流 |
| --- | --- | --- |
| 蓝牙总电源 | `BluetoothRadioPowerBacking` | `BluetoothRadioPowerController` 默认构造 `IOBluetoothRadioPowerBackend` |
| DDC | `DDCVolumeTransport` | `DDCVolumeCoordinator` 和 `VolumeMonitor` 默认构造 `DDCDisplayTransport` |
| 监听模式 HAL | `BluetoothListeningModePropertyReading` | `BluetoothListeningModeController` 默认构造私有 4CC HAL |
| 手机电量 | `MobileBatteryReading` | `MobileBatteryController` 与 `AppleDeviceDiscoveryController` 默认构造 helper reader |
| 提权服务 | `PrivilegedHelperServicing` | `PrivilegedHelperManager.shared` 默认构造 `SystemPrivilegedHelperService` |

协议存在不等于 Store-safe；只要具体默认值仍在共享构造链中，就必须在 B–E
显式注入或移出。

### 实际私有、未文档化或 Direct 专属调用

| 文件 | 调用 / ABI | 发行政策 |
| --- | --- | --- |
| `Sources/DDCPrivateAPI/include/DDCPrivateAPI.h` | `IOAVServiceCreateWithService`、`IOAVServiceReadI2C`、`IOAVServiceWriteI2C` | Direct only；Store 编译与链接均排除 |
| `Sources/StatusTrioCore/Audio/DDCDisplayTransport.swift` | 私有 IORegistry 匹配、`IOAVService*` I2C 读写 | Direct only |
| `Sources/StatusTrioCore/Monitoring/IOBluetoothRadioPowerBackend.swift` | `dlopen`/`dlsym` 查找 `IOBluetoothPreference*` | Direct only；源码审查与动态字符串审计都需要 |
| `Sources/StatusTrioCore/Audio/BluetoothListeningModeHAL.swift` | Apple 私有 HAL 选择器 `iaap`/`lstm`/`lsms` 的数值 ABI | Direct only；不与 Huawei SPP 合并 |
| `Sources/StatusTrioCore/Monitoring/SystemPowerReader.swift` | `AppleSMC` 与 80 字节私有 key-data ABI | Direct only；不能据此删除公开 IOKit 电池读取 |
| `Sources/StatusTrioCore/Monitoring/SystemChargeLimitReader.swift` | `/Library/Preferences/com.apple.powerd.charging.plist` 和私有归档布局 | Direct only |
| `Sources/StatusTrioCore/App/PrivilegedHelperManager.swift` | root LaunchDaemon、`SMAppService`、XPC | Direct only；Store 不打包也不注册 |
| `Sources/StatusTrioCore/App/UpdaterManager.swift` | Sparkle、GitHub appcast、镜像回退 | Direct only；取得系统更新适配器前 Store 不含 Sparkle |

### 公开 API，但 Store 可用性尚未验证

| 能力 | 当前路径 | 风险 / 验收重点 |
| --- | --- | --- |
| Wi-Fi 状态、信号、SSID、扫描、电源 | `WiFiMonitor`、`CoreWLANWiFiSystemReader` | 逐项测 sandbox、CoreLocation、allow/deny/revoke；`setPower` 单独判定 |
| Internet Sharing detector | `SystemInternetSharingDetector` 读取未文档化 `com.apple.nat` | 单独评估或 Store 排除；不得删除公开 CoreWLAN 读取 |
| 蓝牙枚举与连接 | `BluetoothDeviceController`、`IOBluetoothConnectionEventMonitor` | 还需审计 `system_profiler`/`pmset` 子进程、公开 IOBluetooth 和 sandbox |
| BLE 附近设备 | `CoreBluetoothLEBatteryScanner` | 测 Bluetooth entitlement、权限撤销和 demand lifecycle |
| Huawei 监听模式 | `HuaweiRFCOMMTransport` 使用公开 IOBluetooth RFCOMM/SPP + 厂商协议 | 与 Apple 私有 HAL 分开；Store entitlement、设备与协议实测，当前 NOT RUN |
| CoreAudio 输入输出 | `CoreAudioOutputController`、`AudioInputMonitor` 等 | 测 sandbox 内设备枚举、默认设备、音量/ mute 与权限 |
| VPN、有线、本地 IP | SystemConfiguration / Network 路径 | 测 sandbox 可见性、VPN 状态和本地网络权限 |
| 输入法、快捷键 | Carbon TIS 与 Carbon HotKey | 测 sandbox 内选择、快捷键注册和冲突 |
| 登录启动 | `LaunchAtLoginManager` / `SMAppService` | 测 Store signed bundle 的 Login Item 注册、批准和撤销 |
| Dock 可见性 | `DockVisibilityMonitor.liveVisibility()` 使用公开 CGWindow metadata | 受限 sandbox 下效果 NOT RUN；已有 fail-open，不增加屏幕录制权限 |
| 手机电量 helper | `MobileBatteryHelperReader` 启动 bundle 内 helper | 单独审计 usbmuxd、动态库、签名、sandbox、许可和审核风险 |
| 设置与单实例锁 | Foundation home URL + 按 Bundle ID 的 `flock` | 测 sandbox container home 重定向、不同 defaults、两渠道同装和并发锁 |

### 不得混淆的边界

- Apple AirPods 私有 HAL 控制与 Huawei 公开 `IOBluetooth` + 厂商 RFCOMM/SPP
  是两条独立路径。前者必须由 Store 编译闭包排除；后者只能标记为待实测，
  不能因 Apple 分支私有而整项删除或提前判定不可用。
- `WiFiMonitor` 的 `com.apple.nat` detector 是独立未文档化数据源。Store 政策
  需单独评估或排除，不应连带删除公开 CoreWLAN 状态读取。
- `DockVisibilityMonitor` 使用公开 CGWindow 路径，但 Store sandbox 的可见结果
  尚未验证；不要为了动画新增权限或把 NOT RUN 写成 available。

## Phase A 发行契约

`DistributionChannel` 是最小编译期身份：

- `direct`：生产候选 Bundle ID `com.lingsmbp.StatusTrio`。
- `appStore`：生产候选 Bundle ID `com.lingsmbp.StatusTrio.AppStore`，尚未注册核验。
- `STATUS_TRIO_APP_STORE` 未定义时固定为 `direct`。
- 开发 Bundle ID、实际 defaults、锁文件和运行身份不由
  `productionBundleIdentifier` 覆盖。

`CapabilityAvailability` 区分：

- `available`
- `permissionRequired`
- `unsupported(reason:)`
- `temporarilyUnavailable(reason:)`
- `notVerified`

只有 `available.isActionable == true`。未知或未测状态不能折算成 available，
授权缺失也不能折算成 unsupported。Phase A 尚未把该 enum 接入所有 UI/provider；
接线属于 B–E。

遥测资格新增 channel 维度：Direct 保留原 Bundle ID + production marker + 非
Debug 条件，用户同意链不变；Store 无论 Bundle ID 和 marker 如何都 fail closed。
这不代表 Store analytics 已设计或启用。

## 后续发行路线

| 阶段 | 必须先完成的边界 | 退出证据 |
| --- | --- | --- |
| B1 | `UpdateServicing` 与共享更新状态；Direct adapter 保留 Sparkle 回退 | Core/UI 无 Sparkle import 的 source contract、更新回归、full |
| B2a | DDC、Apple 私有 HAL、蓝牙私有电源移入 DirectPlatform | 每片 source graph、link/symbol audit、Direct 行为回归、full |
| B2b | root Helper、AppleSMC、powerd 私有读取边界 | Helper/XPC/lifecycle 回归；Store fake 不注册 daemon |
| B2c | Direct/Store composition root 与无环 DAG | Store-safe Core 独立编译；Direct `swift run` 不退化 |
| C | 真正 Store app target、sandbox、产物审计、同装身份 | unsigned compile、signed sandbox、artifact audit 分开报告 |
| D | 公开 Wi-Fi/网络/蓝牙/CoreAudio provider 与真机矩阵 | allow/deny/revoke、OS/硬件、sleep/wake、设备移除证据 |
| E | capability UI、About 渠道说明、i18n/privacy | 两渠道实际 UI；Menu Bar/Dock 同场景来源 |
| F | 手动 Store archive workflow、版本合同 | 离线 fixtures；不上传、不送审，Direct release 合同不变 |

## 外部参考

2026-10-23 经 GitHub API 读取固定 SHA，仅借鉴结构，不复制 Team、
entitlements、私有 IORegistry 假设或硬件结论。

| 项目 / SHA | 实际读取文件 | 采用 / 不采用 |
| --- | --- | --- |
| CotEditor `95ac82b213c1a6943e25d8b8176ebeb8000e584e` | `Configurations/CotEditor.xcconfig`、`CotEditor-Sparkle.xcconfig`、`UpdaterManager.swift` | 采用 configuration/source exclusion/更新边界；不采用更高 OS API 假设 |
| Budsy `dfd512c12aa064d3e9691c6736f9d2c157727eef` | `project.yml`、`Signing/Budsy-AppStore.entitlements` | 采用可提交工程与 Store scheme 思路；不复制 Team、部署目标或 entitlements |
| NetLights `6b874559621d7245d77a05deb4c0a98ef9eeea65` | `APPSTORE.md`、`Version.xcconfig` | 采用进程内数据源与证据矩阵思路；不复制手建工程或硬件结论 |

## 当前未验证项

整个 Store 硬件与沙盒矩阵为 `NOT RUN`。当前没有 Store target、Store entitlement
签名、sandbox runtime、App Store Connect 产品、Universal DMG、Developer ID
Store 签名或审核结果。Ventura/当前 macOS 的真实运行、TCC allow/deny/revoke、
sleep/wake、设备移除、同装、启动项、更新和 Menu Bar/Dock 实机对齐均未在本轮验证。
