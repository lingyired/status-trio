# 系统监控紧凑四环面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. 用户指定执行模型 auto-deepseek-v4-1-flash；不得静默换模型。

**Goal:** 落地用户已确认的右侧方案：既有四环 + 同列居中的四组数字 / 图标单位，两行紧凑摘要。

**Architecture:** 固定面板摘要使用现有 HardwareMonitorObservable；四环继续走现有 scene / renderer。新增磁盘 reader 接到 HardwareSampler 串行队列和 HardwareMetricsService 需求调度；平均风扇是独立展示计算，不改变图标最高转速来源。

**Tech Stack:** Swift、SwiftUI、AppKit、IOKit、Combine、XCTest，macOS 13+。

**Spec:** docs/superpowers/specs/2026-11-14-system-monitor-compact-design.md；参考图 assets/system-monitor-compact-approved.png。

## Global Constraints

- 基于 feat/hardware-monitor-outer-ring @ aeb8ab201ccf5ff6bd9dd45cf2fbfd78f2628829；仅在 system-monitor-compact-panel 工作。
- 四环样式、尺寸、内容、颜色、顺序、动画不变；不修改共享 renderer、IconSceneState、菜单栏 / Dock 图标设置。
- 330 pt 面板；内部沿用原四环的四等列与列间距；下载、上传、平均风扇、磁盘读 / 写逐列居中。数字上行，图标和单位下行；无模块标题 / 预览文案。
- 不新增设置、权限、Helper、依赖或独立轮询；保留设置导出格式。磁盘 1 s，现有网络 1 s、使用率 2 s、温度 / 风扇 4 s。
- macOS 13；禁用 isolated deinit；保留 icon-sizing-standard 的既有约束。
- 使用 scripts/test.sh 作为唯一 Swift 测试入口；不设 STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1。
- 验收前不合并 / 推送 / 发布；保留工作区。

## Review Focus

1. 磁盘计数回退、重启 / 热插拔不得产生巨大速率，首帧不能当作真实 0。
2. 无风扇与风扇暂不可读必须区分；0 RPM 参与平均，不使用最高值替代平均。
3. 两个磁盘方向的单位必须相同；大数值 / 本地化文字不能越列或增加高度。
4. 面板关闭、切换详情、休眠 / 唤醒不得遗留磁盘需求或重叠读取。
5. 既有硬件指标选择不能使固定四环缺失采样，真实菜单栏 / Dock 风扇值保持原语义。

---

### Task 1: 磁盘 reader 与硬件调度

**Files:** Create Sources/StatusTrioCore/Monitoring/DiskThroughputReader.swift; Modify Monitoring/HardwareMetricsModels.swift, HardwareSampler.swift, HardwareMetricsService.swift, MetricProgressMapper.swift (all under Sources/StatusTrioCore); Test Tests/StatusTrioCoreTests/DiskThroughputReaderTests.swift, HardwareSamplerTests.swift, HardwareMetricsServiceTests.swift.

**Interfaces:** 新建 DiskByteTotals(read: UInt64, written: UInt64)，DiskThroughputReading(readBytesPerSecond: Double, writeBytesPerSecond: Double, sampledAt: Date)。DiskThroughputReader.read(at: Date) -> DiskThroughputReading?、reset()；为纯差分数学提供 rates(previous: [UInt64: DiskByteTotals], previousAt: Date, current: [UInt64: DiskByteTotals], currentAt: Date) -> DiskThroughputReading?。HardwareMetricID 新增 .diskRead/.diskWrite，snapshot 增对应便利属性，family .disk、source .ioStorage。给 HardwareSampler.collect 添加末尾带默认值 diskProvider 注入，不破坏现有调用。

- [ ] 先添加 reader 失败测试：两个设备在 2 s 中增加读 6,000,000、写 2,000,000 bytes，速率为 3,000,000 / 1,000,000 B/s；0 差分为真实 0；首帧无数据；间隔 <= 0、< 0.2、> 15、计数回退、设备 key 集变化均不能返回速率；读取失败清掉基线。
- [ ] 运行 bash scripts/test.sh 'DiskThroughputReaderTests'，确认失败源于尚未实现的接口。
- [ ] 实现只读 IOKit 采集：IOBlockStorageDriver Statistics 累计字节，按 registry ID 唯一计数；释放 iterator/service/CF 对象，缺失键不补 0。差分在 utility queue；reset 同时清 disk baseline。
- [ ] 更新样本映射 / 单位 / family / service 1 s cadence / exhaustive switches。非 measured 不参与进度，磁盘不映射到可选外环。
- [ ] sampler 测试证明不请求磁盘时 provider 调用 0 次；请求任一磁盘方向只采一次，不触发 CPU/GPU/SMC；映射返回对应来源、单位、时间与 availability。service 测试证明磁盘 demand 结束就停，sleep / wake 重建基线且无重叠读取。
- [ ] 运行 bash scripts/test.sh 'DiskThroughputReaderTests|HardwareSamplerTests|HardwareMetricsServiceTests'。通过后本地 commit，不推送。

### Task 2: 摘要展示模型与平均风扇

**Files:** Create Sources/StatusTrioCore/UI/HardwareMonitorSummaryPresentation.swift; Modify Monitoring/HardwareMetricsModels.swift; Test Tests/StatusTrioCoreTests/HardwareMonitorSummaryTests.swift.

**Interfaces:** 新建固定四槽 HardwareSummaryMetric: download/upload/fan/disk；HardwareSummaryMetricPresentation 含 valueText、unitText、symbol、accessibilityLabel/value、help、isStale；HardwareMonitorSummaryPresentation.items(snapshot: HardwareMetricsSnapshot, localization: Localization) -> [HardwareSummaryMetricPresentation]。snapshot 新增 averageFanSample 计算属性，保持现有 fanSummarySample 不变。

- [ ] 添加失败测试：有效 RPM [1000, 3000] 平均 2000，含真实 0 的 [0, 2000] 平均 1000，NaN/负数/stale/不可用不参与，fanCount == 0 返回无风扇，全部不可用返回「—」。现有最高风扇摘要仍为 3000。
- [ ] 运行 bash scripts/test.sh 'HardwareMonitorSummaryTests'，确认预期失败。
- [ ] 实现数字 / 单位分离。十进制 KB/s、MB/s、GB/s 自动缩放；磁盘两方向共享由 max(read,write) 决定的单位；2e6 与 500000 显示 2 / 0.5 + MB/s，不得显示 2 / 500 + 单一单位。数字以合适的 3 位有效数字限制宽度；VoiceOver/help 保留完整值与方向。
- [ ] 添加正常/零/巨大/非有限/单侧缺失/过期/无风扇格式化测试，并验证固定四槽顺序、共同单位、help 和 availability。风扇无效值不伪造 0，失效样本不当实时。
- [ ] 运行 bash scripts/test.sh 'HardwareMonitorSummaryTests|HardwareMonitorCardTests|HardwareRingMapperTests'，通过后 commit。

### Task 3: 原生紧凑面板、四列对齐与需求绑定

**Files:** Modify Sources/StatusTrioCore/UI/MenuBarIconPreviewGrid.swift, UI/StatusPopoverView.swift, Presentation/Panel/StatusPanelViewModel.swift; Create UI/HardwareMonitorSummaryView.swift; Modify Localization/LocalizationKey.swift and Resources/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.lproj/Localizable.strings; Test HardwareMonitorSummaryTests.swift, HardwareMonitorPanelDemandTests.swift.

**Interfaces:** HardwareMonitorSummaryView(model: HardwareMonitorObservable, metricColors: [HardwareMonitorMetric: IconRGBA])。MenuBarIconPreviewGrid 原四环独立为可复用的纯四环内容视图 / 样式；新 summary 与四环使用同一 four-column layout 常量，不能用与圆环不一致的独立固定列宽。静态 requiredMetricIDs 包括 .cpuUsage/.gpuUsage/.memoryUsage/.cpuTemperature/.gpuTemperature/.fanRPM(index:0)/.networkDownload/.networkUpload/.diskRead/.diskWrite。

- [ ] 更新 / 新增面板 demand 测试：固定 IDs 不依赖旧 hardwareMonitorMetricOrder / enabled 集；关闭、详情页、禁用模块、stop 均结束 panel demand，其它 icon consumer 需求不受影响。
- [ ] 运行 bash scripts/test.sh 'HardwareMonitorPanelDemandTests'，确认失败是新布局预期差异。
- [ ] 抽出原四环内容，严格保留 spec(for:)/AnimatedRingLayer/AnimatedSceneIcon 的环参数、文字位置、字体比例和动画。只移除面板中的预览标题、脚注、额外卡片，不重绘圆环。
- [ ] 摘要四列在数字上行独立居中，图标+单位第二行独立居中；数字等宽、无全局数值动画。大数值先换单位 / 限有效位，必要时有限缩放，不能跨列。约 134 pt 是目标，不以固定高度隐藏较长本地化文本。
- [ ] StatusPopoverView .hardwareMonitor 只放一个 summary；不再渲染 HardwareMonitorCardView 和旧预览外壳。模块 show/hide 继续由现有 PopupSection 设置控制，旧 metric 设置保留给原数据 / 图标设置兼容。
- [ ] 实现需求绑定，新增所需本地化键覆盖全部 12 个语言；help/VoiceOver 说明下载、上传、平均 RPM 和磁盘读 / 写顺序、无风扇 / 缺失 / 过期原因。
- [ ] 运行 bash scripts/test.sh 'HardwareMonitorSummaryTests|HardwareMonitorPanelDemandTests|HardwareMonitorSettingsTests|LocalizationTests|LocalizationResourceTests|HardwareRingMapperTests'。通过后 commit。

### Task 4: 最终集成与本地交付

**Files:** Update plan checkboxes; Create docs/verification/2026-11-14-system-monitor-compact.md; Optionally add offline snapshot test/fixture using existing repository patterns, never visible status items/windows.

- [ ] 审查相对 aeb8ab20 的 diff：只改变上述面板 / 内部采样 / 测试 / 本地化；核实 fanSummarySample 和共享 renderer 没变，设置 schema 没变；git diff --check 无错误。
- [ ] 原生离屏截图核对 330 pt 宽、四环完全一致、四列中心一致、正常 / 大数值 / 无风扇 / 缺失状态、light/dark、Reduce Motion/Transparency。若要启动真实 app，先读 background-ui-testing，走项目 launcher 和实例级后台操作，不抢前台。记录无法验证项目，不能把浏览器草图当原生验证。
- [ ] fetch origin 并记录 origin/main 与分支基线及冲突，不自动合并 main：基于该未合并硬件分支是用户指定的产品上下文。
- [ ] 在最终 tree 跑 bash scripts/verify-local.sh full 一次；迭代只跑相关 focused filters。若 renderer 路径受影响，补 Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests。
- [ ] 把命令、exit code、SHA / dirty scope、跳过的 visible UI 和真实 macOS 13/当前系统运行情况如实写入验证报告。失败不得弱化或跳过；先找原因。
- [ ] 手动开发包若需要，使用 bash scripts/build-worktree.sh release no-open；不替换生产应用。保留分支待用户验收，不合并、不推送、不发布。

## 执行与复核说明

用户已明确要求“写一个 plan，然后使用 auto-deepseek-v4-1-flash 来执行”，所以计划写好后按已授权顺序直接执行，无需再次索要执行确认。若指定模型接口不可用，保留计划与现场并说明真实错误，不能声称已用该模型，也不擅自用当前模型实现。执行者结束时报告完成任务、commit、测试证据与未完成项；根代理审查结果后再交付。
