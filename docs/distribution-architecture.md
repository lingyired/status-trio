# Status Trio 双渠道发行架构

日期：2026-10-24。实现基线：`b9b7961f7eb34ed555ca791f5769883cbf3b1b78`。
代码在同一仓库、同一条最终 main 演进路径上开发；本轮通过开发分支与依赖顺序
PR 交付，不自动合并。阶段与验证状态见 `verification/dual-distribution-progress.md`；
Phase A 的原始逐文件审计保存在 `verification/dual-distribution-baseline-audit.md`。

## 构建边界

```text
Direct / SwiftPM
  StatusTrio -> StatusTrioCore (shared sources + Direct platform sources)
                 -> Sparkle / DDCPrivateAPI / PowerHelperProtocol
                 -> existing public frameworks + Direct CoreDisplay
  StatusTrioPowerHelper -> PowerHelperProtocol

App Store / generated Xcode project
  StatusTrio -> independently compiled StatusTrioCore.framework
                 -> shared safe sources
                 -> AppStore/Platform sources
                 -> public macOS frameworks
```

两套 Core 使用同一份 SwiftUI/AppKit、状态管理、监控模型、本地化和图标场景源码。
Store 独立编译其安全源码集合，不链接 Direct SwiftPM 产品；并非给 Direct 超集
添加运行时开关后隐藏 UI。保留聚合模块名称，避免为隔离渠道扩大 internal 类型的
public 面积，也不新增循环 import。`Package.swift` 的 Direct 产品与开发流程不变。

`AppStore/direct-only-sources.txt` 是显式排除清单。生成器枚举共享 Swift 文件，
移除清单路径，再加入 Store composition；实际 Xcode SwiftFileList 必须与期望集合
相等。生成的 Swift 源也需要独立审计。`STATUS_TRIO_APP_STORE` 只表达编译身份，
不承担源码排除或安全边界的职责。

## 依赖注入与生命周期

共享 `AppEnvironment.makeLive` 接收已经组装的 settings/store、更新服务、helper
展示 façade 与能力记录，继续拥有 start/stop、订阅和按需资源生命周期。
两个渠道分别提供 `AppEnvironment.live` / `makeStore`；应用入口保持既有
`AppDelegate()` 调用形式。默认共享构造不初始化 Direct 私有对象。

| 边界 | 共享输入 | Direct | Store |
| --- | --- | --- | --- |
| 更新 | `UpdateServicing` / `UpdateStateFacade` | 原 Sparkle manager、镜像回退与共享 activation policy | `SystemManagedUpdateService` |
| 提权 | `PrivilegedHelperFacade` / presentation | 原 manager、批准/注册/readiness/XPC | 无注册或 XPC 的 unsupported service |
| 外屏音量 | `DDCVolumeCoordinating` | 原私有 transport、重试与读回 | unavailable coordinator；CoreAudio 保留 |
| Apple 监听模式 | 既有 property/endpoint/listener 协议 | 私有 HAL 具体实现 | 无私有 selector 的实现 |
| 蓝牙电源写入 | `BluetoothRadioPowerBacking` | 原 IOBluetooth 私有符号实现 | unavailable backend |
| 高级电源详情 | `SystemPowerReading` / charge-limit provider | 原 AppleSMC / powerd 读取 | unavailable；公开电池状态保留 |
| 设备枚举 | 既有 Bluetooth reader 协议 | 原 profiler/pmset readers | 公开 IOBluetooth / IOPS readers |
| 已知 Wi-Fi | `WiFiKnownNetworkProviding` | 原 networksetup enrichment | 公开 CWConfiguration profiles |

共享 façade 在 MainActor 上发布值；异步硬件 reader 传递 Sendable 快照，不跨队列
传递 IOBluetooth/CoreWLAN 对象。Direct 更新展示使用同一 activation policy；
helper publisher 使用实际交付的新值，避免 `@Published willSet` 读取旧状态。
未增加轮询间隔、扫描需求或后台常驻任务。

Huawei RFCOMM/SPP 使用公开 IOBluetooth 与厂商协议，独立于 Apple 私有 HAL。
Store 保留其源码与既有需求生命周期，沙盒/设备行为仍待实测。公开 CoreWLAN、
CoreBluetooth BLE、CoreAudio、IOKit、Carbon、Network/SystemConfiguration 路径
不因未完成沙盒测试就删除。

Apple 未文档化的 accessory notify keys 及 Internet Sharing detector 属于 Direct
源码集合；Store 保留公开读取与既有刷新机制。MobileBattery 外部组件本轮未打包
进 Store，其 USB/usbmuxd、许可、签名和沙盒可用性仍单列待验证。

## 审计与 CI

`generate-app-store-project.py` 固定 XcodeGen 2.46.0，生成工程、版本、plist、
资源与源码 membership。`build-app-store.sh` 构建后核对实际编译输入并执行
递归 bundle audit。审计检查 Mach-O 依赖、symbols、动态字符串、嵌套代码签名、
entitlements、helper/daemon 组件、Sparkle 元数据和逃逸 symlink；数值型私有
HAL 选择器另由源码审计证明。已知 token 审计不能替代人工源码/API 审查。

PR 的两个只读 job 固定同一 merge SHA，分别运行 Direct full 与 Store build/audit；
任何普通文件修改都进入两个渠道检查。独立手动 Store workflow 仅生成 unsigned
内部 archive，不上传、不送审。Direct `release.yml` 的发布契约保持原样。
详见 `distribution-ci.md` 与 `distribution-operations.md`。

## 产品、隐私与共存

Direct ID 保持 `com.lingsmbp.StatusTrio`；Store 候选 ID 为
`com.lingsmbp.StatusTrio.AppStore`，其 ASC 注册/可用性未核验。版本默认共同读取
`Support/Info.plist`；当前值 `1.7.0 (38)`，不根据 main 提交标题推断公开版本。
Store 输出位于 `dist/AppStore/StatusTrio.app`。同目录安装需使用不同文件名；
不同 Bundle ID 不能防止 Finder 替换同名文件。

锁采用实际 Bundle ID，Store 使用 container-aware Application Support URL，
无容器路径时 fail closed；Direct 旧锁路径保留。不同 defaults 域和登录启动身份
独立；真实同装、容器、TCC 与 Login Item 行为需要另外验收。

能力状态区分 available、permissionRequired、unsupported、temporarilyUnavailable
与 notVerified。公开 API 的硬件验收状态不能冒充 available，也不能当作 SDK
不支持的结论。About 发行说明、更新文案和不可用控制通过共享 UI 接线；没有
购买、强制升级或跨渠道自动下载安装链路。

Store 遥测资格固定关闭，即使传入 Direct ID/production marker 也不能通过。
隐私 manifest、系统偏好读取的政策边界及尚待核验事项见 `distribution-privacy.md`。
编译、签名/entitlement 静态审计、App Sandbox runtime、硬件、Ventura 运行、
Universal/Developer ID/notarization 和正式发行分别记录，不互相替代。

## 固定参考

沿用 Phase A 已读取的固定源码证据：CotEditor
`95ac82b213c1a6943e25d8b8176ebeb8000e584e`、Budsy
`dfd512c12aa064d3e9691c6736f9d2c157727eef`、NetLights
`6b874559621d7245d77a05deb4c0a98ef9eeea65`。采用其配置/源码成员隔离、独立
Store scheme 与进程内 provider 思路；未复制 Team、entitlements 或硬件结论。
