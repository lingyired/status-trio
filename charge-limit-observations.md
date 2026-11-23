# macOS 充电上限 / 优化电池充电 / 立即充满 — 观测总结

> 生成时间：2026-11-09
> 环境：macOS 27.3 (Build 26C5035r)，Apple Silicon (arm64)
> 说明：以下全部为**真机实测观测**，非公开文档；相关接口均为私有 API，跨版本可能变化。

---

## 1. 数据来源（私有 / 无公开 API）

### 1.1 PowerUI 私有 client（`PowerUISmartChargeClient`）
- `isMCLCurrentlyEnabled:` → `mclEnabledRaw`
- `getMCLLimitWithError:` → `mclLimit`
- `smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:` → `uiStateRaw` / `uiLimit` / `overrideAllowed`
- 写操作：
  - `temporarilyDisableMCL:`（立即充满用）
  - `enableMCL:`（结束覆盖 / 恢复）
  - `setMCLLimit:error:`（写上限）

### 1.2 持久化策略文件
`/Library/Preferences/com.apple.powerd.charging.plist` 的 `policies`（`NSKeyedArchiver` 的 `ChargeCtrlPolicy` 数组），每条含：
- `soclimit`（数值）= 上限百分比
- `reason`（字符串）：
  - `manualChargeLimit` = 用户手动设的上限
  - `optimizedBatteryCharging` = 优化电池充电(OBC)自己按的暂停（约 80）
  - 空 = 没有显式上限（等价 100%）

### 1.3 电池信息
IOPS：电量%、是否充电、是否充满、是否接电。

---

## 2. 各字段观测含义

| 字段 | 观测含义 |
|---|---|
| `mclEnabledRaw` | **0** = 未启用（100 / 无限制）；**1** = 正常生效的上限；**3** = 临时覆盖（"允许至明天"） |
| `mclLimit` | 实际生效上限（80 / 100 …） |
| `uiLimit` | 多次观测**恒为 100**，不可靠，**不要用它判断** |
| `uiStateRaw` | 观测到 1 / 3 / 6 / 13 / 14，**含义未解码**，但与状态强相关 |
| `overrideAllowed` | 当前 OBC 暂停是否"可覆盖"；**true 时原生「立即充满」才出现** |

---

## 3. 实测快照（同一台机，电池始终约 80%）

| 时间 | 触发动作 | mclEnabledRaw | mclLimit | uiStateRaw | overrideAllowed | 策略 (policies) | 充电? |
|---|---|---|---|---|---|---|---|
| 15:20 | 初始（100% + OBC，停在 80） | 0 | 100 | 6 | true | optimizedBatteryCharging/80 | 否 |
| 15:29 | 手动设 80 | 1 | 80 | 14 | false | OBC/80 + manual/80 | 否 |
| 15:34 | 「允许至明天」 | 3 | 100 | 13 | false | OBC/80 | 稍后开始充 |
| 15:38 | 再手动设 80 | 1 | 80 | 14 | false | OBC/80 + manual/80 | 否 |
| 15:39 | 「上限设为 100%」（永久） | 0 | 100 | 1 | false | OBC/80 | 否 |
| 16:14 | 系统自行变"可覆盖" | 0 | 100 | 6 | true | OBC/80 | 否（按钮出现） |
| 16:32 | 点菜单「立即充满电」 | 0 | 100 | 3 | false | 空 | 是（开始充） |
| 16:33 | 仅 `enableMCL`（取消） | 1 | 80 | 14 | false | manual/80 | 否（上限被写成 80） |
| 16:39 | 手动设 100% | 0 | 100 | 1 | false | 空 | 否 |

---

## 4. 规律 / 结论

1. **「充电上限 100%」在持久层是"没有策略"(空)**，不是硬 100；OBC 仍可把充电按在 ~80。系统 UI 滑条只有 80–100，没有"关闭"档。
2. **「设到 100%」有两种完全不同的动作：**
   - **「允许至明天」= 临时覆盖**（`raw=3`），会去充满，次日恢复。
   - **「上限设为 100%」= 永久**（空策略 / `raw=0`），OBC 仍停在 80，**不充电**。
3. **OBC 的 80% 暂停独立于充电上限**，持久成 `optimizedBatteryCharging / soclimit=80`。
4. **`overrideAllowed` 会随时间在 false↔true 之间变化**（实测设完后约 35 分钟才 false→true）。false 时：不充、原生「立即充满」不显示；true 时：按钮出现——这就是"按钮时有时无 / 不充电"的根源。
5. **结束「立即充满」**：只调 `enableMCL` 能停止充电，但会把"覆盖前上限"落成 `manualChargeLimit`（这次 80）→ 等于改了上限。**没有"只停止、不改上限"的干净接口**。
6. **"重置到 100% / 无上限" = `enableMCL` + `setMCLLimit:100`** → `raw=0`、策略清空、`mclLimit=100`；但**不等于会充电**（OBC 仍按 80）。

---

## 5. 附：某 App 的「立即充满」按钮显示条件（据此实现）

需同时满足：
- 能力可用（macOS 26.4+ / Apple Silicon / 支持 MCL）
- 面板打开 + 电池区可见 + 有电池
- 接电源 + 未充满 + 电量 < 100%

**且满足其一：**
- (a) 存在有效上限：`mclEnabledRaw == 1` 且 `80 ≤ mclLimit < 100`
- (b) 处于可覆盖暂停：`!isCharging` 且 `overrideAllowed == true`

> 备注：概览卡还受"显示立即充满按钮"开关限制；电池详情页不受该开关限制。

---

## 6. 不确定 / 待验证

- `uiStateRaw` 各值的确切含义尚未解码。
- 两个"立即充满"入口（「允许至明天」vs 菜单「立即充满电」）观测到的 `raw` 分别为 3 与 0，机理未完全确认。
- 仅在 macOS 27.3 本机观测；私有 API 跨版本不稳定。
- 所有"充满 / 取消 / 重置"均为真实写操作，会改变实际充电行为。
