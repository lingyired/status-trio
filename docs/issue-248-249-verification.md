# #248 / #249 蓝牙与配件电量验证记录

## 范围与基线

- 独立分支：`fix/248-249-bluetooth-battery`。
- 分支基线及 2026-11-04 首次、再次 fetch 的 `origin/main`：`053fb3c29b0b1c33c0c48a8c7bf04038f2fd1ab4`。
- #249：`02c0dab9`；#248：`dc24edea`。
- 审查后 #249 截断诊断：`76df99a2`，资源边界说明：`ae30d021`。计数在 cap 前后同时汇总，显示被省略的组及 Watch 数。
- 测试基线修正：`c8cc310c`。#247 的 `b221d721` 已将权限动作文案改为“Wi-Fi 网络”，旧断言仍为“Wi-Fi 名称”；单独同步精确断言，保留语言验证。
- 不合并、不推送、不关闭 issue，留待统一验收。

## 实现及取舍

#248 从 pmset 解析 Accessory Identifier，按 identifier 分组。映射歧义检查包含已断连的同型号已配对设备，输出仅供当前连接设备。异步回调使用当前设备列表。多个 identifier 无法明确归属时整轮不做回退；identifier 缺失也不做回退。因此某个无关/无法归属的 accessory 可能同时让另一合法 accessory 失去补充电量，这是保守策略的代价。

附近 BLE 读数有效期为 180 秒。失败冷却仍为 60/300 秒、连续失败三次后暂停自动重试。缓存可能在冷却结束前到期，行在有新成功读数前消失；不为保持旧电量可见而加快失败重试。

#249 验证了 Watch 继承 iPhone 的 USB/network transport，现有 transport 过滤不是根因。修复 USB 只有 phone metadata 时不再提前停止、可继续已有 network route；候选按 phone-ID 稳定排序并整组保留，避免任务完成顺序影响保留结果。常规预算 8，第一组可为 9（1 phone + 8 Watch）。decodeWatchCandidates 是 phone-read 的旧解析，发现链走 decodeDiscovery 的 inline candidates。

发现工作仍受原需求/取消边界控制。每周期最多探测 8 部手机的既有 USB/network 路由；无 Watch 时最多 16 次 --discover-device，另有 1 次 --list，共最多 17 个 helper 子进程，各发现路由最多 5 秒。诊断不记设备标识符；controller 在计数变化时记录，reader 路由 debug 为逐周期有界输出。发现周期更长可能延长已有候选清空后的空白窗口。

## 本地验证

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
