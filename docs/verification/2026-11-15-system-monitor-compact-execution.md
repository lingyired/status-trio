# 系统监控紧凑面板：计划交付与执行状态

## 当前范围

- 分支：system-monitor-compact-panel；功能基线 aeb8ab201ccf5ff6bd9dd45cf2fbfd78f2628829。
- 计划提交：f1c49d208af6cb0c50ae2f67a9ec2b2d317ac1c2。
- 已交付定稿设计、分任务实施计划和用户确认的截图；尚无产品源代码改动。
- 用户指定模型：auto-deepseek-v4-1-flash；未使用其它模型替代执行。

## 已运行检查

- bash scripts/test.sh 'HardwareMonitorPanelDemandTests|HardwareSamplerTests|HardwareMonitorCardTests'：PASS，exit 0（功能基线）。
- bash scripts/verify-local.sh docs：PASS，exit 0，验证 SHA f1c49d208af6cb0c50ae2f67a9ec2b2d317ac1c2。
- git diff --check：PASS。
- IORegistry 只读可行性检查：PASS，找到 6 组含整数 Bytes (Read) / Bytes (Write) 的 Statistics；这仅证明计数接口可读，不证明生产 reader 去重或速率实现正确。
- origin/main：7a6ae83b1a8b72189f45b1b7c2b867e816843338；merge base：de1c12da8bf32b6fc8f5b709d736cc10c31a8a62；origin/main...HEAD 为 37 / 143。硬件分支有大量未集成历史，本任务不自动合并 main。
- full profile、原生新 UI 截图 / 运行、Ventura、真实 Helper、签名、公证、Universal 和发布：NOT RUN（未开始产品实现）。普通测试未启用 visible UI opt-in。

## 指定模型执行入口失败

只读最小探测任务明确禁止工具调用和文件修改。全局 DSH 0.2.1-rc.2 和应用配套 DSH 0.2.2-rc.3 均以 provider=auto、model=auto-deepseek-v4-1-flash 启动，返回：

`NO_ADAPTER: no adapter registered for provider "auto"`

因此模型没有接到实施计划，也没有开始实现。全局 DSH 0.2.1-rc.2 与应用配套 DSH 0.2.2-rc.3 的 web profile 只读结构检查均报告 @mars-sea/dsh-commandcode-provider@0.12.9 不兼容；该插件声明支持 0.2.0-rc.2 或 0.2.1-alpha.1。没有授权兼容性豁免、升级 / 降级插件或改动全局设置。

下一步需要一个已注册 auto 模型提供方的执行会话，或把当前会话切换到用户指定模型后从实施计划继续。不能把计划完成或基线测试通过写成实现完成。
