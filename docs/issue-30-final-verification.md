# Issue #30 — 最终居中验证报告（真机菜单栏）

分支 `fix-issue30-menubar-alignment`（独立 worktree，基线 origin/main `cf24f1da`）。
**未合并、未发布、Issue 未关闭。** 环境：macOS 27.2（26B123，Apple M3 Max），当前显示器 1728×1117 @2×（primary），Agent Desktop 1.0.2。

## 1. 当前修复总结（偏左的真实原因）

1. **彩色层不跟随按钮 resize**：`NSStatusBarButton` 呈现后会被 AppKit 改宽度，Template 的 `NSImageView` 会自适应，但彩色 `CALayer` 停在旧 frame → 彩色弧相对底图/系统图水平漂移。修复：`StatusIconGeometry.contentFrame`（两图层唯一布局源，等于系统 `imageRect` 中心）+ 图层 `autoresizingMask` 自适应 + 实际 frame 比较。
2. **小尺寸像素栅格跳动**：SF Symbol 直接按最终 ~12–18pt 栅格化时，抗锯齿墨迹随尺寸 snapped 到不同像素相位（18/24pt 最多偏左约 0.6px）。修复：菜单栏渲染改为**2× 超采样 → 一次性高质量降采样**（`StatusIconRenderEnvironment.supersample`，菜单栏入口=2，Dock/预览=1）。
3. 未改动 `artworkCenterX=59.5`、电池外环/音量点设计，无按尺寸硬编码偏移表。

## 2. 真机截图证据（`artifacts/icon-alignment/final/`）

- 原图：`real-{16..36}.png`；裁剪：`annot-{24,28,32}-crop.png`；放大 8×：`annot-{24,28,32}-8x.png`；标注：`annot-*-annotated.png`（绿=按钮中心，红=圆环中心，青=符号中心）。
- 逐状态（`artifacts/icon-alignment/states/`）：wifi / weakWifi / bluetooth / inputSource / charging / plug / animatedWifi 的原图与测量 JSON。

## 3. 量化结果

### 3.1 Wi‑Fi 各尺寸（真机 2×，24pt 起重点，其余抽样）

> 「圆环 vs 按钮」由 float 几何给出：`imageRectCenterOffset = 0`（系统把图片精确居中于按钮，实测 `overlayFrame == templateFrame == imageRect`），圆环几何中心相对画布中心 = (59.5/120 − 0.5)·W ≈ −0.13…−0.30px。
> 「符号 vs 圆环」为真机截图像素实测（`real-*.json`）。

| 尺寸 | 圆环 vs 按钮 (几何) | 符号 vs 圆环 (实测) | 结果 |
| --- | --- | --- | --- |
| 16 pt | −0.13 px | −0.5 px | PASS |
| 18 pt | −0.15 px | 0.0 px | PASS |
| 20 pt | −0.17 px | 0.0 px | PASS |
| 22 pt | −0.18 px | −0.5 px | PASS |
| **24 pt** | −0.20 px | −0.5 px | **PASS** |
| 26 pt | −0.22 px | 0.0 px | PASS |
| **28 pt** | −0.23 px | −0.5 px | **PASS** |
| 30 pt | −0.25 px | −0.5 px | PASS |
| **32 pt** | −0.27 px | 0.0 px | PASS |
| 34 pt | −0.28 px | 0.0 px | PASS |
| 36 pt | −0.30 px | 0.0 px | PASS |

说明：截图中「圆环 vs 按钮」的直接读数约 +1.0px，来自状态栏窗口屏幕坐标的映射不确定性（AX 整数边界、`NSStatusBarWindow` 原点）；同一尺寸的 float 几何（imageRect/图层 frame）证明真实偏移为 0，故此列以几何为准。符号 vs 圆环是纯像素量，不受容器映射影响。

### 3.2 状态与动画（24pt，真机）

| 场景 | 符号 vs 圆环 | 容器偏移 / 图层一致性 | 结果 |
| --- | --- | --- | --- |
| Wi‑Fi 正常 | 0.0 px | 0 / overlay==template / imageRect==template | PASS |
| Wi‑Fi 弱信号 | 0.0 px | 0 / 同上 | PASS |
| 蓝牙耳机 | 0.0 px | 0 / 同上 | PASS |
| 输入法 ABC | 0.0 px | 0 | PASS |
| 充电闪电（顶部缺口） | ink 0.0 px | 0 / overlay==template | PASS |
| 电源插头（对称） | ink 0.0 px | 0 / overlay==template | PASS |
| 充电动画（运行帧） | 0.0 px | 0 / overlay==template（几何与静态一致） | PASS |

动画启停：动画帧与静态帧共用同一 `contentFrame`/图层，几何一致（`overlayFrame==templateFrame==imageRect` 对静态与动画成立）；未捕捉启动/结束的连续帧序列截图 → 该连续过程 **NOT TESTED**，但无帧间几何差异证据。

## 4. 测试与构建

- `StatusBarIconLayoutTests`：11 档尺寸的向量对齐（0.25pt＝2× 半物理像素）+ 菜单栏超采样路径 1×/2× 的质心对齐（≤0.5 物理像素）+ `contentFrame` 居中。
- `StatusBarAnimationLayerPresenterTests.hostResizeKeepsOverlayOnTemplateWithoutAnotherDisplayCall`（resize 同步回归）。
- `Issue30WiFiAlignmentTests`、`ChargingEffectFrameCacheTests` 等保持通过（后者的 pre-rendered 参考环境与生产 supersample:2 对齐）。
- `bash scripts/verify-local.sh full`：**953 tests / 135 suites + Release 构建 + 平台/依赖/发布流水线离线回归全部 PASS**。

## 5. 最终判断

- **是否仍存在可感知偏左**：内建/当前 2× 屏上，24pt 及 16–36pt 全部尺寸符号相对圆环 ≤0.5 物理像素，未见可感知偏左。
- **是否存在系统性布局偏移**：无。剩余 ≤0.5px 为小尺寸抗锯齿/像素栅格客观下限。
- **是否值得合并 main**：建议合并（改动低风险：超采样仅限菜单栏、Dock 不变；测试与 full verify 全绿）。
- **Issue #30 是否可关闭**：建议在**你自己常用的外接显示器**上目视确认后关闭；本机只验证了一块 2× 屏。
- **macOS / 显示器特定风险**：1×（非 HiDPI）显示器 **NOT TESTED**（无该硬件）；跨屏切换本次未复测（中途显示器拓扑变化）→ **NOT TESTED**。这是仅存的风险点。

未验证场景：1× 屏、跨屏切换真机、动画连续启停帧序列 —— 均标 NOT TESTED，未宣称通过。
