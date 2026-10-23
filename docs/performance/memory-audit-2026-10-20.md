# Status Trio 内存分析（2026-10-20）

## 当前实施结论

五类优化和内存压力回收已完成代码修改，位于 `codex/memory-optimization`。
用户已授权提交、合并和推送；独立审查和非发布 CI 预检已通过，结果见文末集成记录。
静态历史缓存的实际像素上限从 12 MiB 降到 4 MiB；512 px 充电变体构建峰值
从约 37.17 MiB 降到 19.10 MiB。它们是像素预算，不是进程 footprint 的承诺。

固定关闭 UI 的最终三组对照：main 中位数 14.657 MiB，
优化版 14.860 MiB（+0.203 MiB）；未证明静置常驻下降。
收益集中于历史图片、导入大图和充电帧构建期间。首轮一次 35 MiB 异常原因未确定，
后续五次优化版运行未再复现，原始数据全部保留。

最终本地全量测试、Release 构建及 CI Xcode26.6/Swift6.3.3 预检通过。
真实 Dock 动画对照及硬件/系统版本验收仍未完成，不能将本次集成视为这些场景的验收。

## 初次分析结论

优先缩小 Dock 静态图标缓存，并在退出 Dock 展示时释放它。当前缓存装满时保存
12 MiB 原始像素；若改成 2–4 张，可少持有约 8–10 MiB 原始像素。实际进程物理
内存降幅需要同场景 A/B 测量，不能直接等同于这个数字。

之后再处理图片解码预算、充电动画缓存的构建峰值，以及引导页隐藏内容。没有证据
支持通过删减监控服务或清空所有缓存来解决当前内存问题。

分析完成后已在独立工作树 `codex/memory-optimization` 实施以下优化。下文分析部分描述
`main@579968ca6f4f1ff5bb668a634c568d238748bdcb` 的原始行为；实施结果和实际对照测量
见文末。实施和测量阶段没有改动生产应用的设置；本次集成不创建版本发布。

## 基线与证据边界

- 源码：本地 `main@579968ca6f4f1ff5bb668a634c568d238748bdcb`，比本地
  `origin/main` 多两个提交，包含 Dock 独立充电动画。没有 fetch，因此不声称它等于远端最新 main。
- 当前运行 PID `49051` 的路径是另一工作树的
  `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/dist-dev/Status Trio Dev.app/Contents/MacOS/StatusTrio`。
  它不是本次 main 的运行基线。
- 对该 Dev 进程的 `vmmap -summary`：物理 footprint 154.9 MiB，历史峰值
  471.0 MiB，CG Raster Data 46.9 MiB。`heap -s` 的 malloc 存活分配约
  47.6 MiB；这些统计有不同口径，不应相加，也不能据此证明泄漏或归因到 main。
- main 的渲染成本通过临时 `MemoryAudit20261020ProbeTests` 调用真实 renderer/cache
  测量。最终一次运行 1 个测试通过，随后删除探针文件。它是离线渲染测量，
  不是 main 完整应用、Dock/WindowServer 或真实充电场景的验收。
- 本地 Swift 6.4 / macOS 27 SDK。初次分析阶段没有产品代码改动，也没有执行发布预检；
  测量测试不替代 CI 的 Xcode 26.6 / Swift 6.3.3 验收。

## 真实渲染的像素成本

场景：电量 62%、正在充电、Wi-Fi 已连接、音量 50%、标准图标配置、深色 Dock。
原始像素成本按 `CGImage.bytesPerRow * height` 或 `NSBitmapImageRep.bytesPerRow * pixelsHigh`
计算。它不包含对象、Core Animation、驱动或系统缓存的额外占用。

| 缓存 | 尺寸 | 原始像素总量 | 测量说明 |
|---|---:|---:|---|
| Dock 静态图标 | 512 × 512，12 张 | 12.00 MiB | 12 个不同电量状态 |
| Dock 稳态充电帧 | 128 px tile，裁剪为 102 × 84 | 2.35 MiB | 36 帧 × 2 个心跳变体 |
| Dock 稳态充电帧 | 192 px tile，裁剪为 152 × 126 | 5.26 MiB | 36 帧 × 2 个心跳变体 |
| Dock 稳态充电帧 | 256 px tile，裁剪为 202 × 168 | 9.32 MiB | 36 帧 × 2 个心跳变体 |
| Dock 稳态充电帧 | 512 px tile，裁剪为 404 × 335 | 18.59 MiB | 字节预算触发，只保留 1 组 |
| 菜单栏充电帧 | 24 pt @2x | 0.63 MiB | 36 帧 × 2 个心跳变体 |
| 菜单栏充电帧 | 36 pt @2x | 1.42 MiB | 36 帧 × 2 个心跳变体 |

Dock 动画的实际 tile 尺寸由 `DockChargingAnimationPresenter.resolvedPixelLength`
按 Dock 尺寸量化，不能把 512 px 的成本当作所有用户的日常成本。表中两个心跳
变体是主动预热后的结果，不表示启动时就都存在。各行是独立情境，不能相加。

临时探针同时记录过 footprint 前后差值，但渲染顺序、系统预热和 allocator 页面复用
会影响它；因此不拿那些差值推算优化后的实际收益。

## 冻结 main 的优化点

以下源码行号指冻结的 main；当前实现已改变，见文末实施结果。

### 1. Dock 静态图标：缩小容量，停止展示时清理（优先）

证据：`Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift:60` 默认保存
12 张图片；`Sources/StatusTrioCore/App/AppIconController.swift:183` 的
`clearDockIcon()` 只清应用图标和 render key，没有调用 `imageCache.reset()`。
`stop()` 也经过这个路径。

即使用户只为打开设置而临时进入 regular 模式，已产生的 Dock 栅格也可在返回
菜单栏模式后继续留在 cache 中。缓存逐渐装满才达到表中的 12 MiB，并非每次
打开设置都会分配满。

建议把真实 Dock 的缓存与预览缓存分别配置：真实 Dock 先试 2–4 张或 2–4 MiB
像素预算；永久切回菜单栏模式及停止 controller 时清理，避免在频繁自动隐藏/
显示 Dock 的每个瞬间清理。预览仍可使用较多的小图片。

收益边界：装满时少持有 8–10 MiB 原始像素，完全退出 Dock 后可释放该缓存持有的
最多 12 MiB。系统可能继续保留 allocator 页面或应用图标副本，footprint 不保证
同步下降。容量减少会增加来回状态切换的重绘次数，应同步观察 CPU。

### 2. 图片解码：按目标尺寸与字节预算缓存（条件性高收益）

证据：`Sources/StatusTrioCore/UI/Icon/IconImageDecodeCache.swift:30` 只限制
8 个条目，`:80` 直接用 `NSImage(contentsOf:)` 保留原图对象，未限制表示尺寸/
解码成本；`:46` 同一 URL 的原图与输入法单色 mask 分别缓存。
`Sources/StatusTrioCore/UI/Icon/InputSourceIconMask.swift:17` 按源图 point size
乘 4 栅格化，允许到 1024 × 1024，每张这样的 RGBA mask 可达 4 MiB。

这说明有放大内存成本的路径，不说明当前用户已加载大图。NSImage 还可能延迟解码，
因此不能把原文件尺寸直接当作当前已占用内存。

建议收集实际音频设备/输入法图片的 representation 尺寸，再按菜单栏、Dock 和预览
三条路径的最大实际像素需求生成受限栅格，同时增加总字节预算与内存压力清理。
不要直接统一缩成菜单栏尺寸，否则 Dock 可能模糊。输入法 mask 也应按显示目标
构建，保留现有黑白底色识别和可见墨迹居中算法。

收益：取决于真实输入图，目前未量化。若实际图片均很小，优先级应降低。

### 3. 充电动画：控制构建峰值与失效粒度（保留 CPU 优化）

证据：`Sources/StatusTrioCore/UI/Icon/DockChargingFrameCache.swift:64` 先构建
新 36 帧，再在 `:83` 插入并裁剪旧组。512 px 标准场景中，切换心跳变体时旧组和
新组可暂时同时存在，约 37.17 MiB 原始帧像素，之后才降回 18.59 MiB。
24 MiB 是构建后的裁剪预算，不是构建过程的硬上限；实现还刻意保留至少一组。

`Sources/StatusTrioCore/UI/Icon/DockChargingAnimationPresenter.swift:234` 的
base key 包括整个 scene，`:252` 在 base 变化时重置 effect 帧缓存。音量/footer 等
变化也会导致充电效果帧重建，尽管 overlay 只绘制 ring effect/accessory。

建议先在预计超预算时退休可丢弃的旧组，保留当前画面和失败回退；再把 effect 的
失效条件缩小到其真实依赖，避免无关 scene 变化重建。需要对不同 ring、背景、
尺寸与充电状态做像素一致性验证。

收益边界：主要降低大 tile 的构建峰值和分配抖动；缩小失效范围本身不降低稳态
帧组大小。128 px 场景两组仅 2.35 MiB，不宜为了省这些内存改回每帧全量重绘，
也不应直接降低帧率或删掉心跳效果。

### 4. 引导页：仅挂载当前页的重型预览（窗口打开时收益）

证据：`Sources/StatusTrioCore/UI/IconGuideOnboardingView.swift:42` 的 ZStack
同时包含 anatomy 和 states 页面，仅通过 opacity、点击与无障碍状态切换。
`Sources/StatusTrioCore/UI/IconGuideView.swift:500` 还有 repeatForever pulse。
隐藏页仍在 view tree 中，但隐藏时实际动画/渲染成本尚未通过 Instruments 确认。

建议用条件分支挂载当前页，保留固定/测量后的容器高度、页面切换状态、动画和
无障碍行为。收益应在引导窗口打开时测量，不能承诺降低关闭后的常驻内存。

设置默认页的九个选项预览是对比选择所需 UI；目前不建议通过删掉未选中预览来
省内存。现有 Dock 预览已限制到 128 px，32 张最多约 2 MiB 原始像素，收益有限。

### 5. 蓝牙历史 token 与失效报告：长期运行清理（较低优先级）

证据：`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:410`
的 `nearbyBLEReadRevisions`、`Sources/StatusTrioCore/Monitoring/NearbyBLEReadAuthorization.swift:60`
的 revisions，以及 `Sources/StatusTrioCore/Audio/BluetoothListeningModeController.swift:91`
的 generations 随历史设备标识增长，没有统一退休机制。

这些字段保存少量 token，实际收益取决于设备标识更替频率，不足以解释几十/
上百 MiB 占用。清理必须保留撤销授权后拒绝旧异步结果的语义，不能简单 removeAll
再从 0 计数，否则旧回调可能重新匹配 token。

`Sources/StatusTrioCore/Monitoring/BluetoothProfilerReportCache.swift:31` 在报告
超过 5 秒后返回 nil，但仍持有最后一份 Data。可以在确定失效或服务停用时释放，
收益上限为该份报告的实际大小，未测量。

已排除一个误判：`BluetoothDeviceController.swift:1101` 已过滤过期的
`nearbyBLEInitialReadSuppressedUntil`，它不是已证实的无限增长字典；scanner 的
retryAfter 也在下一轮扫描开始时过期清理。回调捕获 Dictionary 使用 Swift
copy-on-write，不能声称每次捕获都深拷贝整个字典。

## 已有释放机制，暂不作为泄漏结论

`SettingsWindowController.swift:80` 和 `OnboardingWindowController.swift:51`
在关闭时清空 window；`StatusBarController.swift:576` 在普通弹窗关闭 60 秒后
清空 contentViewController 并停止 panel view model，详情页则立即处理。
初次分析时，窗口/hosting view 的最终 deinit 尚未用弱引用探针验证，不能只因进程 footprint
没有立即回落就认定泄漏。60 秒内重开会延长保留时间，这是现有复用策略。

Dock renderer 的六个 scratch context、32 张小预览，以及两个墨迹偏移字典也可接入
统一内存压力处理，但前两者已有数量/尺寸约束，后者只存小量数值，优先级低于
真实 Dock 图像缓存。Helper 的两秒轮询主要是 CPU/唤醒问题，本次未建立其内存
持续增长的因果证据。

## 实施与验收顺序

1. 先做第 1 项；覆盖缓存淘汰、停止/隐藏时释放、重新展示、菜单栏与 Dock 像素一致性。
2. 用独立 bundle ID 的 main Release 构建建立基线：菜单栏静置、打开/关闭设置后
   65 秒、引导页切换、真实 Dock 充电动画，分别取 footprint 和图像分配，记录 tile 尺寸。
3. 同场景 A/B 比较第 1 项，再决定第 2、3 项是否值得做；同时记录 app/Dock CPU，
   避免用更高重绘成本换取小量内存。
4. 产品 Swift 改动后跑 `swift test`、`swift build -c release` 和
   `swift test --filter Issue30WiFiAlignmentTests`；触及项目规定的隔离/UI binding 等
   路径时，在合并/发布前完成 `publish=false` 的 CI 预检。

## 本机原始测量文件

- `/tmp/status-trio-memory-audit-20261020.log`：main 临时渲染探针输出。
- `/tmp/status-trio-running-dev-memory-20261020.txt`：其他工作树 Dev 进程 vmmap。
- `/tmp/status-trio-running-dev-heap-20261020.txt`：同一 Dev 进程 heap 统计。

这些是临时文件，可能被系统清理；本报告保留了可用于决策的主要测量数值。


## 实施结果（独立工作树）

- Dock 静态历史缓存改为 4 项 / 4 MiB；永久离开 Dock 或停止时清理。
  小预览单独保留 32 项 / 2 MiB。按插入时实际 bitmap stride 和 planes 计费。
- 图片通过 ImageIO thumbnail / 有界 PDF context 解码到最长边 512 px；输入法 mask
  最长边 128 px，二者合计 8 项 / 8 MiB。保留逻辑 point size 和可见墨迹坐标，
  导入图的墨迹测量最长边限制为 1024 px；SF Symbol 的原有 8x 测量不变。
- Dock effect key 独立于 center/footer；无关音量变化不再重建充电帧组。
  新组探测一帧后即退休超预算旧组，避免两组完整 512 px 像素同时存留。
- 引导页只挂载当前页；关闭时清空 hosting controller，原生弱引用探针确认释放。
- 蓝牙仅保存当前有效 UUID token，撤销后迟到结果不能复活；过期 profiler Data
  清除，环境停止显式清理。内存压力通过 OS warning/critical 事件清历史和备用缓存，
  保留正在播放的动画组，不增加轮询 timer。

### 确定性像素预算（不是进程 footprint）

| 情境 | main 原始值 | 优化后 | 证据 |
|---|---:|---:|---|
| 12 个 Dock 静态状态 | 12.00 MiB | 4.00 MiB | 真实 renderer 与缓存 byteCount |
| 512 px 两种心跳的构建峰值 | 约 37.17 MiB | 19.10 MiB | 旧组与新组构建中的实际 stride 求和 |
| 512 px 当前帧组 | 18.59 MiB | 18.59 MiB | 保留 36 帧和 20 FPS |
| scratch context | 最多 6 个不同尺寸 | ≤4 MiB 且最多 6 个 | 真实 context byteCount / reset |

构建峰值指标不包含 presenter 当前 overlay、renderer scratch、驱动和系统副本。
释放 cache 引用不保证 macOS 同步归还 allocator 页面。

### 本地验证边界

测量包使用 main 与优化版分别编译的 Release Swift 可执行文件，配合同一份既有
mobile helper payload（SHA256 `9c9f1969f86e4c0673713b7bbd5fd7edb3f2cca3989f3b8ec6eed44943777714`）。
这是为绕开本机依赖下载 SSL 失败的测量组装，不代表重新源码构建了 mobile helper
或通过正式发行打包验收。生产设置不变，测量 defaults 域为
`com.lingsmbp.StatusTrio.dev.memory-measurement`。

main 菜单栏冷启动预热 15 秒后 60 个样本：footprint 中位数 22.923 MiB、峰值
22.970 MiB。不能把另一开发版本的 154.9 MiB 与此值直接比较。

自动化原生布局、像素和生命周期测试不能替代真实拔插、充满、Reduce Motion、
睡眠/唤醒、多显示器与各 Dock 方向的硬件验收。CI 的 Xcode 26.6 / Swift 6.3.3
预检已通过（运行 `39377387434`，详见集成记录）；硬件验收边界仍保留。

### 最终本地验证

- `swift test`：1717 XCTest，7 skipped，0 failures；697 Swift Testing，103 suites，0 failures。
- `swift build -c release`：最终源码构建通过，37.86 秒。
- Issue30 六项实际可见墨迹回归通过，未改 59.5 或放宽容差；菜单栏与 Dock 的完整像素/布局测试通过。
- Python 测量工具 2 项测试、forbidden actor pattern 检查、macOS 13 deployment contract 通过。
- `VERSION=1.6.1 BUILD=38 PUBLISH=false bash scripts/validate-appcast-notes.sh` 通过：当前基线 notes 有 en/zh-Hans 2/12，符合非发布校验要求；没有生成或改写正式 appcast。
- 独立审查覆盖 Task1/2/3/4/5/6；修复了 planar 计费、初读 token 转移、过期后台写入、重新解码后居中偏移、PDF 旋转和失败渲染回退反复分配。压力触发的完整回收链与实际 NSPopover 开/关均有测试。

整个 AppEnvironment 的 stop 后重启不是本次新增能力：SystemStatusStore 已有 stop 后终止的测试契约。MemoryPressureMonitor 自身的 start/stop、再启动和迟到事件隔离已验证。

### 第一轮进程 A/B（全部原始样本保留）

协议：相同测量 bundle ID，Release、合成充电输入、menuBar、两种动画均关闭，
15 秒预热后 libproc 每秒取样 60 次；CPU 同时取样，app / Dock / WindowServer 分列。
顺序 A→B、B→A、A→B。不是当前运行的另一个 Dev 进程。

| 组 | main 中位数 / 峰值 MiB | 优化版中位数 / 峰值 MiB | app CPU 均值 main→优化 |
|---|---:|---:|---:|
| 1 | 14.657 / 14.766 | 35.173 / 35.454 | 0.01% → 0.03% |
| 2 | 14.532 / 14.610 | 14.891 / 14.970 | 0.01% → 0.02% |
| 3 | 14.563 / 14.641 | 14.891 / 14.970 | 0.02% → 0.00% |

三个运行中位数再取中位数：main 14.563 MiB，优化版 14.891 MiB（+0.328 MiB）。
app CPU 各组差值均低于 0.5 个百分点门槛；Dock 在两边均约 0.00–0.04%。
WindowServer 为 29–58%，不将其变化归因到 app。当前数据不能支持“常驻内存整体下降”。

第 1 组优化版是必须保留的异常：两边 CG Raster Data 均为 1984 KiB；
默认 malloc zone 的分配计数为 35,368 与 75,080，后者额外存在 AttributeGraph zone，
但显式 AttributeGraph 分配只约 56 KiB，不能拿它解释全部约 20 MiB 差值。
第 2、3 组优化版回到约 35,263–35,266 个默认区分配。
代码复核未找到静置启动新建 hosting/window 的路径；无法由当前证据确定异常原因，
不声称是系统噪声、用户点击或优化收益。第一轮起始阶段没有窗口记录。

补测每次启动显式固定引导完成、telemetryConsentVersion=1、统计关闭，另用只读
CGWindowList observer 记录目标 PID 的可见窗口（不记录标题或内容）。
补测结果另列，第一轮异常不从原始记录中删除。

Dock/on 在首个 main 样本未观察到 ChargingEffectClock，既有 CPU 工具拒绝生成零成本
成功数据；其余 5 次记为 not_run。没有修改 Dock 自动隐藏或其他系统设置以绕过门槛。
因此真实 Dock 动画 footprint / CPU 的前后对照仍未完成。

原始目录：`/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/`。
`task7-final-20261020T0433/summary.json` 含六次有效静置取样和 Dock 缺测记录；
`passive-window-observation.jsonl` 是后加的窗口记录。
第一次调度 `task7-final-20261020T0432` 在启动前因只读环境变量冲突失败，
没有有效样本；修复只涉及测量编排脚本，失败记录保留在 ledger.tsv。

### 补测：明确关闭 UI 的三组对照

每次启动显式设置 hasCompletedIconGuideOnboarding.v1=true、hasSeenIconGuide=true、
telemetryConsentVersion=1、sharesAnonymousAnalytics=false；其余取样协议和二进制不变。
只读窗口记录对每个目标 PID 覆盖 82–83 次采样，均未记录到可见窗口。

| 组 | main 中位数 / 峰值 MiB | 优化版中位数 / 峰值 MiB | app CPU 均值 main→优化 |
|---|---:|---:|---:|
| 1 | 14.563 / 14.641 | 14.720 / 14.782 | 0.02% → 0.01% |
| 2 | 14.704 / 14.798 | 14.860 / 14.923 | 0.02% → 0.01% |
| 3 | 14.657 / 14.720 | 15.016 / 15.063 | 0.02% → 0.01% |

三个运行中位数再取中位数为 14.657 / 14.860 MiB；
各组配对差为 +0.156、+0.156、+0.359 MiB。app CPU 跨组均值
0.02% / 0.01%，各组均未超过 0.5 个百分点门槛。
优化版在补测三次中的最高取样 footprint 为 15.063 MiB。

原始结果为 `task7-confirm-20261020T0444/summary.json`；第一轮 outlier 保留，不混合
不同前置条件计算一个更好看的数字，也不将此补测解释为已确定第一次异常原因。

测量可执行文件 SHA256：

- main：`683de16dc66629fa8e3a27942a9a641641ac9629b8acbdd368272df47b1b05cc`
- 优化版：`32ff1987d3ef92b49ad4af6ebe26d8f67c66c65f6103711029e6e3fec3d9c7ef`
- 优化版 Sources 内容 SHA256：`73f1a289b97b06f5f2252cf5c7c185c74a098e40214319657eb9a25566498fb0`

最终源码在测量后重新核对，Sources hash 与组装时一致。测量进程和只读窗口 observer
均已停止；生产应用和生产 defaults 域没有替换或修改。验证日志和工具快照保存在
原始目录的 `final-validation/` 与 `tool-snapshot/`。

### 尚未完成的验收

- 真实 Dock 可见时的充电 CPU / footprint、真正拔插/充满、Reduce Motion、睡眠/唤醒、
  多显示器、左/右 Dock、放大和 macOS13实际窗口布局。
- 设置/弹窗20次及引导切换20次的完整应用 footprint 对照、全部12语言真实截图；
  当前已有原生布局、弱引用释放和 open/closed popover 测试，不能替代这些实测。
- 首轮单次 35 MiB 启动异常的确切原因仍未知，首次升级后的实际启动应保留观察。

### 集成验证记录（2026-10-20）

- 内存实现提交 `04206b5`，测试调度修复提交 `8728003`；两次独立审查均未发现
  P0/P1/P2 问题。首次 CI `39376165822` 的测试失败、复现和修复见
  `docs/swift-ci-compatibility.md`，未将该失败当作通过证据。
- [CI 39377387434](https://github.com/lingyired/status-trio/actions/runs/39377387434)
  对 head `87280038f94d57255a97d8dac96642265053a71a` 全部通过：
  macos-26、Xcode 26.6、Swift 6.3.3；1727 XCTest（7 skipped、0 failures），
  697 Swift Testing / 103 suites，以及 native compatibility tests。
- 完成 arm64/x86_64 Release、mobile battery helper 源码打包与两种 helper bundle
  验证、平台 SDK 元数据校验、DMG 创建及 artifact 上传。参数为
  `version=1.6.1 build=38 publish=false notarize=false`；Ad-hoc 签名，未执行公证、
  未创建 Release/tag 或发布 appcast。
- 测试修复后的本地复验为 1717 XCTest（7 skipped）与 697 Swift Testing 全部通过；
  `swift build -c release` 通过（33.35 秒）。本地与 CI 的 XCTest 发现数量分别记录。
- 最终证据补充仅修改文档；Sources/Tests/scripts 与 CI 通过的 `8728003` 一致。
  实机/Dock CPU 对照、硬件矩阵与启动 outlier 的未完成事项保持原样，不用 CI 替代。
