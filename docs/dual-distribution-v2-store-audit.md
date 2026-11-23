# Status Trio 双发行 V2 — App Store 源码闭包审计与重构施工单

- **日期：** 2026-11-23
- **状态：** 只读审计 + 施工计划（本文件不改产品代码）。
- **基线：** 分支 `feat/dual-distribution-v2`，合并 `origin/main 89aa9d1e` 后的树。
- **方法：** 用 `scripts/verify-app-store-source-closure.py` 的禁用标记规则（`FORBIDDEN_TOKENS` / `FORBIDDEN_IMPORTS`）对 `Sources/StatusTrioCore/**/*.swift` 全量静态扫描；用 `generate-app-store-project.py --check-membership-only` 做 import 级闭包校验。

## 0. 结论

Store 目标当前**不能编译**，且不是「补几个排除项」能解决。根因：main 把一批**私有实现内联进了共享文件**（PowerHelperProtocol 的 XPC 调用、AppleSMC、私有外观偏好、未文档化 NAT key）。旧分支当年用 `Platform/` 的「协议 + Direct 实现 + Store 空实现」把它们拆开了；这一层在本次合并中已移入 `AppStore/reference/`，需要在 main 上**重新抽取**。这就是计划 §3.1「重新审计全部新增源码、重新划分 Provider」的实际内容。

## 1. 扫描结果

- 含禁用标记的文件：**16** 个；含禁用 import 的文件：**10** 个。
- 其中**未纳入** `AppStore/direct-only-sources.txt` 的有 **8** 个（main 新引入）。
- `--check-membership-only` 当前精确阻塞：**5 个 `import PowerHelperProtocol` 的共享文件**。

### 1.1 8 个「必须处理」的文件（按标记）

| 文件 | 命中禁用标记 | 被哪些共享代码反向引用（⇒ 能否直接排除） |
|---|---|---|
| `Monitoring/HighPowerModeClient.swift` | PowerHelperProtocol | 无外部引用（但被 Controller 引用） → **需与 Controller 一起重构** |
| `Monitoring/HighPowerModeController.swift` | PowerHelperProtocol | `UI/Settings/BatterySectionView`、`UI/BatteryDetailsView`、`UI/PowerModePickerRow`、`UI/BatteryStatusView`、`Store/SystemStatusStore` → **不能直接排除，需协议化** |
| `Monitoring/HighPowerModeSystemReader.swift` | PowerHelperProtocol | （辅助）→ 随组处理 |
| `Monitoring/SleepControlController.swift` | PowerHelperProtocol | `UI/QuickActionsCardView`、`Store/SystemStatusStore` → **不能直接排除，需协议化** |
| `Monitoring/LowPowerModeClient.swift` | PowerHelperProtocol | 由上述控制器/同步器使用 → **需协议化** |
| `Monitoring/SMCReadOnlyClient.swift` | AppleSMC | `Monitoring/SystemPowerReader`、`Monitoring/SensorSMCReader` → **需协议化（Sensor Provider）** |
| `Models/SystemIconAppearanceReader.swift` | AppleIconAppearanceTheme / CFPreferencesCopy / kCFPreferencesAnyApplication | `UI/Settings/StatusIconPreviewCard`、`UI/IconGuideView`、`App/AppIconController`、`App/SystemIconAppearanceMonitor` → **必须协议化，Store 用公开/回退实现** |
| `Monitoring/WiFiMonitor.swift` | com.apple.nat（Internet Sharing 检测内联） | Wi-Fi 状态核心组件，Store 必需 → **必须把 NAT 读取抽成注入式 Direct-only 组件** |

> 说明：`com.apple.nat` 在 `WiFiMonitor.swift:363/377`，是内联的 Internet Sharing 探测；旧分支原本有独立 `DirectInternetSharingDetector`（已移入 reference）。Wi-Fi 其余功能必须留在 Store，因此只能抽取，不能整体排除。

## 2. 目标形态（按旧分支设计在 main 上重建）

对每组「共享但夹带私有」的能力，统一采用：

```
共享：定义协议（如 LowPowerModeClienting / SystemIconAppearanceReading / InternetSharingDetecting）
Direct：协议的真实实现（可 import PowerHelperProtocol / AppleSMC / 私有 key）→ 列入 direct-only-sources.txt
Store ：协议的空实现（Unavailable*/Fallback*，返回 .unsupported / 安全回退）
注入：AppEnvironment 组合时按渠道选实现；UI 用能力模型（Phase 1 已实现的 9 态）隐藏/引导
```

这样共享文件不再出现禁用标记，Store 闭包通过 verifier；Direct 行为不变。

## 3. 施工单（Phase 1 剩余，按组）

1. **Power / 睡眠 / 高电量组**
   - 抽 `LowPowerModeClienting` 协议；`DirectPrivilegedPowerClient`（reference 里已有雏形）迁回 `Sources/.../Platform/` 并列入 manifest；加 `UnavailableLowPowerModeClient`。
   - `HighPowerModeController`/`SleepControlController` 改为依赖协议 + 注入；helper 专属的 XPC 类型移入 Direct-only 文件。
   - UI 用能力模型 `power.low-power-mode` / `power.high-power-mode` / `power.sleep-control` 状态决定展示。
2. **Sensor / SMC 组**
   - `SMCReadOnlyClient` 改协议；`SystemPowerReader` / `SensorSMCReader` 依赖协议；Direct 实现列 manifest；Store 空实现返回 `unsupported`。
3. **系统图标外观组**
   - 抽 `SystemIconAppearanceReading`；`SystemIconAppearanceReader`（私有 key）列 manifest；Store 用公开回退（读 `NSApp.effectiveAppearance` 或默认）。
4. **Wi-Fi NAT 组**
   - 把 `WiFiMonitor` 内联的 `com.apple.nat` 读取抽成 `InternetSharingDetecting` 注入；`DirectInternetSharingDetector` 迁回并列 manifest；Store 注入 `Unavailable`（能力 `wifi.internet-sharing` = unsupported）。
5. **Store 组合重建**
   - `AppStore/Platform/StoreAppEnvironment.swift` 基于 main 的真实类型 + 上述 Store 空实现重建；恢复/重写它依赖的公开读取器（`PublicAccessoryBatteryReader` 等）或改用 main 公开路径。
   - 完成 `direct-only-sources.txt` 全量重审（现有 + 上述 Direct 实现 + 后续审计出的私有文件）。
6. **验证**
   - `generate-app-store-project.py --check-membership-only` 通过；
   - `APP_STORE_UNSIGNED=1 build-app-store.sh release no-open` 编译通过；
   - `verify-app-store-source-closure.py`（token 级）通过；
   - Direct 侧 `verify-local.sh full` 保持通过（零退化）。

## 4. 当前证据

- `--check-membership-only` 失败（5 个 PowerHelperProtocol importer，见 §1）。
- `APP_STORE_UNSIGNED=1 build-app-store.sh` 在 membership 阶段即失败（同上）。
- 已安全修正：从 manifest 删除 12 个不存在的旧条目。

> 本审计只做静态与闭包级证据，不代表沙盒运行时、签名或审核结论。
