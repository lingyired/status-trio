# 系统监控共享采样与后台历史验证

2026-11-18 · 分支 feat/system-monitor-detail-pages · 基线 41c38b0e

## 已实现

- 采样间隔按指标混用：每个活跃使用方为同一指标提出自己的目标间隔，物理读取取最短者。慢档面板不会再拖慢图标所需指标，快档图标也不会加速只属于面板的指标。`HardwareMetricsService.interval(for:)` 与 `intervalForTesting(_:)`。
- 采样循环改为按最近到期时间唤醒，不再固定心跳把 4 秒传感器对齐到 6 秒。
- 后台记录历史改为默认开启；开关 `hardwareBackgroundHistoryEnabled` 默认 `true`，沿用面板刷新档位，面板关闭时按同一档位继续采集概览指标，打开详情即可看到趋势。
- 设置页把原「后台刷新秒数」下拉改为「保留后台历史」开关；12 种语言文案同步更新。
- 设置导出目录改为布尔字段 `hardwareBackgroundHistoryEnabled`，旧秒数字段退役（功能未发布，不做迁移）。
- Top 5 应用默认间隔调整为 CPU/GPU/网络 2 秒、内存 6 秒。

## 测试

- 聚焦：`bash scripts/test.sh 'HardwareMetricsServiceTests|HardwareMonitorPanelDemandTests|TopAppsPanelDemandTests|SettingsPreferenceCatalogTests|TopAppsServiceTests|HardwareMonitorSummaryTests|SettingsTransferTests'` 全绿（72 项）。
- 广回归：`bash scripts/test.sh 'Hardware|TopApps|Settings|Localization|Icon|Panel|StatusPanel'` 1451 项，0 失败，59 项可见 UI 按默认跳过。
- 新增 `testSharedCPUAndIndependentPanelDeadlines`：CPU 图标 2 秒 + 面板 CPU/磁盘 5 秒时，CPU 有效间隔 2 秒、磁盘 5 秒；慢档面板传感器保持 3 秒，不被无关 1 秒指标拖快。

## 未覆盖 / 后续

- 未做真机功耗测量（后台关/开、仅 CPU 图标、概览、内存详情），需要用户验收时在同一台机器上对比。
- 计划中「物理读取按 work 拆分」（磁盘容量、内存附加字段独立到期）经核对现状：容量由视图首次读取、内存总量与分解共用同一份 VM 统计，未见重复读取，故本次未重构采样器接口，留作后续按需处理。
- 真实 macOS 13 与当前版本运行检查、可见 UI 手测未执行。

## 面板与详情页性能（Debug，2026-11-18）

面板打开：1 秒档 24.7% → 2.0%，2 秒档 21.8% → 1.4%（移除每次采样的 0.55 秒环形缓动、容量改为出现时读一次）。

详情页（2 秒面板档，修复后实测 30–40 秒）：CPU 3.0%、GPU 1.7%、内存 2.9%、网络 2.1%、磁盘 1.4%。

内存详情原先每 6 秒调用一次 `top -l 1 -o mem`，实测每次约 1.1 秒 CPU（约占用一个核心的 18%）；改用 `ps -Aceo pid,rss,comm` 约 0.04 秒。旧 `top MEM` 是物理内存 footprint，新榜单按 RSS（resident set）排序，两者数值和名次可能不同。

高占用列表可关闭（设置 → 系统监控 → 显示高占用应用）。Debug 实测 CPU 详情页：开启 3.0%、关闭 1.0%，约省 2 个百分点。

## 本轮合并后复测（Debug，2026-11-18 21:02–21:10）

环境：Mac15,9 / arm64 / 16 CPU / macOS 27.3；head `87e60bebceef2ca3d59bac4eac24bad5e0379e0f` 加未跟踪执行记录；面板刷新 2 秒档；每次预热 15 秒，采样 61 次（每次 1 秒）。

| 场景 | CPU 均值 | CPU 峰值 | CPU 中位 | RSS |
| --- | ---: | ---: | ---: | ---: |
| CPU 详情，榜开启 | 3.28% | 7.50% | 4.50% | 44–46 MB |
| CPU 详情，榜关闭 | 1.31% | 3.20% | 1.30% | 43 MB |
| 内存详情 | 2.67% | 12.90% | 0.90% | 41–42 MB |
| GPU 详情 | 2.08% | 4.80% | 2.60% | 41–42 MB |
| 网络详情 | 2.02% | 4.90% | 2.90% | 42–44 MB |
| 磁盘详情 | 1.88% | 5.00% | 2.30% | 41–42 MB |

- CPU 详情关闭高占用榜后均值从 3.28% 降到 1.31%，与上一轮约 2 个百分点的收益一致。
- 内存详情的均值受每 6 秒一次 `ps` 采样影响，峰值 12.90%、中位 0.90%；RSS 41–42 MB。
- 唤醒次数未采样：`powermetrics` 需要 root。详情页内容未做独立视觉确认；启动记录显示 `requestedHardwareDetail` 与目标页一致，面板窗口为 298×578。
- 可见 UI 手测、真实 XPC、macOS 13 运行仍未执行。
