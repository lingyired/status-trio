# 电池详情页交互与功耗图连接 — 验收记录（#281 / #282）

日期：2026-11-06。分支 `overnight-panel-color-refresh`，初始基线 `origin/main=d4598847`。

## 当前方案

- #281：底部两行保留整行可点、独立 hover 的实现。
- #282：按用户本轮反馈，恢复所有卡片原本的四角 12pt 圆角。流带向输入卡片内、分支卡片内各延伸 6pt，卡片绘制在流带上方。
- 卡片是半透明的，单纯调整层级会出现卡内重叠竖带（浅/深色截图均可复现）。最终对流带层应用原圆角卡片轮廓的反向蒙版，卡内不绘制流带，卡外仍衔接到圆角外沿。不加不透明背景，不改变原卡片色彩与透明度。
- 取消前版单侧直角 Shape 和对应几何测试，替换为真实像素回归：既检查圆角与流带衔接，又检查半透明卡片内部没有透带。

## 本轮文件

- `Sources/StatusTrioCore/UI/BatteryPowerFlowView.swift`：先画流带、应用圆角卡片反向蒙版，再画原圆角卡片。
- `Sources/StatusTrioCore/UI/PowerFlowCardGeometry.swift`：6pt 延伸几何、圆角蒙版、原圆角表面。替代旧的 `PowerFlowCardShape.swift`。
- `Tests/StatusTrioCoreTests/BatteryPowerFlowTests.swift`：保留原接口/功率模型回归；连接卡四角保持圆角，流带端点深入卡片。
- `Tests/StatusTrioCoreTests/PowerFlowOverlapRenderingTests.swift`：浅/深色离屏渲染，比较流带重叠区与卡片内部的背景像素，保证没有透带；检查卡外蓝色流带仍到达交界。

## 证据

| 范围 | 结果 |
| --- | --- |
| 行为红：`bash scripts/test.sh 'PowerFlowOverlapRenderingTests'` | FAIL（预期）：浅/深色卡内 RGB 偏差超过 0.02，复现截图中的重叠竖带。日志 `/tmp/status-trio-282-mask-red.log` |
| 行为绿：`BatteryPowerFlowTests|BatteryDetailsLayoutTests|PowerFlowOverlapRenderingTests` | PASS：XCTest 13 项、Swift Testing 浅/深色两种像素场景通过。日志 `/tmp/status-trio-282-mask-green.log` |
| 最终交付：`bash scripts/verify-local.sh quick 'BatteryPowerFlowTests|BatteryDetailsLayoutTests|PowerFlowOverlapRenderingTests|BatterySettingsLinkTests'` | PASS：shell/forbidden 检查、XCTest 13 项、Swift Testing 3 个测试（含浅/深色两个参数场景）。日志 `/tmp/status-trio-282-rounded-quick.log` |
| 离屏图片 | 浅/深色检查：卡片内部重叠竖带消失，四角保持圆角，连接处无明显缝隙。图片保存在 `.agent-artifacts/power-flow-rounded/light.png`、`dark.png` |

截图由临时离屏渲染测试生成，该临时测试已清理；长期像素行为回归保留。没有启动窗口或启用可见 UI 测试。

本轮是电池详情视图局部绘制修正，运行 quick 及对应回归；未重新声明 full/真机运行通过。此前分支的 full 结果见总验收报告，对应当时的树。

## 待人工验收

1. 电池详情功耗图：四角保持原来的圆角，卡内没有深色竖带，流带与卡片边缘连续。
2. 单分支、多分支与电池供电的实际状态。
3. 真实桌面玻璃背景、减少透明度下的观感。
4. #281 两行 hover 与右侧空白真实点击/键盘行为；macOS 13 真机运行。

未合并 main、未推送、未关闭 issue。保留当前隔离工作区供用户验收。
