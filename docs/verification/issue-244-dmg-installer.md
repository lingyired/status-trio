# Issue #244 DMG 安装页验证

日期：2026-11-03。分支：`feat/244-dmg-installer`。基点及对比的 origin/main：`cb62fdd76c854207357cc23ad918165b1c5b300e`。验证覆盖该基点上的本次未提交改动，不应表述为基点本身已包含新实现。

## 结果

- PASS：复核修正后重新执行 `bash scripts/verify-local.sh full`，最终退出 0。日志为 `/tmp/status-trio-244-full-reviewed.log`，本 worktree `.build/local-verification/log.txt` 保存同轮结果。前轮日志另存 `/tmp/status-trio-244-full-final.log`。
- Swift XCTest：2429 项，67 项跳过，0 失败；可见 AppKit UI 测试遵循仓库默认边界，未启用。
- PASS：Release 构建、非 Universal Ad-hoc 本地 bundle、平台/SDK、Helper 与 MobileBattery 契约，以及 full profile 的全部原生与离线发布回归。
- PASS：新 DMG 回归覆盖像素与 DPI、布局参数、App 展示名称、唯一 Applications 链接、版本不符/工具缺失、现有输出拒绝覆盖、Finder 布局失败不回退、原始退出码保留、自有镜像多分区只卸载一次、无关挂载不受影响、busy 挂载保留临时文件。
- PASS：公证离线回归验证 App 公证 → create-dmg → DMG 签名/公证/验证 → 摘要的顺序不变。
- PASS：发布工作流白名单新增第 20 项原生回归，策略和验证入口测试同步通过。
- full 后加严静态断言：publish 及 recovery 禁止调用新的安装页脚本；重新运行 `test-release-notarization.sh` 和 `check-release-workflow-policy.sh`，退出均为 0。
- 后续复核发现三处旧测试只检查部分 trace/日志，未充分证明多分区卸载次数、busy 临时文件保留和 no-space 展示名称参数。已补齐实际行为断言，并分别注入「卸载所有分区」「删除保留目录」「忽略展示名称」故障变体，三个变体均被新断言拒绝。
- 新增成功路径临时目录清理、失败路径上游临时文件清理断言；create-dmg 的 TMPDIR 已限制在本次独占目录内，避免其 AppleScript 失败时遗留文件。
- 新增拒绝 `--skip-jenkins`、`--skip-finalize`、`--sandbox-safe` 的参数断言；三种绕过布局的故障变体均被拒绝。
- PASS：背景在临时目录重新生成，1x/2x 与仓库资源逐字节相同。
- 独立最终复核：未发现阻碍交付的重要源码问题；核对清理归属、App/DMG 公证签名顺序及 native 白名单。复核不代替真实安装页验收。
- 工具链：Xcode 27.0（27A266a）、Swift 6.4、macOS SDK 27.0，本机 arm64 macOS 27.2。

## 发现与修正

首次 full 在 macOS 13 Sparkle 契约停止：旧断言查找 `hdiutil create`。已改为实际创建调用，同时保持必须先验证 App 的顺序断言。随后独立审查发现工作流 native 白名单需要同步，新回归加入后更新为 20 项。两处验证入口 fixture 同步新增脚本。最终重新执行 full 通过，未削弱原有断言。

## 首次真机预览发现（2026-11-03）

用户挂载预览 DMG 后，背景底部「安装完成/启动台」两行被裁切。原因是 Finder 窗口内容区实际约 324pt（含统一工具栏与用户开启的路径栏），小于 420pt 的背景逻辑高度；背景从内容区顶部绘制，底部约 96pt 被裁。图标、箭头与标题位置正确。

修正：把两条提示移到标题下方（top 112/138），全部文字保持在可见区顶部约 160pt 内，底部不再承载信息；重新生成 1x/2x 背景并重新打包预览。仍未在真实 Finder 中复验修正后的效果，等待用户再次查看。

## 尚待人工验收

以下均为 NOT RUN：真实 DMG/Finder 中的图标与箭头对齐、背景逻辑尺寸、Retina、浅/深外观下的文件标签可读性、实际拖入 Applications 与从应用启动台打开、VoiceOver、macOS 13 与当前 macOS 的运行验证。

设计预览由 AppKit 离屏生成，不是 Finder 截图。真实 create-dmg 使用 Finder AppleScript，会打开/关闭卷窗口；本轮仅使用 fake 外部工具，不挂载真实镜像、不操作用户桌面。不把静态 PNG/DPI 检查称为真实 Retina 验收。

低优先级边界：Homebrew 安装最新版、wrapper 精确校验 1.3.0，未来工具升级会明确阻断，未做依赖归档；尚无信号清理回归。公证及 spctl 检查针对原始 App，ditto 后的安装副本未单独验证签名/ticket，真实安装副本检查仍为 NOT RUN。

未进行 Universal 发布打包、Developer ID 签名、公证、线上 appcast 修改、tag、Release、推送、合并或关闭 issue。
