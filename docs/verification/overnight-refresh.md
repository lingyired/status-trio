# #255 双电源刷新间隔 — 验证记录

- 分支：`overnight-panel-color-refresh`
- 基线：`origin/main=d4598847040a5b2d167ec3825c162270eba3492b`（本记录基于 HEAD `d4598847` + 未提交工作树改动）
- 负责人：refresh-interval（task-2）
- 日期：2026-11-06

## 实现摘要

### 设置与迁移

- 新增两个持久设置：
  - `refreshIntervalOnBatterySeconds` → key `statusRefreshIntervalOnBatterySeconds`
  - `refreshIntervalOnPowerSeconds` → key `statusRefreshIntervalOnPowerSeconds`
- 两者范围均为 `5...60`，步进 1 秒，默认 15 秒。
- 旧 key `statusRefreshIntervalSeconds` 保留为迁移来源：
  - 每个新 key 独立判断：新 key 存在时以新值为准；
  - 新 key 不存在、旧 key 存在时从旧值迁移并写入该新 key；
  - 两者都没有时使用默认 15；
  - 迁移只写缺失的新 key，不覆盖已存在的新值，也不改写旧 key。
- 非有限值（NaN/∞）回退默认 15；越界值夹紧到 `5...60`；新设置按整秒夹紧，不再像旧设置那样取整到 5 的倍数。
- 纯选择逻辑：`refreshInterval(forPluggedIn:)`；有电池且未接电用 battery，其余（含台式机无电池、接电）用 power。判断只看“电池是否存在 + 是否接电”，不看 `isCharging`。

### 生产传播

- `StatusBarController` 用 `CombineLatest3` 组合两个设置与“去重后的电源类型 Bool”：
  - 先把 `snapshot.battery` 映射为 `effectivePluggedIn`（无电池视为接电），再 `removeDuplicates()`，无关 snapshot 变化不会重建等待；
  - 计算出的最终 `Duration` 再 `removeDuplicates()`，仅秒数真正变化才通知 `SystemStatusStore`。
- `SystemStatusStore.setRefreshInterval`：
  - 间隔变化时取消旧等待并立即启动新周期；
  - 只重启等待任务，不重启硬件 monitor，不额外立即刷新，不新增 timer；
  - 未 `start()` 前只记录值（由 `start()` 的第一次等待使用），`stop()` 后不复活轮询；
  - 同值调用直接返回。
- `AppEnvironment` 生产路径改用 `settings.refreshInterval(forPluggedIn: false)` 作为初始值（store 初始快照为“有电池、未接电”的占位值），随后由 `StatusBarController` 订阅按真实电源状态修正。旧 `refreshInterval` API 保留以兼容内部旧测试。

### 设置界面

- `GeneralSectionView` 改为两行滑条：
  - “使用电池时” / “接通电源时”，均整秒步进；
  - 当前生效的一行显示“生效中”标记；
  - 台式机（无电池）显示电源行为生效项。
- `LocalizationKey` 新增 3 个键并在 12 种随包语言（`ar, de, en, es, fr, it, ja, ko, pt-BR, ru, zh-Hans, zh-Hant`）全部补齐：
  - `settings.refreshInterval.onBattery`
  - `settings.refreshInterval.onPower`
  - `settings.refreshInterval.active`

## Red → Green 证据

### RED（旧 `SystemStatusStore`，保留新测试）

临时用 `git checkout -- Sources/StatusTrioCore/Store/SystemStatusStore.swift` 还原该文件（仅本任务独占文件），跑：

```
bash scripts/test.sh 'testChangingRefreshIntervalRestartsTheWaitImmediately'
```

结果 `EXIT=1`，失败：

```
SystemStatusStoreTests.swift:2683: error: -[StatusTrioCoreTests.SystemStatusStoreTests testChangingRefreshIntervalRestartsTheWaitImmediately] : failed - Timed out waiting for the expected state
SystemStatusStoreTests.swift:64: error: -[... testChangingRefreshIntervalRestartsTheWaitImmediately] : XCTAssertEqual failed: ("[15.0 seconds]") is not equal to ("[15.0 seconds, 5.0 seconds]") - a cadence change must cancel the old wait and start the new one
Executed 1 test, with 2 failures
```

随后用预先保存的 patch 恢复该文件；`git diff --stat -- Sources/StatusTrioCore/Store/SystemStatusStore.swift` 仍为 `1 file changed, 16 insertions(+)`，`startRefreshTask` 与 `guard hasStarted, !hasStopped` 均在。整模块编译通过（Build complete 19.62s）。

### GREEN

```
bash scripts/test.sh 'RefreshIntervalTests|testChangingRefreshIntervalRestartsTheWaitImmediately|testSettingTheSameRefreshIntervalDoesNotRestartTheWait|testChangingRefreshIntervalAfterStopDoesNotRestartTheWait|testRefreshIntervalSetBeforeStartIsUsedByTheFirstWait|SettingsStoreTests/testRefreshInterval'
```

`EXIT=0`：`RefreshIntervalTests` 8 个 Swift Testing 全通过；`SystemStatusStoreTests` 4 个新生命周期用例通过；旧 `SettingsStoreTests/testRefreshInterval*` 2 个通过。

```
bash scripts/test.sh 'SettingsStoreTests|SystemStatusStoreTests'
```

`EXIT=0`：`Executed 211 tests, with 0 failures`（SettingsStore 132 + SystemStatusStore 79）。

```
bash scripts/test.sh 'LocalizationParityTests|LocalizationTests|SettingsViewTests'
```

`EXIT=0`：`Executed 51 tests, with 0 failures` + 1 个 Swift Testing 用例通过；覆盖 12 语言键完整性与 `GeneralSectionView` 渲染。

每次 `scripts/test.sh` 已包含 `check-forbidden-patterns.sh`，均通过。

## 新增回归测试

- `Tests/StatusTrioCoreTests/RefreshIntervalTests.swift`（Swift Testing）：
  - 默认 15、两电源选择；
  - 旧值迁移到两个新 key、单 key 独立迁移、新 key 优先；
  - 修改一个电源不覆盖另一个迁移值、旧 key 不被改写；
  - 1 秒步进夹紧、NaN 回退、越界夹紧并持久化；
  - 台式机视为接电、未接电（即使 `isCharging` 为真）选 battery。
- `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`（XCTest）：
  - 改间隔立即取消旧等待并立刻进入新等待；
  - 同值不重建等待；
  - stop 后改间隔不复活轮询；
  - start 前设置由第一次等待采用。
- 旧 `SettingsStoreTests` 的 `refreshIntervalSeconds` 用例保持通过（旧 API 兼容）。

## 未验证 / 交接注意

- 未跑 `verify-local.sh full` 全量交付档（由 lead 在最终集成树上执行）。
- 未做真实 GUI / 菜单栏 / Dock 视觉验证；两行滑条与“生效中”标记的观感、键盘与辅助功能仅代码审查 + 渲染测试覆盖，未做后台 UI 截图。
- 未做 macOS 13 真机运行验证（本机工具链编译与单测不等同运行时证据）。
- 未 commit / merge / push；未启动 GUI。
- 本任务移交共享文件：`SettingsStore.swift`、`GeneralSectionView.swift`、`StatusBarController.swift`、`SystemStatusStore.swift`、`LocalizationKey.swift`、`Resources/*/Localizable.strings`。Task 3（蓝牙）可在移交后整合这些文件；本任务之后不再写这些共享文件。
