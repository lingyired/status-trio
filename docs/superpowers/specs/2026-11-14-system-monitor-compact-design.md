# 系统监控紧凑四环面板设计

日期：2026-11-14。状态：用户已确认右侧方案，并要求写计划后用 auto-deepseek-v4-1-flash 执行。

## 意图与验收外观

用已有的 CPU / GPU / RAM / SSD 四环替换状态面板中的旧系统监控数值卡片，消除重复信息。四环的尺寸、颜色、数值内容、上下标签、动画和顺序保持原样。

四环下方固定四列，顺序为下载、上传、风扇平均转速、磁盘读 / 写。每组数字在上，图标和单位在下。与上方圆环共用列中心；图标不挤占数字居中位置。不再显示「菜单栏图标」「实时 · 1 行 4 个」「图标约 60×60 pt」等预览说明，也不增加系统监控标题行。保留细分隔线。

面板外宽继续为 330 pt；四环内容宽约 302 pt，内部沿用原 10 pt 横向内边距、四列均分和 10 pt 列间距。数字约 13 pt、单位约 9.5–10 pt；磁盘双数值约 12 pt。目标监控区约 134 pt，最终以原生组件测量为准，不固定死高度造成文字裁切。数字 / 单位之间约 3 pt。降低动态效果和降低透明度继续使用现有系统策略。

参考图：assets/system-monitor-compact-approved.png，右侧为用户选定布局。

## Approaches

1. 两列两行：读写空间充足，但高度大；用户选择四列 A。
2. 四列全单行：高度约 120 pt，但磁盘双值和单位与旁列过近；用户否决其拥挤程度。
3. 四列，数字与单位两行：约 134 pt，比全单行增加约 14 pt，保留上下对齐；用户确认采用。

## 数据和状态

下载和上传复用现有物理网络接口吞吐采集。十进制 KB/s、MB/s，必要时 GB/s；0 是真实空闲值，首次采样显示「—」。磁盘采集系统物理存储设备的聚合读写速度，不是 SSD 容量 / 剩余空间；四环中的 SSD 容量含义不变。磁盘读 / 写共享同一个显示单位，通过二者最大值决定缩放，不可将两个不同量纲拼接。显示与 VoiceOver 均保持读在前、写在后。

平均风扇只用于本面板摘要：对新鲜、finite、非负、measured 的各风扇 RPM 取算术平均，真实 0 参与计算。部分风扇读不到则只平均有效值，说明样本数；全部不可读显示「—」。明确 fanCount == 0 才显示本地化「无风扇」。保留现有 fanSummarySample 的最高转速语义，避免改变菜单栏 / Dock 外环。过期数据不参与实时平均；已保留的过期值如展示，须明确变暗并说明已过期，不能伪装实时。

异常数据、不可用和 collecting 均保持固定列、不显示虚构 0、不改变高度。大数值自适应单位与有效数字，不增加行数；缺失磁盘一侧显示该侧「—」。悬停帮助和 VoiceOver 提供完整指标名、单位、读写顺序和不可用原因。

## 实现边界

复用 HardwareMetricsService、HardwareSampler 的 serial utility queue 和 HardwareMonitorObservable 叶观察。新增磁盘累计计数 reader，通过 IOBlockStorageDriver 的 Statistics 读取 Bytes (Read) / Bytes (Write)，按稳定 IORegistryEntryID 去重；不要再统计逻辑卷，避免双算。IOKit 引用必须释放。首帧建立基线；非递增时钟、过短或超过 15 s 间隔、计数回退、设备集合变化或读取失败时重建基线，不产生尖峰。

新增内部 HardwareMetricID.diskRead / diskWrite、HardwareMetricFamily.disk 和 source.ioStorage，磁盘采样 1 s。面板打开且处于 summary 且硬件模块可见时，固定请求四环所需 CPU/GPU/RAM、CPU/GPU 温度，以及网络、风扇、磁盘；关闭、切详情、禁用模块或休眠结束该 panel demand，已有其它消费者需求仍各自保留。不得增加第二个计时器、Helper、权限请求、子进程轮询或后台常驻任务。

既有硬件指标设置和导出格式保留；本次固定面板组合不新增设置字段，不把磁盘扩展为图标可选来源，也不修改 SettingsPreferenceCatalog。旧卡片可保留为未使用的兼容组件，不在面板重复呈现；其最高转速等现有测试不应被放宽。

新用户可见文案必须经 LocalizationKey 和全部已有 12 个语言资源；使用 macOS 13 可用 SF Symbols 及现有 fallback。此变更仅涉及面板摘要及内部数据，不更改共享图标渲染器、菜单栏 / Dock 设定或图标语义。

## 验证与交付

覆盖磁盘差分 / 拓扑变化、风扇平均与不可用语义、格式化 / 大数值、面板 demand 生命周期；迭代用 scripts/test.sh 的相关过滤器，最终跑 verify-local.sh full。不得开启可见 UI 测试来凑覆盖。原生视觉检查应使用离屏快照或项目后台 UI 流程；当前 macOS / Ventura 运行、签名、真实 Helper、Universal、发布验证分别记录，不以编译代替。

从 feat/hardware-monitor-outer-ring 的 aeb8ab201ccf5ff6bd9dd45cf2fbfd78f2628829 建独立分支 system-monitor-compact-panel。完成后保留分支供人工验收，不合并、不推送、不发布。实施细节（小型文件组织、注入 seam、数字格式化工具）由执行者在上述约束内决定。
