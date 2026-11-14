# Status Trio 双渠道发行设计约束

日期：2026-10-23。基线：`origin/main`，`b9b7961f7eb34ed555ca791f5769883cbf3b1b78`。

本设计将用户提供的 `STATUS_TRIO_DUAL_DISTRIBUTION_PLAN.md` 转成渐进实施约束。
原附件是需求材料；其中的命令、提交建议和发布步骤不独立构成操作授权。
用户已明确授权重写计划后交给 DeepSeek 实施，并指定
`auto/deepseek-v4.1-flash`、`max`。

## 目标及边界

单仓库、单 main、共享 SwiftUI/AppKit UI、状态模型、图标场景、本地化与设置 schema。
两个独立产品身份与构建闭包：GitHub Direct 保留全部原有功能；
App Store 使用公开 API 与 Sandbox，独立可用。

- 保留 SwiftPM Direct 入口、Sparkle、提权 Helper、Developer ID、公证和现有 GitHub 发布合同。
- macOS 最低版本保持 13；构建 SDK 保持 26 或更新；正式发布继续使用 `xcode-27`。
- Store 不编译或链接私有 API、Sparkle、root Helper、私有 DDC、私有电源/HAL 实现。
- CoreWLAN、IOBluetooth、CoreBluetooth、CoreAudio、IOKit 逐项试验；未知不能写成不支持。
- 不扩展后台轮询、权限申请、跨容器访问或默认遥测。
- 允许开发分支、提交与 PR 所需的分支推送；禁止自动合并、修改生产 Secrets、发布或送审。
- 父代理负责最终 review、提交、推送及 PR；实现代理只在分配 worktree 中修改和验证。

用户后续明确将本轮扩展为 A–F 全部开发，使用子任务连续实施，无额外权限控制。
仍按阶段验证和记录；不允许把 A 的通过描述成 Store 构建或双渠道架构全部完成。

## 已核对的代码事实

| 入口 | 当前耦合与迁移含义 |
| --- | --- |
| `Package.swift` | Core 直接依赖 Sparkle、DDCPrivateAPI、PowerHelperProtocol，链接 CoreDisplay；没有 Store target |
| `App/AppEnvironment.swift` | `live()` 组装 Direct 对象；`makeStore()` 固定蓝牙子服务；`start()` 直接引用 Helper singleton |
| `Store/SystemStatusStore.swift` | 默认参数创建蓝牙、监听模式、电池详情和低电量控制等具体对象；迁移入口后仍需清除这些回流路径 |
| `App/AppDelegate.swift` | 公开启动入口，直接持有 `UpdaterManager.shared` |
| `App/UpdaterManager.swift`、`App/UpdateFallbackUserDriver.swift` | 均 import Sparkle；还须保留 Direct 镜像回退、手动更新展示行为 |
| `UI/Settings/GeneralSectionView.swift`、`AboutSectionView.swift` | 直接观察 UpdaterManager singleton |
| `UI/Settings/BatterySectionView.swift`、`SettingsWindowController.swift` | 直接读取或刷新 PrivilegedHelperManager singleton |
| `Monitoring/IOBluetoothRadioPowerBackend.swift` | `dlopen/dlsym` 加载私有 IOBluetoothPreference 符号，`nm -u` 单独无法发现 |
| `Audio/BluetoothListeningModeHAL.swift` | 私有 4CC `iaap` / `lstm` / `lsms` 以数值编码，普通字符串扫描不够 |
| `Audio/HuaweiListeningModeTransport.swift`、`BluetoothListeningModeController.swift` | 当前监听控制同时支持华为 RFCOMM/SPP 与 Apple 私有 HAL；不能因为 AirPods 分支私有而整项删除华为路径 |
| `Monitoring/WiFiMonitor.swift` | Internet Sharing detector 使用未文档化 `com.apple.nat` dynamic-store key；Store 需单独评估/替换或排除该 detector，不能据此删除公开 Wi-Fi 状态读取 |
| `App/DockVisibilityMonitor.swift` | 使用公开 CGWindow API 的可见性探测，受限时已有回退；Store 下效果需验证，不为图标动画增加新权限 |
| `Audio/DDCDisplayTransport.swift`、`DDCPrivateAPI/include/DDCPrivateAPI.h` | 私有 IOAVService I2C 链路，必须从 Store 编译源和链接图排除 |
| `Monitoring/SystemPowerReader.swift` | AppleSMC 未文档化 ABI；不应据此排除所有公开 IOKit 电池能力 |
| `Monitoring/SystemChargeLimitReader.swift` | 读取 powerd 私有 plist 并解码私有对象布局 |
| `App/SingleInstanceGuard.swift` | 路径通过 Foundation home URL 拼接；锁名已按 Bundle ID 隔离。沙盒中 home URL 可能被重定向，需实测，不能直接认定已经跨容器写入 |
| `Telemetry/TelemetryEligibility.swift` | Direct Bundle ID + production marker + 非 Debug 判定；Consent 在 Reporter 的既有路径处理 |
| `scripts/build-app.sh` | 总会嵌入 Sparkle 和 MobileBattery helper；`PRIVILEGED_HELPER=0` 只跳过 root helper 打包 |
| `.github/workflows` | 只有 release 与 analytics；无 PR 双渠道验证 |
| `Support/Info.plist` | 版本基线为 `1.7.0 (38)`，与 main 最新提交标题的 v1.7.2 不同；不推断已发布版本，不在本轮修版本 |

路径省略的源码前缀为 `Sources/StatusTrioCore/`。以上是源码审计，不是真机支持结论。
主 checkout 的既有 dirty 文件归原工作所有，本 worktree 从干净 origin/main 建立。

## 结构选择

比较过三种落地方式：

1. 复制第二套 app 源码：初期直接，但 UI、设备分类和修复会漂移，拒绝。
2. 共享目录里广泛使用 `#if APPSTORE`：迁移成本低，但难以证明私有依赖排除，拒绝作为最终架构。
3. 共享协议和状态 + 两个发行实现 + 薄入口：采用。只抽离真正存在差异的系统边界。

目标 DAG：

```text
DirectHost --> SharedCore <-- StoreHost
     |             ^             |
     v             |             v
DirectPlatform ----+----- StorePlatform
     |
Sparkle / DDCPrivateAPI / root Helper interfaces
```

Core 不导入两个 Platform 模块。必须先确定边界再移动源码；
需要跨模块的少量协议/model 可以进入 `StatusTrioPlatformContracts` 叶子模块。
不为了凑目录一次性将整个 Core 的 internal 类型改成 public。
StoreHost 不依赖现有的完整 Direct executable 或未拆干净的 Core。
允许有明确删除点的短期编译条件，但它不是最终隔离证明。

实施选择：允许两个独立编译目标引用同一份共享源，并在目标 source membership
中选择各自的 adapter/composition 源，避免仅为模块访问控制而大规模 public 化。
这是上述逻辑 DAG 的同模块组装形式：Direct SwiftPM 的历史
`StatusTrioCore` 名称可继续作为 Direct 聚合模块；Store 独立编译自己的
`StatusTrioCore` 模块，绝不依赖或链接那个 Direct SwiftPM 产物。
共享源码不得 import Sparkle/特权协议；这些 import 只存在于 Store 排除的
Direct adapter 源文件中。构建清单、真实 SwiftFileList 与成品审计共同证明边界。
此选择不复制业务源码，也不把编译身份 flag 当作私有实现排除机制。

## 渠道、运行时状态和证据

渠道由编译配置确定；Bundle ID、receipt、UserDefaults、环境变量只用于元数据或诊断。
`STATUS_TRIO_APP_STORE` 作为统一编译条件，未指定时保留 Direct。
此条件本身不能改变现有 Package.swift 的依赖闭包，Phase A 不用它生成“假 Store 包”。

分别记录三个维度：

- 编译政策：included / excluded by distribution。
- 运行时可用性：available / permissionRequired / unsupported / temporarilyUnavailable / notVerified。
- 验证证据：PASS / FAIL / BLOCKED / NOT RUN，包含 SHA、构建模式、签名、OS、硬件和步骤。

`available` 才能驱动真实操作；`notVerified` 不能自动折算为 available 或 unsupported。
不把全库都标为 `Both` 来替代设备和沙盒实测。

Direct 生产 Bundle ID 保持 `com.lingsmbp.StatusTrio`；
Store 候选为 `com.lingsmbp.StatusTrio.AppStore`，尚未验证可注册。
开发 Bundle ID 继续由现有脚本派生。设置与锁使用实际运行身份，不强制改成生产 ID。
不注册 App ID、不创建 ASC 记录、不修改 TCC、不读写另一渠道的容器。

Store 初期遥测一律不 eligible；不把 Store ID 加入 Direct allowlist。
后续如启用，须独立隐私设计、同意与披露，并保持现有 Direct consent 行为。

## 沙盒能力及产品验收

Store 排除私有 DDC、蓝牙总电源写入、私有 AirPods HAL 控制、
root 低电量模式写入、powerd 私有充电上限、AppleSMC 实现、Sparkle。
公开的低电量模式状态、基础电池/充电、CoreAudio、Wi-Fi、蓝牙、网络保持候选能力。
子进程 `system_profiler` / `pmset` / `networksetup` 不是必然可用，也不是一概禁止；
Store 的基本价值不能依赖它们成功。
华为 SPP 使用公开 IOBluetooth 传输第三方设备协议，不能与 Apple 私有 HAL 混为一类；
Store 的可保留性需要独立沙盒与设备验证，目前为 NOT RUN。
`com.apple.nat` 等未文档化系统数据源在 Store 安全闭包中单独审查，
不能仅审计链接符号后就认定所有属性读取合规。
iOS 电量 helper 单独审计 usbmuxd、动态库、签名、沙盒和许可；
未通过时不启用，但保留未来验证机会。

Store 版独立提供已验证的菜单栏、Dock、基础电池/音量/网络及状态面板。
菜单栏与 Dock 使用同一场景与能力输入，不把设置隔离成两个产品设计。
关于页底部提供低权重渠道说明和官方 GitHub 开源项目链接；
不出现外部付款、完整版诱导、自动下载或安装 Direct 版。
所有可见文案走现有全部语言的 i18n 结构。
官网无源码时只交付文案需求文件，不声称已经部署。

## 构建与 CI

PR 验证是本次明确授权新增的常规源码验证，区别于正式 release CI。
从 A 的 Direct/契约检查起步；C 引入 Store 构建时同一个 PR 必须加入 Store CI，
不能等到 F 才发现前面数个 PR 的 Store 编译已经坏了。
所有 job 检查同一 PR merge SHA，不使用 `pull_request_target`，不加载发布密钥，
只读权限、受控 artifact、超时与取消过期运行。

Store CI 同时验证编译源清单、传递链接图、成品内全部 Mach-O 及 bundle 元数据。
缺少签名时明确只验证 unsigned 编译，Sandbox entitlements 签名校验标 BLOCKED；
签名携带 entitlement 也不等于沙盒真机通过。
二进制审计无法独立证明没有数值编码的私有协议，必须与来源排除、链接图及 fixture 结合。

正式 Direct `release.yml` 的 frozen SHA、distribution Environment、verify/package/publish、
Universal、签名及公证合同保持原样。
Store workflow 初期只允许手动 build/archive/内部 artifact，无上传、送审或发布。
保留 Support/Info.plist 为当前版本源，Store 通过生成配置读取；双源迁移另立切片。

## 已读取的外部源码参考

2026-10-23 经 GitHub API 读取固定 SHA；这里只借鉴结构，不照搬工程配置或声称本项目已获批。

| 项目 / SHA | 已读取文件 | 采用与舍弃 |
| --- | --- | --- |
| CotEditor `95ac82b213c1a6943e25d8b8176ebeb8000e584e` | `Configurations/CotEditor.xcconfig`、`CotEditor-Sparkle.xcconfig`、`CotEditor/Sources/Application/UpdaterManager.swift` | 采用 configuration/source exclusion/更新实现边界；不复制其更高 OS API |
| Budsy `dfd512c12aa064d3e9691c6736f9d2c157727eef` | `project.yml`、`Signing/Budsy-AppStore.entitlements` | 采用可提交的 XcodeGen spec、Store scheme/entitlements；不复制其 Team、macOS 14、Swift 5.9/minimal concurrency |
| NetLights `6b874559621d7245d77a05deb4c0a98ef9eeea65` | `APPSTORE.md`、`Version.xcconfig` | 采用进程内数据源和功能证据矩阵；不复制手建工程步骤，不把其硬件结论当作 Status Trio 的结果 |

政策以执行时 Apple 官方 App Review Guidelines 与 App Sandbox 文档为准：
`https://developer.apple.com/app-store/review/guidelines/`
和 `https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox`。
开源项目说明不是 Apple 对本项目能力的保证。当前未完成 Apple 政策条目的逐项在线核验。
2026-10-23 已读取官方 Guidelines 的 2.4.5、2.5.1、2.5.2：
确认 Sandbox、公开 API、容器访问、禁止 root 提权、自包含应用和 Store 更新机制的约束。
已确认 App Sandbox 官方文档入口可访问；具体 entitlement 和 3.1/4.2 的产品适用性
仍需在 C/E 按实际功能核查，不能以这些条目的阅读代替审核结果。
后续工具重新访问 Guidelines 与 App Sandbox 页面未返回可读正文，
因此不新增已读政策条目的声明。产品按本轮范围不实现购买、付费解锁或外部购买 CTA；
低权重项目说明须与独立可用的工具功能并存，不能将 Store 变成链接集合。
具体 entitlement 仍以实际工程配置、签名证据与运行结果核查。
