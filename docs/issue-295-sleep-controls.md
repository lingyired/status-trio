# Issue #295 — 状态面板「不息屏」「盒盖不睡眠」快捷开关

## 目标

在状态面板中新增一个「快捷操作」区块，提供两个互相独立的开关：

1. **不息屏**：阻止显示器因空闲息屏。纯 App 内 `IOPMAssertion`，无需特权，进程退出或释放即失效。
2. **盒盖不睡眠**：合盖后系统不睡眠。系统会强制合盖睡眠，普通断言无效，只能通过现有 privileged helper 执行 `pmset -a disablesleep 1`（需要 root）。

两个开关都支持可选定时：30 分钟 / 1 小时 / 2 小时 / 不限时，到点自动关闭并给出轻提示。

## 已确认的产品决定

- 两个开关完整实现。
- 「盒盖不睡眠」**仅插电时可用**；拔电自动关闭，低电量也会自动关闭。
- 定时档位：30 分钟 / 1 小时 / 2 小时 / 不限时。
- 面板位置：独立的「快捷操作」卡片，作为一个可排序 / 可隐藏的 `PopupSection`（`quickActions`），与现有面板区块设置体系一致。
- 本次只做面板，不加菜单栏右键 / 全局快捷键。

## 架构

### 协议与守护进程（privileged helper）

- `PowerHelperProtocolVersion` 新增 `disableSleep = 3`，`current = disableSleep`。
- `PowerHelperXPCProtocol` 新增：
  - `readDisableSleep(withReply:)` — 返回 `pmset -g` 中 `SleepDisabled` 的观察值。
  - `setDisableSleep(_:withReply:)` — 写 `pmset -a disablesleep 0|1`，回复写入后观察到的状态。
- 新增 `DisableSleepCommand`（纯值）：
  - `arguments(enabled:)` → `["-a", "disablesleep", enabled ? "1" : "0"]`
  - `parseSleepDisabled(fromPmsetOutput:)` 解析 `pmset -g` 输出里的 `SleepDisabled` 行。
- `PmsetRunning` / `SystemPmsetRunner` / `PowerModeService` 按现有 `LowPowerMode` 的模式扩展。

### App 侧

- `DisableSleepClienting`（XPC 客户端）实现协议读写，复用 `XPCPrivilegedHighPowerClient` 的连接管道。
- `SleepControlController`（`@MainActor ObservableObject`）：
  - 不息屏：`DisplaySleepAsserting` 抽象，默认 `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)`。
  - 盒盖：通过 `DisableSleepClienting` 调 helper；协议版本 < 3 时显示「助手需要更新」。
  - 定时：每个开关一个 `Task` 睡眠到期限后自动关闭；不引入后台轮询。
  - 拔电 / 低电量自动关闭。
  - 残留恢复：写入成功时记 UserDefaults 标记 `sleepControl.ownsDisableSleep`；启动时**只有**标记为真且系统 `SleepDisabled` 仍为 1 时才复位为 0。绝不清理用户手动设置的 `disablesleep`。
  - 退出 App：`applicationShouldTerminate` 返回 `.terminateLater`，异步复位后再退出（带超时兜底）。
- 面板：`PopupSection.quickActions` + `QuickActionsCardView`；`StatusPopoverView` 增加该 case。
- `SystemStatusStore` 持有 `sleepControl`，负责喂入插电 / 电量状态与启动 / 停止。

### 设置与本地化

- `quickActions` 进入 `defaultPopupSectionOrder`（放在 `battery` 之后）与 `defaultEnabledPopupSections`；沿用现有 order / 可见性设置，无新增持久设置。
- 运行态（开关、定时、剩余时间、残留标记）**不进入**设置导出/导入（`SettingsPreferenceCatalog`）：属于设备运行态，不是可移植偏好，属于有意排除。
- 新增本地化 key，12 种语言全部补齐（`LocalizationParityTests` 会校验 key 与占位符一致）。

## 验证

- 单元测试：`DisableSleepCommand` 参数 / 解析；`SleepControlController` 的开关、定时自动关、拔电自动关、残留恢复（仅清自己的）。
- 更新受默认面板顺序影响的 `SettingsStoreTests` / `VPNRowSettingsTests`。
- 本地交付前跑 `bash scripts/verify-local.sh full`（涉及 helper、状态、并发、面板）。
- 真机人工验收（后台模式记为 NOT RUN）：合盖、外接屏、插电 / 电池、低电量自动关、异常退出后残留恢复。

## 已知边界 / 手工验收（未在后台执行）

- 只管理「本 App 设置过」的 `disablesleep`。用户通过终端等外部手段手动设的
  `disablesleep 1`，本 App 不会去改，因此面板开关显示的是本 App 的开关状态，
  而不是镜像外部设置（这是为避免误清用户设置的有意取舍）。
- 以下需要真机 / 前台人工验证，后台本轮记为 **NOT RUN**：
  - 合盖后系统确实不睡眠、开盖恢复；
  - 外接显示器 clamshell 模式、无内置电池的桌面 Mac；
  - 插电开、拔电自动关、低电量自动关的实际时序；
  - App 正常退出 / 强杀后重开，`pmset -g` 的 `SleepDisabled` 残留是否被正确恢复；
  - 系统「显示器睡眠」设置、锁屏与外接屏下不息屏的实际表现。
