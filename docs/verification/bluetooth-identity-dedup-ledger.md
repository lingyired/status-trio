# 蓝牙身份修复执行记录

## 目标和基线

- 用户九阶段计划为执行规范；仅在独立 worktree 开发、提交，不合并、不发布。
- 分支：`fix/bluetooth-identity-dedup`。
- 已 fetch，起点与 `origin/main` 均为 `2208201ad23ed6f1b9e5e4a9f7ddaa01ced383ab`。
- 不按名字认定物理身份；不添加硬件读取、扫描、权限或定时器；保留偏好存储格式。

## 任务状态

1. 审计与复现：进行中。
2. Trusted 当前发现与历史元数据分离：待执行。
3. 纯 Swift 证据约束解析：待执行。
4. 共享显示、排序及隐藏别名：待执行。
5. Magic Mouse 精确 MAC 电量：待执行，独立提交。
6. 回归、full 验证、最终审查与报告：待执行。

## 已核实事实

- `BluetoothDeviceListPresentation.sharedDisplayRows` 按名字分桶，仅当桶里恰好一条 BLE 和一条 trusted 且具体手机/平板型号相等时临时折叠；Watch 不参与。此规则没有证明物理身份。
- `AppleDeviceCatalog.projection` 为所有候选创建行，无快照也创建；调用方把持久历史 metadata 与当前 discovery candidates 相加。
- `SettingsStore.updateTrustedAppleDeviceMetadata` 以 ID 累积 metadata，从不删除历史记录。这些记录本身仍有保留价值，问题在实时投影。
- `BluetoothBatteryLevelFallback.resolveGroupOwner` 根据名字及型号选设备，尚无 Accessory Identifier 精确 MAC 路径。双同型号鼠标因此可能拒绝合法 98% 读数。
- 实际 accessory reader 位于 Monitoring，计划中的 Models 路径已过时。
- `BluetoothDeviceIdentity.preferenceKey` 现有存储规范必须保留。

## 判定

- Ruling: 用户已经给出详细且批准执行的方案，不额外执行产品头脑风暴/等待确认；按计划 inline 执行。身份不足保留多条，不能编造 S2 映射。
- Ruling: 复现夹具使用合成 MAC/ID 和用户给定 98% 事实，不能声称已取得原始日志；继续查找仓库现有匿名日志。

## 验证记录

- 复现测试 `BluetoothIdentityCollisionRegressionTests`：修复前 3 个失败（同 MAC 两种格式两行、双同型号鼠标无法按精确 MAC 归属、明确不匹配 MAC 仍回落型号给错鼠标 98%），其余安全用例通过；修复后全部通过。
- 生命周期测试 `AppleIdentityLifecycleRegressionTests` 修复前因 API 不存在编译失败，修复后通过。
- 已运行并通过：Bluetooth 全量（245）、Apple 设备相关、计划指定回归集合；Battery fallback 原 48 个 XCTest 全部通过。

## 已实现改动

1. `AppleDeviceCatalog.currentCandidates`：历史 metadata 与当前发现分离；只有当前发现、上一轮成功发现 ID、或 1200 秒内有效快照的已验证历史身份进入显示投影。`lastSuccessfulIDs == nil` 保留历史（初始化/失败/权限）。不删除 `trustedAppleDeviceMetadata`。
2. `AppleDeviceDiscoveryController.lastSuccessfulCandidateIDs`：仅完整无失败（任何路由失败都不算）的周期发布；清空候选时复位为 nil。
3. `SystemStatusStore` 镜像并传给面板、设置页。
4. 新增 `BluetoothDeviceIdentityResolver`：S1 精确来源身份（标准化 MAC、BLE UUID、Trusted/Watch 稳定 ID）才合并；代表行按内容稳定选择；无证据不跨来源。
5. `sharedDisplayRows`/`uniquelyIdentifiedDevices` 先精确解析，再保留原有单对手机/平板展示折叠（仅展示层，不持久、不外溢）。
6. `BluetoothBatteryLevelFallback`：`Accessory Identifier` 为六字节 MAC 时按地址精确匹配并校验 vendor/product；明确携带 MAC 时不回落名称/型号；断连不供能；profiler 电量仍优先；AirPods UUID 路径不变。


## 复现矩阵（修复前）

| 场景 | 当前实际结果 | 判定 |
| --- | --- | --- |
| MAC 相同、分隔符不同的来源 | 2 行 | 已证实身份规范化缺陷 |
| 同名不同 MAC 的鼠标 | 2 行 | 正确，必须保留 |
| 一条系统 + BLE + Trusted 同名手机 | 3 行 | 身份不足，不能认定缺陷 |
| 同名不同 Trusted ID | 2 行 | 正确，必须保留 |
| 双同型号鼠标，pmset 精确连接 MAC | 无电量 | 已证实归属缺陷 |
| 只有一台鼠标但 pmset MAC 属于别台 | 错显 98% | 已证实错误电量归属 |
| pmset MAC 对应断连鼠标或型号冲突 | 拒绝 | 正确，保留防护 |
| 元数据历史 ID，无当前发现/快照 | 仍造行 | 已由代码证实，测试待验证 |
| 新旧 BLE UUID 均在 180 秒期内 | 各自存活 | 无强映射不能合并；过期路径已有 TTL |
| Watch 同名、Parent ID 不同 | 不折叠 | 正确，无证据不得名称合并 |

原始日志未在仓库 docs 查到；测试仅使用用户给定事实构造匿名夹具，不能声称原案例所有重复都是同一物理设备。

## 提交

- `612bbe3f fix(bluetooth): constrain stale Apple device projections`
- `5f452c7a refactor(bluetooth): introduce evidence-based identity resolver`
- `e427cfea fix(bluetooth): match accessory battery by exact MAC`
- 待提交：验收报告与执行记录；最终 full 验证结果补录于此。

## 最终验证

- `bash scripts/verify-local.sh full`：PASS，mode=full，head=`818a5b91`，分支 `fix/bluetooth-identity-dedup`。
- 全量 Swift：3119 tests，99 skipped，0 failures；包含 Release 构建、非 Universal 本地 app bundle 及 platform/SDK、Helper、mobile battery、依赖与离线发布脚本检查。
- 不替代：签名、公证、DMG、正式 release CI、Universal 打包、macOS 13/macOS 26+ 真机运行验收（NOT RUN）。
- 额外提交 `818a5b91 fix(bluetooth): require address-shaped text for MAC identity`：阻止 `xyz02:00:…` 这类非地址文本被宽松规范化成真实 MAC。
