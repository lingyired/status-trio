# Settings Semantic Infrastructure — 实施报告

> 分支 `feat/settings-semantic-infrastructure`，基准 `origin/main` @ `7c125bf8`。
> 本报告随实现推进更新；未列出的能力即尚未实现。

## 1. 已完成范围

| Phase | 状态 | 交付 |
|---|---|---|
| 0 设置盘点 | ✅ 完成 | `docs/settings/settings-inventory.md`：152 个 `@Published`、169 个存储键、49 legacy-only 键、50 计算属性；128 个 UI 绑定（user-visible）作为覆盖目标，含分类与排除原因。 |
| 1 语义注册表 | ✅ 完成 | `Semantic/` 下 ValueType / Condition / Constraint / AccessPolicy / PerformanceImpact / Option / Mutation / PreferenceDescriptor / FeatureDescriptor / Capability / Action / Registry。注册表确定性排序、结构校验、Feature 环检测。`SettingsSemanticCatalog` 收录 47 个设置（覆盖 8 个模块及计划中的复杂案例）。 |
| 2 依赖解析与约束 | ✅ 完成 | `SettingsPlanner`：Feature 依赖闭包、`onChange` 连带修改（虚拟设置镜像）、`distinctValues→swap`、`minimumCount/requires/numericRange`、类型/范围校验、确定性、幂等。 |
| 3 统一 SettingsService | ✅ 完成（内存 provider） | list/describe/snapshot/preview/apply/restore；预览不改状态、apply 全量校验后一次写入并捕获 before。`SettingsStateProvider` 协议预留各领域 provider。 |
| 4 复杂模块适配 | ✅ 核心完成 | `CoreSettingsProvider` 把 47 个 core 设置经真实 `@Published`/setter 读写（含 hardwareRingConfiguration 嵌套、ring slots 领域 setter、boldText 虚拟设置）。未接入的领域：Localization/LaunchAtLogin（非 core，返回 nil）。 |
| 5 Capability/Action/权限 | ✅ 完成 | Capability/Action 描述符 + `SettingsAccessPolicy`；`SettingsStateEvaluator` 实现 effective/available/enabled 三态判定；`SystemSettingsCapabilityProvider`（ui.liquidGlass 实测，其余 unknown）。`overridden` 状态预留。 |
| 6 Development Profile | ✅ 完成 | `DevelopmentTestProfile`/Validator/Bootstrap + `CoreSettingsProvider`；`AppEnvironment.live` 在迁移后、监控启动前应用；`.dev-profile.example.json`；`build-app.sh` 仅开发版身份签名前嵌入 + `STAllowsDevProfile` 标记；加载仅开发构建生效。 |
| 7 Schema 导出 + Skill | ✅ 完成 | `SettingsSchemaExporter` 确定性输出 5 份 JSON + 每模块 md；`.agents/skills/status-trio-settings/`（SKILL.md + references）。 |
| 8 AGENTS.md | ✅ 完成 | 新增 Development Test Profile 规范与"新增设置必须同步语义定义"。 |
| 9 性能/体积 | ◑ 静态测量 | 见 §5；运行时/包体/冷启动为 NOT RUN。 |
| 10 测试 | ◑ 部分 | 新增 5 个测试套件（见 §4）；§13.4 监控生命周期、真实硬件、完整 UI 回归未覆盖。 |

## 2. 架构

```
Settings/Semantic/  纯数据语义层（Foundation-only，可独立编译）
  SettingsValueType / SettingsCondition(强类型组合) / SettingsConstraint
  SettingsAccessPolicy / SettingsPerformanceImpact / SettingsOptionDescriptor
  SettingsMutationDescriptor / SettingsPreferenceDescriptor
  SettingsFeatureDescriptor / Capability / Action / SettingsSemanticRegistry
  SettingsSemanticCatalog        ← 作者维护的注册表内容
Settings/Service/   规划与服务层
  SettingsMutationPlanning       ← SettingsSnapshot/Plan/Planner（纯函数）
  SettingsService                ← 统一入口 + SettingsStateProvider 协议
Settings/Development/ 开发测试配置
  DevelopmentTestProfile(模型+Validator+Loader) / DevelopmentProfileBootstrap
Settings/Schema/    SettingsSchemaExporter（确定性 JSON/Markdown 导出）
```

设计原则：语义层不读 UserDefaults、不探测硬件、不发网络请求；planner 是纯函数
（输入 snapshot，输出 plan）；apply 由 service 通过 provider 在业务接口上提交；
预览绝不调用 setter。

## 3. 对外接口（内部）

```swift
SettingsService.listPreferences() / describePreference(id:) / listFeatures()
SettingsService.snapshot() -> SettingsSnapshot
SettingsService.preview(enableFeature:) / preview(setPreference:to:) / preview(mutations:) / preview(features:preferences:mutations:)
SettingsService.apply(_:) / apply(enableFeature:) / apply(setPreference:to:) -> SettingsApplyResult
SettingsService.restore(_:)
```

未来外部 IPC/CLI/MCP 只需在此接口之上加适配层，无需改本层（本阶段不实现）。

## 4. 测试证据（本次实际运行通过）

| 套件 | 用例 | 结果 |
|---|---|---|
| `SettingsSemanticRegistryTests` | 9 | ✅ 全通过 |
| `SettingsMutationPlannerTests` | 9 | ✅ 全通过 |
| `SettingsServiceTests` | 5 | ✅ 全通过 |
| `DevelopmentProfileTests` | 8 | ✅ 全通过 |
| `SettingsSchemaExporterTests` | 6 | ✅ 全通过 |
| `SettingsEffectiveStateTests` | 6 | ✅ 全通过 |
| `CoreSettingsProviderTests` | 4 | ✅ 全通过（真实 SettingsStore） |

运行方式：`bash scripts/test.sh '<Suite>'`（含 forbidden-pattern 检查）。
`swift build -c release --target StatusTrioCore` 通过（116s）。

## 5. 性能与体积（静态测量）

| 指标 | 结果 | 说明 |
|---|---|---|
| 语义层 release 单架构 dylib（`-O`，未 strip，含全部 4 个目录） | ≈ 0.7 MB（723,120 bytes） | 上界估计，已低于 1 MB 目标 |
| standalone exporter 可执行（含 model+catalog+export） | ≈ 0.56 MB | 上界 |
| 新增后台进程 / 定时器 / 轮询 | 0 | 纯数据与服务，无运行时常驻 |
| 正式版默认值变化 | 0 | 未改任何 SettingsStore 默认或存储格式 |
| 未使用配置服务时是否生成完整 Schema | 否 | 导出为离线工具，不在启动路径 |

**NOT RUN（需真实签名 App Bundle 与运行环境）**：App 包体增量、可执行/Core 库
增量、DMG/ZIP 压缩体积、空闲 CPU、常驻内存/physical footprint、冷启动时间、打开
设置页面性能。方法论见计划 §12.3，须在同一工具链/配置/架构/签名下对比重构前后。

## 6. 明确未完成 / 后续

1. **覆盖率到 100%**：当前 `SettingsSemanticCatalog` 描述 47/128 个 user-visible 设置。
   其余（大量电池标记/颜色、音频设备排序、图标子来源、蓝牙设备级等）需补进目录；
   每补一个都要在 `docs/settings/settings-inventory.md` 对上。
2. **运行时 Capability provider 与 Effective State**：用现有缓存/系统信息给出
   available/unavailable/unknown（unknown≠不支持），不为查 Schema 启动采集。
3. **真实性能/体积测量**：需签名 App Bundle 与运行环境，按 §12.3 对比前后。
4. **§13.4 监控生命周期测试**：验证父模块自动开启不无条件启动全部采集等。

已完成的启动闭环：dev build 启动 → `AppEnvironment.live` 在迁移后、控制器/监控
启动前 → `DevelopmentProfileBootstrap` 校验→预览→经 `CoreSettingsProvider` 写入
真实 SettingsStore → 日志输出。

## 7. 未改变的契约（防回归）

- 未修改 `SettingsPreferenceCatalog` 导入导出白名单与文件格式。
- 未修改 SettingsStore 默认值、UserDefaults Key、图标迁移/同步逻辑。
- 未新增常驻服务、轮询、第三方运行时。
- 正式发行版：`build-app.sh` 仅在 `DEVELOPMENT_CODENAME` 非空且 bundle id 为
  `com.lingsmbp.StatusTrio.dev.*` 时嵌入 profile；加载逻辑另要求 `STAllowsDevProfile`
  标记或 codename，正式版永不加载。
