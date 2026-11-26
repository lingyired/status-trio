# Module: hardware

Generated from `SettingsSemanticCatalog`. Do not edit by hand.

| id | title | type | default | storage key |
|---|---|---|---|---|
| `hardware.history.backgroundEnabled` | 后台历史采集 | `boolean` | — | hardwareBackgroundHistoryEnabled |
| `hardware.history.windowMinutes` | 历史记录长度（分钟） | `integer` | — | hardwareHistoryWindowMinutes |
| `hardware.metricBottomIndicatorStyle` | 硬件指标底部样式 | `enumeration` | — | metricBottomIndicatorStyle |
| `hardware.metricColors` | 硬件指标颜色 | `map` | — | hardwareMonitorMetricColorsV1 |
| `hardware.network.downloadCapMbps` | 下载速度上限（Mbps） | `number` | — | hardwareDownloadCapMbps |
| `hardware.network.uploadCapMbps` | 上传速度上限（Mbps） | `number` | — | hardwareUploadCapMbps |
| `hardware.refresh.cpuUsage` | CPU 占用刷新频率（秒） | `integer` | — | hardwareCPUUsageRefreshSeconds |
| `hardware.refresh.disk` | 磁盘刷新频率（秒） | `integer` | — | hardwareDiskRefreshSeconds |
| `hardware.refresh.gpuUsage` | GPU 占用刷新频率（秒） | `integer` | — | hardwareGPUUsageRefreshSeconds |
| `hardware.refresh.memory` | 内存刷新频率（秒） | `integer` | — | hardwareMemoryRefreshSeconds |
| `hardware.refresh.network` | 网络刷新频率（秒） | `integer` | — | hardwareNetworkRefreshSeconds |
| `hardware.refresh.temperature` | 温度刷新频率（秒） | `integer` | — | hardwareTemperatureRefreshSeconds |
| `hardware.ring.memoryDisplayMode` | 内存环显示模式 | `enumeration` | — | memoryRingDisplayModeV1 |
| `hardware.ring.ssdDisplayMode` | SSD 环显示模式 | `enumeration` | — | ssdRingDisplayModeV1 |
| `hardware.rings.enabled` | 显示硬件圆环 | `boolean` | true | showsHardwareRings |
| `hardware.ssd.externalVolumePaths` | 外置磁盘卷路径 | `set` | — | hardwareSSDExternalVolumePathsV1 |
| `hardware.ssd.includeExternalInPercent` | 外置磁盘计入百分比 | `boolean` | — | hardwareSSDIncludeExternalInPercentV1 |
| `hardware.summary.enabled` | 显示硬件摘要行 | `boolean` | true | showsHardwareSummaryRow |
| `hardware.summaryMetrics` | 启用的硬件摘要指标 | `set` | — | enabledHardwareSummaryMetricsV1 |
| `hardware.temperature.enabled` | 温度监控 | `boolean` | true | hardwareTemperatureMonitoringEnabledV1 |
| `hardware.topApps.enabled` | 显示占用最高的 App | `boolean` | true | showsHardwareTopApps |
| `hardware.topApps.refreshSeconds` | 高占用应用刷新频率（秒） | `integer` | — | hardwareTopAppsRefreshSeconds |
