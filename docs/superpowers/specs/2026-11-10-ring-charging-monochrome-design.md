# 充电 / 连接电源时使用黑白圆环 — 设计

## 意图（为什么）

mac mini、Mac Studio 这类无电池机器，圆环在 #309 之后默认用「连接电源色」（默认绿）。
用户希望它们能自己选：圆环用原始黑/白，还是连接电源绿；同时**低电量模式、高电量模式的颜色
仍然生效**。

现有的「单色电量弧」一键预设是把「电池状态颜色」整体关掉，语义太宽，和这个需求混在一起，
容易误会，应该去掉。

## 目标

- 新增一个全局开关「充电 / 连接电源时用黑白」：
  - **开**：充电、已连接电源（无电池机器视为一直连接）时，圆环用前景黑/白，不用充电色；
    低电量模式、高电量模式、临界低电量仍用各自状态色（优先级不变）。
  - **关**：保持现状，充电/连接用充电色（默认绿）。
- **默认值按机器区分（未设置时自动）**：
  - 无电池机器（mac mini / Studio）默认**勾选**（黑白）；
  - 有电池机器默认**不勾选**（充电绿）。
  - 用户一旦手动切换，就固定为其选择，不再自动。
- 无电池机器因此可选：勾选 = 黑白，取消 = 连接绿。
- 菜单栏与 Dock 同源，自动一致。
- 去掉「单色电量弧」预设按钮。

## 非目标 / 反目标

- 不改变低电量 / 高电量 / 临界状态的颜色与优先级。
- 不移除「电池状态颜色」总开关。
- 不是只对无电池开放的设置；有电池机器同样可用。
- 不改变默认外观（默认关，充电仍是绿色）。

## 方案（已选定 C）

考虑过三种：

- **A** 无电池专属「圆环颜色」二选一（单色 / 连接绿）。最贴合 mac mini，但只覆盖无电池。
- **B** 无电池时复用「电池状态颜色」开关演绎成二选一。最省代码，但同一开关含义随有无电池变化，绕。
- **C（选定）** 全局「充电 / 连接电源时用黑白」开关。一个概念同时覆盖 mac mini 的选择，以及普通
  电池机器“充电时想要黑白”的需求。

## 具体做法

- **设置**：`SettingsStore.monochromeChargingRing: Bool?`，`nil` 表示“自动”（未手动设置），
  持久化，纳入 `iconAppearancePublisher` 的电池输入链。
  - 自动解析规则：`nil → !battery.isPresent`（无电池即黑白，有电池即绿）。
  - UI 开关的显示值 = `store.monochromeChargingRing ?? !effectiveHasBattery`（模拟/无电池时显示为勾选）；
    用户拨动即写入显式 `Bool`。
- **模型**：`BatteryIconOptions.monochromeCharging: Bool?`，默认 `nil`，加入其初始化器。
- **Mapper 解析**：`let monochromeCharging = options.monochromeCharging ?? !isPresent`，
  再交给 `StatusMappings.batteryColorRole`。
- **映射**：`StatusMappings.batteryColorRole(..., treatAsConnected:, monochromeCharging:)`
  —— 在 charging/connected 分支里，`monochromeCharging` 为真则返回 `.foreground`；
  low/high/critical 分支保持不变。
- **Mapper**：`IconPresentationMapper.batteryState` 传 `monochromeCharging: options.monochromeCharging`、
  `treatAsConnected: !isPresent`（保留“无电池视为连接”，这样关时是绿、开时是黑白）。
- **UI**：`AppIconRingView` 的「颜色」组，用 `SettingsToggleRow`「充电 / 连接电源时用黑白」
  替换原「单色电量弧」预设行。无电池提示文案更新为：电量百分比 / 充电图标不适用，圆环颜色默认黑/白，
  低/高电量模式仍上色。
- **删除**：`applyMonochromeBatteryArcPreset`、`clearMonochromeBatteryArcPreset`、
  `isMonochromeBatteryArcActive` 及「单色电量弧」相关本地化键。
- **本地化**：新增开关标题与说明（全部 12 种语言）。

## 约束

- 属于图标渲染路径：按 `.agents/rules/rendering.md` 在交付前跑 `full` 本地验证，
  含 `Issue30WiFiAlignmentTests` 与菜单栏/Dock parity。
- 默认关，原有外观不变。

## 留给实现者

- 键名、开关在组内的精确位置。
- 测试清单：映射器（充电 / 连接 / 无电池 × 开关开/关 × 低/高/临界优先级）、
  设置持久化、本地化 parity。
