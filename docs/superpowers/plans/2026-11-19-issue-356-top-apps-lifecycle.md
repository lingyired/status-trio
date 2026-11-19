# #356 Top Apps Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Track each step with the checkboxes below.

**Goal** 修正共享进程执行器的管道收尾并验证 Top Apps 详情会话的取消与重置。

**Architecture** 两个非阻塞 DispatchSourceRead 由同一状态队列协调。有界读取与明确的 FD 所有权降低清理成本。会话验证复用 Demand、sessionGeneration 与 inFlight。

**Tech Stack** Swift、Foundation Process、Dispatch、Darwin、Swift Testing、XCTest。

**Spec** [生命周期设计](../specs/2026-11-19-issue-356-top-apps-lifecycle-design.md)。

## 全局约束

- 原始基线为 origin/main f1e915a37d9a31f621d889c75b40f1800ad5f2c3，执行期间更新到 fcac7f44aff7b153ca29b5442f5a3db860f10794。新增提交仅涉及系统监控外环与相关代码。Runner 与 Top Apps 分支独立验证，整合时以最新 main 为基线。本地修改留待用户验收。
- macOS 13+。保留权限边界、硬件监控结构、榜单口径、UI、CPU/GPU/网络 2 秒及内存 6 秒的正常间隔。
- 实现及审查子任务采用 auto/deepseek-v4.1-flash，reasoningEffort max。

## Review Focus

- 继承写端跨过 deadline。调用返回时两路 FD 和读源已经释放。
- 继承写端稍后关闭。保留子进程报告尾部与双流输出完整性。
- 无穷写入、同时输出或中断。读批次要让出队列，逐路检查输出限制。
- 结束、取消、deadline、EOF 同时到达。结果恰好返回一次，重复停止不重发信号。
- 同指标重开或快速睡醒，旧读取在 reset 之后才回来。新会话首个有效累计样本只建基线。

### Task 1: 共享 Runner 管道收尾

**Files** [Runner](../../../Sources/StatusTrioCore/Monitoring/BoundedProcessRunner.swift)、[Invocation tests](../../../Tests/StatusTrioCoreTests/BoundedProcessInvocationTests.swift)、[Drain tests](../../../Tests/StatusTrioCoreTests/BoundedProcessDrainTests.swift)、[Cleanup tests](../../../Tests/StatusTrioCoreTests/BoundedProcessHandlerCleanupTests.swift)，保留 [Dual-stream tests](../../../Tests/StatusTrioCoreTests/BoundedProcessDualStreamTests.swift)。

**Interfaces** 保留 BoundedProcessInvocation.init / run / runSync / start / cancel 的生产接口和 BoundedProcessOutcome。测试通过现有 isMonitoringPipes 或对应同步诊断观测真正关闭的读端。诊断不得阻塞回调所在队列。

- [ ] 复用主动释放的继承写端 fixture。先补直接子进程已退出、写端未关闭时重复取消的测试。断言在原 deadline 前返回 cancelled、结束回调一次。运行定向测试并记录 RED，再写实现。
- [ ] 增加只持有 stdout、只持有 stderr 和双流的可控场景，覆盖超时后读端关闭、EOF 与取消/超时相邻发生、大双路尾部、任一路单独 outputTooLarge，及启动前取消、启动失败、反复 100 次正常 invocation 的资源释放。使用事件或进程状态同步，fixture 子进程按所有路径收尾。
- [ ] 在状态队列上建立两个非阻塞读源。每个事件限制系统调用次数，以保证持续写入或 EINTR 不会拖延 deadline，处理 EAGAIN、EOF 和读错误。EOF 取消单路源，来源取消处理器统一释放读端。保留完整的退出后排空，直到两路 EOF 或原调用 deadline。
- [ ] 启动、信号升级和结束由同一个所有者控制。保持 250 ms kill grace / 500 ms 错误收尾 grace，仅向仍在运行的直接子进程发信号。同步与异步完成一次，首个终止原因固定，实际清理后通知调用者。处理设置/启动失败与未触发或迟到回调。
- [ ] 运行 bash scripts/test.sh 'BoundedProcess|TopAppCommandReader'，确认新旧 Runner 测试和命令调用契约通过。独立提交 Runner 与直接回归测试。

### Task 2: Top Apps 会话收尾

**Files** [Service](../../../Sources/StatusTrioCore/Monitoring/TopAppsService.swift)、[Sampler](../../../Sources/StatusTrioCore/Monitoring/TopAppsSampler.swift)、[Service tests](../../../Tests/StatusTrioCoreTests/TopAppsServiceTests.swift)、[Panel demand tests](../../../Tests/StatusTrioCoreTests/TopAppsPanelDemandTests.swift)。[面板接线](../../../Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift) 优先验证。

**Interfaces** 保留 setDemand(_ metric: TopAppMetric?)、sleep()、wake()、stop()、TopAppsSampling.read 和 reset。已有依赖注入点用于控制采样、时钟与睡眠。

- [ ] 用可分别挂起读、reset 的 sampler 假件测试两个顺序。CPU→GPU→网络→内存移动不覆盖最后页面且活动 read 上限为 1。睡眠/唤醒发生在旧 GPU/网络 read 中，下一次 read 必须在旧采样结束及 reset 结束后开始。补同指标关闭重开的 ABA 场景，并确认关闭设置、面板与 stop 期间无新 read。记录可观察 RED。
- [ ] 在现有状态所有者中标记待重置，安排旧采样退出后、下一轮采样前执行。避免 detached reset 与读取交错。在发布或启动新读之前复核会话与 Demand。精简为实际 RED 所需的变更。
- [ ] 运行 bash scripts/test.sh 'TopApps|TopApp|HardwareMonitorPanelDemand'。验证 GPU/网络第一帧 collecting、第二帧依据新基线计算，现有 2/6 秒间隔及面板 Demand 不变。独立提交服务和回归测试。

### Task 3: 综合验证与交付

- [ ] 对整合树运行 bash scripts/test.sh 'BoundedProcess|TopApps|TopApp|HardwareMonitorPanelDemand'。按脚本接口验证，记录两套测试数。检查共享蓝牙、Wi-Fi、AirPods、Battery/Power 调用方覆盖。
- [ ] 诊断运行可用工具链的 Thread Sanitizer。首选独立 scratch path 的 Runner 测试，先通过仓库 forbidden-patterns gate，记录实际命令、状态、已知工具链限制。
- [ ] 运行一次 bash scripts/verify-local.sh full，记录 SHA、退出码、各阶段及可见 UI 跳过项。审查提交范围并保留分支供验收。
- [ ] 真机使用固定环境对比基线和候选 build。关闭 Top Apps 记录对照，CPU 页保持至少五分钟，四类页面各观察一次，开关和换页累计 100 次，合上面板继续观测。记录 CPU 平均值与峰值、直接子进程、线程、FD、失败率及采样尾迹。开发机、M1 Pro/macOS 27.2 报告机、macOS 13 运行检查分别记录 PASS、FAIL、BLOCKED 或 NOT RUN。
- [ ] 按基线分析元信息与图标查询成本，以及重复失败是否造成明显进程开销。维护 2/6 秒成功采样间隔。只有证据充分时另行提交优化。
