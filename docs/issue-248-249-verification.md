# #248 / #249 蓝牙与配件电量验证记录

**当前补修状态：** 四项软件补修与交叉审查完成，已合并进 `main`（`fcce4213`）并推送；合并后最终树 `8db0045b` 的 `bash scripts/verify-local.sh full` 通过（exit 0，XCTest 2469 项、71 跳过，Swift Testing 907 项，零失败）。真机验收 **NOT RUN**，按用户决定改由真实设备使用验证，不代表 #248/#249 已整体验收或发布，issue 仍保持打开。下文前半保留原分支历史。

## 原分支范围与基线（历史）

- 独立分支：`fix/248-249-bluetooth-battery`。
- 分支基线及 2026-11-04 首次、再次 fetch 的 `origin/main`：`053fb3c29b0b1c33c0c48a8c7bf04038f2fd1ab4`。
- #249：`02c0dab9`；#248：`dc24edea`。
- 审查后 #249 截断诊断：`76df99a2`，资源边界说明：`ae30d021`。计数在 cap 前后同时汇总，显示被省略的组及 Watch 数。
- 测试基线修正：`c8cc310c`。#247 的 `b221d721` 已将权限动作文案改为“Wi-Fi 网络”，旧断言仍为“Wi-Fi 名称”；单独同步精确断言，保留语言验证。
- 该历史分支后来随补修分支一并合入 `main`（`fcce4213`）；issue 仍不关闭，等发布版本统一核对。

## 实现及取舍

#248 从 pmset 解析 Accessory Identifier，按 identifier 分组。映射歧义检查包含已断连的同型号已配对设备，输出仅供当前连接设备。异步回调使用当前设备列表。多个 identifier 无法明确归属时整轮不做回退；identifier 缺失也不做回退。因此某个无关/无法归属的 accessory 可能同时让另一合法 accessory 失去补充电量，这是保守策略的代价。

附近 BLE 读数有效期为 180 秒。失败冷却仍为 60/300 秒、连续失败三次后暂停自动重试。缓存可能在冷却结束前到期，行在有新成功读数前消失；不为保持旧电量可见而加快失败重试。

#249 静态链路与契约测试确认，companion Watch 继承 iPhone 的 USB/network transport，正常输出不会仅因现有 transport 过滤被排除；这不能据此确定用户真机缺失 Watch 的根因。修复 USB 只有 phone metadata 时不再提前停止、可继续已有 network route；候选按 phone-ID 稳定排序并整组保留，避免任务完成顺序影响保留结果。常规预算 8，第一组可为 9（1 phone + 8 Watch）。decodeWatchCandidates 是 phone-read 的旧解析，发现链走 decodeDiscovery 的 inline candidates。

发现工作仍受原需求/取消边界控制。每周期最多探测 8 部手机的既有 USB/network 路由；无 Watch 时最多 16 次 --discover-device，另有 1 次 --list，共最多 17 个 helper 子进程，各发现路由最多 5 秒。诊断不记设备标识符；controller 在计数变化时记录，reader 路由 debug 为逐周期有界输出。发现周期更长可能延长已有候选清空后的空白窗口。

## 原分支本地验证（历史）

环境：macOS 27.2 (26B123)，Xcode 27.0 (27A266a)。

- PASS：combined focused / quick，107 个 Swift Testing 测试（8 suites），及所选 XCTest。
- PASS：`bash scripts/test-mobile-battery-helper.sh` 原生 helper 契约测试（注入 API，不是真机）。
- 首轮 full：FAIL，唯一 XCTest 失败为上述旧 Wi-Fi 文案断言；855 个 Swift Testing 测试通过。后续构建/契约未到达。
- `c8cc310c` 修正后 `PresentationTextMapperTests`：PASS。
- 第二轮 full：完整 Swift 测试通过；因期间新增候选截断诊断，主动停止此轮，不作为最终完整证据。
- 最终 full：**PASS**，exit 0，冻结且干净的提交 `81ee56c17a2eb336a103eadefea7cec572d31f99`。XCTest 2436 项、0 失败、67 项跳过；Swift Testing 857 项（122 suites）通过。Release、非 Universal app bundle、平台/SDK、MobileBattery/特权 Helper bundle，以及全部原生检查和离线发布模拟通过。可见 UI 默认跳过，未启用 opt-in。
- 最终日志：`/tmp/status-trio-248-249-full-final.log`；本地验证日志副本为 `.build/local-verification/log.txt`。这不是硬件、运行时、签名、公证或发布通过。

## 真机验收与证据边界

以下均为 **NOT RUN**，不能用 mocks 或本机键鼠 pmset 样本替代：

1. 两副同型号 AirPods 各自连接/断连/离场，确认不串台、不留错误回退电量。
2. 真 AirPods 的 L/R/Case 完整 `pmset -g accps -xml`：确认各 part 的 Accessory Identifier 是否共享。现有 fixture 中出现 Group Identifier，但没有足够证据证明其真实语义；不得由此推断应该改用该键。
3. 缺失 Accessory Identifier 的真实配件回退行为。
4. 已信任且可达的 iPhone + 配对 Watch，验证 USB、预先配置的 Wi-Fi 同步、首读及断开恢复。
5. 当前 macOS 应用真机行为与 macOS 13/Ventura 运行验证。

**待验收风险：** 若同一套 AirPods 的不同 part 使用不同 Accessory Identifier，当前保守逻辑会放弃整套的回退电量。该风险需要真实多 part 样本裁决；目前没有证据可安全改成 Group Identifier。

未启动/操作应用 UI，未修改系统信任、蓝牙配对或 Wi-Fi 同步设置，未抢前台。未进行签名、公证、Universal/DMG、发布验证。

## 2026-11-04 独立审查后的补修（新 worktree）

- 用户要求新增分支/worktree：`fix-248-249-review-followup`，从旧分支 `3ff11ffbad0f1b0aeb27f362c72897ee7ac5907d` 开始；原 worktree 与未提交计划保留不动。
- 计划：`docs/superpowers/plans/2026-11-04-accessory-battery-review-followup.md`；已配置 `group/smart-auto` 的子任务实施与交叉审查，主代理做最终整合验证。新任务的本地 full 结果须单列，不能沿用上文旧 SHA 的 PASS。
- 合并前的 `origin/main`：`ddd728eeb50e992721158dfc64642841edf01b40`。合并基 `053fb3c2` 之后主线只在 `PanelPresentationTextTests.swift` 与补修分支重叠，两边是同一处「Wi-Fi 网络」文案修正，`git merge --no-ff` 无冲突。
- 新 worktree 基线 focused：PASS，exit 0，21 XCTest + 60 Swift Testing（3 suites）；日志 `/tmp/status-trio-followup-baseline.log`。
- Task 1：`cc53657c`。脚本 executor 等到传入的 USB timeout 用尽后抛错的回归先红后绿（不是真机 USB），27 Swift Testing 通过；独立审查 Spec/Quality Approved。Watch 5 秒总执行预算保留，按剩余路由均分；双路由首路最多约 2.5 秒，最后一路拿当时剩余预算。每路前检查取消。慢 USB 的真机影响仍待验证，不保证进程清理后的墙钟严格 5 秒。
- Task 2：`15f03ca3`。Reader → Controller 的全失败/部分失败/坏 JSON/原生错误分类先红后绿，8 XCTest + 47 Swift Testing 通过；协议兼容回归 31 XCTest + 10 catalog tests 通过。独立审查 Spec/Quality Approved。
- Task 3：`63f991f1`。真实 Reader 的 summary sink 回归先红后绿（33 Swift Testing 通过）：USB `[p]` / network `[p,w]` 计 2 个 identity；多 phone 重复、首组 9、预算丢弃的计数均覆盖。只对统计视图去重，实际 cap/返回候选及路由诊断不变。独立审查 Spec/Quality Approved。
- Task 4：`532e75d1`。组内 records 一致性及交叉歧义、connection generation/设备快照 generation 保护先红后绿。聚焦 19 XCTest + 24 Swift Testing 通过；蓝牙扩大回归 414 XCTest（2 跳过）+ 210 Swift Testing 通过，均 0 失败。独立审查 Spec/Quality Approved。每次连接事件即清电量，warm 请求等到当前 generation 的新设备快照；旧 profiler/accessory 晚回调均不能恢复旧电量。事件缺少地址，因此可能短暂清掉其他设备电量；仍合并 I/O，不增加 profiler 并发或轮询。
- 最终整合/full：**PASS**，命令 `bash scripts/verify-local.sh full`，exit **0**；干净冻结提交 `5ca8c0801086af497b3fb8db7063e5ae880de410`（源代码与 `532e75d1` 相同，之后仅补文档）。Xcode 27.0 / Swift 6.4 / SDK 27.0；XCTest **2442 项、67 跳过、0 失败**；Swift Testing **872 项 / 122 suites 通过**。Release、非 Universal Ad-hoc app bundle、SDK/平台与两个 Helper bundle 契约、全部原生检查及离线发布流程模拟通过。可见 UI 默认跳过，未启用 opt-in。
- 本轮日志：`/tmp/status-trio-248-249-followup-full.log`，保留副本 `.build/local-verification/248-249-followup-full.log`（与后续 docs 检查日志分开）。文档收尾提交不改变已验证源代码；不把此验证称为 Developer ID 签名、公证、Universal、DMG、发布或 macOS 13 运行时通过。
- 最终全分支复核：`3ff11ffb..5ca8c080`，14 个路径；逐任务 Spec/Quality 全部 Approved。`group/smart-auto` 两位成员复核安全/输入假设/资源滥用、架构/组合/合法操作级联，未发现本轮新增阻塞问题；主代理追过成功 snapshot 对早前 USB failure 的显示优先级。审查与行为测试不能替代硬件验收。
- 已知既有窗口：deactivate 不清空设备列表，也不推进连接 generation；重新激活时，在新 profiler 快照到来前可能短暂沿用旧设备列表。该路径未被此次连接事件补修覆盖，未作为已修成果；重新打开与真机离场行为仍需单独验收。
- 13:59（UTC+8）被动执行 `pmset -g accps -xml` 只看到两条 Mouse 类 accessory，无 part；这仅说明当时没有可用的 AirPods 多 part 样本。只留类别/字段是否存在的匿名记录，不留真实 identifier，不构成 AirPods 验收。
- 15:05（UTC+8）执行本轮冻结提交打包 helper 的 `--list`：exit 0、schemaVersion 1、**phones = 0**，stderr 为空。仅作被动枚举，未保留设备名称或标识符；没有可用于本轮 Watch 读取验收的手机路由。
- 两套 AirPods/多 part identifier 语义/列表外旧读数、已信任 iPhone+Watch 的 USB/Wi-Fi/首读/重连、Ventura 与当前 macOS 应用真机验收：**NOT RUN**。用户确认这些项目只能由实际使用者在真实设备上尝试，因此以合并后由用户验证代替本机硬件验收。不自动改用 Group Identifier，不配置系统信任或配对，不启动前台 UI。
- 合并：`fcce4213`（`--no-ff`，分支 `fix-248-249-review-followup` 入 `main`），同日主线另有 #262 合并 `8db0045b`。合并后最终树 `8db0045b` 的 `bash scripts/verify-local.sh full` **PASS，exit 0**：XCTest **2469 项、71 跳过、0 失败**、Swift Testing **907 项 / 127 suites**；日志 `/tmp/status-trio-main-merge-full.log`。已推送到 `origin/main`。issue 仍未关闭，等发布版本统一核对。
