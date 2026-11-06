# 夜间四项改进交付说明（明早验收）

- 日期：2026-11-06
- 分支：`overnight-panel-color-refresh`
- 提交：`f2b61f5c`（基线 `origin/main=d4598847040a5b2d167ec3825c162270eba3492b`）
- 状态：**已在分支提交，未合并 main、未推送、未关闭 issue、未发布**。

## 一句话

四项都已完成并通过本地 full 验证，验收开发包在
`dist/StatusTrio.app`（`Status Trio (Overnight Panel Color Refresh)`，独立开发 bundle ID）。明早直接打开试这四个点即可。

## 四项改动

| Issue | 改了什么 | 明早怎么验 |
| --- | --- | --- |
| [#281](https://github.com/lingyired/status-trio/issues/281) 电池详情底部两行 | “打开系统电源设置 / 打开应用电池设置”整行可点（含右侧空白），两行各自 hover 高亮；原行高、文字位置和间距不变，高亮与按钮的 hover/点击区域一起向外扩展横向 8pt / 纵向 5pt；两行共用一个高亮状态，重叠处当前高亮行优先 | 电池详情页底部，分别悬停两行看是否只亮当前行；点文字右侧空白也能打开设置 |
| [#282](https://github.com/lingyired/status-trio/issues/282) 功耗流入图缝隙 | 按验收反馈保留卡片原本四角圆角；流带向卡内延伸 6pt，再按圆角轮廓遮掉内部流带，避免半透明卡片透出重叠竖带 | 查看浅/深色功耗图：连接处无缝，卡片内部无深色竖带，四角保持原圆角；再看单/多分支与减少透明度 |
| [#275](https://github.com/lingyired/status-trio/issues/275) 蓝牙图标一直蓝色 | 蓝牙图标颜色改为三选一：默认蓝色 / 跟随系统黑白 / 自定义颜色；与音量蓝色开关完全独立 | 应用图标 → 中间图标 → 蓝牙设备，分别选蓝、跟随系统、自定义色；看菜单栏和 Dock 图标是否同步变化，音量条颜色不受影响 |
| [#255](https://github.com/lingyired/status-trio/issues/255) 刷新间隔分电源 | “使用电池时 / 接通电源时”两个滑条（5–60 秒，默认都 15）；自动按是否插电选择；旧设置自动迁移；切换立即生效 | 通用设置里改两个无刻度滑条为不同值，插/拔电源后刷新周期立即使用对应值，无需等旧周期（按验收反馈已移除“生效中”角标） |

### 本轮验收反馈的电池详情调整

- 去掉「整机读取时间」这一诊断行，避免它在 SMC 采样晚到时异步出现、把下面的内容顶下去。
- 新增「最大容量」与「电池状态」行；最大容量优先读系统 `MaxCapacity` 百分比（与 macOS 设置一致），读不到时才回退到原始容量估算；电池状态按系统永久故障标记显示「正常 / 建议维修」。
- 高电量模式行改为直接读取系统 `pmset -g cap` / `pmset -g`：支持时显示「开启/关闭」，系统不支持显示「不支持」；不再依赖 helper 的探测结果（helper 只负责实际开关）。低电量模式仍按系统状态显示「开启/关闭」。
- 这些行沿用详情页原有行样式，不新增卡片，也不增加后台轮询。

## 验证结果

### 自动验证

| 范围 | 结果 |
| --- | --- |
| 最终集成树 `bash scripts/verify-local.sh full` | **PASS**：XCTest 2668 个（0 失败，82 个可见 UI 测试按规则跳过）＋ Swift Testing 943 个全部通过；Release 构建成功；平台/SDK、Helper、MobileBattery、发布流水线离线检查通过。日志 `/tmp/status-trio-full-custom2.log` |
| #281/#282 聚焦与回归 | `PowerFlowCardShapeTests|BatterySettingsLinkTests` 8 passed；`BatteryDetailsLayoutTests|BatteryPowerFlowTests` 13 passed，0 失败 |
| #255 聚焦与回归 | 新生命周期 + `SettingsStoreTests|SystemStatusStoreTests` 211 passed；本地化/设置页 51+1 passed |
| #275 聚焦 | `BluetoothIconColorTests|BluetoothIconColorSettingsTests|IconAppearancePublisherTests|IconPresentationMapperTests|BluetoothAudioIconChoiceTests|IconSceneRendererParityTests|StatusIconPreviewCardTests|PresentationArchitectureTests|LocalizationParityTests|SettingsViewTests` 全部通过 |
| 12 语言 | 新文案在 ar/de/en/es/fr/it/ja/ko/pt-BR/ru/zh-Hans/zh-Hant 全部补齐，parity 测试通过 |

### 验收包

- 路径：`dist/StatusTrio.app`
- 名称：`Status Trio (Overnight Panel Color Refresh)`
- 开发代号：`Overnight Panel Color Refresh`（按规则仅开发包显示）
- Bundle ID：`com.lingsmbp.StatusTrio.dev.overnight-panel-color-refresh`（不影响正式应用）
- 架构：本机 arm64（本地验证包，非 Universal 发布包）；最低 macOS 13；Ad-hoc 签名
- 打开方式：`open "dist/StatusTrio.app"`

## 明早验收时仍属未验证（NOT RUN）

这些不能由自动测试替代，需要你在真机点一遍：

1. #281 两行 hover 观感、右侧空白真实点击、键盘激活。
2. #282 真实玻璃背景与减少透明度下的接缝观感；浅/深色离屏图已检查，卡片内部无透带。
3. #275 蓝色 / 跟随系统 / 自定义色的实际观感，菜单栏与 Dock 是否同步，切换是否闪烁。
4. #255 插拔电后后台刷新周期实际变化；两个滑条保留原生无刻度外观，不再显示角标。
5. macOS 13（Ventura）真机运行。

## 分支处理

验收通过前保留 `overnight-panel-color-refresh` 和 worktree；未合并、未推送、未关闭 issue。你确认没问题后再合并并统一在发布版本里关 issue。
