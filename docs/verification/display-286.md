# #286 系统调整亮度后面板滑杆不跟随

- 分支：`fix-display-284-285`（沿用显示器修复分支）
- 基线：`a149f294`（#284/#285 修复后的本地提交）
- 环境：Apple M3 Max、Xcode 27.0、Swift 6.4；内建 Color LCD + 外接 XV272U

## 根因

内建屏固定使用 `DisplayServices`。原 [DisplayServicesBrightnessController.swift](../../Sources/StatusTrioCore/Display/DisplayServicesBrightnessController.swift) 只在启动、面板刷新和自己的写入后读取亮度，**没有订阅 DisplayServices 的亮度变化通知**。因此按亮度键、控制中心或系统设置改变实际亮度后，面板没有触发重新读取，滑杆停在旧值。

另一个相关问题：面板关闭时 Store 中的乐观目标值 `pendingBrightnessScalars` 没有清除。若写入尚未确认就关闭面板，重新打开时旧目标会继续覆盖真实读数。

后端差异：

- 外屏新增默认 `自动` 后端：BetterDisplay 正在运行时用 BetterDisplay，否则用直接 DDC；用户明确选择的后端（包括 DDC）会持久化并优先，不会被自动覆盖。BetterDisplay 启动/退出会在面板可见时重新解析并切换。
- 内建屏 DisplayServices：已接入 `DisplayServicesRegisterForBrightnessChangeNotifications`（macOS 10.14+ 私有符号），外部变化立即读回。
- BetterDisplay 外屏：OSD 分发默认未开启，不能作为唯一同步来源；已兼容 `brightness` / `hardwareBrightness` / `softwareBrightness` / `combinedBrightness` 四类通知。面板可见时另以约 2 秒的有界读回兜底。
- 直接 DDC 外屏：没有系统亮度通知，DDC 使用自己的计时器在面板可见时约 2 秒读回；失败仍按 2/4/8/16/32/60 秒退避，外层不会强行刷新挤压慢读/待写。
- 所有外屏兜底都随面板隐藏、屏幕休眠、停止和拓扑重建取消；没有可刷新外屏时循环自行退出。

已知数值差异：BetterDisplay 后端读的是 BetterDisplay 的用户/合成亮度，实测与系统 OSD 约 1% 内；直接 DDC 后端读的是显示器硬件亮度（实测 XV272U 0.875，对应 BetterDisplay 合成值 0.9375），因此键盘调光后 DDC 显示的百分比会与 BetterDisplay/系统 OSD 有系统性差值。这不是同步失败；若要求数值完全一致，应选择 BetterDisplay 后端。

## 改动

- `DisplayServicesBrightnessController.swift`
  - 新增可注入的 `DisplayServicesBrightnessAPI`，把私有 API 的读写与通知注册收口。
  - `start()` 注册亮度变化通知并观察内部通知；`stop()` 注销观察并反注册。
  - 每次订阅分配独立 `observerID`，C 回调按 passthrough 返回该 ID，不会因同屏新旧 controller 并存而互相注销。
  - 订阅由独立的 `DisplayServicesBrightnessObservation` 持有：`stop()` 和直接释放 controller 都会移除 NotificationCenter observer 并反注册原生回调，不依赖 `deinit` 的 actor 隔离。
  - 控制器收到通知后用原有读回路径读取新值，不信任回调中的数值；注册或符号不可用时只退化为原有打开/刷新行为，不新增定时器。
- `SystemStatusStore.swift`
  - 当亮度面板和亮度设置都不再可见时清空 `pendingBrightnessScalars`，避免旧拖动目标跨面板存活。
- `BrightnessMonitor.swift`
  - 修正注释：内建屏使用 DisplayServices，并说明各后端刷新策略。
  - `refresh()` 和 `rebuild()` 都拒绝在屏幕休眠或亮度区不可见时创建后端，避免打开面板/切换后端/设置变化在休眠期间注册 DisplayServices 回调。
  - 保持亮度更新流只保留最新值。给每块屏幕的实际后端观察分配单调 `readSequence`，Store 在本地写入时记录该屏基线。基线之前已排队的旧读数不能覆盖拖动；该屏实际的新读数可以接管目标，即使中间确认被合并掉。其他屏幕变化不会推进该屏读数序号。
  - `DisplayBrightness.readSequence` 仅用于顺序判断，不参与可视内容相等判断，因此相同亮度读数不增加界面刷新。
- 自动后端
  - `BrightnessBackend` 新增 `.automatic`；新外屏未显式选择时使用该默认值。
  - `SettingsStore` 对未配置显示返回自动，并持久化包括直接 DDC 在内的显式选择；旧配置读取不再把直接 DDC 当默认值丢弃。
  - `BrightnessMonitor` 按 `NSRunningApplication` 是否运行 BetterDisplay 解析自动后端；监听 BetterDisplay 启动/退出通知，在面板可见时重建。
  - Settings 的外屏后端选项显示“自动”，文案补齐 12 种本地化。
- `BetterDisplayIntegrationClient.swift`
  - 亮度 OSD 识别兼容 BetterDisplay 实际使用的 `hardwareBrightness`、`softwareBrightness`、`combinedBrightness`，不再只认笼统的 `brightness`。
- `BrightnessMonitor.swift`（外屏追加）
  - 新增面板可见期间的外屏读回循环（约 2 秒），只覆盖 BetterDisplay 和外屏 DisplayServices；DDC 保持自己的计时器和失败退避，外层绝不对 DDC 强制刷新。
  - 循环在隐藏、休眠、停止和拓扑重建时取消；无可用外屏时自行退出。
- `BetterDisplayBrightnessCoordinator.swift`
  - 新目标已在等待时，不发布旧读/旧写完成的标量或失败；处理完旧事务后继续提交最新目标，最新目标的成功与失败照常发布。

## 验证

- 红：移除通知接线后，`testBrightnessChangeNotificationPushesTheNewValue` 失败（注册列表为空、值仍为 0.2）；见 `.agent-artifacts/286-red.log`。
- 绿：通知到达后滑杆值更新为 0.6；另一显示器通知不刷新本屏；停止后不再响应；直接释放 controller 会注销；同屏双 controller 互不干扰；重启后旧通知被拒绝；注册失败不新增轮询。9/9 通过，见 `.agent-artifacts/286-green.log`。
- 红：面板关闭后旧目标值仍覆盖 0.3 的新读数；见 `.agent-artifacts/286-pending-red.log`。
- 绿：隐藏面板后待确认目标清除，重新打开显示 0.3；见 `.agent-artifacts/286-overflow-green.log`。
- 红：本地写入确认与外部读数同处一个主线程轮次时，0.6 的旧目标盖住 0.3 的系统读数；见 `.agent-artifacts/286-stream-red.log`。
- 绿：改每屏 `readSequence` 后，同轮外部读数显示为 0.3；16 轮连续外部刷新最终显示 0.8；16 次本地写后的外部读数显示 0.3；另一屏的新读数不会清掉本屏目标；写前已排队旧读数不能覆盖目标。
- 红：休眠时打开亮度区会重建后端并注册通知；见 `.agent-artifacts/286-sleep-red.log`。
- 绿：`refresh`/`rebuild` 增加休眠与可见性守卫；79/79 亮度相关聚焦测试通过，见 `.agent-artifacts/286-focused.log`。
- BetterDisplay：红 `.agent-artifacts/bd-286-red.log` 复现旧读/旧写完成时多发旧值；绿 `.agent-artifacts/bd-286-green.log` 覆盖旧成功/失败×最新成功/失败，15/15 通过。
- 外屏追加：BetterDisplay 可在面板可见时被兜底刷新、隐藏后停止；外层回退循环不驱动 DDC；DDC 原生 2 秒读回能用、失败退避保持 `[2s,4s,8s]`、慢读不新增轮询且最终写不被饿死；OSD 识别新增 `hardwareBrightness` 等目标。聚焦共 84/84 通过，见 `.agent-artifacts/ext-refresh-focused.log`、`.agent-artifacts/ddc-native-poll-green.log`。
- 自动后端：未配置外屏默认自动、显式 DDC 选择重载后保留；BetterDisplay 运行状态变化时从 DDC 切到 BetterDisplay 再切回 DDC；Settings/本地化/相关聚焦 170/170 通过，见 `.agent-artifacts/auto-backend-focused-final.log`。
- 用户实机确认：内建屏跟随；外接屏 BetterDisplay 与直接 DDC 均能跟随。BetterDisplay 与系统值约 1% 内；DDC 显示硬件亮度，与 BetterDisplay 合成值存在系统性差值（已实测 0.875 vs 0.9375）。
- 只读实机验证：`DisplayServicesRegisterForBrightnessChangeNotifications(1, 1, callback)` 返回 0，符号注册可用；未实际改变屏幕亮度，真实亮度键效果 **NOT RUN**。

## 实机验收

1. 打开面板亮度区，用键盘亮度键或控制中心调整内建屏亮度，确认滑杆跟随变化，不需要重新打开面板。
2. 关闭面板后在系统里调整亮度，重新打开面板，确认显示当前实际亮度，而不是旧值。
3. 外接屏按所选后端分别验证：BetterDisplay 面板打开时约 2 秒内跟随；直接 DDC 面板打开时约 2 秒内跟随。两者数值差异见上文“已知数值差异”。
4. 自身拖动和外部调整交替操作，确认无永久回跳、无跨屏更新。
5. 实机已由用户确认：内建屏跟随；外接屏 BetterDisplay 与直接 DDC 均能跟随。BetterDisplay 与系统值约 1% 内；DDC 显示硬件亮度，与 BetterDisplay 合成值的系统性差值见上文。

## 完整本地验证

`bash scripts/verify-local.sh full`：**PASS，exit 0**（在 `a149f294` 加本次工作区改动上运行，随后提交到分支 HEAD）。

- Core XCTest：2715 项，82 项按可见 UI 边界跳过，0 失败。
- Swift Testing：927 项 / 129 suites 通过。
- Release 构建、非 Universal Ad-hoc 应用包、平台/SDK、Helper/MobileBattery、原生兼容性契约、离线发布模拟全部通过。
- 日志：`.agent-artifacts/full-286-auto.log`。

## 未验证

- 真实键盘亮度键/控制中心的运行效果、实际硬件回读、macOS 13 运行均 **NOT RUN**（自动测试使用注入的 DisplayServices fake；只读注册探针返回 0）。
- 多屏镜像/合盖、真实休眠唤醒下的通知投递尚未实机验收。
- 未做签名、公证、DMG、Universal 包或发布。
