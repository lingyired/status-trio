# 菜单栏配色基线与自定义状态色执行计划

Issue #188 / #193，当前分支 `menubar-status-colors`。

## 执行修正

- Ruling: 保留 #165 I+：透明 non-template button footprint + 独立 template NSImageView + 彩色 CALayer；不新增 focus/opacity/dimming 检测。原计划「彩色不继承非激活变暗」错误，历史 verification 记录 maintainer 在本机双屏环境确认 I+ 同时通过 #112 Space 拖动和 #165 非激活显示器观感检查。自动测试只能锁定架构与像素，不能替代人工结果。
- Ruling: `systemGreen` / `systemYellow` / `systemRed` 是语义色基线，不保证与系统电池逐像素一致。按真实 appearance 一次解析，Dock 按 tile 外观解析，保留高对比度外观。
- Ruling: 原设计 1.2:1 指充电尾巴相对填充；本功能配置的是填充，不能相对自身计算。自定义填充以黑/白参考背景及其 22% 反色 track 的合成色检查可见性，两个参考外观均至少 1.2:1，低于下限时在 RGB 空间定向抬升并显示实际参考对比度。**预设为固定的六组明暗 HSB 对，不做基线 HSL 偏移/目标对比度派生**（这是对设计稿尾巴预设的有意简化，已写入文档）；system/preset 保持原色、只有 custom 执行 1.2 兜底。真实透明菜单栏/clear Dock 背景无法预知，不能保证任意壁纸。
- Ruling: 状态色关闭后完全忽略自定义配置，但**不等于整图 template**：充电动效等 effect 元数据仍会让 `chromaticRegions` 非空并走 overlay。保持既有 monochrome/animation 区域分类，不强制全 template；不采用原计划「保留自定义亮度差」。
- Ruling: 分支最终 rebase 到 `origin/main` `e3477268e794f6794decaa7ac3b2a03968d512a0`。最终提交：PR1 `6585aead`、PR2 `96f2c67d`、独立 timing 测试修复 `f3d07ef3`；不含他人提交。

## PR1 / 逻辑 commit 1：#188

1. 模板墨色使用 alpha=1 的黑/白，状态色统一语义 palette。旧 labelColor 的非满 alpha 是可测差异，但它是否为 #188 用户观感反馈根因仍待人工比较，不宣称已经证明。历史 powered 颜色为浅底 #1F8F3D、深底 #34C759。
2. 不改变 scene 区域分类或 #165 presenter。
3. focused renderer/template/region/parity/charging/alignment tests；新增精准 palette 与 alpha 测试，必要时核对像素后更新指纹。
4. 完成后立即通知 lead 独立只读 review，继续 PR2。

## PR2 / 逻辑 commit 2：#193

1. 三角色 charging/lowPower/critical：system / 六个 preset / custom HSB。
2. SettingsStore 持久化，publisher 使用已发布值，scene 携带配置并参与 hash/cache，所有 scene copy 保留配置。
3. 共享 resolver 为菜单栏、Dock、popover、设置预览解析相同配置；状态色关闭时忽略配置。
4. 设置：每角色模式/预设/ColorPicker/reset；参考对比度与调整披露，12语言完整本地化。
5. 模型、存储、publisher、renderer、cache、surface parity 与本地化回归。
6. 最终集成树运行 full profile 和 alignment/parity focused tests，根因修复失败。
7. `bash scripts/build-worktree.sh release no-open` 构建隔离 app。
8. 写 `output/status-colors-implementation-report.md`：改动、base、tests、局限、app路径、commits。无 push/merge/PR，lead 安排最终独立 review 与统一人工验收。

## 验收边界

#112 template 实时反色和 #165 架构由自动回归约束；Space 手势、非激活双屏 dimming、系统电池视觉配色、macOS 13 与当前系统运行、性能测量本轮未经实际执行则明确 NOT RUN。保留历史 verification，不改写旧结论。

## 最终状态

- 最终树 `f3d07ef3` 上 `bash scripts/verify-local.sh full` 一次通过：Swift 全量（2204 XCTest + 805 Swift Testing，0 失败）、Release 构建、app bundle、平台/SDK、MobileBattery、Helper、native 契约与离线 release 模拟。日志 `/tmp/status-colors-full-final3.log`。
- 历史失败如实保留：run1 WiFi debounce、run2 BetterDisplay 3 秒超时（均已由独立 timing 测试修复）；run2 另有一次 `ChargingEffectRenderingTests` 静态指纹 `55ad…` 仅 Wi-Fi 字形 155px 偏离、环/音量一致，未新增 hash、未放宽容差，最终 full 未复现，作为 finding 记录。
- AppIcon 两个 committed artwork 由渲染器重生成，AppIcon 指纹表仅按本机实测重录；CI/headless 指纹 NOT RUN。
- 后台 UI：项目仅允许 Codex native Computer Use；本会话无该工具，故运行态设置交互、Space 拖动、双屏 dimming 人工观感均 NOT RUN，只能提供隔离 Debug 实例启动与焦点采样。
