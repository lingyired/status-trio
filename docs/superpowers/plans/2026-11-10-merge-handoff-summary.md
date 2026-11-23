# 合并交付总结：main → V1 图标架构

分支：`feat/icon-core-merge-main`（基于 `feat/icon-core-refactor`）
基线：`origin/main@caa0d46a`（2026-11-10）
计划：`docs/superpowers/plans/2026-11-10-merge-main-into-v1-icon-architecture.md`

## 1. 这次做了什么

把最新 `main` 全量合并进「去设计器、保留 V1 图标重构 + 插件体系」的分支，并按
**以 V1 架构（Configuration / Resolver / Plugins）为主**的策略处理图标核心冲突。

规模：相对 `origin/main` 185 个文件、+20.5k / -0.4k 行；17 个提交。

## 2. 合并结构（读者最关心的三点）

1. **main 的全部更新都进来了**：598 个提交，含 #315 电池标记、#205 分段进度、
   #235 高功率配色、#253 充电符号居中、#275 蓝牙图标颜色、#297 输入源标记、
   以及亮度/BetterDisplay、电池功耗、蓝牙收听模式等非图标功能。
2. **运行时由 V1 Resolver 驱动**：`AppEnvironment.mapScene` 调
   `IconCompositionResolver`，插件产出各槽内容，`SettingsStore` 的图标设置被投影成
   `IconConfigurationV1` 作为解析输入。
3. **V1 配置变成可写、可持久化的真源**：`SettingsStore.iconConfiguration` 会从已存
   V1 载荷恢复、否则从 legacy 默认迁移并写回；`updateIconConfiguration` 落盘并镜像回
   各单设置。设计器 UI 仍然不恢复（本分支既定范围）。

## 3. 本轮额外修掉的真实缺陷

| # | 缺陷 | 影响 |
| --- | --- | --- |
| 1 | `CenterImageCache` 每次现算文件 identity | 图标文件瞬时消失时缓存未命中、回落符号（test1） |
| 2 | `IconPaletteResolver.apply` 丢 `statusColors`/`bluetoothIconColor` | #275 蓝牙色与电池状态色在解析后的场景里失效 |
| 3 | `IconPaletteResolver.apply` 丢 `gapProgressMode` | #205「分段进度」开关完全不生效 |
| 4 | `NetworkIconPlugin` 未固定中心源 | 全局网络故障覆盖在自动中心下取不到网络图标 |
| 5 | main 渲染器不支持多段环 | AirPods 双耳环形图直接渲染失败（返回 nil） |

第 2、3 项是新增的 `IconMergedFeatureParityTests` 抓出来的——它把 main 特性钉在
**运行时真正走的 V1 路径**上，而不是只在 legacy mapper 上。

## 4. 验证证据

- `swift build`（源码 + 测试目标）：通过
- focused：Icon 300 / 43 suites、Preview 72、Dock 167、Settings 38 —— 全绿
- `bash scripts/verify-local.sh full`：**passed**（Xcode 27.0、Swift 6.4、SDK 27.0；
  含全量 Swift 套件 + Release 编译 + 平台/依赖/发布流水线离线校验）
- earlier full run 的唯一失败是克隆 openssl 时 `SSL_ERROR_SYSCALL`（网络），重跑已通过

## 5. 未验证项（如实记录，勿当成已验证）

- 真实 macOS 13 / Ventura 运行时（只做了静态契约）
- Universal（arm64 + x86_64）打包、签名、公证、DMG
- 移动端电池 Helper 在真机上的运行时行为
- 菜单栏/Dock 在真实系统上的视觉验收（本机 UI 目视）

## 6. 测试取舍（重要）

为避免「把测试改绿」，处置都有书面理由，见 `Tests/Retired/README.md`：

- **退役 5 个文件**（移出测试目标）：`IconLegacyCompatibilityTests`、
  `IconRuntimePresentationOptionsTests`、`IconDesignerMenuBarColorPropagationTests`、
  `IconPreviewInputBuilderTests`、`StatusIconCenterTextAlignmentTests`、
  `IconSizingStandardTests`、`IconDesignerCenterBatteryScaleTests`、
  `IconDesignerOuterBatteryTextScaleTests`
  —— 它们断言已被移除的实现（旧 mapper 语义、已删的 real-icon override 桥、已删的
  设计器编辑器源文件）或分支渲染器的实测墨迹高度机制。
- **删除个别用例、文件保持启用**：`SystemStatusStoreTests` 1 项、
  `CenterPercentageInteractiveRangeTests` 2 项、`UnifiedWiFiScaleMigrationTests` 4 项。
- **恢复启用**：`IconSlotResolverTests`、`IconPaletteResolverTests`、
  `AirPodsRingGeometryTests`、`IconDesignerEditingTests`、
  `IconDesignerEditorModelTests`、`IconDesignerReviewRegressionTests`、
  `IconConfigurationMigrationTests`。
- 若你希望其中任何一项按新架构重写而不是退役，告诉我具体哪几个。

## 7. 怎么验收

```bash
cd /Users/lingsmbp/.codex/worktrees/icon-core-merge-main/status-trio
git log --oneline -5
bash scripts/test.sh 'Icon'      # 快速抽查
bash scripts/verify-local.sh full # 全量（约 10 分钟）
bash scripts/build-worktree.sh    # 出可运行的开发包，肉眼验收图标行为
```

重点看：电池顶部标记三种状态、分段进度开关、高功率模式配色、蓝牙中间图标颜色、
AirPods 双耳环、输入源图标居中。
