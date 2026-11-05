# #275 蓝牙图标独立配色 — 验证记录

- 分支：`overnight-panel-color-refresh`
- 基线：`origin/main=d4598847040a5b2d167ec3825c162270eba3492b`
- 日期：2026-11-06
- 负责人：lead

## 结论

本地自动化 **PASS**；真实菜单栏/Dock 视觉与鼠标交互 **NOT RUN**。未 commit / merge / push，未启动真实前台 GUI。

## 行为

- 新增 `usesBluetoothAudioIconColor`（key `usesBluetoothAudioIconColor`，默认 `true`）。
- 开启：中间蓝牙/设备符号沿用 `.bluetooth` 状态色（与升级前一致）。
- 关闭：中间蓝牙/设备符号改用 `.primary`，随菜单栏明暗自动变为黑/白。
- 与既有 `usesBluetoothAudioVolumeColor` 完全独立：关闭图标蓝色不会改变底部音量条颜色，反之亦然。
- 覆盖自动当前设备、指定设备符号、手动选择符号三条渲染路径；设置页“应用图标 → 中间图标 → 蓝牙设备”新增独立开关。
- 菜单栏与 Dock 继续共用同一 `iconAppearancePublisher` / `IconSceneState`，新设置进入该发布链一次即可同时刷新两个表面；Dock 缓存按 scene 哈希，颜色变化会失效重绘。

## 代码边界

| 文件 | 变更 |
| --- | --- |
| `Sources/StatusTrioCore/Models/BluetoothAudioIconOptions.swift` | 新增 `usesIconColor`（默认 true），保持旧构造调用兼容 |
| `Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift` | 中间蓝牙符号颜色由固定 `.bluetooth` 改为 `usesIconColor ? .bluetooth : .primary` |
| `Sources/StatusTrioCore/Settings/SettingsStore.swift` | 新增持久设置、默认值、读取与 options 传递 |
| `Sources/StatusTrioCore/Settings/SettingsStore+IconAppearance.swift` | 设置发布链及缩放的蓝牙 options 带上 `usesIconColor` |
| `Sources/StatusTrioCore/UI/Settings/MiddleIconSettingsGroup.swift` | 蓝牙图标设置组新增开关 |
| `Sources/StatusTrioCore/UI/IconGuideView.swift` | 引导卡片沿用配置的图标颜色 |
| `Sources/StatusTrioCore/Localization/LocalizationKey.swift` + 12 语言 strings | 新增 2 个键并全部补齐 |

## Red / Green

| 阶段 | 命令 | 结果 |
| --- | --- | --- |
| Red | `bash scripts/test.sh 'BluetoothIconColorTests'` | FAIL（预期）：3 个新断言在旧 mapper 下 `bluetooth != primary`，默认蓝色用例通过 |
| Green | `bash scripts/test.sh 'BluetoothIconColorTests|BluetoothIconColorSettingsTests|IconAppearancePublisherTests|IconPresentationMapperTests|SettingsStoreTests|LocalizationParityTests|SettingsViewTests'` | PASS，EXIT=0（日志 `/tmp/status-trio-275-green.log`） |

## 测试覆盖

- `BluetoothIconColorTests`：默认蓝、关闭后 `.primary`、指定设备同样遵守、图标色与音量色互不影响。
- `BluetoothIconColorSettingsTests`：默认值、持久化、音量色独立、`iconAppearancePublisher` 发布变化。
- `IconAppearancePublisherTests`：新增 mutation，保证改变图标色会发布新 appearance 并刷新缓存 key。
- `LocalizationParityTests` / `SettingsViewTests`：12 语言键完整、设置页渲染通过。

## 未验证（人工）

1. 关闭开关后菜单栏实际呈黑/白，并随系统浅色/深色切换。
2. Dock 图标同步变色，且不与菜单栏不一致。
3. 使用中切换开关不会造成图标闪烁或延迟。
4. macOS 13 真机运行。
