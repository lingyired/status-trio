# Status Trio 全部内存优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成内存分析报告中的五类优化及配套缓存回收，在保留菜单栏、Dock 和现有交互的前提下，减少可回收的常驻图像、分配峰值和历史设备状态。

**Architecture:** 沿用现有 renderer、缓存和 controller，分别收紧图像预算、对象生命周期与异步授权 token 的保留范围。缓存失效必须遵循实际绘制依赖；内存压力回收只退休可重建资源，保留当前画面并防止逐帧重建。性能结论以同一 main 基线、相同场景的 Release 构建 A/B 为准。

**Tech Stack:** Swift、AppKit、SwiftUI、CoreGraphics、ImageIO、Dispatch、Swift Testing/XCTest、SwiftPM、GitHub Actions。

**Spec:** `docs/performance/memory-audit-2026-10-20.md`，本计划补充具体预算、实现边界和验收条件。

## Global Constraints

- 仓库根目录：`/Users/lingsmbp/Documents/aiwork/status-trio`；下文文件清单相对该目录。分析基线为本地 `main@579968ca6f4f1ff5bb668a634c568d238748bdcb`。执行前重新确认 main；如有新提交先核对相关实现，不覆盖新修复。
- 支持 macOS 13；构建 SDK 必须为 macOS 26 或更新。CI 验收为 `macos-26`、Xcode `26.6`、Swift `6.3.3`，本地 Swift 6.4 通过不代替 CI。保留 SDK 与 `LC_BUILD_VERSION` 检查。
- 不使用 `isolated deinit`、`weak let` 或实验隔离编译标志；actor 方法作为回调时使用显式 closure。
- 菜单栏和 Dock 图标表现同步；保留 `StatusIconGeometry.artworkCenterX = 59.5`、可见墨迹居中、颜色、template 分层、图标选项和深浅/clear 背景。
- 保留 20 FPS、36 帧稳态、1.8 秒循环、0.6 秒 burst、1.35 心跳、Reduce Motion、睡眠/唤醒、Dock 隐藏/重现及独立开关。
- 不删设置页九个对比预览，不改变匿名统计偏好、蓝牙授权范围、设备电量可用性或 Helper 行为。报告排除的两秒轮询不作为内存改动。
- 全部五类均实施；收益未量化的项先补回归证据，再做有界修改。窗口实际泄漏若未复现，只增加释放验证，不臆造清理补丁；这是该调查项的完成条件。
- 当前主工作区有用户改动和产物。执行时用基于 main 的独立 `codex/memory-optimization` 工作树，遵循 `using-git-worktrees`；只带入本报告与计划，不自动搬运其他未提交文件。
- 用户以“继续”授权后，已在独立工作树实施全部五类修改并通过本地全量测试和 Release 构建。用户随后授权提交、合并和推送，包含必要的 `publish=false` CI 预检；不创建版本发布。完整场景矩阵与外部验收的未完成项保留为明确交付边界。

## Review Focus

1. 大图、PDF/ICNS、多表示图像及偏心墨迹：缩采样后 Dock 清晰，输入法黑白图可读，几何和 #30 不回归，由任务 2 验证。
2. 充电开关、粗细、心跳、背景或电量变化：效果缓存必须失效；仅音量/中心变化则不重建独立 ring overlay，由任务 3 验证。
3. 撤销后重选同一 UUID/地址、停止后迟到回调：旧授权绝不复活，initial read 保持现有安全边界，由任务 5 验证。
4. 解码或构帧期间收到内存压力：不会复活已清缓存、死锁、丢失画面或每 50 ms 重建全组，由任务 2、3、6 验证。
5. 快速开关设置/引导/弹窗和页面切换：布局、无障碍、临时 activation policy、60 秒弹窗复用均保留，由任务 1、4、6 验证。

## 执行分工与顺序

| 顺序 | 任务 | 执行者与依赖 |
|---|---|---|
| 0 | main 基线、隔离构建和可重复测量 | 主代理先完成，避免把正在运行的其他 Dev 版当 main |
| 1 | Dock 静态缓存容量/生命周期 | `group/auto-deepseek-v4-1-flash`；工具可用模型别名为 `auto/deepseek-v4.1-flash` |
| 2 | 图片解码与 mask | 同上；与任务 1 可并行，任务 1 不改 renderer |
| 3 | 充电帧预算/失效粒度 | 主代理或独立 DeepSeek worker；任务 2 完成后串行，避免同时修改 renderer |
| 4 | 引导页按需挂载与窗口释放验证 | 独立 DeepSeek worker；可与任务 1、2、5 并行 |
| 5 | 蓝牙历史 token/失效报告 | 独立 DeepSeek worker；可并行，写集仅 Monitoring/Audio 及其测试 |
| 6 | 内存压力回收与收尾集成 | 主代理，在任务 1–5 接口稳定后完成 |
| 7 | 全套回归、A/B、CI 验收 | 主代理整合并审查，不把 worker 自述当通过证据 |

每个 worker 只获得所属任务、全局约束及报告；直接修改其隔离写集并交付 diff、测试结果和风险。主代理先做任务 0，同时安排独立任务，不把当前阻塞任务交出后空等。只在依赖结果确实阻塞时等待。此表定义未来执行方法，本轮不派发实现。

## 初始预算和共同规则

| 资源 | 执行后的初始策略 | 收益/限制 |
|---|---|---|
| 真实 Dock 静态图 | 4 条目且最多 4 MiB 原始像素 | 对比装满 12 张，少持有约 8 MiB；永久退出 Dock/stop 后缓存为 0 |
| Dock 预览 | 保留最多 32 条目，增加 2 MiB 像素预算，最大 128 px | 保留全部选项预览；不与真实 Dock 共用小容量配置 |
| 解码原图与 mask | 合计最多 8 条目、8 MiB；原图输出最长边最多 512 px，mask 最多 128 px | 512 px 是兼顾当前最大 Dock 输出的保守上限；若实际目的尺寸更小可用量化尺寸桶 |
| Dock 充电帧 | 保留既有最多 2 组、24 MiB 策略；构建前腾出预算 | 若一整组自身超限，明确记录单组例外；不称其为硬物理内存上限 |
| scratch contexts | 最多 6 个且最多 4 MiB，LRU | 单个 context 大于预算时只临时使用，不入缓存 |
| 墨迹偏移 | symbol 最多 256 条，image 最多 64 条，LRU | 仅淘汰并重测，不改测量方法与数值精度 |

预算统计采用归一化后的真实 bitmap bytes；未知成本的惰性 NSImage 必须先变成可计费表示，不能按 0 字节入缓存。条目替换减去旧成本；超预算单图照常返回给调用者但不持有。预算调整必须附 A/B 证据并更新本表；不能为了“完成”而静默抬高上限。

### Task 0: 建立可重复 main 基线与测量工具

**Files:** Create `scripts/measure-memory.py`；Create `Tests/StatusTrioCoreTests/MemoryBudgetRenderingTests.swift`；更新 `docs/performance/memory-audit-2026-10-20.md` 保存基线证据。

**Interfaces:** 工具命令 `python3 scripts/measure-memory.py --pid <pid> --seconds 60 --output <json-path>`。只读指定 PID，检查可执行文件路径及开始时间，输出 footprint/RSS 的中位数、峰值、取样次数和可用的 vmmap 图像摘要；不启动、退出或修改生产进程。

- [x] 确认 main SHA、工作区差异，建立隔离执行工作树；确认现有报告和计划完整带入。用同一测量 bundle ID 顺序运行基线/优化版，避免同时出现不同 defaults 域或两个样本进程。
- [x] 保存静态/帧组精确像素成本探针，复用现有 renderer fixture。测试只验证预算与输出，不把常量自身相等当收益。用 `CGImage.bytesPerRow * height`，不以对象数量估计字节。
- [x] 实现上述只读工具，footprint 使用 `proc_pid_rusage`/`RUSAGE_INFO_V4`，RSS 另列；PID 无权限、退出或身份改变时明确失败，不输出 0 内存的成功记录。vmmap/heap 可读失败不伪装为空结果。使用原始 byte 和 MiB 两种单位。
- [ ] 按任务 7 的场景表建立基线；冻结设置/输入、记录显示器/Dock 尺寸、构建 SHA 和工具链。测量域关闭引导自动弹出和统计上传；不得改用户生产域。仅记录用户显式打开的 UI 场景。
- [x] 运行 `swift test --filter MemoryBudgetRenderingTests` 并保存 raw log；记录静态满缓存 12 MiB 和不同 tile 的帧组数据。验证工具 JSON 确有目标 PID/path 与非零有效样本。

### Task 1: Dock 静态缓存和生命周期

**Files:** Modify `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`、`DockIconPreviewCache.swift`、`Sources/StatusTrioCore/App/AppIconController.swift`；Test `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift`、`DockIconPreviewCacheTests.swift`、`AppIconControllerTests.swift`。

**Interfaces:** `DockIconImageCache.init(limit: Int = 4, maximumResidentBytes: Int = 4 * 1024 * 1024)`；只读 `entryCount: Int`、`residentByteCount: Int`；保留现有 `image(for:)`、`store(_:for:)`、`reset()`。Preview 显式传 32/2 MiB，不能沿用真实 Dock 默认容量。

- [x] 先加入大/小实际 bitmap 混合淘汰、同 key 替换、超大图不持有、最近使用顺序、reset 归零测试。用下面的行为检查，fixture 以真实 `NSBitmapImageRep` 创建，不用空 `NSImage(size:)` 证明预算：
  ```swift
  #expect(cache.entryCount <= 4)
  #expect(cache.residentByteCount <= 4 * 1024 * 1024)
  cache.reset()
  #expect(cache.residentByteCount == 0)
  ```
- [x] 运行 `swift test --filter 'DockIconRenderCacheTests|DockIconPreviewCacheTests|AppIconControllerTests'`，确认新预算/释放用例先失败，再加入实际成本记录与双条件 LRU 淘汰。
- [x] 在 `clearDockIcon()` 中无条件清理 image cache，再处理 `hasRenderedDockIcon`；`stop()` 即便没有已设置的应用图标也释放缓存。永久退出 Dock 或临时设置窗口结束后退出 regular 模式时归零；保留自动隐藏期间的复用策略。
- [x] 增加 controller 的行为测试：填缓存→退出 Dock→相同状态重新展示应再次调用 renderer；反复 show()/stop() 可重入；自动隐藏/重现无静态缓存清空风暴；预览不会被退化为 4 张。
- [x] 重跑上述过滤测试和 `swift test --filter Issue30WiFiAlignmentTests`。验收满缓存不超过 4 MiB，退出生命周期后为 0，视觉和重新展示不变。

### Task 2: 图片解码、输入法 mask 与总字节预算

**Files:** Modify `Sources/StatusTrioCore/UI/Icon/IconImageDecodeCache.swift`、`InputSourceIconMask.swift`、`StatusIconRenderer.swift`、`Sources/StatusTrioCore/UI/InputSourceListView.swift`；Create `Sources/StatusTrioCore/UI/Icon/IconImageRasterizer.swift`；Test `Tests/StatusTrioCoreTests/IconImageDecodeCacheTests.swift`、`InputSourceIconMaskTests.swift`、`InputSourceIconRenderingTests.swift`；Create `Tests/StatusTrioCoreTests/IconImageRasterizerTests.swift`。

**Interfaces:** 保留现有 decode/mask 调用签名并增加有默认值的预算参数；`IconImageRasterizer.image(at: URL, maximumPixelLength: Int) -> NSImage?` 负责产出有界、单 bitmap 表示；`IconImageDecodeCache.reset()`、`residentByteCount: Int`、`entryCount: Int` 提供统一清理/测量。`InputSourceIconMask.make(from:pixelScale:maximumPixelLength:)` 的新参数默认 128。

- [x] 为 4096 px PNG、横长透明图、非正方形、PDF、ICNS、多表示图、损坏文件、透明/偏心墨迹建立输入 fixture；先写输出最长边、实际 bytes、失败后可重试和 menu/Dock 墨迹位置测试。按目标尺寸限制像素而不裁剪内容，不放大低分辨率源图。
- [x] 运行 `swift test --filter 'IconImageRasterizerTests|IconImageDecodeCacheTests|InputSourceIconMaskTests|InputSourceIconRenderingTests'` 记录失败；实现 ImageIO thumbnail 解码：
  ```swift
  let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelLength,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true
  ]
  ```
  对支持的 bitmap/ICNS 选择匹配的表示；PDF 在受限 context 栅格化；无法处理时返回 nil 走现有符号 fallback，不无限保留完整多表示原图。源图宽高比与逻辑坐标关系必须明确保留。
- [x] 缓存归一化输出并计费；原图与 mask 合计执行 8 条目/8 MiB 预算。mask 使用受限目标 raster，保留亮底/暗底墨迹判断。移出锁后加载，锁内二次确认 key，避免 mask 嵌套调用 decodedImage 时死锁。
- [x] 为 reset 与加载完成的竞态增加 epoch：加载前捕获 cache epoch，reset 时递增；完成后 epoch 已改变则可将结果返回当前调用者，但不重新入缓存。图像/偏移 key 必须对应同一归一化尺寸；不得不同表示共享错误的墨迹偏移。
- [x] 重跑上述测试，加跑 `swift test --filter 'Issue30WiFiAlignmentTests|IconSceneRendererParityTests|DockIconRendererTests'`；保留全部当前输入法 mask 可读性和 menu/Dock 像素定位断言。512 px 以内旧图像不得出现未经解释的视觉退化。

### Task 3: Dock 充电帧的构建峰值和独立 effect key

**Files:** Modify `Sources/StatusTrioCore/UI/Icon/DockChargingFrameCache.swift`、`DockChargingAnimationPresenter.swift`；Test `Tests/StatusTrioCoreTests/DockChargingAnimationTests.swift`、`DockChargingSplitParityTests.swift`、`DockChargingEnvironmentTests.swift`；Create `Tests/StatusTrioCoreTests/DockChargingEffectKeyTests.swift`。

**Interfaces:** 新增 phase-free `DockChargingEffectKey: Equatable`，包含完整 `OuterRingState`、`DockIconBackgroundStyle`、`pixelLength`，心跳 multiplier 仍属于 variant key。`DockIconRenderKey` 保持供静态图/base 使用的既有语义。增加 frame cache 的 `peakResidentByteCount` 测量计数与 `trimForMemoryPressure()`，不把临时缓存预算计数当进程峰值。

- [x] 先写用例：仅 center/footer 改变时 base 更新、effect rebuildCount 不变；ring 进度、粗细、颜色、accessory、effect.pulsesAccessory、背景和 tile 尺寸任一变化时 effect 重建。必须覆盖充电开关 off→on 和同 key 的 failed render 后状态变化重试。
- [x] 运行 `swift test --filter 'DockChargingEffectKeyTests|DockChargingFrameCacheTests|DockChargingAnimationPresenterTests|DockChargingSplitParityTests'` 记录失败。将 presenter 的 base 更新与 effect 失效分开；不能继续在每次 `ensureBase` 时无条件 reset effect cache。
- [x] 渲染新组首帧取得 `bytesPerRow * height`，以真实组长预计组成本；在继续分配其他 35 帧之前淘汰不再适合预算的旧变体。当前 overlay/base 必须继续持有当前图，失败时按既有静态 fallback 恢复，不能留空/错帧。新组构建失败不入缓存；失败 key 不在每个 tick 重试。
- [x] 测试 transient 持有计数：同组命中不分配，512 px 变体切换不同时持有两套完整 36 帧；允许当前画面、首帧和必要 scratch 的明确额外成本。256 px 在预算内仍保留双变体；清理/停止释放；steady 阶段维持 20 FPS 和固定 tick 的 lookup 行为。若完整单组大于预算，报告例外，禁止静默降帧率或图像质量。
- [x] 跑 `swift test --filter 'DockCharging|ChargingEffectFrameCacheTests|ChargingEffectRenderingTests|Issue30WiFiAlignmentTests'`；所有背景/粗细和关键 phase 做 split 合成对比。不要把独立 ring effect key 套用于菜单栏完整 chromatic overlay，后者还依赖中心/footer。

### Task 4: 引导页按需挂载与窗口释放验证

**Files:** Modify `Sources/StatusTrioCore/UI/IconGuideOnboardingView.swift`，按验证结果修改 `IconGuideView.swift`、`Sources/StatusTrioCore/UI/OnboardingWindowController.swift`、`Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift`；Test `Tests/StatusTrioCoreTests/IconGuideRedesignTests.swift`、`SettingsWindowControllerTests.swift`；Create `Tests/StatusTrioCoreTests/GuideWindowLifecycleTests.swift`。

**Interfaces:** 保留 `IconGuidePage`、外部 controller 的 `show()` 和 callbacks；页面选择和 help 状态由父视图保存，不通过常驻两棵页面树维持状态。

- [ ] 先测 anatomy/states 两页在全部当前语言、Reduce Motion 下的最小/理想高度，尤其长德语、中文和 RTL；记录现有 back/next/done、help、统计同意区域的行为。新建 hosting view/window 弱引用探针，关闭并排空 autorelease/run-loop 后观察实际释放，测试不要自己强持有待释放对象。
- [ ] 增加当前页挂载/旧页卸载的生命周期观察测试和多次 show/close 不累积对象测试，先运行 `swift test --filter 'IconGuideRedesignTests|GuideWindowLifecycleTests|SettingsWindowControllerTests'`。生命周期测试注入轻量 observer，不用源代码字符串匹配断言实现。
- [x] 将 ZStack 的透明两页替换为条件挂载，固定既有设计要求的容器高度或用不保留两棵树的纯布局数据计算高度：
  ```swift
  switch page {
  case .anatomy:
      IconGuideView(settings: settings, isMenuBarHelpPresented: $menuBarHelp.isPresented)
  case .states:
      IconGuideStateGalleryView(settings: settings)
  }
  ```
  切页时关闭属于旧页的 help；旧页 repeatForever 动画应随卸载停止，返回当前页时尊重 Reduce Motion 重启。保留 footer/授权文案和无障碍顺序，不能靠裁切长文维持尺寸。
- [x] 若弱引用探针证实 window/content 遗留，针对已确定的持有链清理 content/delegate/observer；否则保留现有关闭实现，只提交验证用例。弹窗保持关闭后 60 秒复用策略，详情关闭立即释放，不借本项改变体验。
- [ ] 重跑过滤测试；用原生窗口截图验证两页和 12 语言尺寸/RTL；窗口关闭 65 秒后比较 footprint 和对象计数。离线 hosting 测试与实际 WindowServer 结果分别记录。

### Task 5: 蓝牙历史 token 与过期报告的有界生命周期

**Files:** Modify `Sources/StatusTrioCore/Monitoring/NearbyBLEReadAuthorization.swift`、`BluetoothLEBatteryScanner.swift`、`BluetoothDeviceController.swift`、`BluetoothProfilerReportCache.swift`、`Sources/StatusTrioCore/Audio/BluetoothListeningModeController.swift`；Create `Sources/StatusTrioCore/Monitoring/DeviceOperationToken.swift`；Test `Tests/StatusTrioCoreTests/NearbyBLEReadAuthorizationTests.swift`、`NearbyBLESessionLifecycleTests.swift`、`NearbyBLEControllerDemandTests.swift`、`BluetoothListeningModeControllerLifecycleTests.swift`；Create `Tests/StatusTrioCoreTests/BluetoothProfilerReportCacheTests.swift`。

**Interfaces:** 只对当前授权/当前操作保留不可复用 token；不再对历史 ID 永久保留 UInt64 计数。共享值类型：
```swift
struct DeviceOperationToken: Equatable, Hashable, Sendable {
    private let value = UUID()
}
```
`NearbyBLEReadAuthorization.token(for id: UUID) -> DeviceOperationToken?` 和 `accepts(_:token:) -> Bool` 替换 revision 接口；相同有效 grant 保留 token，撤销移除，重新授权创建新 token。同步更新 scanner session 字段和所有 callback 类型。

- [x] 先写一个确定旧实现失败的测试：撤销再添加同 ID 后旧 token 必须拒绝；连续遍历 10,000 个 ID 后仅保留当前授权数量；不变授权不让其他设备在途读取失效。保留一个旧回调到 stop/start 后再交付，验证其不能更新新会话。
- [x] 运行 `swift test --filter 'NearbyBLEReadAuthorizationTests|NearbyBLESessionLifecycleTests|NearbyBLEControllerDemandTests|BluetoothListeningModeControllerLifecycleTests'`；引入上述 token，并把 controller 的允许列表快照和 listening-mode 变更任务改为只持有当前 token。取消/移除时退休，迟到 closure 只比较其捕获 token 与当前 map 的可选值，不以缺失默认值判断相等。
- [x] 单独覆盖 initialReadCandidateIDs 路径：当前 scanner 既允许显式设备，也允许初读候选。必须对现有合规初读请求签发 token，并在候选退出/授权撤销时退休，不能把可选 token 的 nil==nil 当允许，也不能只改显式 allowlist 造成初读永久失败。保持扫描 session generation 及隐藏/后台策略的独立检查。
- [x] 为 profiler report 的过期读取先写测试；在锁内失效且 maxAge 条件满足时清空 entry。不要无条件设置五秒自动清理破坏调用者自定义 maxAge；服务真正停止且无其他共享消费者时可显式 reset。明确测试调用者持有返回 Data 的合法生命周期，不宣称清 cache 就释放所有引用。既有冷却表保持原有 TTL，不把它们错误改成每次关闭立即清空。
- [x] 运行上述测试及 `swift test --filter 'NearbyBLE|BluetoothListeningMode|BluetoothBatteryControllerTests|BluetoothProfilerReportCacheTests'`。完成标准是 retained token 数随当前授权/活动任务有界，授权/电量/听力模式表现不变；不承诺几十 MiB 收益。

### Task 6: 内存压力处理、辅助缓存预算和停止回收

**Files:** Create `Sources/StatusTrioCore/App/MemoryPressureMonitor.swift`；Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`、`AppIconController.swift`、`Sources/StatusTrioCore/UI/StatusBarController.swift`、`Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`、`StatusIconRenderer.swift`、`DockIconPreviewCache.swift`；按接口需要修改任务 2、3 的缓存；Create `Tests/StatusTrioCoreTests/MemoryPressureMonitorTests.swift`、`MemoryPressureReclamationTests.swift`。

**Interfaces:** `@MainActor final class MemoryPressureMonitor` 提供 `start()`、`stop()`、`onPressure: (@MainActor () -> Void)?`，内部使用 warning/critical 的 `DispatchSourceMemoryPressure`，不新增轮询 timer。`AppIconController.releaseCachedImages()` 只清历史缓存，不清当前应用图标；`StatusBarController.trimForMemoryPressure()` 回收已关闭弹窗内容与非活动帧组；`DockIconRenderer.resetScratchContexts()`、`StatusIconRenderer.resetInkOffsetCaches()` 回收可重建资源。

- [x] 用注入 event source 的测试先验证 start/stop 可重入、取消后迟到事件被丢弃、回调在 MainActor、重复压力事件不重复挂新订阅。不在测试中真实耗尽系统内存。
- [x] 实现事件 monitor，由 AppEnvironment 与现有 start/stop 对称管理；回调弱捕获环境，任一 actor 边界显式 hop，不从后台事件直接碰 NSImage/NSWindow。
- [x] 按初始预算收紧 scratch LRU 和墨迹偏移 LRU；仅缓存/淘汰测量结果，不舍入坐标或放宽 #30 容差。线程安全与 renderer 当前调用位置一致；清理时不得在持有 decode 锁的 closure 中递归清同一缓存。
- [x] 压力回收：清历史静态图、小预览、decode/mask、scratch 和墨迹偏移；关闭中的 popover 可提前释放。活动 Dock/menu 动画保留当前组/必要当前图，清备用组，不直接 clear presenter 或 stop clock。测试连续 100 个相位推进后 rebuildCount 不随 tick 增长，并验证所有缓存 reset epoch 防止在途结果复活。
- [x] 环境 stop 时停止 monitor、清历史资源和已停止的动画帧；MemoryPressureMonitor 自身支持再次 start 并拒绝上一代事件。保持现有 SystemStatusStore 的 stop 后终止语义，不在内存任务中扩大整个 AppEnvironment 的重启能力。跑 `swift test --filter 'MemoryPressure|AppIconControllerTests|DockCharging|Issue30WiFiAlignmentTests|StatusBarChargingAnimationTickTests'`，检查重复压力事件下无重建风暴、冻结或空图。

### Task 7: 集成验收、性能对照与交付

**Files:** 更新 `docs/performance/memory-audit-2026-10-20.md` 的 before/after 和 raw log 位置；更新 `docs/performance/dock-charging-cpu-optimization.md` 追加新测量且保留旧证据；有失败 GitHub Actions 时更新 `docs/swift-ci-compatibility.md`。

- [x] 主代理检查全部 diff，只接受本计划范围；对各 worker 的失败原因/修复/测试逐项复核。执行完整本地检查，不在无新变化的情况下反复跑同一全套测试：
  ```bash
  swift test
  swift build -c release
  swift test --filter Issue30WiFiAlignmentTests
  bash scripts/check-forbidden-patterns.sh
  bash scripts/validate-appcast-notes.sh
  ```
  appcast validator 若因基线 release notes 缺项失败，准确记录其已有原因，不借内存优化改写或伪造发布内容。
- [x] 构建两个独立输出路径的 Release app，顺序使用同一测量 defaults 域，核对可执行文件 path/hash/SHA。固定相同合成输入、设置、Dock 尺寸、显示器与动画阶段；除测量目标外不要改变后台状态。CPU 使用现有 `scripts/measure-dock-charging-cpu.sh`，显式传目标 APP_BUNDLE/BUNDLE_ID；原始输出放工作树外的持久测量目录并附构建信息。
- [ ] 执行下表；每组 A/B 做 3 对交替运行，缓存/启动预热 15 秒，取样 60 秒。UI 关闭场景先额外等待 65 秒以覆盖原有弹窗回收。记录 median/peak footprint、CG Raster、持有像素、rebuildCount 及 app/Dock CPU，保留失败/缺测，不挑单次最低值。

  | 场景 | 操作与验收 |
  |---|---|
  | 菜单栏静置 | 同设置冷启动；不新增常驻服务或 timer，内存和 CPU 不回归 |
  | Dock 静态满缓存→菜单栏 | 受控输入产生 12 个状态；优化后缓存 ≤4 MiB，退出后为 0；footprint 降幅据实报告 |
  | 设置/弹窗反复开关 | 各 20 次并等待 65 秒；对象计数不按次数持续增长，九个选项保持可用 |
  | 引导双页 | 切换 20 次；只挂一页，关闭可释放，语言/RTL/无障碍不裁切 |
  | 大图和输入法 | 4096 px PNG、ICNS/PDF、黑白/偏心输入法；输出/缓存受预算限制，menu/Dock 清晰且居中 |
  | 真实 tile 与 512 px 极端 tile 充电 | 20 FPS、心跳/burst 正常；只改音量不重建 ring 组；变体构建峰值下降 |
  | 内存压力及蓝牙高 churn | 注入压力/10,000 个历史 ID；有界缓存/当前 token，旧回调拒绝，steady tick 不全量重建 |

  确定性预算和像素测试是硬条件；真实内存期望整体下降，但不预先承诺 main 从 155 MiB 降到某值。CPU 的每对差值若持续超过 `max(0.5 个百分点, 基线的 10%)`，停止合并并定位退化，不用 WindowServer 噪声掩盖 app/Dock 的持续回归。该阈值是本次工程验收标准，不是历史实测结论。
- [ ] 审查独立开关、真正拔插/充满、Reduce Motion、睡眠/唤醒、多显示器、左/右/底部 Dock、自动隐藏和放大。只有实际覆盖的场景写为通过；合成电池、离线图片和 mock 测试分别标记。完成一次独立整分支 code review，修复有证据的问题后补相应验证。
- [x] 本计划触及 actor/UI binding/泛型等路径，合并前需要 CI `publish=false` 预检。执行时从已发布版本取得显式递增版本/build；在已有远端操作授权后上传待验分支，派发并 watch：
  ```bash
  : "${PREFLIGHT_REF:?set to the authorized remote branch containing the reviewed changes}"
  : "${NEXT_VERSION:?set an explicit version after checking published releases}"
  : "${NEXT_BUILD:?set an explicit build greater than the published build}"
  gh workflow run release.yml --repo lingyired/status-trio \
    --ref "$PREFLIGHT_REF" -f version="$NEXT_VERSION" -f build="$NEXT_BUILD" -f publish=false
  : "${RUN_ID:?set to the dispatched run and verify its head SHA matches the reviewed branch}"
  gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
  ```
  不自动挑未审查的 branch/SHA，不触发 publish=true。每次失败 run 在 compatibility 文档写 run ID、阶段、根因、修复及复验。没有远端操作授权时提交本地已验证成果并明确 CI 尚未执行，不称已满足合并/发布门槛。

## 交付清单

- 五类优化及辅助回收的实现和有意义的回归测试；对未复现的窗口泄漏保留验证结论。
- main/优化版相同情境的 before/after、缓存预算、raw log、CPU 和未覆盖硬件/UI 项。
- 全部本地测试、Release 构建、#30 回归和独立 review 结果；CI 状态与源码 SHA 单独列出。
- 清晰列出修改文件和未完成外部验收，不以理论像素释放替代进程实测，不自动提交/合并/发布。

## 计划自检

- 覆盖：静态缓存、解码/mask、充电峰值与 key、引导页、蓝牙 token/报告均有实施任务；辅助缓存与压力处理单独集成。
- 接口：任务 6 使用任务 1–3 已定义的清理/预算接口；任务 5 同步更新 scanner/controller 的 token 类型和 initial read。
- 风险：5 项 Review Focus 均有归属测试；不以缩图破坏 Dock、不清 active 帧造成风暴、不重置历史计数让旧授权复活。
- 状态：代码修改和本地全量验证已完成，checkbox 表示有证据完成的动作。完整场景矩阵与硬件/UI 项保持未勾选；CI `39377387434` 已对 `8728003` 通过，独立审查及后续测试修复补审通过；最终文档补充不改产品和测试源码。详见内存审计报告。
