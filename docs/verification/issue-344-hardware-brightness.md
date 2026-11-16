# #344 BetterDisplay 亮度读数不一致 → 统一到硬件亮度

- 分支：`fix-344-unify-hardware-brightness`
- 基线：`7a6ae83b`（main）
- 环境：本地 macOS 26 / Xcode 27 / Swift 6.4（无内建屏可实测，见“未验证”）

## 根因

Status Trio 是「系统/硬件亮度」这一套刻度：

- 内建屏固定走 `DisplayServices`（`DisplayServicesGetBrightness`/`SetBrightness`），与 macOS 控制中心同一值。
- 外接屏默认「自动」后端：BetterDisplay 运行则走 BetterDisplay。此前读取的是 `brightness` 特性（BetterDisplay 会自动选中「组合/软件」刻度），于是同一块屏在 Status Trio 与外接屏/内建屏之间出现系统性差值。

BetterDisplay 的「亮度（组合）」= 硬件亮度 + 软件压暗 + HDR 余量，是一条与硬件百分比不同的曲线，只在 100% 处重合——正好对应报告里的「只有 100% 是准的」。内建屏之所以“不一致”，是因为它没有 BetterDisplay 后端可选项，只能读硬件值。

## 改动

- `BetterDisplayBrightnessCoordinator`：读写特性由 `brightness` 改为 `hardwareBrightness`，使外接屏百分比 = 显示器硬件亮度，与内建屏 DisplayServices、直接 DDC 同一刻度。
- 增加一次性降级：若某显示器没有硬件亮度（只能软件压暗），硬件特性和回包都不可用时，回退到 `brightness`（自动/组合）并记住该选择用于后续写入，避免整行不可控。
- 停止 / BetterDisplay 退出时重置为硬件特性。
- 更新 `display-286.md` 的“已知数值差异”说明。

## 选项：使用 BetterDisplay 的组合亮度

- 设置 → 亮度 → 「Brightness Backend」组新增开关「使用 BetterDisplay 的组合亮度」，默认关。
- 只有安装了 BetterDisplay（`NSWorkspace` 能找到其 bundle）才可开启；未安装时开关置灰并提示。
- 开启后：BetterDisplay 正在运行时，走 BetterDisplay 的 Display（含内建屏）改用 `combinedBrightness` 读写，数字与 BetterDisplay 面板一致；BetterDisplay 没在运行或未安装时，自动回落系统/硬件值（内建 DisplayServices，外接 DDC/hardwareBrightness）。
- 已计入设置导出/导入目录（`useBetterDisplayCombinedBrightness`）。

## 未验证 / 待人工验收

- 内建屏 + 外接屏同时在线的真机对比：两条滑块的百分比应与 macOS 控制中心一致（本机为合盖单外屏，内建屏不可测）。
- BetterDisplay 开启「组合亮度」的显示器：Status Trio 应显示硬件百分比（可能不同于 BetterDisplay 面板），关闭组合亮度后两处应一致。
- 只有软件压暗、无硬件亮度的显示器：应保持可调（走降级）。
- 以上均需在装有 BetterDisplay 的多屏 Mac 上手动确认；单测只覆盖请求参数与降级路径。
