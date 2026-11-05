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
| [#281](https://github.com/lingyired/status-trio/issues/281) 电池详情底部两行 | “打开系统电源设置 / 打开应用电池设置”整行可点（含右侧空白），两行各自 hover 高亮 | 电池详情页底部，分别悬停两行看是否只亮当前行；点文字右侧空白也能打开设置 |
| [#282](https://github.com/lingyired/status-trio/issues/282) 功耗流入图缝隙 | 有流带的卡片连接边改为直角，外侧保留 12pt 圆角；无流带卡片仍四角圆；fill/stroke 同轮廓并在连接处搭接 1pt | 打开电池详情看流入图，重点看卡片上下圆角与蓝色流带交界是否不再留缝；切换单/多分支、深色、减少透明度 |
| [#275](https://github.com/lingyired/status-trio/issues/275) 蓝牙图标一直蓝色 | 新增“蓝牙图标使用蓝色”开关，默认开；关闭后中间蓝牙图标改用黑/白并随明暗切换；与音量蓝色开关完全独立 | 应用图标 → 中间图标 → 蓝牙设备，关闭该开关；看菜单栏和 Dock 图标是否变黑/白，音量条颜色不受影响 |
| [#255](https://github.com/lingyired/status-trio/issues/255) 刷新间隔分电源 | “使用电池时 / 接通电源时”两个滑条（5–60 秒，默认都 15）；自动按是否插电选择；旧设置自动迁移；切换立即生效 | 通用设置里改两个滑条不同值，插/拔电源看“生效中”标记切换；插拔后刷新周期立即使用对应值，无需等旧周期 |

## 验证结果

### 自动验证

| 范围 | 结果 |
| --- | --- |
| 最终集成树 `bash scripts/verify-local.sh full` | **PASS**：XCTest 2665 个（0 失败，82 个可见 UI 测试按规则跳过）＋ Swift Testing 943 个全部通过；Release 构建成功；平台/SDK、Helper、MobileBattery、发布流水线离线检查通过。日志 `/tmp/status-trio-full.log` |
| #281/#282 聚焦与回归 | `PowerFlowCardShapeTests|BatterySettingsLinkTests` 8 passed；`BatteryDetailsLayoutTests|BatteryPowerFlowTests` 13 passed，0 失败 |
| #255 聚焦与回归 | 新生命周期 + `SettingsStoreTests|SystemStatusStoreTests` 211 passed；本地化/设置页 51+1 passed |
| #275 聚焦 | `BluetoothIconColorTests|BluetoothIconColorSettingsTests|IconAppearancePublisherTests|IconPresentationMapperTests|SettingsStoreTests|LocalizationParityTests|SettingsViewTests` 全部通过 |
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
2. #282 深色/减少透明度/玻璃背景下的接缝观感，以及 1pt 搭接的抗锯齿效果。
3. #275 菜单栏实际黑/白、Dock 同步、开关切换是否闪烁。
4. #255 插拔电瞬间“生效中”标记与后台刷新周期实际变化。
5. macOS 13（Ventura）真机运行。

## 分支处理

验收通过前保留 `overnight-panel-color-refresh` 和 worktree；未合并、未推送、未关闭 issue。你确认没问题后再合并并统一在发布版本里关 issue。
