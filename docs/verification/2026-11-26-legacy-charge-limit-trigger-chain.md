# 低版本（macOS 13–15）充电上限「需要批准电源 Helper」误报 — 根因与修复记录

记录日期：2026-11-26
工作区：`.agents/worktrees/fix/207-charge-limit-compat`
分支：`fix/207-charge-limit-compat`，HEAD `85d7a9b0`（比 `origin/main` 领先 61 提交，远端同名分支已同步，尚无 PR）。

## TL;DR

- **现象**：macOS 15、公证 DMG 安装、Helper 已在「登录项与扩展」中允许、低电量模式正常可用；但 设置 → 电池 →「充电上限限制」组一直显示**「需要批准电源 Helper」**，「管理充电上限」开关灰置不可用。
- **根因（已用真实运行日志确认）**：legacy 充电上限的 XPC 回复胶囊 `SMLegacyChargeLimitProbeReply` / `SMLegacyChargeLimitWriteReply` 在 `init?(coder:)` 里用**不安全的 `decodeObject(forKey:)`** 解嵌套 `String`；NSXPC 安全解码器对回复只放行顶层类，嵌套 `NSString` 不在允许集 → **解码失败、回复被丢弃** → `probe()` 失败 → 控制器把任意 probe 错误折叠成 `.unavailable(.helperUnavailable)` → 界面误报「需要批准」。
- **修复**：`Sources/PowerHelperProtocol/LegacyChargeLimitXPC.swift` 改用带显式类型的安全解码 `decodeObject(of: NSString.self, forKey:)`。`PowerHelperProtocol` 目标编译 **Build complete**。
- **此前那版「批准后重新探测」修复不是根因**：probe 每次都因解码失败而失败，重探多少次都没用。真正的修复是本记录 §3。
- **待办**：用 Xcode 27 重新构建 **app + helper 同源** 的新包，装到 macOS 15 真机验证（组应变为「未启用」、开「管理充电上限」能限充）。端到端真机验证 **NOT RUN**。

## 1. 现象（用户实测）

- 环境：`/Applications/Status Trio.app`（公证包，pid 953），`StatusTrioPowerHelper`（pid 1070），macOS 15。
- 截图信息：设置 → 电池 的低版本组「当前电池优化状态 = **需要批准电源 Helper**」，「管理充电上限」开关灰置；而「系统设置 → 通用 → 登录项与扩展」里 Status Trio 的后台项**已打开**（1 个项目，影响所有用户），且低电量模式可用。
- 结论：Helper 本身工作正常，问题在 legacy 充电上限的 XPC 探测路径。

## 2. 根因（真实运行日志证据）

打开 设置→电池 时的统一日志（`log show`）直接给出：

```
StatusTrio[953] <NSXPCConnection: ... com.lingsmbp.StatusTrio.PowerHelper>:
Exception caught during decoding of reply to message 'probeLegacyChargeLimitWithReply:',
dropping incoming message and calling failure block.
Allowed classes are: 'SMLegacyChargeLimitProbeReply'
  … NSXPCDecoder __decodeXPCObject:… → _decodeReplyFromXPCObject:forSelector: …
  … _NSXPCSerializationDecodeInvocationArgumentArray … → _validateAllowedClass:forKey: …
  … SMLegacyChargeLimitProbeReply.init?(coder:) …
```

**机理**：`SMLegacyChargeLimitProbeReply.init?(coder:)` 用 `coder.decodeObject(forKey:)` 解 `architectureName` / `osBandName` / `errorDescription` 等 `String`。这是“不安全”的解码入口，依赖解码器为**该 key** 预先放行的允许类；而 NSXPC 对回复参数只放行了顶层类 `SMLegacyChargeLimitProbeReply`（`NSString` 不在允许集），于是 `_validateAllowedClass` 抛异常，整个回复被丢弃，客户端 `probe()` 的失败 block 触发 → 抛错。

**为何低电量模式正常**：低电量/高功率的 XPC 回复是原始 `Bool`/`String`，不经过自定义 `NSSecureCoding` 胶囊，没有嵌套对象解码问题。

**为何之前测试没抓到**：所有单测都注入 `FakeLegacyClient`（`Tests/.../LegacyChargeLimitControllerTests.swift`），真实的 `XPCPrivilegedLegacyChargeClient` 编解码从未被执行；`verify-local.sh full` 的 Swift 套件也不覆盖真实 NSXPC 解码。属真实业务路径的覆盖盲区。

**为何界面误导**：`LegacyChargeLimitController.refresh()` 的 catch 把**任何** probe 错误一律映射成 `.unavailable(.helperUnavailable)`，而视图 `needsHelperApproval = (availability == .unavailable(.helperUnavailable))` → 即使 Helper 正常，只要 XPC 探测失败就显示「需要批准电源 Helper」。

## 3. 修复

文件：`Sources/PowerHelperProtocol/LegacyChargeLimitXPC.swift`

- `SMLegacyChargeLimitProbeReply.init?(coder:)`：`architectureName` / `osBandName` / `errorDescription` 由 `decodeObject(forKey:)` 改为 `decodeObject(of: NSString.self, forKey:)`。
- `SMLegacyChargeLimitWriteReply.init?(coder:)`：`errorDescription` 同样改为 `decodeObject(of: NSString.self, forKey:)`（`observedLimit` 原本已用 `decodeObject(of: NSNumber.self, …)`，正确）。

说明：只改解码侧（app 解 daemon 的回复），键名与 `encode(with:)` 不变，编解码格式向后兼容，daemon 无需改动；app 与 helper 引用同一 `PowerHelperProtocol` 源码，一起重建即可。

编译校验（本机，Xcode 27 / Swift 6.4 工具链）：
- `swift build --target PowerHelperProtocol` → **Build complete（0.65s）**，无 error。
- 整包 `swift build` 本机**无法完成**：失败点在 `StatusTrioCore` UI（`PanelLevelSlider.swift` 的 actor 隔离诊断 + 用 CLT 15.5 SDK 的本地化 emit），与本改动无关，属本机“CLT SDK + Xcode 工具链 + 许可未接受”混用的环境问题；应在正常 Xcode 27 环境 / CI 构建。

## 4. 验证状态

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 根因确认（真实运行日志） | **PASS** | §2 日志直接指认 `probeLegacyChargeLimit` 回复解码失败 |
| 修复编译（`PowerHelperProtocol`） | **PASS** | `swift build --target PowerHelperProtocol` Build complete |
| 整包构建 / Swift 测试 | **BLOCKED（本机）** | 本机为 CLT Swift 6.1.2 + Xcode 27 许可未接受，无法跑 XCTest/整包；见 §7 |
| 端到端真机验证（macOS 15） | **NOT RUN** | 需重新出包（app+helper 同源）后验证，见 §5 |
| 真实 SMC 写入/读回、睡眠策略、自愈等 | **NOT RUN** | 见 handoff §9 |

## 5. 下一步

1. 用 Xcode 27 重新构建 **app + helper 同源** 的新测试包（`build-candidate.yml` 或本地 `build-worktree.sh`，app 与 helper 必须同源重建）。
2. 安装到 macOS 15，打开 设置 → 电池：
   - 预期：组由「需要批准电源 Helper」变为「未启用」，「管理充电上限」开关可用；打开后滑杆到 80–95% 应真正限充。
   - 复跑日志应**不再**出现 `Exception caught during decoding of reply … probeLegacyChargeLimit`。
3. 通过后按 handoff §5/§7 用同一候选发布或合并；验收前不要合入 main。

## 6. 变更清单（当前未提交）

| 文件 | 状态 | 内容 |
| --- | --- | --- |
| `Sources/PowerHelperProtocol/LegacyChargeLimitXPC.swift` | M | **根因修复**：回复胶囊改用 `decodeObject(of: NSString.self, forKey:)` |
| `Tests/StatusTrioCoreTests/LegacyChargeLimitControllerTests.swift` | M | 新增回归 `testRefreshAvailabilityRecoversAfterTheHelperIsApproved`（L272） |
| `docs/verification/2026-11-26-legacy-charge-limit-trigger-chain.md` | 新增 | 本记录 |

## 7. 背景：最初的“批准后重探”假设（非根因）

在拿到运行日志前，曾判断缺口是「批准 Helper 后组不刷新」。分支上确有两个相关提交：
- `55d7ea89`：授权按钮改为真正打开「登录项与扩展」。
- `2796ff8c`：在 `LegacyChargeLimitSettingsView` 里，`helper.isSharedHelperReady` 变 true、`helper.status` 变化、App 激活（`didBecomeActiveNotification`）时都 `controller.refresh()`。

这些对“批准返回后刷新”是合理加固，但**不是本问题的根因**：只要 XPC 回复解码失败，`probe()` 每次都会失败，重探多少次都仍显示「需要批准」。真正的修复见 §3。

相关代码位置（供参考）：
- `LegacyChargeLimitSettingsView.swift`：L23 `@ObservedObject helper`；L32–L34 `.task { await controller.refreshAvailability() }`；L155–L164 `.onChange(isSharedHelperReady/status)` + `.onReceive(didBecomeActiveNotification)`；L211–L213 `needsHelperApproval`。
- `LegacyChargeLimitController.swift`：L225–L229 `refreshAvailability()`→`refresh()`；L243–L271 `refresh()`（L260 `client.probe()`，catch→`.helperUnavailable`）。
- `LegacyChargeLimitClient.swift`（真实客户端）：L76–L91 `probe()`；L177–L195 `currentConnection()`；L197–L227 `perform()`。
- `PrivilegedHelperManager.swift`：`isSharedHelperReady` L246、`refreshForApprovalSettings` L352、`refreshAfterActivation` L367、`openLoginItemsSettings` L735。
- `LowPowerModeControlSynchronizer.swift` L34–L43：激活 → `refreshAfterActivation()`。

## 8. 本机工具链限制（为何这里跑不了 Swift 测试/整包）

- `xcode-select -p` → `/Library/Developer/CommandLineTools`；`swift --version` → **Swift 6.1.2**（CLT）。该工具链把分支 helper 的 Sendable 诊断当 **error**（`PowerModeService.swift:504`、`LegacyChargeLimitService.swift:78`），而 Xcode 27 / Swift 6.4 下只是 **warning**（`swift build --target StatusTrioPowerHelper` 成功）——属工具链诊断差异。
- `XCTest.framework` 仅存在于 Xcode：`…/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework`；CLT 没有。
- Xcode 27（`/Volumes/Macintosh HD/Applications/Xcode.app`，27A266a）**许可协议未接受**：`DEVELOPER_DIR=… xcrun --sdk macosx --show-sdk-path` → `You have not agreed to the Xcode license agreements`；`sudo -n true` → 需要密码，故无法在本机自动接受。
- 结论：本机只能做 `PowerHelperProtocol` 等不依赖 XCTest/Xcode SDK 的目标编译；聚焦测试、`verify-local.sh full` 与整包构建需要在已接受许可的 Xcode 27 环境或 CI 执行。

## 9. 明确未验证（不得声称通过）

- 真实 SMC 写入/读回（Intel `BCLM`、Apple Silicon `CH0B/CH0C/CHTE`）。
- 到点停充/恢复、高于上限表现、4% 迟滞。
- 两种睡眠策略实际效果、唤醒/插电自愈。
- 退出还原、启动重设、开机自启后自动恢复。
- 与系统「优化电池充电」的实际冲突与提示。
- 真机端到端：批准 Helper 后组状态是否正确、限充是否生效（§5 NOT RUN）。

## 10. CI 构建结果（2026-11-26，本机代触发，fast）

- 运行：`build-candidate.yml` **#45785265404**（`release_mode=fast`，`--ref main`，`candidate_sha=ca7e3ee0a5c6535236b151729f589e9907b1600c`）
- 结果：`prepare` success、`package` success；`verify`/`native` 按 fast 跳过。
- 版本/构建：`1.10.6 (77)`；`publishable=false`（非 main，属于测试候选，不会创建 Release/tag/appcast）。
- 签名/公证：`signing.kind=developer_id`；`notarization.status=accepted_and_stapled`。
- 工具链：Xcode 27.0（27A266a）/ Swift 6.4 / SDK 27，runner `xcode-27`。
- 产物（已下载到本机）：`~/Downloads/StatusTrio-candidate-1.10.6-b77/`
  - `StatusTrio-1.10.6.dmg`（sha256 `ac815bfa…ac041`）
  - `StatusTrio-1.10.6.zip`（sha256 `63465910…2c2f`）
  - `release-manifest.json`（含上述证据；DMG/ZIP 的 sha256 实测与清单一致）
- 下一步：装到 macOS 15 真机，按 §5 验证（组不再误报“需要批准”，开“管理充电上限”能限充）。真机端到端仍为 **NOT RUN**。

## 11. 真机复测：解码已修好，但 macOS 15 上 toggle 仍禁用（平台限制，非代码 bug）

在本机（**macOS 15.8.3 / 24H241 / Apple M3 Max / Mac15,9 / arm64**）安装 build 77 后：
- 「充电上限限制」组**不再显示“需要批准电源 Helper”**，改为「当前电池优化状态 = 未启用」——**§10 的 XPC 解码修复生效**。
- 但「管理充电上限」开关**灰置打不开**：`controller.isAvailable == availability.isAvailable == false`，即 `availability = .unavailable(.noSupportedKeys)`（statusText 仍走 `.notEnabled` 所以显示“未启用”）。

**用与 daemon 相同的 AppleSMC 私有 ABI 在本机实测（非 root）**：

| 键 | INFO result | 类型 / 值 |
| --- | --- | --- |
| `CHBI` | 0（存在） | ui32，值 `0` |
| `CHSC` | 0（存在） | ui8，值 `0` |
| `CHIE` | 0（存在） | hex_，值 `0` |
| `CH0J` | 0（存在） | ui8，值 `0` |
| `BCLM` / `CH0B` / `CH0C` / `CHTE` / `CHWA` | **132（key not found）** | — |
| `CHLS` | kern `0xe00002c1`（无权限） | — |

当前实现只认 `BCLM/CH0B/CH0C/CHTE`（`LegacyChargeSMCKeys.writeAllowlist`），这些键在本机**全部不存在** → daemon `validRead` 全 nil → `probe.siliconPairPresent/siliconCHTEPresent/intelBCLMPresent` 全 false → `.noSupportedKeys` → 开关被 `!isAvailable` 禁用。

**平台原因**：macOS 15 起 Apple 对 SMC 充电控制键实施私有 entitlement 强制（`com.apple.private.applesmc.user-access`），第三方签名 App/Helper 无法获得；`bclm` 项目明确记录 “BCLM does not work on macOS >= 15.0 … cannot be circumvented without disabling SIP”（zackelia/bclm #49）；`CHLS` 返回“无权限”也印证了按键级 entitlement 门禁。代码里 `LegacyOSBand.fifteen` 的注释本就写着 “distinct SMC-capability band, possibly entitlement-gated”。

**结论 / 建议**：
- 这不是本应用代码可修复的 bug；macOS 15（至少 15.8.3 M3 Max）上第三方 SMC 限充被系统权限封死，禁用 SIP 也不适合发行版。
- 建议把「实际限充」范围收敛为 **macOS 13–14**；macOS 15 上**隐藏该组**，或明确提示“系统限制，暂不可用”，不要留一个灰掉的 toggle 误导用户；macOS 26.4+ 走系统原生。
- 解码修复（§10）仍有效且必要（否则连“未启用/状态”都读不出来）；后续可选：为 `SMLegacyChargeLimit*Reply` 加 `NSSecureCoding` 往返单测。

## 12. 开源项目调研：macOS 15.8 改用固件限充键 `bfD0/bfE0/bfF0`

调研结论：**macOS 15.7.1 / 15.8 起 Apple 换了固件限充机制，旧键 `CH0B/CH0C/CHTE/CHWA` 被移除，但有新的固件限充键可用，且不需要私有 entitlement。** 主要开源项目都改用了它：

- `zackelia/bclm` #49：macOS 15.0 beta 起 `CHWA`（及 `CH0B/CH0C`）返回 `keyNotFound`，bclm 在 15+ 失效。
- `charlie0129/batt` #34：SMC 充电/限流键受私有 entitlement 保护——`com.apple.private.applesmc.user-access`（`CHLS` 等按键）、`com.apple.private.iokit.soc-limit`（SOC 限制）；需 SIP+AMFI 关闭并签名私有 entitlement 才能用。
- `actuallymentor/battery` #482：15.7.9→15.8.1 后 `CH0B/CH0C/CHTE` 变 “no data”；**PR #485 改用固件限充键后恢复可用**（macOS 15.8 也可）。
- `AppHouseKitchen/AlDente` #1808：新固件（如 `mBoot-20457.1.28`）下旧键 `CH0B/CH0C/CHTE/CH0I` 全 absent；发现**新固件限充键**（全部可写，`attr 0xd4`）：
  - `bfD0`  ui32，上限百分比（字节小端：`50 00 00 00` = 80）
  - `bfE0`  ui32，下限/回滞百分比（如 `4e 00 00 00` = 78）
  - `bfF0`  ui8，开关（`00` 关闭 / `02` 开启）
  - 由固件按上下限自行回滞控制，无需应用反复写；AlDente 1.39 即为此重写。

**在用户本机（macOS 15.8.3 / M3 Max）只读实测**：`bfD0`、`bfE0`、`bfF0` 均存在（`attr 0xd4`，当前值 `00/00/00` 即未启用）；`CHTE/CH0B/CH0C/CHWA` 均 `keyNotFound`。→ **本机走固件限充键这条路是可行的**。

**对本项目的意义 / 建议实现**：新增“固件限充后端”：
1. `SMCPrivateAPI.c`：把 `bfD0/bfE0/bfF0` 加入写允许名单与值校验。
2. `LegacyChargeLimitService`：探测到三键存在即视为可用；`setLimit(L)` 写 `bfE0=L-2`、`bfD0=L`、`bfF0=02`（记录原值用于还原）；`disable` 写 `bfF0=00`；`chargeToFullOnce/cancel` 用 `bfF0` 切换；固件后端下**跳过**应用侧反应式抑制（避免与固件打架）。
3. `LegacyChargeLimitProbeFacts`/`SMLegacyChargeLimitProbeReply` 增加 `firmwareLimitPresent`；app 侧 `LegacyChargeBackend` 增 `.firmwareLimit`，`resolve` 命中即 `.available(.firmwareLimit)`。
4. 风险：写 SMC 固件键属高风险改动，需在真机验证；做法对齐 AlDente 1.39 / battery PR #485 的成熟流程（写前记录原值、写后读回、退出还原）。

## 13. 实现：固件限充后端（bfD0/bfE0/bfF0）

提交 `c16a29eb`（分支 `fix/207-charge-limit-compat`）实现：

- `SMCPrivateAPI.c`：写允许名单与校验加入 `bfD0/bfE0`（ui32，低字节百分比，校验 `bytes[1..3]==0 && ≤100`）与 `bfF0`（ui8，0/2）。仍为显式白名单，不开放任意键写入。
- `LegacyChargeLimitService`：
  - `LegacyChargeSMCKeys` 增 `bfD0/bfE0/bfF0`（宽度/allowlist/`isValidValue`）。
  - `probeLegacyChargeLimit` 增 `firmwareLimitPresent`（三键均存在）。
  - `discoverOriginal()` 优先探测固件键；journal 后端由键集推导（`bfD0`→`.firmwareLimit`）。
  - `desiredRaw()` 固件分支：`bfD0=上限`、`bfE0=上限-2`、`bfF0=2`（`full`/100% 时 `bfF0=0` 解除）；Intel/旧 Silicon 路径不变。
  - `loadOwnedJournal` 接受 `{bfD0,bfE0,bfF0}` 键集；`disable` 还原原值（`bfF0=0`）；`prepareForSleep` 对非 `.silicon` 为 no-op。
- `PowerHelperProtocol` 回复胶囊 `SMLegacyChargeLimitProbeReply` 增 `firmwareLimitPresent`（init/encode/decode）。
- app 侧：`LegacyChargeLimitProbeFacts` 增 `firmwareLimitPresent`（并入 `hasAnySupportedKey`）；`LegacyChargeLimitClient` 转发；`resolve()` 命中即 `.available(.firmwareLimit)`；`LegacyChargeBackend` 增 `.firmwareLimit` 与 `LegacySMCKeys` 新键。

编译校验：`swift build --target StatusTrioPowerHelper`（含 `SMCPrivateAPI`/`PowerHelperProtocol`）**Build complete**（仅历史 Sendable warning）。app 侧需 SDK 26+/Xcode 27 编译（本机 CLT 15.5 SDK 缺 `glassEffect` 等 macOS 26 API，无法本机构建），由 CI 构建。

## 14. CI 构建结果（固件限充后端，build 78）

- 运行：`build-candidate.yml` **#45790370967**（`release_mode=fast`，`--ref main`，`candidate_sha=c16a29ebc57f4ee2e4210f51dd393c006cbb854f`，`build=78`）。
- 结果：`prepare` success、`package` success（`distribution` 环境已由 agent 按用户授权自动批准）；`verify/native` 按 fast 跳过。**app+helper 在 SDK 27 下编译通过**（证明固件后端改动可编译）。
- 清单：`source_sha=c16a29eb…`，`version 1.10.6 build 78`，`publishable=false`，`developer_id`，`notarization=accepted_and_stapled`。
- 产物（已下载）：`~/Downloads/StatusTrio-candidate-1.10.6-b78/StatusTrio-1.10.6.dmg`（sha256 与清单一致）。
- 下一步：装到 macOS 15.8.3 真机，打开「管理充电上限」并设 85%，插电观察是否停在 85% 附近；退出 App 应还原（`bfF0=0`）。真机物理行为仍为 **NOT RUN**。
