# 蓝牙设备身份统一与重复显示修复：交付报告

分支 `fix/bluetooth-identity-dedup`，基线 `origin/main` = `2208201ad23ed6f1b9e5e4a9f7ddaa01ced383ab`。所有改动仅在独立 worktree，未合并、未发布。

## 1. 根因（代码与测试已证实）

1. **历史可信设备元数据直接当实时行投影**：`AppleDeviceCatalog.projection` 为每个可信候选建行，即使没有当前发现和电量快照；调用方又把持久 `trustedAppleDeviceMetadata` 与当前发现相加。删除/改名后的历史 ID 因此长期占行。
2. **来源身份没有规范化**：显示层只用精确 `device.id` 字符串去重。同一 MAC 以 `02:00:…` 和 `02-00-…` 出现时被当成两台设备。
3. **手机/平板跨源折叠只是显示层名称规则**：仅当恰好一条 BLE + 一条 trusted、名称相同、具体机型和兼容时才折叠；Watch 不参与，三条同名来源直接失效。它没有物理身份证据。
4. **`pmset` 的 `Accessory Identifier` 被一律当作 UUID**：Magic Mouse 实际可给蓝牙 MAC。双同型号鼠标时严格规则判歧义，合法 98% 无法归属；单机场景又可能按型号回落给错误鼠标。

未证实：原始用户日志未在仓库文档中找到，因此**不能声称**用户截图里的所有同名行都是同一物理设备。

## 2. 修改文件与原因

- `Sources/StatusTrioCore/Models/AppleDeviceCatalog.swift`：新增 `currentCandidates`，把历史元数据、当前发现、成功发现 ID、1200 秒有效快照分开；历史元数据不删除，只限制实时投影。
- `Sources/StatusTrioCore/Monitoring/AppleDeviceDiscoveryController.swift`：新增 `lastSuccessfulCandidateIDs`，只有完整且无路由失败的发现周期才发布；清空候选时复位为 nil。
- `Sources/StatusTrioCore/Store/SystemStatusStore.swift`：镜像成功发现 ID 并接入面板、设置页；不再叠加历史与当前候选。
- `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`、`UI/Settings/BluetoothSectionView.swift`、`UI/StatusPopoverView.swift`：统一使用同一份 `currentCandidates` 结果。
- `Sources/StatusTrioCore/Models/BluetoothDeviceIdentityResolver.swift`（新增）：纯 Swift 身份解析，S1 精确来源身份才合并，代表行按内容稳定选择，输入顺序无关。
- `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`：先精确解析再显示折叠；保留原单对手机/平板展示折叠并明确标记为临时展示层；排序/隐藏使用全部来源别名。
- `Sources/StatusTrioCore/Models/BluetoothBatteryLevelFallback.swift`：`Accessory Identifier` 为六字节 MAC 时按地址精确匹配并校验 vendor/product；明确携带 MAC 时不回落名称/型号；断连不供能、profiler 电量优先、AirPods UUID 路径不变。

## 3. 测试结果

修复前（失败测试先写）：

- `BluetoothIdentityCollisionRegressionTests`：3 个用例失败（同 MAC 两格式两行；双同型号鼠标无法按精确 MAC 归属；明确不匹配 MAC 仍回落型号给错鼠标 98%）。
- `AppleIdentityLifecycleRegressionTests`：因缺少 `currentCandidates` 编译失败。

修复后已通过：

- `BluetoothIdentityCollisionRegressionTests`（12）、`BluetoothAccessoryBatteryIdentityTests`（4）、`AppleIdentityLifecycleRegressionTests`（4）。
- 全部 `Bluetooth` 过滤测试（245）。
- Apple 设备相关：`AppleDeviceDiscoveryControllerTests`、`AppleDeviceCatalogTests`、`AppleDeviceSettingsTests`、`AppleDevicePanelVisibilityTests`、`NearbyBLESettingsTests`。
- 计划指定：`BluetoothDeviceListPresentationTests`、`BluetoothBatteryLevelFallbackTests`、`BluetoothAccessoryBatteryTests`、`BluetoothPollingLifetimeTests`、`BluetoothLEBatteryScannerStateTests`。
- 完整本地 profile 结果见文末「验证记录」。

## 4. Magic Mouse 98%

可以安全关联：当 `pmset` 的 `Accessory Identifier` 是有效六字节 MAC 且等于已连接鼠标 MAC、vendor/product 不冲突、该标识只对应唯一设备时，98% 归属该鼠标。若该 MAC 属于断连鼠标、型号冲突或不匹配任何设备，则不显示电量，也不回落到同型号猜测。

## 5. iPhone / Watch 重复场景

- 已解决：同一 MAC 的多种格式、同一 BLE UUID、同一 trusted/Watch 稳定 ID（Parent + Watch ID）重复来源 → 面板与设置页一条。
- 保留：没有强身份证据的同名 BLE / trusted / 系统行仍是多条。特别是「系统蓝牙 + BLE + Trusted」三条同名 iPhone，现有数据只能证明两个来源可能是同一展示对象，不能证明三者同一物理设备；因此系统 MAC 行保持独立，不会为截图效果强行合并。
- Apple Watch 只在 Parent ID + Watch ID 完全相同时合并，不进入同名手机/平板折叠。

## 6. 历史修复回归

`#86/#93` BLE 与可信合并、`#155` 首次读取失败抑制、`#232` 面板缓存、`#265` 蓝牙关闭清理、`#288` 断连电量、`#294` 120 秒轮询、`#300` 睡眠门控、`#330` 系统列表残留：对应既有测试全部通过；`knownNearbyAppleDeviceNames` 允许列表未改动。

## 7. 性能与权限

未新增扫描、轮询、GATT 连接、系统命令调用或权限；身份解析为每次设备快照的 O(n) 分组，使用字典/集合索引。快照 TTL 保持原语义（BLE 180 秒、移动设备 1200 秒）。

## 8. 剩余风险

- 无法用现有日志证明用户全部重复行同源；同名多来源保留可能会被用户继续看到。
- 历史身份清理依赖一次完整无失败的发现周期；若某条发现路由长期失败，过期历史行会继续保留（这是避免误删在线设备的保守取舍）。
- 没有新增跨会话 S2 映射；BLE UUID 与系统 MAC 之间仍不做不可验证的永久关联。
- 真实 AirPods 多 part 的 identifier 语义仍按既有保守策略，未改变左右耳/盒分组。
