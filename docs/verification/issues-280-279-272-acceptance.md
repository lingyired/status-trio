# 验收说明：issues #280 / #279 / #272

分支：`issues-280-279-272`  
Worktree：`/Users/lingsmbp/Documents/aiwork/status-trio/.agents/worktrees/issues-280-279-272`  
基线：`d4598847040a5b2d167ec3825c162270eba3492b`（origin/main）

验收前不合并、不推送、不关 issue；下面的改动都已提交在分支上，工作区干净。

## 改动摘要

### #280 立即充满按钮不显示

- `scripts/probe-charge-to-full-now.sh --inspect` 现在输出
  `newRequestVisibility`（`available` / `hidden:battery-full` /
  `hidden:on-battery` / `hidden:no-active-limit-or-override` /
  `unavailable:state-read-failed` 等）、PowerUI 状态字段、电池状态与可用上限。
- 本机 27.2/arm64 实测：PowerUI 正常，100% 已充满 → `hidden:battery-full`；
  不是 macOS 27.2 能力故障。详见 `docs/charge-to-full-now-poc.md`。
- 修复电池详情页对 `ChargeToFullNowPresentation.unavailable` 只留空位、不显示说明的 UI bug：
  现在显示“立即充满电当前不可用。”。
- `.transparent` 状态下没有改 #231 的摘要/详情可见性规则。

### #279 输入源图标显示 a/A

- 英文键盘布局（ABC、US、US Extended、British、Australian、Canadian、Irish、
  Dvorak、Colemak）的图标文字按 `Caps Lock || Shift` 显示 `a` / `A`：
  任一开启或两者同时开启都是大写，两者都关闭才是小写。
- 英文布局移除系统图标 URL，避免图标盖住字母；输入源列表仍使用原始描述符和 ID。
- 新增只监听 `.flagsChanged` 的 `SystemInputSourceModifierObserver`：启动、应用激活、
  唤醒时快照当前修饰键；去重；停止时移除本地/全局监听。不请求辅助功能/输入监控、
  不建 event tap、不轮询、不采集字符。
- 菜单栏、Dock、设置实时预览共用同一 `InputSourceState.iconDescriptor`。

### #272 VPN 摘要行开关

- `VPNServiceReading` 保留 `serviceID`、`name`、完整连接状态（connecting/
  connected/disconnecting/disconnected/invalid）和 `isEnabled`。
- VPN 摘要行有系统 VPN 服务时显示电源按钮：未连接连第一条启用服务；已连接/连接中
  断开当前活动服务；切换期间禁用。
- 失败、拒绝、超时会在行内短暂显示本地化提示并主动刷新 VPN 状态。
- 只有系统代理或只有 `utun`（第三方隧道）时不显示开关；不新增设置，
  不做服务选择菜单；使用公开 `SCNetworkConnectionStart/Stop`，无特权 helper、
  entitlement、`scutil` 子进程或私有 API。

## 已执行的自动验证

- `bash scripts/test.sh`：**2669 tests，82 skipped，0 failures**。
- `bash scripts/verify-local.sh full`：见最终汇报；包括完整 Swift 套件、
  Release 构建、非 Universal 本地 app bundle、平台/SDK、Helper、原生兼容与依赖检查、
  离线 release-pipeline 模拟。
- `bash scripts/probe-charge-to-full-now.sh --self-test`：28 checks，0 failures。
- `bash scripts/probe-charge-to-full-now.sh --inspect`：只读，本机输出
  `newRequestVisibility = hidden:battery-full`。

## 明天人工验收建议

1. 从本 worktree 构建开发包：
   `bash scripts/build-worktree.sh release no-open`
2. **#279**：设置 → 菜单栏/Dock 中间图标来源选「输入源」；保持英文输入源，
   在别的 App 里切换 Caps Lock / Shift，观察菜单栏和 Dock 的字母是否同步为 a/A。
   特别验证：Caps Lock 锁定大写后再按 Shift，图标仍应保持大写 `A`；中文/日文等输入源不应改变。
3. **#272**：先在系统设置里添加一个 VPN 配置，打开状态面板 → VPN 行应出现电源按钮：
   未连接时点击应启动第一条配置服务；连接中按钮禁用；已连接点击应断开当前服务；
   系统设置弹认证时 App 不接管，最终以系统状态为准。只有系统代理、没有系统 VPN 时
   不应出现按钮；第三方 utun-only 客户端也不应出现按钮（保持只读）。
4. **#280**：接电源且电量 <100%、系统充电上限在 80–95% 时，电池详情页应显示
   「立即充满电」；100%/已充满/未接电时不显示。若某台机器不支持，详情页会显示
   「立即充满电当前不可用。」而不是空白。诊断命令：
   `bash scripts/probe-charge-to-full-now.sh --inspect`。

## 仍然是 NOT RUN

- #272 真实 VPN 连接/断开、认证/OTP、不同系统版本与 PPP/IPSec/L2TP 的实际可控性
  （自动测试只使用可注入 fake backend，不触碰用户网络）。
- #279 无辅助功能权限下的全局 `.flagsChanged`、其他 App 前台、锁屏/唤醒、
  左右 Shift、外接键盘；Ventura 实测。
- #280 真实充电写入、其余 macOS 27 beta build、Intel 架构；本机只做只读诊断。
- 可见 UI 自动化（`STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS` 未开启）。
