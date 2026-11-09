# Issue #30 — 顶部圆环配件（插头 / 闪电 / 百分比）对齐

分支 `fix-issue30-menubar-alignment`。接续 `docs/issue-30-wifi-centering-analysis.md`
与 `docs/issue-30-final-verification.md`，本轮处理后续评论「新加一个插头图标看着也偏左」。

完整报告与全部截图/测量 JSON 在 `artifacts/icon-alignment/`（该目录被 .gitignore 忽略，属本地证据）。

## 根因（本轮定位）

三套 x 基准：`canvas.midX=60`、`artworkCenterX=59.5`（手绘艺术轴，圆环/中点用它）、屏幕像素中心。

1. **插头锚点继承闪电非对称 bbox**：`batteryTopIndicatorCenter(boltScale:)` 旧实现用
   `pivot + (bolt.boundingBoxOfPath.midX − pivot)*scale` 求 x。闪电 bbox.midX≈59.45，
   于是插头（及顶部 fallback 字形）中心 = `59.5 − 0.05·boltScale`，随尺寸放大而左漂。
2. **百分比按排版框而非墨迹居中**：`StatusIconRenderer.drawSceneText` 用
   `CTLineGetTypographicBounds` 的 advance 宽度居中，`"8"/"50"/"100"` 各自因左右侧承不同而偏移，
   离屏 8× 下 `"50"` 偏 +0.94 SVG 单位。
3. 闪电自身 bbox 中心 59.4375、面积质心更左，属**形状固有光学特性**，保留，不强行拉平。

（更早的用户可见「偏左」来自彩色 CALayer 不随 `NSStatusBarButton` resize，前几轮已修。）

## 修复

- `StatusIconGeometry.batteryTopIndicatorCenter`：x 直接钉 `artworkCenterX`（仅 y 随闪电缩放）。
  插头离屏偏移由 −0.1875 → −0.0625 单位，与闪电同中心；**闪电绘制与 App Icon 素材不变**。
- `StatusIconRenderer.drawSceneText`：改用 `CTLineGetBoundsWithOptions(.useGlyphPathBounds)`
  墨迹 bounds 居中；1/2/3 位百分比墨迹中心一致（≤0.0625 单位）。
- 未改 `artworkCenterX`、圆环/音量点设计；无按尺寸硬编码偏移表；无新增轮询/动画。

## 验证

- 新增 `Tests/StatusTrioCoreTests/RingAccessoryAlignmentTests.swift`（scale=8 离屏精确几何）。
- 真实菜单栏（Agent Desktop）矩阵 18/24/28/32/36 pt，插头/闪电/百分比(8/50/100) 全部 PASS，
  同一尺寸下各配件 `toRing` 一致（18pt≈0.20、24pt≈0.22、28pt≈0.20、32pt≈0.28、36pt≈0.36 px）。
- 动态切换（plug↔bolt、percent↔plug、24↔32、wifi↔bt）水平跳动 spread ≤0.06 px，PASS。
- `bash scripts/verify-local.sh full`：**PASSED**。

## 工具（可复现）

```bash
bash scripts/build-worktree.sh debug no-open
python3 scripts/run-menubar-accessory-alignment.py --sizes 24,28,32   # 真机矩阵
python3 scripts/run-menubar-accessory-alignment.py --sizes 18,36      # 抽测
python3 scripts/check-menubar-accessory-stability.py                  # 动态切换
```

## NOT TESTED

非 2× 显示器倍率、非焦点显示器淡化、充电动画真机逐帧、真实 macOS 13 运行时、正式签名/公证。
