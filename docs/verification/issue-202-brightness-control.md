# Issue #202 — 屏幕亮度控制 验证记录

Date: 2026-11-01

Branch: `feat/issue-202-brightness-control`

Base: `origin/main` at `1a0e4753007c8467a3586c72edbd729638080724`

Design: `docs/superpowers/specs/2026-11-01-issue-202-brightness-control-design.md`

Plan: `docs/superpowers/plans/2026-11-01-issue-202-brightness-control.md`

## 交付内容

- 外接屏：直接 DDC（VCP `0x10`）亮度读/写，写后读回确认，fail closed。
- 内置屏：BetterDisplay 亮度读/写（按 displayUUID），写后读回确认。
- 状态面板新增「亮度」分区（`sun.max`）：每块屏一行，滑块 + 百分比；
  不可调控时显示原因。默认不启用，用户在 Settings →「Displayed Items」打开。
- 模型/监控/Store/设置接线：`BrightnessStatus`、`BrightnessMonitor`、
  `SystemStatusStore`、`ExternalBrightnessConfiguration`。

## 单元测试（无硬件，mock）

| 套件 | 结果 |
| --- | --- |
| `DDCBrightnessReplyTests` + `DDCBrightnessCoordinatorTests` | 通过（task-1 独立 worktree：18/18；合并后整体套件绿） |
| `BetterDisplayBrightnessTests` | 12/12 通过 |
| `LocalizationParityTests` | 7/7 通过（11 语言键集 628=628，占位符一致） |
| `BrightnessPanelMapperTests` | 7/7 通过 |
| `DDCVolumeReply/Transport/Coordinator/Selection` 回归 | 通过（音量链路无回归） |
| `BetterDisplay` 音量回归 | 通过（101 XCTest + 23 Swift Testing） |

## 验证矩阵

- `swift build`（debug）：PASS。
- `swift test`（完整）：XCTest 全绿；`ChargingEffectRenderingTests.-
  nilPhaseKeepsThePreEffectStaticPixelFingerprint` 在全量并发下偶发失败、单独运行
  通过。**已在基线 `1a0e4753` 复现**：在干净基线 worktree 连续跑 3 次
  `scripts/test.sh`，第 1 次同一条指纹测试失败、第 2/3 次通过。属预先存在的
  测试隔离/并发抖动（多个用例并行改写静态图标缓存），本分支未引入、未弱化或
  跳过该测试。
- `bash scripts/verify-local.sh full`：Swift 测试步骤被上面那条预先存在的指纹抖动
  挡下（3 次尝试均在 `Swift tests + forbidden patterns` 步骤停在同一条指纹测试）。
  其余 full 步骤已手动逐项通过：
  - `swift build -c release`：PASS
  - `build-app.sh release no-open`（非 Universal ad-hoc bundle）：PASS
  - `verify-platform-version.sh … 13.0 26`：PASS
  - `verify-mobile-battery-bundle.sh` / `verify-privileged-helper-bundle.sh`：PASS
  - `test-macos13-bundle-contract` / `test-app-icon-contract` /
    `test-otool-dependencies` / `test-macos13-sparkle-contract` /
    `test-macos13-deployment-contract` / `test-powerui-charge-restore`：PASS
- 独立验证：`ChargingEffectRenderingTests` 单独运行 5/5 通过；全量套件也曾
  多次整体通过（`swift test` 与 `--no-parallel` 均出现过整体绿）。
- 真机 DDC 亮度效果：**NOT RUN**（本环境无外接屏 I2C 通路）。
- 真机内置屏 BetterDisplay 亮度效果：**NOT RUN**（未安装/未授权 BetterDisplay）。
- macOS 13 / macOS 26 运行时：**NOT RUN**。
- 硬件签名 / 公证 / DMG / Universal 打包 / 正式发布 CI：**NOT RUN**（本地验证不覆盖）。

## 风险与后续

- `CGDisplayCreateUUIDFromDisplayID` 与 IORegistry `EDID UUID` 在旧系统可能不等，
  解析失败即报错不猜测；真机需确认多屏匹配。
- BetterDisplay 亮度命令的 `brightness/min/max` 参数键与 payload 形态照 volume
  移植，未在真实 BetterDisplay 上核对。
- DDC 写后读回按「读回值==写入值」严格确认；显示器若取整可能 fail closed
  （设计取向，真机再评估是否加容差）。
- 设置页暂只提供分区开关；每块外屏的后端选择 API
  （`ExternalBrightnessConfiguration`）已就位，UI 选择器留作后续。
