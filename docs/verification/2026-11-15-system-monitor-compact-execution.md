# 系统监控紧凑四环面板 — 实施与验证记录

日期：2026-11-15。执行模型：auto-deepseek-v4-1-flash（会话切换为 deepseek-v4.1-flash 后执行）。

## 范围

- 分支：system-monitor-compact-panel；功能基线 aeb8ab201ccf5ff6bd9dd45cf2fbfd78f2628829（来源 feat/hardware-monitor-outer-ring）。
- 设计：docs/superpowers/specs/2026-11-14-system-monitor-compact-design.md；计划：docs/superpowers/plans/2026-11-14-system-monitor-compact-plan.md。
- 用户已确认右侧方案截图：docs/superpowers/specs/assets/system-monitor-compact-approved.png。

## 实现摘要

- DiskThroughputReader：只读 IOBlockStorageDriver 累计读写计数，按 IORegistryEntryID 去重；首帧建基线；间隔非法、计数回退、设备集合变化、读取失败均不出假速率。接入 HardwareSampler 串行队列与 HardwareMetricsService 需求调度，磁盘 1 s，需求结束即停。
- 新增 .diskRead/.diskWrite 指标、.ioStorage 来源、.disk 家族；MetricProgressMapper 不将磁盘画到外环。
- 平均风扇：averageFanSample 对新鲜有效 RPM 取算术平均（真实 0 参与，NaN/负数/过期/不可用排除，无风扇为 unsupported）；fanSummarySample（最高）语义不变，图标/外环不受影响。
- 摘要展示：HardwareMonitorSummaryPresentation 固定四槽（下载、上传、平均风扇、磁盘读/写）；磁盘读写共享同一单位（按较大值定档）；数字不超过 3 位有效数字；缺失显示破折号，不伪造 0。
- 面板 UI：抽取 HardwareRingStrip（与原四环渲染逐字一致，预览与面板共用），HardwareMonitorSummaryView = 四环 + 分隔线 + 一行四组数据；四组与四环同用四等列与 10 pt 间距，数字在上、图标+单位在下，逐列居中对齐。
- 面板需求改为固定 HardwareMetricsService.hardwareSummaryMetricIDs，不再依赖卡片指标顺序/开关；旧 HardwareMonitorCardView 保留为兼容组件，面板不再重复呈现。
- 新增 9 个 hardware.monitor.* 键，覆盖全部 12 种语言。

## 本地验证

- Task 1：test.sh 'DiskThroughputReaderTests|HardwareSamplerTests|HardwareMetricsServiceTests' → PASS。
- Task 2：test.sh 'HardwareMonitorSummaryTests|HardwareMonitorCardTests|HardwareRingMapperTests|ChargingEffectLocalizationTests' → PASS（含 12 语言一致性）。
- Task 3：test.sh 'HardwareMonitorPanelDemandTests|HardwareMonitorSummaryTests|HardwareMonitorCardTests|HardwareMonitorSettingsTests' 与 'LocalizationParityTests|HardwareRingMapperTests|HardwareRingConfigurationTests' → 均 PASS。
- Task 4：HardwareMonitorSummaryLayoutTests 离屏尺寸：在 302 pt 宽、12 语言 × 5 可用性状态下属 Pass（宽度贴合、高度紧凑、无窗口）。
- 完整档 `bash scripts/verify-local.sh full`：PASS，exit 0，head 68c6b87a0cfda7635ca061019be196c8a72bb0c8。含全量 Swift 套件、Release 构建、非 Universal 本地 app bundle 及其平台/SDK、Helper、原生兼容与依赖、离线发布流水线模拟。

综上：本地实现与验证完成；仍需用户人工验收与真机 macOS 13 / 当前系统运行核对。

## 未做 / 边界

- 未启动真实 app 做前台人工视觉核对；使用离屏 AppKit 尺寸测试作为排版证据，不能替代原生运行截图。visible UI 测试未开启。
- 真实 macOS 13、当前系统运行、真实 Helper、签名、公证、Universal、发布：NOT RUN。
- 未合并、未推送、未发布；保留分支与工作区待用户验收。

## 说明

早前阶段此文件记录的是指定模型入口不可用（NO_ADAPTER: provider "auto"）的受阻状态；模型切换为该模型后已完成实现与本地验证。


## 追加：后台监控频率与缓存显示（2026-11-15）

- 新增设置 `hardwareBackgroundRefreshSeconds`：关闭(0，默认)/5/10/15/30/60 秒；存入 SettingsStore、加入 SettingsPreferenceCatalog（可导出导入）、覆盖 12 种语言、设置页「系统监控」新增下拉。
- HardwareMetricsService 新增 `.background` 需求：仅当后台需求是唯一消费者时按设定秒数采样；面板打开时仍用快速节奏。StatusPanelViewModel 随设置开启/关闭后台需求。
- HardwareMonitorObservable 保留上次有效读数；摘要用 summarySnapshot 在缺值时回退显示上次缓存（变暗），打开面板不再闪「—」。
- 测试：设置校验/往返、后台节奏、需求生命周期、摘要缓存回退，共 78 项相关测试通过。



## 追加：面板打开刷新频率可调（2026-11-15）

- 新增设置 `hardwarePanelRefreshSeconds`：1/2/3/5/10 秒，默认 1 秒；存入 SettingsStore、加入 SettingsPreferenceCatalog、覆盖 12 种语言、设置页「系统监控」新增下拉。
- HardwareMetricsService 在面板是唯一非后台消费者时按该秒数节流；菜单栏/Dock 等消费者仍按各自需要的节奏。
- 测试：设置校验/往返、面板节奏；相关 48 项测试通过。



## 追加：格式化与正确性优化（2026-11-16）

- Phase1 统一 `ByteRateFormatter`（十进制 KB/s→TB/s，按量级选精度），网络、旧卡片、菜单栏顶部共用；0–999 B/s 显示 0 KB/s。
- Phase2 磁盘摘要显示读写合计（同一采样周期才合计；缺失/混合不冒充总量），tooltip/VoiceOver 保留读、写、合计。
- Phase3 网络改按接口差分，接口集合变化重建基线不出尖峰，排除 utun 等虚拟接口；stale 缓存超过 300 秒不再显示。
- Phase4 保留 averageFanSample 平均逻辑，部分风扇不可读时 tooltip 说明参与数量；fanSummarySample 语义不变。
- Phase5 离屏布局在 999KB/1.0MB/125MB/1.3GB、0、—、过期等边界下高度稳定。
- 聚焦测试 122 项通过；完整档 verify-local full 结果见下。

