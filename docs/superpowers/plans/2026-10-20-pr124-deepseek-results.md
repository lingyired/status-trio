# PR #124 DeepSeek 修复交付

日期：2026-10-20。四项生产代码问题已修复；相关回归通过。当前没有满足合并门槛，未提交、推送或合并，未发布版本。

## 代码位置

- PR：https://github.com/lingyired/status-trio/pull/124
- 基线 Head：`ace36b341d32da004614e4555b95fa341b9b346f`。
- 独立工作区：`/tmp/status-trio-pr124-review`。
- 本地分支：`codex/pr124-huawei-fixes`，改动尚未提交；分支指针仍在原 PR Head。
- 可恢复补丁：[deepseek-fixes.patch](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/deepseek-fixes.patch)。已运行 `git apply --reverse --check` 验证它完整对应当前修复；应用目标为上述原始 PR Head。
- 模型：子任务工具使用 `auto/deepseek-v4.1-flash`，这是工具列出的 DeepSeek V4.1 Flash 调用名称；用户指定名称为 `group/auto-deepseek-v4-1-flash`。实现与独立审查均使用该 DeepSeek 配置。

主工作区原有修改均保留。源 PR 没有更新，修复代码目前只在上述独立工作区和补丁中。

## 修复内容

1. `StatusPanelViewModel` 使用当前收到的 `VolumeStatus.outputDevices` 组成发现任务身份，覆盖输出端点增加与移除。
2. `HuaweiAudioEndpointMatcher` 严格解析六字节冒号/连字符地址，拒绝让同名匹配覆盖冲突地址，保留唯一 opaque UID 名称回退和重复证据失败规则。
3. `HuaweiRFCOMMTransport` 使用同步操作状态及取消处理，让预先取消和排队取消不再发出指令；运行中的等待检查取消，部分打开通道在错误/取消路径中清理。
4. 关闭同步推进会话代际，覆盖线程启动及取得 run loop 后尚未入队的窗口；统一 drain 所有权，防止嵌套 RunLoop 重入；合并尚未启动时的关闭请求。重新打开仍只使用一个工作线程。

新增测试也验证精确关闭编号：重复旧关闭通知不能满足新关闭等待；信号和任务等待有超时，超时会抛错并释放测试 gate。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 输出列表身份测试 | 14 项通过 |
| 耳机端点匹配测试 | 7 项通过 |
| 传输生命周期测试 | 11 项通过 |
| 默认 IOBluetooth 传输启动路径测试 | 1 项通过 |
| 最终完整 XCTest | 1,749 项，跳过 7 项，0 失败 |
| 最终完整 Swift Testing | 697 项中 1 项测试失败，产生 4 条断言问题；见下方基线复现 |
| Release 构建 | 成功，Xcode 27.0 / Swift 6.4；最终仅修改测试文件后，三份生产代码 diff 均保持与该构建一致 |
| 非发布 appcast 说明校验 | 通过，`VERSION=1.6.1 BUILD=38 PUBLISH=false`，现有 en/zh-Hans 两种语言 |
| `git diff --check` | 通过 |
| GitHub Actions | 未运行，尚无修复提交及对应远端 SHA |
| CI 工具链验收 | 未完成；本地 Xcode 27 / Swift 6.4 不能替代 Xcode 26.6 / Swift 6.3.3 |
| 华为耳机实机验收 | 未执行 |

验证曾在此前两轮完整运行中通过；最终状态必须以最后一次运行的失败记录为准，不能用先前通过覆盖它。

## 已验证的原有测试阻挡

`StatusBarChargingAnimationTickTests.steadyTicksReuseTheTemplateBaseAndThePreRenderedFrames` 期望静态基础图只栅格化一次，但当前本机运行观察到 2 次，并伴随重复图像赋值计数。

- 修复工作区完整运行：该单一测试产生 4 条失败断言，其余 XCTest 无失败。
- 修复工作区单独运行 `swift test --filter StatusBarChargingAnimationTickTests`：同一测试失败，产生 5 条断言问题。
- 全新且干净的原始 PR 工作区 `/tmp/status-trio-pr124-baseline-check`，Head 与原始 PR 一致：运行同一过滤命令，同一测试同样出现 5 条失败断言。该工作区 `git status --porcelain` 为空。
- 本轮没有修改 `StatusBarController.swift` 或该图标测试，也没有修改菜单栏或 Dock 渲染路径。该失败已在原始基线复现；具体多栅格化触发条件尚未定位，不将其推断为本次修复引起或已修好。

对应日志：

- [最终整套测试](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/complete-final-test.log)
- [原始 PR 基线复现](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/original-charging-baseline.log)
- [修复工作区单独复现](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/charging-isolated.log)
- [Release 构建](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/repaired-final-release.log)

## 审查结论与一个非阻挡测试限制

独立审查确认原四项 P2 和后续发现的 drain 重入均已修正。最后复审确认关闭编号精确匹配、等待 continuation 单次恢复及超时抛错成立。

保留一个仅影响失败路径的测试清理限制：如果被测任务本身无视取消，测试超时后取消目标和观察任务并退出，gate 由 `defer` 释放，但不等待疑似卡死任务终止，以免超时保护本身失效。通过的回归路径不受影响；不能将这套 fake 生命周期测试当作真实 RFCOMM 通道、回调时序或耳机硬件的验收。

详细证据：[实现报告](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/task-3-4-report.md)、[最终复审与裁定](/Users/lingsmbp/Documents/aiwork/status-trio/output/pr124-review/final-rereview.md)。

## 执行决定及代价

1. 沿用已有隔离工作区并保留两个已复现的失败回归；如迁移有误，代价是重新迁移测试。
2. 传输取消与启动关闭由同一子任务一起处理，维护共同锁/代际约束；代价是单次审查范围更大。
3. 实现者不提交或推送，父任务先验证组合改动；代价是当前交付保留为工作区补丁，没有细粒度提交。
4. 保留替代 native I/O 的最小执行接口，测试使用真实队列、启动、取消、drain 与代际；代价是原生通道的部分打开清理仍需实机验收。
5. 审查包路径问题由父任务修正成仓库相对路径；最终补丁已检查，避免把工件格式问题当作产品缺陷。
6. 对超时后无界等待的建议采用有界失败优先的裁定；代价是失败测试可能留有等待目标退出的观察任务。已如实记录为非阻挡测试限制。

## 合并前仍需完成

解决或明确处置上述已复现的原有图标测试失败；取得完整验证通过后，再准备修复提交与准确远端 SHA，并按仓库规则运行 `publish=false` 的 release workflow，使用 Xcode 26.6 / Swift 6.3.3 验收。该 CI 未通过前不合并或发布。
