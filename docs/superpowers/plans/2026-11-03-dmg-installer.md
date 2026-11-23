# Issue #244 DMG 安装引导实施计划

设计依据：[设计稿](../../design/issue-244-dmg-installer.md)。用户已确认方向并要求补充完成安装及应用启动台打开提示。

## 文件与任务

1. **回归先行**：新增 `scripts/test-dmg-installer.sh`，用 fake create-dmg / hdiutil 覆盖布局参数、唯一 Applications 链接、依赖版本、拒绝覆盖、失败不回退、只清理自有挂载；扩展 `scripts/test-release-notarization.sh` 的 fixture 与签名顺序断言。先观察测试因缺少实现失败。
2. **资源生成**：新增 `scripts/generate-dmg-background.swift`，用 AppKit 系统字体生成 `assets/dmg/background.png`、`background@2x.png`（72/144 DPI）。支持单独的设计预览输出：只在预览中绘制示意图标和标签。新增双语安装完成/Launchpad 提示。验证像素、逻辑尺寸和图像内容，不做易碎的字体像素快照。
3. **打包接入**：新增 `scripts/create-installer-dmg.sh APP_DIR OUTPUT_DMG`。检查 create-dmg 1.3.0、背景、App 图标和现有输出；独占临时输出目录；create-dmg 创建链接和布局；trap 通过 hdiutil plist 中 image-path 的严格路径归属判断清理自有挂载，并保留原始失败状态。`package-release.sh` 移除预建 Applications 链接，改调用封装，既有公证与签名顺序不变。
4. **工作流与文档**：package job 准备并核验 create-dmg；native/full 验证包含新回归。更新发布文档说明依赖、资源生成、Finder 副作用和未验证范围。
5. **交付检查**：运行新回归、release notarization/pipeline/workflow 测试，再跑一次 full profile。对最终 diff 做一次独立审查并处理实质问题。生成更新后的预览和验证报告；保留分支，不自行合并/推送/发布/关闭 issue。

## 验收边界

不通过此修改执行真实发行 DMG 创建、签名、公证或发布。真实 Finder 的 Retina、浅/深外观、拖拽安装及 Launchpad 打开留待人工验收，未执行项记为 NOT RUN。普通测试不启动 Finder 或 App。

## 执行记录

- 2026-11-03：基点与 origin/main 同为 cb62fdd76c854207357cc23ad918165b1c5b300e，工作树独立。
- Ruling：更正初查时关于 `--overwrite` 的结论，create-dmg 1.3.0 完整帮助/源码均支持；使用独占输出避免依赖覆盖行为。
- Ruling：采用用户指定的「应用启动台 / Launchpad」文案；当前 macOS 的入口名称可能不同，后续人工验收需要同时检查 macOS 13 和当前系统。
- 完成：资源生成、打包接入、工作流依赖、离线回归与新手说明。新测试先因 wrapper 缺失失败，再通过；资源 DPI 回归曾正确发现 1x PNG 使用默认 72 DPI 不写 pHYs，明确保留 2x 的 144 DPI 硬断言。
- Ruling：package 命令保留原有诊断重跑输出替换行为，先验证绝对父目录和文件名；独立 wrapper 仍拒绝覆盖输出，防止误覆盖。
- 初轮最终验证：`bash scripts/verify-local.sh full` 退出 0；2429 XCTest、67 skipped、0 failures。详见 ../../verification/issue-244-dmg-installer.md。保留未提交验收工作树，无合并/推送。
- 后续复核：补齐多分区卸载总次数、busy 真实目录/文件保留、no-space 展示名参数断言；三个故障变体均被拒绝。补充绕过布局参数拒绝和成功清理断言。上游工具 TMPDIR 隔离到本次临时目录，修复 AppleScript 失败时临时文件泄漏；重新执行 full，退出 0（/tmp/status-trio-244-full-reviewed.log）。
