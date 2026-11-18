# 系统监控详情页高占用应用 Top 5 验证记录

**状态：** 功能实现完成，等待用户验收。分支 `feat/system-monitor-detail-pages`，最终代码树 `faf95767b533208bb782a6f79a088645a3e5a9ed`；未合并、未推送。

## 范围

CPU、GPU、内存、网络详情页新增按应用合并后的高占用前 5 名。网络行同时显示实时下载、上传速度。磁盘页不新增榜单。实现沿用 Stats 的 `ps` / `top` / `nettop` / IOAccelerator 客户端累计时间方案，统一在榜单层按应用合并；`responsibility_get_pid_responsible_for_pid` 只作为可选归属信号，失败进程保留独立行。

新增代码集中在 `Sources/StatusTrioCore/Monitoring/TopApp*.swift`、`ProcessAppResolver.swift`、`TopAppsService.swift`，UI 为 `Sources/StatusTrioCore/UI/TopAppsListView.swift`。面板只在当前可见的 CPU/GPU/内存/网络详情页登记需求；关闭面板、切页、隐藏硬件模块、睡眠或停止都会结束需求并清理累计基线。

## 验证环境

- Mac15,9 / Apple M3 Max / arm64。
- macOS 27.3（26C5047e）。
- Xcode 27.0（27A266a），Swift 6.4，macOS SDK 27.0。

## 自动化验证

- PASS：`bash scripts/test.sh 'TopApp'`。覆盖应用合并与排序、CPU/内存解析、网络累计字节与真实间隔、GPU 客户端时间差、服务会话切换/睡眠/停止、面板可见性、展示格式与离屏卡片渲染；共 38 个榜单相关测试（不含默认跳过的快照）。
- PASS：`bash scripts/verify-local.sh full`，`exit 0`，head `faf95767b533208bb782a6f79a088645a3e5a9ed`。XCTest 3655 项（103 项跳过，0 失败），Swift Testing 1186 项（171 suites，0 失败）。Release build、非 Universal 本地 app bundle 与项目 native 契约全部通过。
- PASS（可选离屏快照）：`STATUS_TRIO_TOP_APPS_SNAPSHOT=1 ... bash scripts/test.sh TopAppsSnapshotTests` 生成 CPU/网络卡片 light/dark PNG；已人工检查 5 行、长名称截断、网络双列与图标/齿轮占位。快照骨架默认跳过，不进入普通测试。

## 真实命令与真实数据冒烟（2026-11-18）

- CPU：`ps -Aceo pid,pcpu,comm -r` 读取 1159 个进程；应用合并后前五示例：`DeepSeek Harness=80.0%`（多个 Helper 合并）、`BlueStacks=51.0%`、`Microsoft Edge=34.5%`、`syspolicyd=31.5%`、`微信=13.8%`。出现大于 100% 的单应用值时展示层保留一位小数、不截断。
- 内存：`top -l 1 -o mem -stats pid,command,mem` 读取 1159 个进程；前五示例：`BlueStacks≈11.9 GB`、`DeepSeek Harness≈3.3 GB`、`Microsoft Edge≈3.2 GB`、`豆包≈2.6 GB`、`微信≈2.0 GB`。
- 网络：两次 `nettop -P -L 1 -n -J bytes_in,bytes_out` 间隔约 1 秒；60+ 个进程计数产生应用行，示例为 `DeepSeek Harness↓2689↑2689`、`ChatGPT↓352↑223`、`BlueStacks↓191↑276` B/s。本机回环流量会成对计入两个进程，属于 nettop 连接口径的正常现象。
- GPU：IOAccelerator 真实遍历读取到 29 个客户端；不支持的架构或缺少 `AppUsage` 字段时返回 `unsupported`，不会用 0% 冒充。

### 采样开销与周期

- `top` 单次约 0.84 秒（user 0.08 / sys 0.75），`ps` 约 0.04 秒，`nettop` 约 0.02 秒，GPU IOKit 遍历约 0.003 秒。
- 因此 CPU / GPU / 网络保持 1 秒周期，内存榜单改为 3 秒周期；打开内存详情页时约 28% 单核占用，而不是接近持续 85%。该调整已写入设计和计划。

## 未完成或未验证

- **Live UI 操作：BLOCKED。** 本机 `cua.getCapabilities()` 返回 `sessionLocked: true`；按后台 UI 测试规则停止 GUI 输入，未对真实窗口进行点击或截图。离屏 `ImageRenderer` 已覆盖卡片布局与状态。
- **Debug 测试实例启动：BLOCKED。** `bash scripts/launch-computer-use.sh --panel` 发现已有非 launcher 的 PID 45545 正在运行 `dist/StatusTrio.app`；按 worktree 安全规则未终止他人实例，`--reuse` 也因缺少 launcher 身份被拒绝。未做真实应用内路由/滚动验收。
- macOS 13 运行时：NOT RUN。当前仅完成 macOS 27.3 本机验证。
- Intel / x86_64 运行时：NOT RUN。GPU 榜单在非 arm64 上设计为 `unsupported`；Universal 正式包未在本轮构建。
- 签名、公证、DMG、Universal packaging、正式 release CI：NOT RUN（本地 full 明确不覆盖）。
- 共享内存重复计数、VPN/代理/回环造成网络口径差异、顶部整机指标与应用合计不可严格对账，仍按设计保留为已知口径限制。

## 结论

功能代码、单元/集成测试与离屏视觉检查完成，最终代码树本地 full 通过。等待用户真机验收后再合并、推送或关闭 issue；分支与 worktree 保持保留。
