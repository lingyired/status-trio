# 指定模型续接：系统监控紧凑面板

## 执行前提

用户明确指定 auto-deepseek-v4-1-flash。只有执行会话实际选择 / 成功注册该模型后才开始产品实现；不要用其它模型冒充，也不要把本说明当作修改全局模型插件、兼容性豁免或凭据的授权。

## 无需重新讨论的决定

- 用户已确认截图右侧方案：四环原样保留，四组数字在上、图标和单位在下，与四环按列居中。
- 四组顺序：下载、上传、风扇平均转速、磁盘读 / 写。面板 330 pt，摘要目标约 134 pt，详见设计。
- 用户已授权写计划后直接执行。不要重新询问 A/B、重新制作浏览器草图或索要实施确认。

## 工作区与资料

分支 system-monitor-compact-panel，功能基线 aeb8ab201ccf5ff6bd9dd45cf2fbfd78f2628829，来源 feat/hardware-monitor-outer-ring。

先核对 pwd、git branch --show-current、git status，再读取：

1. AGENTS.md。
2. docs/superpowers/specs/2026-11-14-system-monitor-compact-design.md。
3. docs/superpowers/plans/2026-11-14-system-monitor-compact-plan.md。
4. docs/verification/2026-11-15-system-monitor-compact-execution.md。

按 executing-plans 逐任务执行，从 Task 1 开始；当前所有任务复选框仍未勾选。已交付的设计 / 计划 / 记录属于本任务，不应重置或删除。

## 已有证据

监控基线 focused tests 和 verify-local.sh docs 均 exit 0。IORegistry 只读检查发现可用读写累计计数字段。尚无产品代码实现；尚未进行实现后的 full profile / 原生 UI 验证。

## 停止重复的失败尝试

全局和应用配套 headless CLI 均 NO_ADAPTER: no adapter registered for provider "auto"。两种 web profile 检查均因 @mars-sea/dsh-commandcode-provider@0.12.9 版本契约不兼容而失败。在模型环境没有改变前，不重复启动相同探测任务；不得修改全局插件 / 跳过兼容性保护。

完成后报告代码提交、focused 与 full 验证证据、实际 UI 与 macOS 13 / 当前系统的运行验证范围。保留分支和工作区待用户验收，不合并、不推送、不发布。
