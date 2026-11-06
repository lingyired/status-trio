# #284 / #285 显示器修复验证

- 分支：`fix-display-284-285`
- 基线：`origin/main`，`d4598847040a5b2d167ec3825c162270eba3492b`（2026-11-06 开始时 fetch）
- 环境：Apple M3 Max、Xcode 27.0（27A266a）、Swift 6.4；内建 Color LCD + 外接 XV272U。
- 原工作区已有改动留在原处，本修复在独立 worktree 完成。

## #284：连续 DDC 亮度反馈

要求：首值及时发送，连续输入按受控频率发送最新值；每屏串行、有界待写；松手提交最终目标；硬件读后确认与 UI 目标值分开；停止、休眠及拓扑变化取消旧代请求。

旧实现的回归复现：新增测试先在原代码下得到 4 项失败，覆盖首值/连续输入饥饿、重复写入和旧回读。修复同时保留原有 10 秒按需监控刷新，没有增加空闲轮询。

整合审查发现：拓扑变化会重建 coordinator，仅在单个实例中串行仍不足以防止同屏新旧实例的物理事务重叠。最终实现按稳定 EDID UID 提供跨实例准入，每屏只有 1 笔在途与至多 1 笔最新待执行，不阻塞线程等待，不同屏独立；取消的待执行请求必须收到完成回调以释放实例状态。相关边界纳入回归。

## #285：外接屏目标映射

只读实机检查（不设置亮度、不启动应用）：

- XV272U 的真实 CG display ID 为 `5`，CG UUID 与 framebuffer 的 EDID UUID 不同。
- 外屏 `DisplayAttributes.ProductAttributes` 的 vendor/product/非零 serial 与在线 CG 显示器相符。
- `CGDisplayCreateUUIDFromDisplayID(0)` 与内建屏 ID `1` 返回相同 UUID，证实 `0` 不能当作有效外屏 ID。

修复保留 EDID UUID 作为直接 DDC 身份，同时为需要 CG ID 的后端提供唯一匹配的真实 ID。无法可靠映射时自动后端不可用；禁止把 `0` 或 CG 的 `display-N` 失败占位值当作目标。显式配置的 BetterDisplay UUID 仍可使用。

自动映射的保守限制：缺失/零序列号、身份不完整或匹配歧义时拒绝自动映射。该限制优先避免误控其他屏幕；支持无序列号设备的进一步映射方式不在本次证据范围内。

## 最终本地验证

- #284 聚焦：21/21 通过；跨实例测试先在旧代码下复现同屏重叠，修复后同屏等待、不同屏独立、替换/取消回调、准入 barrier 均通过。
- #285 聚焦：54/54 通过，涵盖匹配、目录、监控、BetterDisplay、面板映射与目标值发布。
- 独立只读审查：最终源代码未发现未解决的高/中问题；已处理跨实例重叠与取消时完成回调缺失。
- `git diff --check` 通过；交付前再次 fetch，`origin/main` 仍为上述基线。原工作区改动未改变。
- `bash scripts/verify-local.sh full`：**PASS，exit 0**。Core XCTest 2689 项（82 项按可见 UI 边界跳过，0 失败），Swift Testing 927 项/129 suites 通过；Release 构建、非 Universal Ad-hoc 应用包、平台/SDK、Helper/MobileBattery、原生兼容性契约及离线发布模拟均通过。
- 完整日志：`.build/local-verification/log.txt`（末尾 `Local verification passed: mode=full`，exit 0）；`status.txt` 仅在失败时记录步骤，成功时为空；外层留档：`.agent-artifacts/full-verify.log`。
- 完整验证开始前曾中止一轮，原因是审查发现跨实例串行缺口。上述 PASS 来自补齐后的最终源码，未沿用中止轮次的结果。

最终 DDC 源码 SHA256：`1632b7b4f0db64f2ecbbec250aaef6b4b1618bc67cbfc9b337b733bb5c2a3fee`。本次在上述基线加修复的树上验证，改动已提交到本地分支 `fix-display-284-285`，未推送、未合并。

## 验收包

- 应用：`dist/StatusTrio.app`（本地 arm64 Release，Ad-hoc 签名，非 Universal）
- 压缩包：`.agent-artifacts/StatusTrio-fix-display-284-285.zip`
- Bundle ID：`com.lingsmbp.StatusTrio.dev.fix-display-284-285`
- 显示名：`Status Trio (Fix Display 284 285)`，开发代号 `Fix Display 284 285`
- 版本：`1.9.3 (50)`
- 构建入口：`bash scripts/build-worktree.sh release no-open`，`codesign --verify --deep --strict` 通过

## 改动文件

- `Sources/StatusTrioCore/Display/DDCBrightnessCoordinator.swift`
- `Sources/StatusTrioCore/Display/DisplayIDMapper.swift`（新增）
- `Sources/StatusTrioCore/Display/DisplayCatalog.swift`
- `Sources/StatusTrioCore/Display/DisplayServicesBrightnessController.swift`
- `Sources/StatusTrioCore/Monitoring/BrightnessMonitor.swift`
- `Tests/StatusTrioCoreTests/DDCBrightnessCoordinatorTests.swift`
- `Tests/StatusTrioCoreTests/BrightnessMonitorTests.swift`
- `Tests/StatusTrioCoreTests/DisplayCatalogTests.swift`（新增）
- `Tests/StatusTrioCoreTests/DisplayIDMapperTests.swift`（新增）

## 实机验收步骤

1. 退出正式版 Status Trio，启动上面的验收包（不同 Bundle ID，不会覆盖正式版）。
2. 面板亮度区选择外接屏 XV272U，后端用默认直接 DDC：连续拖动数秒，观察拖动期间屏幕实际亮度是否连续变化；快速往返后松手，确认最终亮度与最后位置一致、没有旧指令追赶或回跳。
3. 设置 → 亮度：把 XV272U 后端切到 BetterDisplay，拖动外接屏亮度条，确认只有 XV272U 变化、内建屏亮度不变；再拖内建屏，确认外接屏不变。
4. 若测试 DisplayServices 后端：外接屏应作用于 XV272U，或明确显示不可用，绝不应改到内建屏。
5. 可再试休眠唤醒、拔插外接屏后重复第 2/3 步，确认无卡死或多屏互相影响。

## 实机验收尚未执行

以下均为 **NOT RUN**，自动测试与只读身份检查不能代替这些效果验证：

1. XV272U 使用直接 DDC 后端连续拖动数秒，松手前可见多次实际亮度变化；快速往返后最终亮度与最后目标一致，无旧指令追赶。
2. BetterDisplay 后端只改变选中的外屏，内建屏保持原亮度；内建亮度调节不影响外屏。
3. DisplayServices 后端目标正确；硬件不支持外屏时如实显示失败，不触及内建屏。
4. 慢响应设备、多外屏、真实休眠/断开/重连时的硬件表现。
5. macOS 13（Ventura）运行验证。

未启用可见 UI 测试，未发布、未合并、未关闭 issue。
