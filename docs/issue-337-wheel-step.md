# Issue #337：统一滚轮调节步长

## 行为

- 状态面板设置提供每格 1–20% 的步长，间隔 0.5%，默认 5%。用于输出音量、屏幕亮度、音频输入及主面板空白区域音量调节。
- 该交互只存在于状态面板，不影响菜单栏与 Dock 图标渲染。
- 非精确滚轮事件的原始行数不是物理刻度计数。完整事件（绝对值至少 1）统一视为一格，避免常见 1/3 行设备的三倍差异；不足 1 的事件累计到一格。方向改变、目标改变、精确滚动或间隔超过 0.75 秒时清空余量。
- AppKit 不提供通用的物理刻度数；合并事件或第三方驱动的特殊事件无法仅凭 delta 完美还原，需真实设备验收。快速滚动按收到的完整事件数推进。
- 精确触控板事件继续每点 0.002 的连续映射，不应用步长。
- 偏好持久化并显式纳入 SettingsPreferenceCatalog；旧版本导入文档缺少该键时保留现值，非法值回退到默认值。

## 实施与验证

1. 回归测试复现 3 行被放大问题。
2. 统一换算函数，隔离不同目标的不足一格余量；接入三个消费路径。
3. 设置页、本地化、持久化、导入导出及相关测试。
4. 完整本地验证，构建独立开发包；保留 worktree 等待人工手感验收，不合并、不关闭 issue。

## 本地验证记录（2026-11-13）

- 分支：`dsh-20ee9696-a0ba`；基线与验证前最新 `origin/main` 均为 `4e6f67319925d9b7fe8da06addf81f123cbd65ff`，无上游差异。
- 工具链：Xcode 27.0（27A266a）、Swift 6.4、macOS SDK 27.0、arm64。
- RED：新增 1/3 行等幅测试在原实现上失败，3 行产生 ±0.15 而预期 ±0.05。
- PASS：`bash scripts/test.sh 'PanelLevelScrollStepTests|PopupVolumeScrollAdjustmentTests|SettingsPreferenceCatalogTests|SettingsTransfer|SettingsViewTests'`；63 个 XCTest 与 16 个 Swift Testing 测试，0 失败。
- PASS：`bash scripts/verify-local.sh full`；Core XCTest 3281 项（48 项可见 UI 测试按策略跳过）、Helper XCTest 26 项、Swift Testing 1019 项，0 失败；Release 编译、应用包、平台/SDK、依赖、Helper 与离线发布流程检查通过。
- 日志：本 worktree 的 `.build/local-verification/log.txt`；完整 profile 验证的是基线加本次工作树改动，非已发布版本。
- NOT RUN：真实鼠标/触控板输入、音量/亮度/麦克风硬件反馈、Ventura 与当前系统的实际运行验收、签名公证和正式发布。

## 人工验收

1. 打开独立测试版，在「设置 → 状态面板 → 面板滚动」调整「滚轮调节步长」。默认应为 5%，可调 1–20%，间隔 0.5%。
2. 鼠标每格分别调节音量、亮度、麦克风，确认等于所选步长；再试 2.5% 和 10%。
3. 触控板小幅连续滚动，确认仍平滑；快速滚轮与反向滚动检查设备驱动下的手感。
4. 重启后保留设置；导出、修改步长、再导入，确认恢复原值。

状态：开发验证通过，等待人工验收。分支与 worktree 保留；尚未合并、推送或正式发布。
