# AlDente 仪表盘直达调研（2026-09-28）

## 当前结论

Status Trio 的「AlDente」电池动作通过 `NSWorkspace.openApplication` 启动或激活 AlDente。用户在开发版实测：该动作没有直接显示 AlDente 仪表盘，还需操作 AlDente 自己的菜单栏入口。这是当前集成能力的边界，不是已实现的仪表盘直达功能。

本次保留现有代码和远程分支 `codex/battery-action-targets`，不加入未经验证的 URL，也不要求辅助功能权限。此结论仅表示**尚未找到可靠的直达接口**，不等于断言 AlDente 永远不支持它。

## 已核查的入口

1. **URL scheme：**本机 `/Applications/AlDente.app` 版本 1.39.4（build 112）的 `Info.plist` 注册了 `aldente` scheme。这只能证明系统会把 `aldente:` URL 交给该应用；注册信息没有列出可打开仪表盘的地址。搜索 AlDente 官方资料和社区记录后，未找到可核实的仪表盘 deep link。因此没有把猜测的 `aldente://dashboard` 写入 `KnownBatteryApps`。
2. **快捷指令：**在本机「快捷指令」的 AlDente 操作库中，看到电池状态查询和充电控制等 12 项操作，没有「打开仪表盘」。[AlDente 官方功能页](https://apphousekitchen.com/aldente-overview/features/)列出的 Shortcuts 集成也集中在这些操作上。
3. **AlDente 自带界面：**[AlDente 1.33 更新说明](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/discussions/1545)说明菜单栏右键可配置为打开 Dashboard；[1.35 版本讨论](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/discussions/1604)将 Dashboard 描述为设置窗口的默认视图。这些是 AlDente 自己的交互入口，不构成其他应用可调用的接口。
4. **社区自动操作：**社区有[操作其他应用菜单栏项目的 Hammerspoon 示例](https://gist.github.com/Qubus0/a25d01b032c7402e771269887ccd629d)，但没有找到针对当前 AlDente 仪表盘、经过验证的无权限直达方案。[Hammerspoon 入门文档](https://github.com/Hammerspoon/hammerspoon.github.io/blob/master/getting-started.md)也要求开启辅助功能授权。模拟点击菜单栏依赖 AlDente 的界面结构，暂不纳入 Status Trio。

## 后续重查条件

AlDente 如果发布明确的 Dashboard URL、Shortcuts「打开仪表盘」动作或其他公开接口，先在当前版本实测，再把已验证的入口加入已知应用目录，并保留应用启动作为失败回退。若未来选择界面自动操作，需单独设计权限提示、失败处理和跨版本验证。
