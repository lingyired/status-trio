# 新会话执行提示词

下面整段可以直接复制到新的 Codex 会话。它授权的是执行规格和计划，不是发布/合并。先阅读文档，确认符合你的预期后再使用。

```text
请执行 Status Trio 2.0 独立图标设计器计划，而不是重新做布局脑暴。

先阅读以下文件，并把它们作为本次工作范围：
1. /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/AGENTS.md
2. /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/docs/superpowers/specs/2026-10-10-icon-designer-window-design.md
3. /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/docs/superpowers/plans/2026-10-10-icon-designer-window.md
4. /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/docs/superpowers/references/2026-10-10-icon-designer-layout-v2.html

实现必须使用 gpt-6-luna，推理强度 high；若当前模型不是 Luna，先把产品实现交给该模型，当前会话负责协调和验证。使用 executing-plans 或 subagent-driven-development 技能，按计划逐任务执行并记录进度。

继续使用 /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio，分支 codex/v2-settings-icon-designer。这里有大量已经完成但未提交的2.0改动；先保存并核对dirty baseline，不得从main/HEAD重建后丢掉它们，不得改 /Users/lingsmbp/Documents/aiwork/status-trio 主checkout。文档或worktree缺失时停下说明缺少什么，不能从记忆猜测实现。

网页只是视觉参考。最新确定的设计是：独立大设计器窗口，模拟数据放独立浮动工具窗口，不在主页面展开；模拟样例绑定数据源，主/工具窗共享，不写defaults、不影响真实图标、不进入撤销、不被元素重置清除；中间蓝牙统一入口，再选跟随当前音频或指定在线设备，音频设备才显示音频定制；不实现未来输入法或中间音量来源。其余默认、兼容、动效和验收规则以规格为准。

允许修改当前worktree的本任务代码并本地构建/运行开发版。保留无关改动；本次不commit/push/merge、不发布、不创建tag、不改appcast、不重置系统权限、不覆盖正式版、不启用夜间自动检查。需要CI推送或产品范围改变时另行说明，不能扩大授权。

逐项TDD；完成后运行 swift test、swift build -c release、开发版构建契约和12语言检查，最后 bash scripts/build-dev-app.sh release open。保持Developer ID签名和独立bundle身份。不得用本地新Swift工具链通过冒充CI通过。

最终用中文报告：完成项、测试/构建实际结果、分支和未提交状态、开发App绝对路径、仍需我验证的真实AirPods/权限项。不要把模拟测试说成真实硬件测试。
```
