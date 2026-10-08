<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Status Trio 八种程序坞图标状态，深色与浅色背景对称排列，包含 Wi-Fi、蓝牙音频、电池、圆点和圆弧状态">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio 应用图标">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>三个系统状态，一个原生 macOS 状态图标 —— 可放在菜单栏或程序坞。</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="下载 macOS 版 —— 通用二进制，需 macOS 15 或更高版本"></a>
</p>

<p align="center">
  想先看看实际效果？打开 <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a>，即可在浏览器里模拟预览各种图标状态。
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="最新版本"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS 工作流状态"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="许可证：Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="支持 macOS 15 或更高版本">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="通用二进制，支持 Apple Silicon 与 Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <strong>简体中文</strong> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio 菜单栏图标：连接 Wi-Fi 时显示 Wi-Fi 图标，并展开状态弹层">
</p>

Status Trio 是一个原生 macOS 状态应用，将 Wi-Fi、电池和音量整合进一个紧凑、可配置的图标，可显示在菜单栏、程序坞，或两处同时显示。弹出面板比图标本身更深入：Wi-Fi 面板可查看附近网络与链路详情，蓝牙面板列出已配对设备，还有电池详情页，以及当前正在播放的音频设备。灵感源自 iPhone Duo 将 Wi-Fi、电池和蜂窝网络合并展示的状态栏图标，并在 Mac 上以音量替代蜂窝网络。

> Status Trio 是独立项目，与 Apple 无隶属关系。

## 主要特性

- **三合一图标**：电池、Wi-Fi 和音量共用一个图标，放在菜单栏、程序坞或两处都行；播放蓝牙音频时，设备自己的图标可以接管中间的位置。
- **蓝牙**：播放时音量指示会变成蓝色。面板列出已配对设备，点一下即可连接或断开，电量默认显示；面板默认不显示，需要时再打开。
- **电池**：电量百分比、充电或已接电源、充满预计时间，电量偏低时会变色；点开可以看适配器功率、电压、电流、循环次数和低电量模式。
- **Wi-Fi**：显示当前网络和信号强度，也能查看附近网络、链路详情，或直接关掉 Wi-Fi。切换网络请在系统设置的 Wi-Fi 面板中操作。
- **音量**：音量大小、静音状态和输出设备，样式可选圆点或圆弧；在面板或音量控件上滚动都能调节，方向也能选。
- **按自己的习惯调整**：图标大小、图标缩放、圆环粗细、状态颜色，以及面板显示哪些区块、按什么顺序排列。
- **菜单栏、程序坞或两处**：程序坞图标可以跟随系统样式，也可以固定为深色或浅色。
- **原生 macOS 操作**：左键打开面板，右键打开菜单，首次启动有引导说明图标每一部分；有线连接、热点或互联网共享也可以继续显示 Wi-Fi 图标。
- **保持最新**：状态由系统事件驱动、低频轮询兜底，Sparkle 通过已签名的更新源更新应用。
- **其他**：十二种语言，以及可选的开机时启动。

## 蓝牙音频

播放蓝牙音频时，**设置 › 蓝牙**中的两个开关可以让中部图标变成该设备自身的图标（AirPods、耳机、音箱等设备各自提供自己的图标），并让音量圆点或圆弧变成蓝色。两者默认关闭。默认开启的**网络异常优先于蓝牙图标**会在连接本身异常时保留网络图标：

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio 菜单栏图标：连接 AirPods 时显示 AirPods 图标，并展开状态弹层">
</p>

弹层中的蓝牙行会显示实时状态：已连接设备的名称，以及 AirPods 的左耳、右耳和充电盒电量。蓝牙面板列出已配对设备及其连接状态：点一下设备即可连接，再点一下已连接的设备即可断开，键盘、鼠标、触控板和手柄会先在行内确认。面板默认关闭，需在**设置 › 状态面板**中开启，首次使用会请求蓝牙权限。**设置 › 蓝牙**还可以控制是否读取电量（默认开启）、列出已配对设备供你拖动排序并设定显示数量，并把蓝牙图标在 100%–180% 之间缩放。

## 程序坞图标

同一个实时图标也可以放在程序坞，而不是菜单栏，或两处同时显示：

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="程序坞中的 Status Trio 实时图标（暗色外观）">
  <br>
  <sub>程序坞图标（暗色外观）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="程序坞中的 Status Trio 实时图标（亮色外观）">
  <br>
  <sub>程序坞图标（亮色外观）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="程序坞中的 Status Trio 与蓝牙区块（亮色外观）">
  <br>
  <sub>蓝牙区块预览</sub>
</p>

程序坞图标绘制的是和菜单栏一致的三合一图标，开启蓝牙音频取代后，设备图标同样会取代中部图标。它的背景可以跟随系统图标样式，也可以固定为深色或浅色：

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio 程序坞图标：两行分别展示 Wi-Fi 状态与蓝牙音频取代 Wi-Fi 图标，各含深色、浅色与透明背景三种样式">
</p>

## 图标状态

三合一图标支持的全部状态，均由应用自身的渲染器绘制 —— 顶部是电池指示，中部是 Wi-Fi 状态（开启该选项后蓝牙音频设备可取代它），底部是音量圆点或圆弧，播放蓝牙音频时会变成蓝色：

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio 图标状态：顶部依次为充电中、已连接电源未充电、已充满、电量数字、低电量、低电量模式、只显示圆环；中部依次为 Wi-Fi 各档信号、未关联、关闭、无互联网、个人热点、临时连接、互联网共享、有线连接；再往下为蓝牙音频取代 Wi-Fi 图标、网络异常时保留 Wi-Fi 图标，以及蓝色圆点与蓝色圆弧；底部为音量圆点与圆弧样式">
</p>

同一批状态在深色菜单栏下的渲染：

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Status Trio 图标状态（深色外观）：白色图标配深色底块，保留充电绿色、低电量红色和低电量模式黄色强调，蓝牙音频使用更亮的蓝色">
</p>

## 系统要求

- 运行 app 需要 macOS 15 或更高版本
- 构建需要带 macOS 26 SDK 的 Swift 6 工具链（Xcode 26 或更高版本）。用更旧的 SDK 构建会静默产出
  Tahoe 之前的弹出面板观感，因此 `scripts/build-app.sh` 在 SDK 低于 26 时会直接失败。

## 从源码运行

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## 构建本地应用

构建 ad-hoc 签名的应用包并启动：

```bash
bash scripts/build-app.sh release
```

应用包位于 `dist/StatusTrio.app`。如果只想构建，不退出或启动现有实例：

```bash
bash scripts/build-app.sh release no-open
```

ad-hoc 签名的应用包适合本地个人使用。如果应用包携带 quarantine 元数据后转移，可能会被 Gatekeeper 拦截。

## 安装 GitHub Release

从 [GitHub Releases](https://github.com/lingyired/status-trio/releases) 下载最新的 `StatusTrio-*.dmg`，打开后将 `Status Trio.app` 拖入 `/Applications`。

当前公开版本使用 ad-hoc 签名，尚未经过 Apple notarization。macOS 首次启动时可能提示：

> Apple 无法验证“Status Trio”是否包含可能危害 Mac 安全或泄漏隐私的恶意软件。

这是 Gatekeeper 因缺少 Developer ID 签名和 Apple 公证而显示的警告，并不代表应用一定包含恶意软件。只有在 DMG 来自官方 GitHub Releases 页面，并且发布的 SHA-256 校验值匹配时，才应绕过此警告。

将应用复制到 `/Applications` 后，移除 quarantine 属性并启动：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

也可以先尝试打开一次应用，然后前往 **系统设置 → 隐私与安全性**，选择 **仍要打开**。

不要全局关闭 Gatekeeper。后续 Sparkle 更新会通过应用的 EdDSA 签名密钥进行验证；通常只有第一次手动安装时需要执行 `xattr` 命令。

## 使用方法

- **左键点击**菜单栏图标或程序坞图标，打开状态弹层。
- **右键点击**图标，显示原生菜单，其中包含版本和退出操作。
- 在弹层中点击 Wi-Fi 或电池行会打开对应页面：Wi-Fi 详情与附近网络、电池详情。蓝牙行则直接在行下列出已配对设备（点一下连接或断开），放不下时用「展开」查看。
- 打开**设置**可以选择图标显示位置（菜单栏 / 程序坞 / 两处），并调整图标大小、颜色、圆环粗细、面板区块及顺序、滚动调节音量行为、语言、更新检查和开机时启动。
- 可随时从**设置 › 应用图标 › 打开指引**重新查看**认识你的图标**引导。
- 如需显示当前 Wi-Fi 网络名称，请按提示启用定位权限；这是可选功能。

## 已知限制

有两条边界，是 macOS 与本项目各自有意划下的。详细说明见[已知限制](docs/known-limitations.md)。

- **切换网络在系统设置里完成。** 在弹层里选择网络会打开 Wi-Fi 面板；Status Trio 从不读取也不保存 Wi-Fi 密码——macOS 没有用已保存密码连接的公开 API，而其他做法最后都会让 app 持有你的密码。
- **「立即充满电」留在 macOS 里。** 当优化电池充电或充电上限使充电暂停时，弹层会如实显示暂停状态并提供跳转到电池面板的入口；没有公开 API 能让应用越过上限恢复充电，Status Trio 也不会为此写 SMC 或附带特权 helper。

## 支持的语言

Status Trio 默认跟随 macOS 首选语言，支持 English、简体中文、繁体中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português (Brasil)、Русский 和 العربية。

## 隐私

Status Trio 通过 macOS 公开框架读取系统状态。匿名使用统计为可选功能，只有你主动开启后才会向第一方服务发送简短心跳；升级用户默认关闭，新安装用户会在引导中选择。心跳包含随机安装 ID、应用和 macOS 版本、语言及图标位置，不包含姓名、账户详情、网络详情或硬件标识符。完整字段、同意方式和保留期限请见[遥测与隐私说明](docs/privacy-telemetry.md)。Status Trio 不会读取或保存 Wi-Fi 密码，也不会请求钥匙串访问。定位权限为可选项，仅在用户选择显示当前 Wi-Fi 网络名称或打开 Wi-Fi 详情时请求。蓝牙权限仅在显示蓝牙面板时请求，用于显示已配对设备的连接状态。

## 开发

运行完整测试：

```bash
swift test
```

通过测试辅助脚本运行指定的 XCTest：

```bash
bash scripts/test.sh BatteryMonitorTests
```

在主应用之外运行 worktree 构建：

```bash
bash scripts/build-worktree.sh release
```

该脚本会根据当前分支生成开发版 bundle identifier 和显示名称，也可以通过环境变量覆盖：

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

单实例锁按 bundle identifier 隔离，因此不同标识的构建可以同时运行。

## 技术基线

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` 菜单栏辅助应用，显示程序坞图标时切换为常规应用策略
- 使用 Sparkle 检查更新

## 文档

- [已知限制](docs/known-limitations.md)
- [GitHub Actions 自动发布](docs/github-actions-release.md)
- [Status Trio 设计规格](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [菜单栏图标 SVG](status-menubar.svg)
- [数据驱动图标演示](status-menubar-demo.html)

## 许可证

Copyright 2026 lingyired。

本项目采用 Apache License 2.0 许可。详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。

## 作者

由 [lingyired](https://github.com/lingyired) 创建并维护。<br>
主页：[https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
