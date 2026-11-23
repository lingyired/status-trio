# Wi-Fi 摘要行电源开关（#252）

状态面板首页的 Wi-Fi 摘要行带一个电源按钮，等价于蓝牙标题行的蓝牙电源开关。详情页顶部原有
的电源 `Toggle` 保持原样，两者都调用 `SystemStatusStore.setWiFiPower(_:)`。

## 显示规则

- 设置项「显示 Wi-Fi 电源开关」（`SettingsStore.showsWiFiPowerControl`，默认开）只控制摘要行
  的 affordance，不影响 Wi-Fi 本身；没有 Wi-Fi 硬件（`WiFiState.unavailable`）时不显示设置项。
- 摘要行按「行是不是 Wi-Fi 行」决定，而不是按点击目标：`wifiDetails`、`requestWiFiNameAccess`、
  `locationSettings` 都显示按钮；`wiredDetails`、VPN、蓝牙行不显示。
- 权限行也保留按钮：授予定位权限只影响读取网络名称，切换无线开关不需要它，隐藏按钮会让没有
  授权定位的用户在面板里失去唯一的开关。
- 可见性规则集中在 `WiFiPowerControlVisibility`（`showsSummaryToggle(intent:isEnabled:)`），
  视图只做渲染，测试直接覆盖策略。

## 确认

`WiFiPowerTogglePolicy.requiresConfirmation(for:)` 对任何已关联网络的状态都返回 true
（`connected`、`noInternet`、`hotspot`、`temporary`、`shared`），此时关闭 Wi-Fi 会先弹确认；
`notAssociated`、`off` 直接关闭。`.shared` 是网络共享，关掉会断开所有共享客户端，所以也确认。

## 失败提示与恢复

- 写入通过 `WiFiNetworkController.setPowerFromQuickAction` 完成，不要求详情列表处于 active。
- 失败时 `wifiPowerFailed` 为 true，摘要行第二行显示「Wi-Fi 切换失败」，失败提示只在提供按钮的
  行出现（`showsFailureMessage(intent:isEnabled:failed:)`）。
- 后续快照到达与请求状态一致（例如系统侧或再次成功切换）时自动清除；接口消失时保留提示，避免
  把硬件消失误报成成功。
- 切换完成后立即 `refresh` 一次快照，不等轮询；切换进行中按钮禁用。

## 未覆盖

- 详情页的电源 `Toggle` 仍不弹确认（#252 边界要求另开 issue 统一）。
- 菜单栏右键快捷操作直接切换，不弹确认。
- 失败提示会暂时占用摘要行第二行，权限行的授权提示在提示清除后恢复。

## 测试

`Tests/StatusTrioCoreTests/WiFiPowerSummaryTests.swift`：设置往返与默认值、可见性、确认策略、
无障碍标签/值、摘要行渲染（开关数量、330pt 单行）、quick action 路径、失败提示与清除。
