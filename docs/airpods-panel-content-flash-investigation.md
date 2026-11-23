# AirPods 面板内容瞬闪：调查进展

日期：2026-11-05。分支：`codex/fix-airpods-rapid-disclosure`。
基线：`0620ad3c671764a11fba8e66e7501d60e9b95c83` 加本轮开始前已有的未提交修复。

## 当前结论

**人工验收失败：用户运行候选开发版后反馈“还是会”。**

该反馈发生在本会话启动开发版之后；开发包二进制与本地构建记录的 SHA-256
一致。移除 `.preferredContentSize` 不是解决该瞬闪的充分修复，不能继续把
10pt 初始化异常当作用户症状的完整解释。自动化仍没有有效复现用户看到的
“固定外框内顶部内容瞬间上移/消失后恢复”；此前 full 通过不构成 UI 验收通过。

本次反馈后的工作仅限只读分析和更新计划；不新增源码修改，不运行测试、
构建或实窗操作，也不重启或终止应用。

本轮子任务均使用用户指定的 `auto/deepseek-v4.1-flash`。
使用实际 `LocalizedRootView` / `StatusPopoverView` / OutputDeviceList / Footer，
五个 synthetic 输出设备及一个 synthetic AirPods preview，发现了此前简化行测试
没有覆盖的生产 sizing 配置问题。

首次显示的控制组追踪得到：

```text
contentHeight = 531
panel sets frame = 330 x 531
orderFront: frame becomes 330 x 10
contentHeight = 538
panel sets frame = 330 x 538
window resize: frame becomes 330 x 10
host preferredContentSize = 330 x 10
scroll clip height = 0
```

控制组没有 fixture overlay marker，也没有调用 `cacheDisplay` 或录屏。
该时序证明窗口的显式内容测量和 preferred sizing 存在竞争；但初始化已失败，
有效 disclosure 点击数为零，不能把它当成用户录屏中瞬闪的直接复现。
XCTest hosting 生命周期与真实产品窗口的差异仍需验证。

## 候选改动

- `Sources/StatusTrioCore/UI/StatusBarController.swift`：不再对 status panel 的
  hosting controller 开启 `.preferredContentSize`，保留
  `StatusPanelLayoutMetrics` 和现有 layout coordinator 决定窗口尺寸。
  未增加动画驱动或修改动画参数。
- `Tests/StatusTrioCoreTests/MacOS13UICompatibilityTests.swift`：
  将旧的 preferred sizing 正向源码契约改为防止第二尺寸来源重新进入的契约，
  保留无关 onboarding 兼容检查。

曾加入实际 summary root 的诊断 fixture 和 DEBUG 测量 hook。独立审查发现
顶部可见性、连续有限 viewport、观测副作用和失败初始化清理仍有缺口，
又因 live 路径停止无法验证，因此已将这套脚手架归档到本地
`.superpowers/sdd/2026-11-05-airpods-panel-content-flash-investigation/diagnostic-draft/`。
`AirPodsDisclosureIntegrationTests.swift` 与 `AnchoredStatusPanel.swift` 均逐字节
恢复本轮开始前的内容，上轮已有 16 个实窗测试保留。归档不代表这些新回归已经通过。
本轮实际代码修改仅上面两个文件。

## 验证与停止边界

Focused 命令：

```sh
bash scripts/test.sh 'MacOS13UICompatibilityTests|AirPodsDisclosureIntegrationTests|StatusPanelContentResizeTests|StatusPanelScrollAreaTests|StatusPanelResizeAnimationTests|StatusPanelResizeCoordinatorTests'
```

撤出诊断草稿后的 focused 结果：50 项中 32 项通过，18 项 visible UI 用例默认
跳过，0 failures。这是非 GUI 回归和编译证据，
**不证明候选改动已通过实窗验证**。

最终树 `bash scripts/verify-local.sh full` 已通过：Helper XCTest 15 项，
Core XCTest 2524 项（87 项跳过），Swift Testing 875 项，0 failures；
Release 构建、arm64 本地 bundle、平台/依赖契约和 27 个 native/offline 检查通过。
最终证据为本地 `final-full.log` / `final-full.exit`，不是撤出草稿前的 `full.log`。
独立复审未发现最小候选代码的新静态缺陷，但完整规格验收仍判定未完成。

另经 `bash scripts/build-worktree.sh release no-open` 准备了
`dist/StatusTrio.app`，Bundle ID 为
`com.lingsmbp.StatusTrio.dev.fix-airpods-rapid-disclosure`，
开发代号 `Fix Airpods Rapid Disclosure`，未启动。
此为本地 arm64 开发包，不是 Universal 正式发布或公证验收。

控制组第一次实窗观测记录 0 次目标进程激活、panel 非 key；后一次控制组
运行记录到目标进程 activation，已停止此 live fixture 路径。没有继续尝试
post-fix treatment，也没有改用全局鼠标/键盘或激活后恢复焦点。
不能对整轮实验宣称“零干扰”。

目前 `NOT RUN`：

- 候选改动后的 finite viewport 与实际 20ms 反向。
- 完整页面的 30 次 20–80ms 交替、分批状态、关闭及超屏幕矩阵。
- 合成器连续画面、真实 AirPods、Ventura 和真实 1x 显示。

## 后续验收

先在已重新评估的后台窗口路径或用户明确进行的手动验收中，确认候选改动后
首展不再被 preferred sizing 覆写；再观察用户描述的固定外框内瞬闪。
若仍出现，按计划继续区分 clip origin、host/ancestor 几何和实际节点可见性，
不把消除一个 sizing 竞争点当成完整症状已经解决。

计划：`docs/superpowers/plans/2026-11-05-airpods-panel-content-flash-investigation.md`。
本地详细报告和控制组时间线保留在
`.superpowers/sdd/2026-11-05-airpods-panel-content-flash-investigation/`；
该目录为本地忽略文件，不随提交分发。
未提交、推送、合并或发布。
