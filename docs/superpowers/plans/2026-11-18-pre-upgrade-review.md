# Status Trio 升级前审查与修复计划

建议在冻结发布候选前修复合盖睡眠恢复。系统监控、并排详情、Gitee 镜像可以分开处理和验收。下列问题基于静态审查，现有测试通过，新增故障场景仍需要回归用例。

基线为正式发布的 v1.9.6，发布清单 source_sha 与 tag 均为 3ef2a50b0ddccd7cc1b0803a8fe4936b0d01a258。审查目标为本地及远端共同的 main ea99cbcb9ee347efee2cd8384d030c09ad5e0765。共 321 个提交，460 个文件，+51,123 / −1,111 行。范围限定在已提交的 main。[GitHub 正式发布](https://github.com/lingyired/status-trio/releases/tag/v1.9.6)

## 问题与执行计划

### 1. P1 · 合盖不睡眠可能失去恢复依据

开启过程先持久化归属，再发 Helper 写请求。若系统写入成功，但客户端收不到回复，且紧接着回读也失败，客户端会把未知当作关闭并删除标记。界面显示关闭，也不启动定时清理。退出和下次启动都失去清理依据。初始回读期间如果用户拔电、进入低电量或退出，回读之后到真正写入之前也缺少一次当前意图和策略检查。Helper readiness 的残留恢复另开异步链路，和正常开关共用归属标记，需要纳入同一个状态转换约束。[SleepControlController.swift:510](../../../Sources/StatusTrioCore/Monitoring/SleepControlController.swift#L510) · [恢复入口:643](../../../Sources/StatusTrioCore/Monitoring/SleepControlController.swift#L643) · [AppDelegate.swift:74](../../../Sources/StatusTrioCore/App/AppDelegate.swift#L74)

- [ ] 在假 Helper 覆盖「写已落地但回复超时且回读失败」。断言保留归属，重启恢复通信后先确认系统关闭再清标记。挂起首次回读后模拟拔电、退出和 readiness 变化，断言没有过期的开启写入或恢复动作。[SleepControlSafetyTests.swift:130](../../../Tests/StatusTrioCoreTests/SleepControlSafetyTests.swift#L130)
- [ ] 让开启、关闭和残留恢复服从同一个串行状态机。开启写入前重检当前意图、电源条件和退出状态。明确关闭才清标记，未知走有界恢复。保留外部工具归属、旧 Helper 降级及退出超时保护。
- [ ] 执行 §验收命令第 1 条。签名开发包实机核对真实 XPC、退出和重启清理、拔电与低电量联动。

### 2. P2 · 详情采样绕过频率限制，旧结果也能回流

- GPU 详情打开时，任何指标到期都可能读 IOAccelerator。GPU 使用率依赖两次查询的时间区间，额外查询会改变下轮结果。磁盘详情会在本轮没有磁盘样本时把速率写成 nil，界面因此可能跳成横线。内存详情也会在内存未到期时额外读取。[HardwareSampler.swift:49](../../../Sources/StatusTrioCore/Monitoring/HardwareSampler.swift#L49) · [详情采样:79](../../../Sources/StatusTrioCore/Monitoring/HardwareSampler.swift#L79) · [HardwareDetailView.swift:338](../../../Sources/StatusTrioCore/UI/HardwareDetailView.swift#L338)
- 并排详情复用摘要的指标集合。切页或关闭详情后集合可能不变，旧请求仍持有效 generation，把刚清掉的详情负载写回。等慢读期间也没有真正暂停调度。已有指标到期时，循环仍可能每 50 ms 唤醒主线程检查。实际 CPU 增量待测。[StatusPanelViewModel.swift:1044](../../../Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift#L1044) · [HardwareMetricsService.swift:237](../../../Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift#L237) · [唤醒循环:334](../../../Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift#L334) · [结果合并:448](../../../Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift#L448)

- [ ] 用假时钟、挂起 reader 和家族读取计数补回归。非 GPU tick 读取次数为零，非磁盘 tick 保留上次有效速率，挂起时没有 50 ms 重复唤醒，切页或关闭后丢弃旧详情负载。[HardwareMetricsServiceTests.swift:162](../../../Tests/StatusTrioCoreTests/HardwareMetricsServiceTests.swift#L162) · [HardwareMonitorPanelDemandTests.swift:195](../../../Tests/StatusTrioCoreTests/HardwareMonitorPanelDemandTests.swift#L195)
- [ ] 保留共享采样服务。由到期指标驱动对应详情读取，磁盘容量按独立需求更新。详情会话独立校验迟到回调，允许普通样本继续服务摘要和图标。慢读期间暂停周期回调，完成后重排下一次采样，同时明确数据过期时机。
- [ ] 执行 §验收命令第 2 条。同机对比 1.9.6 和候选，每个稳定场景取 5 分钟，记录 CPU、唤醒、RSS、读次数和子进程数。覆盖默认闲置、开启硬件模块后关窗、1 秒与 8 秒设置，以及详情连续切换。硬件模块默认关闭，用户启用模块后默认开启后台历史。实测后决定是否保留这一默认值。[SettingsStore.swift:192](../../../Sources/StatusTrioCore/Settings/SettingsStore.swift#L192) · [默认模块:276](../../../Sources/StatusTrioCore/Settings/SettingsStore.swift#L276)

### 3. P2 · 并排详情设置可能延迟生效

控制器订阅 @Published 后丢掉新值并马上重读存储。Combine 在 willSet 送值，布局仍按旧设置计算。若面板已打开，之后又没有移动、缩放或有效路由事件，详情可能一直留在原位置。[StatusBarController.swift:625](../../../Sources/StatusTrioCore/UI/StatusBarController.swift#L625) · [SettingsStore.swift:1665](../../../Sources/StatusTrioCore/Settings/SettingsStore.swift#L1665)

- [ ] 加控制器回归。固定窗口和路由，先开后关并排详情，每次设置事件立即得到正确布局。再覆盖屏幕没有足够空间时退回内嵌详情。[StatusPanelLayoutIntegrationTests.swift:192](../../../Tests/StatusTrioCoreTests/StatusPanelLayoutIntegrationTests.swift#L192)
- [ ] 将本次送达的设置值传入布局决策。路由和几何通知继续读取当前设置。执行 §验收命令第 3 条，实际窗口检查菜单栏和 Dock 入口、Escape 焦点返回及多屏切换。

### 4. P2 · 重跑旧 tag 会让 Gitee feed 倒退

同步工具为调用者给出的 tag 生成单条 feed 并替换当前镜像。并发 SHA 检查只判断读取后有没有被修改，已有 feed 包含更高 build 时仍能写入旧版。一旦较新镜像发布后再执行旧版本恢复，较新版本就会从镜像更新源消失。现有模拟覆盖同 tag 重试，缺跨版本倒序用例。[sync-gitee-release.mjs:186](../../../scripts/sync-gitee-release.mjs#L186) · [写入检查:204](../../../scripts/sync-gitee-release.mjs#L204) · [generate-gitee-appcast.py:91](../../../scripts/generate-gitee-appcast.py#L91)

- [ ] 用离线 fixture 先同步高 build，再请求低 build，断言 feed 字节不变且没有远端写入。并测同 build 同字节幂等、同 build 不同身份拒绝、竞争写入拒绝。[test-sync-gitee-release.mjs:61](../../../scripts/test-sync-gitee-release.mjs#L61)
- [ ] 以已验证的 manifest build 和当前 feed build 判断能否继续，保留提交时的并发检查。低 build 在首次写入前退出。执行 §验收命令第 4 条。实机验收 1.9.6 升级、两个来源的归档签名及更新失败恢复。

### 5. P2 · 设置文案与分类

**通用 → 状态补查间隔。** 截图里的两行只有供电条件，读不出调节对象。「状态变化的频率」也容易被理解成所有数据都会按这个间隔更新。实际是电池、Wi-Fi、音量的定期补查。电池每个有效周期检查一次，面板和设置都关着时 Wi-Fi 和音量每四个周期补查一次。无电池的 Mac 使用接通电源档。[GeneralSectionView.swift:141](../../../Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift#L141) · [StatusBarController.swift:435](../../../Sources/StatusTrioCore/UI/StatusBarController.swift#L435) · [SystemStatusStore.swift:1386](../../../Sources/StatusTrioCore/Store/SystemStatusStore.swift#L1386)

- [ ] 从通用页的系统卡片拆出「状态补查间隔」卡片。行名拟用「电池供电时」「接通电源时」，公共说明放在分组下方，拟用「定期补查电池、Wi-Fi 和音量状态。间隔越短，补查越频繁。」可访问性名称带上行名和「状态补查间隔」，避免单独聚焦时失去上下文。保留现有滑杆、取值范围、默认数值及导入导出映射。[SettingsPreferenceCatalog.swift:85](../../../Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift#L85)
- [ ] 通用页的「右键操作」改为「菜单栏图标右键操作」，与全局快捷键归到「快捷操作」，便于区分应用级入口和状态面板内的设置。沿用当前可用性提示和设置绑定。[GeneralSectionView.swift:210](../../../Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift#L210)
- [ ] 侧边栏「监控」改为「系统监控」。把「面板刷新」改为「硬件数据刷新间隔」，说明打开面板时生效，开启后台历史后关窗也沿用此设置，各指标仍有自己的读取频率上限。保留蓝牙电量、能耗排行各自的刷新入口。[HardwareMonitorSectionView.swift:39](../../../Sources/StatusTrioCore/UI/Settings/HardwareMonitorSectionView.swift#L39) · [HardwareMetricsService.swift:479](../../../Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift#L479)
- [ ] 「状态面板 → 打开行为」改为「详情与打开方式」，将「并排显示详情」说明补全为「优先在右侧显示，其次是左侧。两侧都放不下时，在面板内显示。」硬件模块可同时从功能页和状态面板模块列表控制，两处继续绑定同一设置。电池和保持唤醒保留独立功能页。统一简中「合盖不睡眠」用字，把「低电量时自动关闭」写清是关闭合盖不睡眠。[PopoverSectionView.swift:61](../../../Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift#L61) · [KeepAwakeSectionView.swift:58](../../../Sources/StatusTrioCore/UI/Settings/KeepAwakeSectionView.swift#L58)
- [ ] 同步已发布语言的分组、说明和可访问性标签，检查中英、德语长文本和阿语布局。能明确用原有本地化键表达的地方继续复用。运行第 5 条验收命令，并检查菜单栏右键、范围与秒数、两处模块开关同步。

### 6. P2 · 默认高度容不下完整侧边栏

默认内容尺寸是 720 × 530 pt。按当前 11 个一级项目、4 个始终展开的图标子项、固定顶部与底部间隔估算，单行文本已经需要约 555 pt。侧栏隐藏了滚动指示，但内容仍会溢出。[SettingsView.swift:182](../../../Sources/StatusTrioCore/UI/Settings/SettingsView.swift#L182) · [默认尺寸:511](../../../Sources/StatusTrioCore/UI/Settings/SettingsView.swift#L511) · [SettingsSubtopic.swift:9](../../../Sources/StatusTrioCore/UI/Settings/SettingsSubtopic.swift#L9) · [SettingsChrome.swift:1118](../../../Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift#L1118)

- [ ] 首次打开以 720 × 600 pt 为验收起点。用实际侧栏内容高度验证，包含当前全部类别、展开项和底部固定入口。保持现有行高和命中范围。窗口初始高度须适应所在屏幕的可用区域，空间不足或用户手动缩小时继续支持侧栏滚动。[SettingsWindowController.swift:216](../../../Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift#L216)
- [ ] 覆盖无保存尺寸首次打开、已有保存尺寸恢复、短屏与手动缩小。保留原 autosave 键、最低 460 pt 与现有缩放行为。正常屏幕的默认尺寸下全部侧栏项目直接可见，右侧长页面独立滚动。验收简中、英文和长文本语言，macOS 13 与当前 macOS 分开记录结果。运行第 6 条验收命令。[SettingsWindowControllerTests.swift:49](../../../Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift#L49)

## 合并执行顺序

先完成 1。并行推进 2 和 4。任务 3 完成后统一验收任务 5 中的并排文案与交互。任务 5 和 6 可在同一设置分支，分开提交，按最终翻译核对高度。集成后冻结同一个候选 SHA，执行本地 full 和实机升级验收。发布前复核 P1 关闭、P2 结果、实际性能数据与 Gitee 离线防倒退测试。

## 验收命令

1. 合盖和 Helper：
   ~~~bash
   bash scripts/test.sh 'SleepControlSafetyTests|SleepControlControllerTests|PrivilegedHelperManagerTests'
   ~~~
2. 采样与详情：
   ~~~bash
   bash scripts/test.sh 'HardwareMetricsServiceTests|HardwareMonitorPanelDemandTests|HardwareDetailTests|TopAppsServiceTests'
   ~~~
3. 并排面板：
   ~~~bash
   bash scripts/test.sh 'StatusPanelRouteTests|StatusPanelLayoutIntegrationTests|TopAppsPanelDemandTests'
   ~~~
4. 离线发布：
   ~~~bash
   bash scripts/test-gitee-mirror.sh && bash scripts/test-release-workflow-policy.sh && bash scripts/test-release-pipeline.sh
   ~~~

5. 设置分类与本地化
   ~~~bash
   bash scripts/verify-local.sh docs
   bash scripts/test.sh 'SettingsViewTests|SettingsPreferenceCatalogTests|SettingsStoreTests'
   ~~~
6. 设置窗口与侧栏
   ~~~bash
   bash scripts/verify-local.sh quick 'SettingsViewTests|SettingsWindowControllerTests'
   ~~~

## 上轮验证和覆盖

- 已核对完整文件清单，静态深读集中在电源 Helper、采样、详情、配置持久化、图标需求、更新及镜像，另抽查 BetterDisplay 和发布脚本。新增图标和蓝牙实现、各语言文案、文档和图片未逐行审查。历史问题仅在读到相关链路时检查。
- Xcode 27.0 / Swift 6.4 / SDK 27.0 下，STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=0 bash scripts/test.sh 退出 0。XCTest 汇总 3,679 项，跳过 104 项，失败 0。Swift Testing 报告 1,203 项通过。Gitee、发布工作流策略和离线流水线模拟均退出 0。
- Sources、Tests、scripts 和工作流的 git diff --check 通过。全范围检查找到一处文档末尾空行。[验证记录:103](../../verification/2026-11-15-system-monitor-compact-execution.md#L103)
- 完整本地验证在打包阶段前取消，以保留已有本地 App 包。最终候选在隔离目录跑 bash scripts/verify-local.sh full，并验收菜单栏/Dock 图标一致性及 Wi-Fi 对齐。另分别在 Ventura 和当前 macOS 验证实际安装升级，覆盖 Intel 和 Apple Silicon 的能力差异、IOReport 私有库加载和降级。正式签名、公证、Universal DMG、真实 Helper 及性能实测均待验收。[verify-local.sh:102](../../../scripts/verify-local.sh#L102) · [Package.swift:46](../../../Package.swift#L46)
