# 夜间四项改进设计：#281 / #282 / #275 / #255

用户已授权：先写计划，再连续执行，早上统一验收。实施在 `overnight-panel-color-refresh` 分支，基线 `origin/main=d4598847040a5b2d167ec3825c162270eba3492b`。验收前不合并、不发布、不关闭 issue；原工作区和其他 worktree 的未提交改动不动。

## 产品行为

### #281 电池详情页底部两行

“打开系统电源设置”和“打开应用电池设置”各自成为整行命中目标，包括右侧空白，保留当前文案、动作、字号及双行布局。每行独立轻微 hover 高亮，鼠标移出恢复；保持原生 Button 语义、键盘和辅助功能。仅让这两行使用专用样式，不改变全局按钮。

### #282 功耗图卡片与流带连接

采用 issue 优先方案 A：存在真实连接的卡片，只有连接侧两个角为直角，外侧仍为 12pt 圆角。输入卡片右侧、分支卡片左侧为连接边；孤立/无有效流带时四角仍为 12pt。macOS 13 自定义 Shape，fill/stroke 共用路径，必要时在卡片下面搭接 1pt，避免抗锯齿缝。保持卡片尺寸、布局、颜色、功率分支比例算法及无动画时钟不变。

### #275 蓝牙图标独立配色

原 issue 的意图是让图标可以跟随系统单色，而非按连接状态改颜色。增加 `usesBluetoothAudioIconColor` 持久设置，默认 true，独立于现有 `usesBluetoothAudioVolumeColor`。开启保留当前 `.bluetooth` 状态色及已有自定义调色板；关闭时中间蓝牙/设备符号使用 `.primary`（随明暗变化），不修改音量显示颜色。设置放在“应用图标 > 中间图标”相关蓝牙配置，文案明确区分图标和音量。所有自动、指定设备、手选符号路径以及菜单栏、Dock、设置预览共用同一配置。无需新增扫描、权限或自定义颜色体系。

### #255 双电源刷新间隔

新增 `refreshIntervalOnBatterySeconds`、`refreshIntervalOnPowerSeconds`，keys 为 `statusRefreshIntervalOnBatterySeconds`、`statusRefreshIntervalOnPowerSeconds`。范围均 5...60、步进 1、默认 15。新 key 各自不存在时从旧 `statusRefreshIntervalSeconds` 迁移；新 key 优先。非有限值、越界值按现有合法化约定安全回退/夹紧。保留旧 key 作为迁移来源，不覆盖已迁移新值。

纯选择逻辑依据电池是否存在和是否接电：有电池且未接电用 battery，其余含台式机用 power；不得根据“正在充电”判断。Settings 使用两行滑条并标注当前生效项。StatusBarController 组合两个设置与去重后的电源类型，最终秒数变化才通知 SystemStatusStore。更新间隔立即取消旧等待并启动新周期；不重启硬件 monitor，不额外立即刷新，不新增 timer，不因无关 snapshot 变化反复重建。未 start 或 stop 后不能启动刷新任务。任务取消与 deinit 正确，旧任务不得在新周期继续刷新。

## 实施边界与验收

- 两个电池 UI 问题可并行开发；刷新间隔负责共享 SettingsStore/本地化期间，蓝牙修改共享文件需顺序整合。
- 先写行为回归，确认旧行为失败，再实现；视觉检查用隔离离屏渲染或项目后台 UI 流程，普通测试不得产生真实窗口。
- 新文案补齐 12 种已随包语言，保持完整键覆盖。
- 重点回归：右侧空白可点、两行 hover 独立；有/无输入和单/多分支卡片；蓝牙图标/音量配色互相独立与两种表面一致；迁移、上下界、台式机、插拔电、睡眠取消、停止后不复活。
- 最终整合树运行 focused icon parity/alignment 与 `bash scripts/verify-local.sh full`；制作 `bash scripts/build-worktree.sh release no-open` 独立开发包，保留 STDevelopmentCodename。真实交互及 Ventura 运行未测时如实标记 NOT RUN，留待明早人工验收。

## 执行裁定

Ruling: 用户已明确要求睡觉期间直接执行，设计与计划写入后不再等待二次审批；未指定细节采用原 issue 和现有产品惯例，成本是验收时可在隔离分支调整。
Ruling: #275 增加独立图标配色开关，继续复用现有蓝牙自定义色；不扩展为新的颜色编辑器，因为当前体系已有状态色。
Ruling: #255 双默认均为 15 秒，避免新装/升级后增加后台唤醒；旧用户两项均继承旧合法值。
