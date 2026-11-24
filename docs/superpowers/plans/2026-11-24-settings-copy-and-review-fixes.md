# 设置文案与主线审查修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkboxes for tracking.

**目标**　让 12 种语言的设置更好读，在 Settings 和状态面板的窄宽度下保持可读，并收尾上一轮审查指出的本地代码问题。

**方案**　设置继续使用现有 `LocalizationKey`、设置控件和 Preference 绑定。按控件的显示空间精简文案，用离屏 AppKit/SwiftUI 布局测试验证实际尺寸。音频、强退和发布脚本以独立的回归测试验证。

**技术栈**　macOS 13+、SwiftUI、AppKit、Swift Testing/XCTest、12 个 `.strings` 语言包、Bash。

**依据**　用户对 2026-11-24 审查的反馈，主线基线 `56ec144e`，英文状态面板防截断提交 `ef75d72d`（#379）。执行使用 DSH Magpie `auto/deepseek-v4.1-flash`、`high`。

## 约束

- 「电量模式」同时覆盖高、低电量模式和辅助程序。保留分组含义和现有简中标题。保留「关注作者，欢迎点赞留言」。
- 所有改过的键覆盖 12 种语言，保留格式占位符、阈值、条件和动作。标题先说明对象或动作，次要细节放说明。用实际字体和可用宽度验收。允许说明换行，避免遮挡控件或截掉关键信息。
- 保留 11 个一级页面及应用图标四个子页。界面移动共用控件时沿用原有绑定和数据。保留菜单栏与程序坞设置一致性。
- 在独立 worktree 执行。实机交互按项目后台测试规则。离线发布模拟使用测试夹具。正式环境的改动、远程构建及实际发布留给单独流程。

## 审查重点

- 在最小 640 pt 设置窗口检查长译文、菜单、选择器和辅助说明。英文状态面板使用生产宽度，并检查长动态值。补查德语和阿拉伯语反向布局。
- 已有当前输出、设备正在读取、真实无设备区分准确。当前设备无需等待列表才能操作。
- 确认强退时原进程已经退出或标识变化，不能作用到后来出现的进程。
- 分支包只能经过需要人工审批的签名环境。候选版号领先更新源可以本地验证，公开源滞后必须明确可见。

## 任务 1 · 文案和分组

文件范围为 [UI/Settings](../../../Sources/StatusTrioCore/UI/Settings)、[资源](../../../Sources/StatusTrioCore/Resources)、[LocalizationKey.swift](../../../Sources/StatusTrioCore/Localization/LocalizationKey.swift) 及相关设置测试。

- [x] 应用图标介绍补齐本机电池、AirPods、自定义三种顶部内容。简化图标大小、充电状态避重和底部指标名称。统一同个元素在标题、说明和跨页提示的叫法。
- [x] 电池阈值行用「自动开启阈值」。保留「电量模式」和「关注作者，欢迎点赞留言」。在电池图标共用设置注明同步。保持唤醒说明准确区分防止显示器休眠、合盖不睡眠和 20% 自动恢复。保留现有辅助程序安装与授权逻辑。
- [x] 网络定位说明区分连接状态、网络名称和扫描结果。蓝牙电量说明覆盖支持的配件，Apple 设备说明写清读取条件。音频把「显示规则」改为「设备列表」，说明默认展开与手动隐藏的关系。亮度使用「亮度控制方式」，明确显示器开关只控制面板上的亮度行，将组合亮度单列为 BetterDisplay 组。
- [x] 系统监控新增「采样与趋势」组名，说明后台历史范围及刷新逻辑。把「圆环进度左右平分」压短并保留左右进度语义。状态面板把原「面板背景」扩为「外观」，移动通用页的滑杆外观控件。保留音频页的音量滚动范围及提示音，精简状态面板滚动方向、滚轮步长及打开关闭说明。通用使用「登录时启动」「状态检查频率」「导入与导出设置」。
- [x] 对所有改动键验证同键、同占位符和数值语义。补离屏布局回归，设置使用实际 640 pt 窗口约束，状态面板延用 #379 的英文 Wi-Fi、功耗、时间值和刷新选项。列出 12 种语言的覆盖结果。离屏证据与有窗口实测分别报告。
- [x] 执行 `bash scripts/test.sh 'SettingsViewTests|SettingsCopyLayoutTests|LocalizationParityTests|LocalizationTests|PanelPresentationMapperTests|BatteryDetailsLayoutTests|PanelActionAlignmentTests'` 以及 12 份运行时资源的 `plutil -lint`。预期无失败。

## 任务 2 · 懒加载音频空态和强退身份

文件范围为 [VolumeControlsView.swift](../../../Sources/StatusTrioCore/UI/VolumeControlsView.swift)、[AudioInputControlsView.swift](../../../Sources/StatusTrioCore/UI/AudioInputControlsView.swift)、现有 Panel mapper / state、[AppQuitter.swift](../../../Sources/StatusTrioCore/UI/AppQuitter.swift) 及调用视图和测试。

- [x] 先增加真实当前输出、设备列表未加载的用例。断言存在可用滑杆和滚动区。为现有滚动测试注入有效音频状态。覆盖无设备保持空态、占位列表保持布局。输入侧区分当前设备和列表。
- [x] 按设备状态决定空态，保留当前设备的音量、静音和滚动。验证 `bash scripts/test.sh 'PopoverScrollTargetsTests|PanelActionAlignmentTests|AudioInputControlsViewTests|AudioPanelMapperTests|CompactAudioLayoutTests'`，预期全绿。
- [x] 先测试强退确认前 PID 复用及读取启动时间失败。验证每个应用实例和子进程的启动时间都在执行前重新核对。身份不匹配时不发送信号，保持批次失败可报告。用注入进程和信号提供者覆盖，测试不向真实进程发信号。验证 `bash scripts/test.sh 'AppQuitterTests|TopApps'`，预期全绿。

## 任务 3 · 发布边界与验证

文件范围为 [build-candidate.yml](../../../.github/workflows/build-candidate.yml)、[check-info-plist-version-sync.sh](../../../scripts/check-info-plist-version-sync.sh)、[publish-release.sh](../../../scripts/publish-release.sh)、现有策略测试和发布说明。

- [x] 先用离线策略用例固定三个分支。非 main SHA 无论操作者是谁都走人工审批环境。main SHA 的 owner-only 例外还需从 main 启动。其他情况保持审批。同步分支构建说明，让分支候选可以从 main 的 workflow 提交冻结 SHA，保留 test_candidate 不可发布门禁。
- [x] 先用离线版本夹具覆盖待发版本领先、比公开版本落后、相同 build 但营销版本不同。把运行于普通本地验证的检查设为允许领先、拒绝回退，保留发布对齐的精确检查模式，并将使用场景写进发布文档。
- [x] 将认证 API 确认与客户端公开更新源验证拆开。公开更新源尚未传播时保留有界重试和明确的未确认状态。两边都匹配后才报告公开验证通过。离线用例覆盖 API 已更新、公开源滞后、公开源匹配。
- [x] 跑 `bash scripts/test-candidate-workflow-policy.sh`、`bash scripts/test-release-candidate-provenance.sh`、`bash scripts/test-release-candidate-publish-gate.sh`、`bash scripts/test-release-pipeline.sh` 和版本检查。预期全绿。

## 集成和交付

- [x] 收掉审查指出的测试文件末尾空行。运行 `git diff --check` 和 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=0 bash scripts/verify-local.sh full`。提交每批可验证改动，保留分支和 worktree 供验收。

## 验证记录

- 隔离分支 `review-fixes-settings-copy` 基于 `origin/main` 的 `56ec144e`。Flash 高推理负责实现和首轮回归修正，当前会话负责实际运行测试，并将布局测试改用支持有界提案的 `NSHostingController`。
- 聚焦回归 85 项通过。设置测试以 640 pt 窗口的 444 pt 内容列为约束，离屏测量生产设置行，覆盖 12 种语言和阿拉伯语 RTL。`plutil -lint` 核对 12 份语言资源，受保护的两处文案均与基线一致。330 pt 状态面板复用既有 Wi-Fi、功耗、续航排版及选项回归。
- `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=0 bash scripts/verify-local.sh full` 退出 0。XCTest 共 4,004 项，其中 105 项跳过，失败 0。Swift Testing 报告 1,278 项通过。Release 构建、非 Universal 本地包、原生检查和离线发布模拟通过。
- 真实窗口操作、Ventura 实机、开发者签名与线上发布尚未执行。签名环境的分支限制仍需仓库管理员按[发布说明](../../github-actions-release.md#审批边界与-environment)配置。
