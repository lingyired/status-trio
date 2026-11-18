# 图标设计器：输入法、蓝牙图标与全局网络异常优先 Implementation Plan

> **For agentic workers:** 使用 executing-plans 按下面任务顺序执行并逐项更新复选框。用户明确要求先写 plan 然后由 DeepSeek 4.1 Flash 执行，不另开布局脑暴或重复审批。

**Goal:** 把已合入 main 的输入法和蓝牙设备图标能力完整纳入独立图标设计器，并把网络异常显示优先级统一为中心区域的全局规则。

**Architecture:** V1 CenterSource 增加 inputSource，复用现有 InputSourceController、descriptor 和 renderer。蓝牙目标与符号选择沿用现有模型；中心全局策略仍持久化在 CenterOverridePolicy，解析器先判断网络异常再解析首选/备用，实时、模拟、菜单栏和 Dock 共用一个 scene。去掉依靠运行时覆盖 .network 来选择输入法的隐式双重来源行为，通过兼容迁移保留用户旧设置。

**Tech Stack:** SwiftPM、SwiftUI/AppKit、Combine、XCTest / Swift Testing。

**Spec:** 本文的产品规则及 docs/superpowers/specs/2026-10-10-icon-designer-window-design.md、docs/icon-sizing-standard.md；本文取代旧规格中“未来输入法不做”和“仅音频蓝牙可被覆盖”的限制。

## Global Constraints

- 仅 /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio，分支 codex/v2-settings-icon-designer；起点 main 合并提交 da053067。保留现有 30 个 dirty 文件中的 AirPods 顶部标记、64-unit 开口以及全部未提交改动。
- 执行模型 group/auto-deepseek-v4-1-flash，reasoning high，父级协调审查验证。用户本轮模型指令优先于早前 Luna 偏好。
- 不 commit、push、merge、发布、改 appcast、安装特权 helper、重置权限或覆盖正式版；构建并运行独立 Developer ID Dev bundle。不得修改主 checkout。
- SDK >= macOS 26，deployment macOS 13；本机通过不等于 CI macos-26 / Xcode 26.6 / Swift 6.3.3 通过。
- 中心统一 100–180% 尺寸；保留菜单栏/Dock 墨迹中心、缓存失效、颜色语义及充电动画；模拟数据仍在独立浮动窗口，仅内存，不写 defaults、不进撤销。

## 产品规则与迁移决定

1. 中心首选与备用列表加入“输入法”。使用当前系统输入法：图标文件 > 短标签 > keyboard，复用 main 的 descriptor/resolvedForDrawing 规则。没有当前 descriptor 时按来源不可用处理并使用配置备用，禁止悄悄改写来源。监听需求同时考虑首选、备用及面板，退出需求后停止监听。
2. 蓝牙来源保留“跟随当前音频输出／指定蓝牙设备”。图标选择在对应来源行为区可见，使用 main 已有自动及设备符号集合、现有设备覆写模型；不要只把新 picker 留在 automaticLegacy 隐藏分支。非音频设备也能自动使用其类型图标，音量相关选项仍只适用于音频。手动选图标及自动恢复必须即时影响预览、菜单栏和 Dock，并进入同一撤销事务。禁止增加配对、主动连接或新权限请求。
3. 中心行为区独立全局开关名称为“网络异常时优先显示网络图标”。不跟随首选/备用行为 tab 隐藏；启用后覆盖全部中心来源，包括输入法、电量数字、蓝牙设备、网络、兼容来源及“无”，以及首选不可用时的备用。网络恢复立即回到原解析结果，不改变配置。使用 StatusMappings.isNetworkOffline(wifi:connection:)：offline 是异常；ethernet/other 有可用网络时 Wi-Fi 关闭不是异常；Wi-Fi 未连接、无互联网、关闭、不可用使用现有异常符号。覆盖路径禁止被旧 inputSource 设置或蓝牙替换再次抢占，trace.reason 为 overridden(networkProblem)，source 为 network，颜色能力模型纳入可达网络颜色。
4. 保留 CenterOverridePolicy.networkProblemOverridesPrimary 旧 bool 编码及已存 true/false，默认不擅自开启。旧 input-source 开关、输入法告警优先、蓝牙网络告警设置不可继续独立控制同一 V1 scene：首次加载明确迁移旧 inputSource 到 V1 inputSource（仅旧 network/automaticLegacy；不覆盖明确 bluetooth/battery/none），只对尚未存 V1 全局策略的旧偏好做兼容，不用 OR 永久覆盖已存 false。有冲突时以已存 V1 来源及全局策略为准，并在文档写清。旧外部设置 UI 删除重复的中心来源／告警控制，保留进入设计器入口及设备／网络自身行为。
5. 首选/备用/大小/颜色/全局策略/蓝牙图标选择的 reset、undo、外部修改失效规则一致；未知旧图标或 OS 不支持符号保持原始偏好并显示自动。模拟工具窗按需求提供输入法样例及网络异常样例，全局策略即使中心为 none 也必须能模拟网络；隐藏样例保留，不影响系统输入法。

## Review Focus

- 升级已有 V1 配置时输入法旧开关不覆盖用户明确选择；显式 false 不被迁移重新开启。
- 实际有线网络正常但 Wi-Fi 关闭，绝不能覆盖输入法或蓝牙图标。
- 首选断开、备用接管及 none 中心也遵守同一全局策略并恢复正确。
- 非音频蓝牙无音量控件；所有新图标选择都能撤销、重置并在 Dock 即时重绘。
- 预览样例与真实 controller 生命周期分开，无权限/输入法不可读不会请求系统授权。

## Task 1：来源模型、兼容迁移与输入法需求

**Files:** Presentation/Icon/Configuration/IconCompositionConfiguration.swift、IconConfigurationMigration.swift、IconConfigurationV1.swift；Settings/SettingsStore.swift；App/AppEnvironment.swift；UI/Settings/IconDesigner/IconDesignerSourceSelection.swift、IconDesignerEditingModel.swift；Tests/StatusTrioCoreTests/IconConfigurationMigrationTests.swift、InputSourceMonitoringLifecycleTests.swift、IconDesignerBluetoothTargetTests.swift。

- [x] 快照当前 HEAD、git status、binary patch 及所有计划修改的 untracked 文件到 output/icon-designer-window/designer-center-sources/baseline；不得 stash/reset 现有改动。 证据：baseline/{HEAD.txt,git-status.txt,dirty-tracked.patch,dirty-stat.txt,untracked.txt}
- [x] 先补会失败的配置 round-trip／旧缺字段／旧输入法偏好／明确 false／首选和备用监听需求测试。表驱动用例必须包括 network、automaticLegacy、bluetoothAudioOutput、systemBatteryPercentage、none。 证据：task1/red.log
- [x] 增加 CenterSource.inputSource 和 IconDesignerCenterChoice.inputSource，更新所有穷尽 switch、来源本地化与能力表。更新输入法监听需求并确保 selectedDescriptor 变化发布。
- [x] 迁移只在存储读取边界执行，不在 body、preview 或 normalized() 中反复读取 defaults。保持旧 JSON 解码与未知符号原始偏好兼容。
- [x] 运行 swift test --filter 'IconConfigurationMigrationTests|InputSourceMonitoringLifecycleTests|IconDesignerBluetoothTargetTests|SettingsStoreTests'，保存命令、退出码及日志。 证据：task1/task-done.log（exit 0，118 tests）

## Task 2：显式输入法解析与全局网络策略

**Files:** Presentation/Icon/Resolution/CenterResolver.swift、IconCompositionResolver.swift；Presentation/Icon/IconPresentationViewModel.swift、IconPresentationConfiguration.swift；Settings/SettingsStore+IconAppearance.swift、SettingsStore+IconPresentation.swift；UI/Settings/IconDesigner/IconDesignerCenterColorRoleModel.swift；Tests/StatusTrioCoreTests/IconSlotResolverTests.swift、IconRuntimePresentationOptionsTests.swift、IconAppearancePublisherTests.swift。

- [x] 为每个 CenterSource、首选断开/备用生效及 none 写全局策略 ON/OFF 测试；异常矩阵包含 offline、wifi off/notAssociated/noInternet/unavailable、正常 ethernet/other、正常wifi/hotspot/shared；测试开启→异常→恢复全过程配置保持相同。 证据：task2/green-final.log
- [x] 明确输入法 descriptor 有图标／仅短标签／无标签使用 keyboard／descriptor nil 使用备用；使用 mapper 原有 input-source 标记构造，不在输入法分支进入蓝牙抢占。
- [x] 把全局异常判断放在 automaticLegacy early return、chooseSource nil return 之前。覆盖使用独立 networkState 分支并避免旧 priority flag 重入；不要修改 StatusMappings 公共判定以通过特例测试。
- [x] 移除上一轮合并的 usesInputSourceInCenter 对 V1 network 的隐式覆盖，保留 fullThreshold/runtime Bluetooth choice 等非本轮功能。确保 publisher 送达值、trace、中心颜色和 Dock cache 输入完整。
- [x] 运行 swift test --filter 'IconSlotResolverTests|IconRuntimePresentationOptionsTests|IconAppearancePublisherTests|InputSourceIconPresentationTests|IconDesignerCenterColorRoleModelTests'。 证据：task2/green-final.log（exit 0，51 tests）

## Task 3：设计器输入法／蓝牙图标及撤销

**Files:** UI/Settings/IconDesigner/IconSourceEditor.swift、IconDesignerBluetoothEditor.swift、IconBehaviorEditor.swift、IconDesignerEditorModel.swift、IconDesignerEditSnapshot.swift、IconDesignerDefaults.swift、IconDesignerBluetoothTargetModel.swift；UI/Settings/NetworkSectionView.swift、BluetoothSectionView.swift；Tests/StatusTrioCoreTests/IconDesignerEditingTests.swift、IconDesignerEditorModelTests.swift、IconBehaviorEditorSourceContractTests.swift、SettingsPagesOptimizationContractTests.swift。

- [x] 中心来源列表显示输入法；蓝牙行为 picker 使用真实支持的符号集合，当前音频/指定音频/非音频设备分别验证作用域，保留离线选择且不要篡改设备地址。
- [x] 所有中心来源都显示一个全局开关，首选/备用行为切换不改变其值；去掉原只对蓝牙音频的 gating 及设备页重复开关。名称按产品规则，帮助说明网络正常后恢复原图标。（名称："网络异常时优先显示网络图标"，帮助说明网络恢复后返回原图标）证据：task3/green-final4.log（exit 0，43 XCTest + 15 Swift Testing）
- [x] 通过 editorModel.perform/updateIconConfiguration 完成图标设置；若需改已有独立 store 偏好，在 IconDesignerEditSnapshot 与外部订阅失效中一并纳入，禁止直接 Binding 绕过 undo。reset center 恢复对应默认并保留其他插槽／设备偏好。（bluetoothAudioIconChoice 纳入 snapshot/undo/reset）
- [x] 扩展现有 tests 验证一次编辑一次撤销、切来源后控制有效目标、global bool 保留、外部变更清理历史，真实 view accessibility 验证开关始终可见。
- [x] 运行 swift test --filter 'IconDesignerEditingTests|IconDesignerEditorModelTests|IconBehaviorEditorSourceContractTests|SettingsPagesOptimizationContractTests|SettingsViewTests'。 证据：task3/green-final.log（exit 0，41 tests + Swift Testing suites）

## Task 4：浮动模拟数据与双表面回归

**Files:** Presentation/Icon/Preview/IconPreviewSampleValues.swift、IconPreviewInputBuilder.swift、IconDesignerPreviewResolver.swift；UI/Settings/IconDesigner/IconPreviewDataView.swift、IconDesignerPreviewSession.swift；UI/Settings/StatusIconPreviewCard.swift；Tests/StatusTrioCoreTests/IconPreviewInputBuilderTests.swift、IconDesignerPreviewSessionTests.swift、IconSceneRendererParityTests.swift、IconSurfaceIntegrationTests.swift。

- [x] 输入法样例提供可用性和短标签，必要时复用固定样例 descriptor，不读写系统真实输入法；全局策略启用时总是包含网络样例依赖。来源变化只隐藏样例不清除数值。
- [x] 真实与模拟都走同一 resolver；测试中心 none + global on + 模拟异常显示网络，恢复网络后回到 none；输入法 unavailable + 配置备用可用时显示备用。
- [x] 输入法图像、短标签及蓝牙选定图标使用统一 100–180% 中心大小；保持 Issue30 可见墨迹锚点。渲染 tests 使用菜单栏 layers 与 Dock 实际像素，覆盖告警开关即时刷新、网络恢复及插槽独立性，不只比较 scene 常量。
- [x] 运行 swift test --filter 'IconPreviewInputBuilderTests|IconDesignerPreviewSessionTests|IconSceneRendererParityTests|IconSurfaceIntegrationTests|Issue30WiFiAlignmentTests|IconSizingStandardTests'。证据：task4/green-final.log（exit 0，22 XCTest + 34 Swift Testing）

## Task 5：12 语言、规格和最终验证

**Files:** Localization/LocalizationKey.swift；Resources 下全部 12 个 Localizable.strings；docs/superpowers/specs/2026-10-10-icon-designer-window-design.md、docs/input-source-center-slot.md、docs/icon-sizing-standard.md；本 plan。

- [x] 更新 12 语言的新来源、全局规则名称/说明和模拟文案，保留 placeholder 一致；删除误导性的音频专属帮助，不随意删除旧 key 导致语言缺失。证据：task5/green-final.log、task5/green-final2.log（每次 exit 0；12 语言均为 647 keys）
- [x] 更新当前规格的来源与全局优先规则，记载旧偏好兼容和 manual QA 边界。每完成任务更新本 plan 复选框及证据路径，不因子任务“通过”冒称父级已验收。
- [x] （父级执行）运行 swift test、swift build -c release、bash scripts/test-local-dev-build-contract.sh、bash scripts/test-macos13-deployment-contract.sh、bash scripts/check-forbidden-patterns.sh；保存日志和退出码。失败先定位根因，不放宽居中容差或删除测试。
- [x] （父级执行）审查后运行 bash scripts/build-dev-app.sh release open，确认独立 bundle、Developer ID、进程路径；不安装 helper、不覆盖正式版。
- [x] （父级执行）GUI 验收输入法来源、蓝牙自动/手选图标、任意中心来源全局开关、模拟异常→恢复及浮动窗口。真实蓝牙与输入法切换由用户最终验收；不运行远端 CI 或推送，说明本地和 CI 验证区别。

## 父级最终验证记录（2026-10-16）

- `parent-full-test-accepted.log`：exit 0，1944 XCTest（7 skipped，0 failures）及 664 Swift Testing / 102 suites 全通过；包括 Issue30 可见墨迹居中和菜单栏／Dock 集成。
- `parent-release-build-final.log`：`swift build -c release` exit 0。三个合同／禁用模式脚本及 `git diff --check` exit 0。
- GUI 发现输入法来源的槽位辅助功能名称缺漏，已统一来源名称映射并补回归。
- 原有两处旧语义测试已改为输入法来源列表及真正的 global ON→OFF 双表面断言，不改变超时或放宽断言。一次 Swift Testing 误用 XCTest 宏的编译问题已修复。
- 详细本地证据：`output/icon-designer-window/designer-center-sources/parent-validation.md`。本地 Xcode 27 / Swift 6.4，不等同于 CI 工具链；未推送／运行远端 CI，真实蓝牙设备和系统输入法切换待用户验收。

- `parent-dev-build-final.log`：独立 Dev 构建／签名校验／启动 exit 0；bundle `com.lingsmbp.StatusTrio.Dev`，Developer ID team `HCB7JKMQ2F`。最终 GUI 确认「输入法，已选中」的辅助功能摘要已修复；临时配置撤销回原状态，实时预览保留。
