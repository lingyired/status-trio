# #286 系统调整亮度后面板滑杆不跟随

- 分支：`fix-display-284-285`（沿用显示器修复分支）
- 基线：`a149f294`（#284/#285 修复后的本地提交）
- 环境：Apple M3 Max、Xcode 27.0、Swift 6.4；内建 Color LCD + 外接 XV272U

## 根因

内建屏固定使用 `DisplayServices`。原 [DisplayServicesBrightnessController.swift](../../Sources/StatusTrioCore/Display/DisplayServicesBrightnessController.swift) 只在启动、面板刷新和自己的写入后读取亮度，**没有订阅 DisplayServices 的亮度变化通知**。因此按亮度键、控制中心或系统设置改变实际亮度后，面板没有触发重新读取，滑杆停在旧值。

另一个相关问题：面板关闭时 Store 中的乐观目标值 `pendingBrightnessScalars` 没有清除。若写入尚未确认就关闭面板，重新打开时旧目标会继续覆盖真实读数。

后端差异：

- 内建屏 DisplayServices：已接入 `DisplayServicesRegisterForBrightnessChangeNotifications`（macOS 10.14+ 私有符号），外部变化立即读回。
- BetterDisplay 外屏：沿用现有 OSD 提示触发刷新。
- 直接 DDC 外屏：没有系统通知，面板打开期间沿用既有约 10 秒刷新；重新打开面板会主动刷新。慢设备、失败重试和在途事务可能延长等待，不承诺 10 秒为上限，不做额外后台轮询。

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
- 只读实机验证：`DisplayServicesRegisterForBrightnessChangeNotifications(1, 1, callback)` 返回 0，符号注册可用；未实际改变屏幕亮度，真实亮度键效果 **NOT RUN**。

## 实机验收

1. 打开面板亮度区，用键盘亮度键或控制中心调整内建屏亮度，确认滑杆跟随变化，不需要重新打开面板。
2. 关闭面板后在系统里调整亮度，重新打开面板，确认显示当前实际亮度，而不是旧值。
3. 外接屏按所选后端分别验证：BetterDisplay 记录是否有 OSD 通知；直接 DDC 记录面板打开时最长约 10 秒内跟随、重新打开立即刷新。
4. 自身拖动和外部调整交替操作，确认无永久回跳、无跨屏更新。

## 完整本地验证

`bash scripts/verify-local.sh full`：**PASS，exit 0**（在 `a149f294` 加本次工作区改动上运行，随后提交到分支 HEAD）。

- Core XCTest：2706 项，82 项按可见 UI 边界跳过，0 失败。
- Swift Testing：927 项 / 129 suites 通过。
- Release 构建、非 Universal Ad-hoc 应用包、平台/SDK、Helper/MobileBattery、原生兼容性契约、离线发布模拟全部通过。
- 日志：`.agent-artifacts/full-286.log`。

## 未验证

- 真实键盘亮度键/控制中心的运行效果、实际硬件回读、macOS 13 运行均 **NOT RUN**（自动测试使用注入的 DisplayServices fake；只读注册探针返回 0）。
- 多屏镜像/合盖、真实休眠唤醒下的通知投递尚未实机验收。
- 未做签名、公证、DMG、Universal 包或发布。
