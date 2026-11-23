# Issue #331 — 内建屏亮度滑块拖出面板后 0%↔100% 抖动

分支：`fix-issue-331-brightness-slider-flicker`（基于 `origin/main`）
状态：开发者自测/确定性测试通过；**真实内建屏实机复现与验收为 NOT RUN**（见文末）。

## 1. 根因报告

抖动来自**两条独立的缺陷叠加**，二者都只在「拖动 + 指针停在边缘」时被放大：

### 根因 A（主因，直接造成 0↔100 抖动与屏幕明暗闪烁）
`PanelLevelSliderCell.trackRect` 直接返回 `controlView?.bounds`，即**拖动期间轨道宽度是实时的**。
`NSSliderCell` 在拖动中每个事件都用 `trackRect` 把指针位置换算成值：`(x - minX) / width`。
SwiftUI 在拖动期间仍会因乐观发布而重新布局这一行；一旦布局把控件宽度瞬时压到 0：

- `+inf` → `NSSlider` 收敛为 `1.0`；`NaN` → 收敛为 `0.0`（已用脚本验证：`min(1,max(0,Double.nan))==0`，且 `NSSlider.doubleValue = .nan → 0.0`、`.infinity → 1.0`）。
- 于是拖动中反复上报 1/0，`valueDidChange` 每次又写一次硬件亮度，屏幕就 0%↔100% 明暗交替。

即：**第一次异常值来自 NSSlider 在“宽度瞬时塌缩”的轨道上按 `(x-minX)/width` 算出的 1.0 / 0.0，再被原样写到硬件。** 关键点：`NSSlider` 会把 NaN/inf 内部收敛成有限的 0/1，所以「入口处拒绝非有限值」挡不住它——必须在源头冻结轨道几何。

### 根因 B（次因，会额外打断手势/销毁滑块）
`DisplayServicesBrightnessController.setBrightness` 在用 `DisplayServicesSetBrightness` 写入被接受后，立刻 `DisplayServicesGetBrightness` 回读；只要回读与目标差 >2%（快速拖动时回读可能滞后），就发布 `scalar=nil, canAdjust=false, source=.unavailable(.writeNotConfirmed)`。
`BrightnessPanelMapper` 把 `canAdjust=false` 变成「不可调占位控件」，`BrightnessRowView` 因此**在拖动中把 `PanelLevelSlider` 整个换掉**（销毁原生控件、打断 `super.mouseDown` 的原生跟踪），随后的系统通知又把滑块恢复，形成控件生命周期抖动。这也是验收条件「不因正常的异步回读暂未匹配就错误销毁滑块」所指的问题。

### 根因 C（读回竞争，潜在）
`SystemStatusStore.reconcilePendingBrightness` 把任意 `readSequence > baseline` 的发布当成「权威新读数」并清除待确认目标。但序号只表示「发布更晚」，不代表「读取发生在写入之后」——一次写入前排队的旧读取若在写入后发布，会用旧值取消最新目标。

## 2. 事件时序（从用户输入到硬件到界面）

```
鼠标拖动
 → NSSliderCell.trackMouse 用 trackRect 换算值（根因 A：width 瞬时塌缩 → 1/0）
 → PanelLevelSliderView.valueDidChange（30Hz 节流）→ SwiftUI binding.set
 → StatusPanelActions.setBrightness → SystemStatusStore.setBrightness
     · 记录 pending 目标 + 基线序号，乐观发布（面板立即跟随）
     · 调用 BrightnessMonitor.setBrightness → DisplayServicesBrightnessController.setBrightness
 → DisplayServices SetBrightness（硬件写入）+ 立即 GetBrightness 回读
     · 回读滞后/不符 → 旧代码发布 canAdjust=false（根因 B）
 → BrightnessMonitor.apply 分配新 readSequence → updates 流
 → SystemStatusStore.applyBrightness → reconcilePendingBrightness
     · gesture 活跃时保留 pending；否则按序号/容差判定（根因 C）
 → BrightnessPanelMapper → BrightnessRowView（canAdjust=false 时滑块被替换）
 → 用户看到滑块 0↔100 跳、屏幕反复明暗
```

## 3. 修复说明（按 Phase 4 分项、分提交）

### 4.1 区分「写入未确认」与「后端不可用」— `DisplayServicesBrightnessController.swift`
- 写入返回非 0（真正写失败）仍报 `.unavailable(.writeNotConfirmed)`。
- 写入被接受（返回 0）但回读不符/失败时，**不再**发布 `canAdjust=false`；改为发布被接受的 `target` 且 `canAdjust=true`。由真实通知/读取稍后校正。无重试、无定时器、无轮询，不伪造成功（写失败仍会失败）。

### 4.2 / 4.4 手势状态与几何/数值防护 — `PanelLevelSlider.swift`
- 新增 `PanelLevelSliderTrackingGeometry`：**手势开始时快照轨道矩形**，整个手势期间 `trackRect` 用它；手势外仍用实时 bounds（命中测试不变）。`knobRect` 与 `trackRect` 使用同一冻结宽度，取值与绘制不会打架。
- `mouseDown`/`keyDown` 进入手势时冻结；`finishActiveGesture()` 统一收尾（flush 最终节流值 + `onEditingChanged(false)` + 解冻）。
- `viewWillMove(toWindow:nil)` 在手势中被移除时正常结束手势，避免卡在 `isEditing`。
- `animateValue` 拒绝非有限目标（程序化入口防御）。注意：真正的修复是**几何冻结**——`NSSlider` 会把 inf/NaN 内部收敛成有限的 0/1，入口处「拒绝非有限值」挡不住 #331，所以 `valueDidChange` 里的非有限判断只是兜底、并非根因修复。

### 4.3 旧回读竞争 — `SystemStatusStore.swift` + `StatusPanelActions.swift` + `BrightnessControlsView.swift`
- 新增 `beginBrightnessAdjustment(displayID:)`；`BrightnessRowView.onEditingChanged(true)` 调用它，`false` 与 `.onDisappear` 收尾。
- `reconcilePendingBrightness`：**手势活跃期间**，该显示器一律显示 pending 目标且 `canAdjust=true`，不因更高序号的旧读数取消最新目标；手势结束后恢复既有逻辑，让真实硬件状态/外部修改重新接管。
- `setBrightness`：加入「完全相同目标（≤1e-6）」的重复写去重，且**仅在手势活跃期间生效**（首次必写，0/1 不被过滤；限定作用域以免吞掉后续合法的同值重写）。滚轮走 `StatusBarController` 直接调用 `setBrightness`、不进入手势集合，故不受该去重影响，也不受根因 A 影响（不经 `trackRect`）。

### Phase 2 诊断 — `PanelBrightnessDiagnostics.swift`（DEBUG-only，默认关闭）
集中开关 `PanelBrightnessDiagnostics.isEnabled`（默认 false，Release 编译为空实现）。可记录手势边界、`bounds` 变化（**关键：证明拖动中是否发生宽度塌缩**）、`trackRect`、`doubleValue`、上报值，均带单调时间戳。正常 Release 不产生任何高频日志。

## 4. 测试结果

### 单元 / 集成（本地，确定性）
- 新增/扩展：`PanelLevelSliderTests`（+4：冻结几何、退化起点、cell trackRect 冻结、非有限值 thumb 中心）、`DisplayServicesBrightnessChangeTests`（+4：写成功但回读仍旧、真实写失败、非有限忽略、写后读失败仍可调）、`BrightnessOptimisticPublishTests`（+5：手势中旧读不抢目标、手势结束真实值接管、同值只写一次、非有限目标忽略、手势中异值仍写）。
- 目标套件聚焦运行：`scripts/test.sh 'DisplayServicesBrightnessChangeTests|BrightnessOptimisticPublishTests|BrightnessMonitorTests|PanelLevelSliderTests|BrightnessPanelMapperTests|StatusPanelViewModelTests|PanelActionRoutingTests|PanelPresentationWiringTests|BrightnessBackendAutomaticTests|BetterDisplayBrightnessTests|DDCBrightnessCoordinatorTests'` → **153 XCTest + 7 Swift Testing，0 失败**。
- 全量 `scripts/test.sh`（最终树）：**exit 0，全绿 0 失败**（Swift Testing 997 tests / 141 suites 全通过；XCTest 全通过）。全量 `scripts/verify-local.sh full` 早前一轮：Swift 全量测试 3062 tests / 0 failures / 99 skipped（skipped 为按策略跳过的可见 UI 测试），Release 构建通过。
  - **App bundle 阶段 BLOCKED（网络）**：`prepare-mobile-battery-sources` 的 `git clone` 报 `RPC failed; curl 18 Transferred a partial file`，为外部网络/依赖拉取失败，与本改动无关；该阶段标为 NOT RUN，需网络恢复后重跑。

### 真实设备（NOT RUN）
- 内建屏真实拖动 / 真实 `DisplayServices` 写读 / 屏幕明暗感受：本会话未做（会造成屏幕闪烁且需真人手势）。建议用户按 Issue 步骤验证，必要时打开 `PanelBrightnessDiagnostics.isEnabled` 抓 DEBUG 日志确认宽度是否塌缩。
- 外接屏 DDC / BetterDisplay 真实控制：无实测环境，**NOT RUN**。

## 5. 风险说明
- macOS 13–27：仅用公开 AppKit/SwiftUI API 与既有私有 DisplayServices 封装，未改部署目标；实机未覆盖。
- DDC / BetterDisplay：逻辑未改；`finishBrightnessAdjustment` 仍只在手势结束 flush DDC。相关既有测试全绿。
- 共用滑块（音量/麦克风）：`PanelLevelSlider` 仅新增手势冻结与非有限防护，行为对音量/麦克风同样安全；其测试全绿。
- 手势集合清理依赖 `begin/finish/onDisappear/viewWillMove/hide/stop`；已多路兜底。
- 手势活跃期间若显示器从列表消失，pending 仍按既有规则被裁掉，仅短暂不影响显示。

### 5.1 已知取舍 / 待人工验证
- **S1 面板关闭时的 AppKit 手势复位（需人工验证）**：`StatusPanelLayoutMetrics` 记录「面板关闭后 hosting 树仍在」，故 `viewWillMove(toWindow:nil)` / `.onDisappear` 在「关面板」这条路径不一定触发。Store 侧已在面板隐藏时清空 `pending*`/`brightnessGestureDisplayIDs`（安全）；NSSlider 的 `isGestureActive` 正常会在 `super.mouseDown` 返回后由 `finishActiveGesture` 复位，仅在「拖动中关面板且 AppKit 未送回 mouseUp」的极端路径下可能残留。**请人工验证「拖动中按 Esc/Cmd-Tab 关面板再打开」滑块是否卡住；若复现则需补面板关闭显式复位。**
- **S2 写后读失败也按乐观处理（有界取舍）**：写入被接受但回读失败时，本修复仍显示目标并保持可调，避免瞬时读失败拆滑块；持续读失败仍会由 `refresh()/.readFailed` 暴露（`DisplayServicesBrightnessController.refresh` 未改）。已加 `testReadFailureAfterAcceptedWriteKeepsDisplayAdjustable` 锁定该取舍。
- **N3/N4（轻微）**：轨道与 bounds 双退化时 `effectiveTrackRect` 仍可能返回零宽（正常命中测试下无法在该状态开始拖动）；`viewWillMove` 中被移除时丢弃 ≤33ms 内的节流末值。均不影响硬件写入正确性。

## 6. 性能评估
- 未增加任何常驻轮询/定时器/观察者；未新增后台工作。
- 诊断日志 DEBUG 且默认关闭，Release 为空实现。
- 新增的「同值去重」减少边缘停顿时对硬件的重复写入。
- 手势冻结只是把每事件的轨道矩形改为读取快照字段，无额外开销。

## 7. Issue #331 验收状态
- 根因可由确定性测试/代码解释：**PASS（代码级）**；真实日志/实机证据：**NOT RUN**。
- 拖到边缘并移出面板不再 0↔100 抖动：**代码级修复完成，实机 NOT RUN**。
- 不因正常异步回读暂未匹配就销毁滑块：**PASS（确定性测试）**。
- 鼠标释放后最终状态准确 / 系统键与外部变更仍同步 / 0% 与 100% 均为有效目标 / 无重复写入或无限回调：**PASS（确定性测试）**。
- 真实内建屏交互：**NOT RUN**；外接屏 DDC/BetterDisplay：**NOT RUN**。

### 自动化测试运行方式
```
bash scripts/test.sh 'PanelLevelSliderTests'
bash scripts/test.sh 'DisplayServicesBrightnessChangeTests|BrightnessOptimisticPublishTests|BrightnessMonitorTests'
bash scripts/verify-local.sh full        # 全量；App bundle 阶段可能因网络暂 BLOCKED
```
