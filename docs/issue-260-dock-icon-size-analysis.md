# Issue #260：Dock 图标视觉尺寸分析

## 现象

用户在 Dock 中观察到 Status Trio 的白色圆角底板略大于相邻的「系统设置」等图标。

## 根因

Dock 实时图标是由应用自己绘制的独立位图，系统**不会**像处理应用包图标那样替它套
图标形状与安全区，透明留白必须由 `DockIconRenderer` 自己画进位图。

修复前底板取自原始 896 网格：`bodyRect` 占 1024 画布的 **87.5%**，而 macOS 图标的
可见底板是 824/1024 = **80.47%**。Dock 按统一尺寸摆放各 App 的位图，所以这 7 个百分点的
差就直接表现为「看起来大一圈」。

Issue 里列为「可能原因」的另外两项经实测排除：应用包图标与动态图标确实走两条路径，
但应用包图标本身是对的（系统裁切后同为 80.47%）；充电动画与静态图共用同一个
`DockIconRenderer`，不存在单独的尺寸来源。

## 实测依据

用 `NSWorkspace.icon(forFile:)` 取系统实际渲染结果，在 1024 槽位上量不透明边界：

| 图标 | 可见底板 |
| --- | --- |
| System Settings / Calculator / Notes / App Store | 824 px (80.47%) |
| Status Trio 应用包图标（系统裁切后） | 824 px (80.47%) |
| Status Trio Dock 实时图标（修复前） | 896 px (87.50%) |
| Status Trio Dock 实时图标（修复后） | 824 px (80.47%) |

社区常引用的 824/1024 网格与这里对系统应用的实测一致，因此采用它而不是另选一个
百分比。

## 修复

- `DockIconGlyphLayout` 引入 `artworkSide = 824` 与 `artworkScale = 824/896`。
  底板、圆角、描边都从这一单一真源派生；glyph 的位置与尺寸按同一比例绕画布中心
  等比缩入，图案与底板的比例保持 75% 不变。
- 描边的 2 设计单位**不参与**缩放：在 512 px 位图里它正好落在 1 像素上，缩放反而会糊。
- `.square`（应用包图标）路径的 glyph 缩放会抵消网格缩放，因此素材逐像素不变，
  `AppIconPreviewTests` 的指纹无需更新。
- 菜单栏图标走 `StatusIconGeometry`，不受影响。
- 充电动画与基础图共用同一个 renderer，覆盖层经 `tileRect` 走同一坐标变换，不会错位。

## 自动化证据

- 新增 `DockIconRendererTests.testDockBodyFillsAppleIconGrid`：钉住底板占 824 网格、
  四边留白对称。
- `IconGuideRedesignTests.testDockGlyphFrameMatchesRendererLayout` 的期望值同步到新网格，
  并新增「glyph 占底板 75%」的比例断言。
- 聚合渲染后实测：Dock 位图底板 412/512 = 80.47%，glyph 占底板 70.6%（系统 App Store
  实测 70.9%），应用包图标 MD5 修复前后完全相同。
- `bash scripts/verify-local.sh full` 通过：Swift 全量 2461 个测试 0 失败、Release 构建、
  非 Universal App bundle、platform/SDK 与 Helper 契约、native 依赖检查、离线发布模拟。
- 文档改动另跑 `bash scripts/verify-local.sh docs` 通过。

## 验收结论

- **用户于 2026-11-04 自测确认 Dock 里与系统应用齐平，可以合并。**
- 已合并到 `main`（合并提交 `761ab8a6`）。

## NOT RUN

- 多种 Dock 尺寸、1x/2x 屏下的边缘清晰度定量复核：NOT RUN（仅目视确认，未量边缘）。
- macOS 13 真机运行外观：NOT RUN。
- 正式发布签名/公证/Universal 打包：按 release 流程另行验证，不属于本次修复。
