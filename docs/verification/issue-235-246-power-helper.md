# Issue #235 + #246 — 电源 helper 扩展 验证记录

Date: 2026-11-04

Branch: `feat/power-235-246`

Base: `main` at `f6e9b17e`（最新 main；此前使用的 `fix/207-charge-limit-compat`
基线落后 57 个提交，已弃用）

## 范围

本分支只包含 #235 高电量模式与 #246 低电量自动开启低电量模式。

**#187 充电上限已按要求移除**：该功能原本基于 `PowerUIPrivateAPI` 的 MCL 私有
API，只在 Apple 芯片 + macOS 26.4+ 可用；而它要解决的是旧系统没有原生充电上限
的场景，方向不成立，高版本应直接使用系统自带的能量/充电管理。相关文件
（`ManagedChargeLimitController`、`ChargeLimitSettingsView`、MCL 写入路径、
对应测试与设置项）已全部删除；已合并的「立即充满」功能保持不变。

## 交付内容

- **#235 高电量模式**：helper XPC 协议 v2（版本握手）；`pmset -g cap` 能力探测；
  `pmset -a powermode 2|0` 写入（macOS 26 起 `highpowermode` 参数已被拒绝）；
  低/高互斥由 daemon 完成；旧 daemon 显示「需要更新」；Apple 芯片 + macOS 26.4+
  才显示。状态面板电池行有高电量/低电量快捷按钮；详情页为三态分段选择器。
- **#246 自动开启低电量模式**：独立阈值 `autoLowPowerThreshold`（与临界颜色阈值
  `batteryCriticalThreshold` 分离），使用电池且低于阈值时自动开启，每段低电周期
  一次；需 helper 真正 `isReady` 且「电量模式控制」已开启。
- 高电量外环默认蓝色，可在设置 → 电池 → 状态颜色中自定义。
- 面板行尾部图标统一按图标自身宽度 + 统一内边距与间距排布。

## 验证

- `bash scripts/verify-local.sh full`：PASS（`f6e9b17e` 基线 + 本分支改动）。
- 聚焦测试：307 个电源/面板/本地化测试通过。
- 真机：#246 已在阈值 90%、拔掉电源后自动开启低电量模式（`powermode` 0→1）。
- 打包：Developer ID 签名、Apple 公证 Accepted、stapled、Gatekeeper accepted
  （构建时 bundle id 为生产标识，便于 helper 认证）。

## 未验证 / 需要手动确认

- 高电量端到端（需接电源）：`pmset -g` 变 2、菜单栏与 Dock 电池环变蓝。
- 自定义颜色在真机上的即时生效与重启保留。
- 旧 daemon「需要更新」提示（需换回旧 helper 才能复现）。
- macOS 13 Ventura 运行时；不支持高电量机型的隐藏行为。
- 可见 UI 自动化（按项目约定默认跳过）。
