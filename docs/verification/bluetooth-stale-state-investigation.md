# 蓝牙耳机电量与连接状态滞后调查

## 范围与结论

- 时间：2026-11-08 至 2026-11-09（Asia/Shanghai）。
- 基线：已 fetch 的 `origin/main`，`96ca37d549a6f2b89ecdcaf0581f0fd3e6fabfe7`。
- 分支：`bluetooth-stale-battery-connection`；独立 worktree，未合并、未推送。
- 用户反馈：耳机实际约 30%，App 仍显示九十几；耳机放回仓断开后，App 仍显示连接。

**代码允许出现这两种显示滞后，但还没有用户耳机的真机复现证据，不能认定它们一定由同一个原因造成。**

发现并补上一个断连通知注册缺口：原来的监控只在收到 connect 回调时为设备安装 disconnect 观察者。打开面板时已经连接的配对设备，没有显式安装 disconnect 观察者的路径。若 SDK 不补发该设备的 connect 回调，断连只能依靠后续刷新发现。SDK 头文件将 connect 通知描述为发生新连接时的通知，并未保证补发已有连接。

补丁在启动监控时，为当前已连接的配对设备补注册 disconnect 通知。它不额外发起蓝牙连接或扫描，不新增定时器；原有 stop 路径释放注册。实际 AirPods 入仓时是否及时送出该通知仍需真机验收。

## 数据来源与可能原因

### 连接状态

`SystemProfilerBluetoothPairedDeviceWorker.parse` 根据 `system_profiler -json SPBluetoothDataType` 的 `device_connected` / `device_not_connected` 段生成 `BluetoothDevice.isConnected`，面板据此显示状态。

正常收到连接事件后，控制器先清空旧电量，再经默认 750ms 去抖重读 profiler。若缺少通知，面板打开期间依靠默认 120 秒的安全网刷新；sleep 允许 24 秒容差。约两分钟是正常运行时的名义刷新间隔，**不是保证纠正显示的最长时间**：系统调度、读取失败、设备报告本身滞后等都可能延长它。

关闭面板会停止该监控；重开会重新读取，加载期间可能使用内存里的 `cachedDevices` 绘制占位内容。占位内容不等于一次新的硬件测量。

证据：

- `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`：解析 `device_connected` / `device_not_connected`、`refresh`、`schedulePeriodicRefresh`、`receiveConnectionEvent`。
- `Sources/StatusTrioCore/Monitoring/BluetoothConnectionEventMonitor.swift`：`start`、`deviceConnected`、`deviceDisconnected`。
- `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`：缓存列表与加载状态。

### 电量 30% 却显示九十几

配对设备的主电量来自 profiler；设备 worker 每次刷新重读报告，电量 worker 优先复用同一份报告。共享缓存默认最长复用 5 秒，单纯这个缓存不能解释长时间停在九十几。

主电量解析器只取 `device_connected` 段。若 profiler 没提供电量，`pmset -g accps -xml` 配件电源数据可按 identifier 安全匹配后补缺；它不会覆盖 profiler 已有电量，只给已连接设备补电量。

因此有几种需要区分的情况：

1. 面板尚未等到刷新事件或下一次安全网读取。
2. macOS 报告本身仍携带旧百分比；App 继续读取也会得到旧值。补断连观察不能让上游报告立即变新。
3. 用户对比的是不同通道（整机、左耳、右耳或耳机仓）。展示模型保留这些独立字段，需看实际截图或通道数值才能判断。

控制器在拿到断开的设备快照后，会过滤掉该地址的配对设备电量；连接通知也会使旧电量及在途读取失效。这部分已有防护，本次保留。

证据：

- `Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift`：只取已连接段，按 main/left/right/case 解析。
- `Sources/StatusTrioCore/Monitoring/BluetoothProfilerReportCache.swift`：`defaultMaxAge = 5`。
- `Sources/StatusTrioCore/Models/BluetoothBatteryLevelFallback.swift`：配件来源只补缺且按标识匹配。
- `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`：`connectedBatteryLevels`、电量请求 generation gate。
- `docs/known-limitations.md`：macOS 电量来源与 accessory 通知的限制。

### 其它路径

- nearby BLE 电量缓存寿命为 180 秒；其合并生成的行是 `isConnected: false`，不能直接解释已连接标记。配对设备匹配要求唯一同名且已连接。
- `MobileBatteryController` 默认缓存 1,200 秒，用于 iPhone/iPad/Watch 等 Apple 移动设备，不应据此解释普通耳机电量。
- 若 SDK 拒绝注册、未送出通知，或 profiler 仍报告已连接，仍会依赖原有刷新路径。补丁不承诺消除所有系统数据滞后。

## 修改与验证

修改：

- `BluetoothConnectionEventMonitor.start` 枚举当前已连接的配对设备，补注册断连观察；补注册本身不调用刷新 handler。
- 新增 token 生命周期回归测试，覆盖补注册后的断连清理、重连替换、停止清理及 SDK 返回 nil。
- 独立代码复核未发现阻断问题。SDK 枚举和 start 接线本身未用 fake 覆盖，实际硬件回调仍需人工验证。一次性 SDK 查询在调用线程同步执行，未做性能实测。

本地执行：

- `bash scripts/test.sh 'BluetoothConnectionEventTests'`：13 项通过，0 失败。
- `bash scripts/verify-local.sh full`：退出码 0；完整 Swift suite、Release build、本地单架构 bundle、平台/Helper/依赖契约与离线发布模拟通过。
- 全量 XCTest 汇总：4,091 项，82 项跳过，0 失败；Swift Testing：59 项通过，3 项跳过。
- 可见 UI fixtures 按项目默认跳过；没有启动 App 或操作用户桌面。
- macOS 13 真机兼容性、用户耳机电量对照、AirPods 入仓断连回调：NOT RUN。
- full 的验证对象是上述基线加本 worktree 的两个 Swift 未提交改动；这不是已发布版本、Universal 包、签名或公证证明。
- 交付时 `origin/main` 已前进至 `2d3fabd8`，比本分支多两个 Wi-Fi 设置提交（`ab2545e1`、`2d3fabd8`），与两个修改的 Swift 文件无路径重叠；未合入本分支，也未将本次 full 结果视为新 main 的集成验证。合并前需再次集成检查。
- 完整日志：`/tmp/status-trio-bluetooth-full.log`（本机临时文件）。

## 人工验收建议

1. 先连接耳机，再打开测试版面板；把耳机放回仓并合盖，观察连接状态是否在断开后及时消失。
2. 再测打开面板后才连接耳机的路径，以及反复关闭/重开面板。
3. 出现 30% / 九十几差异时，同一时间对照系统蓝牙界面、`system_profiler -json SPBluetoothDataType` 和 App 对应的左右耳/耳机仓字段。先确定上游报值是否一致，再判断是否需要进一步调整数据来源。

原始蓝牙报告含设备名称与地址；排查时只需分享相关设备的去标识字段，不需要完整报告。
