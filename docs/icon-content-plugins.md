# 图标内容插件

图标内容通过 `Presentation/Icon/Plugins` 注册。插件接收宿主提供的快照并返回有类型的绘制状态；宿主负责首选/备用选择、异常临时覆盖、配色、统一尺寸、监控和实际渲染。

内容来源有两类：

- **内置插件**：编译进应用的模块，ID 以 `builtin.` 开头。
- **本地 JSON 包**：用户显式启用的目录，只读取固定文件 `manifest.json` 和 `data.json`，不加载动态二进制、不执行脚本。包目录只是数据边界，写文件由用户自己的生产者负责。

两类来源都通过 `IconSlotBindingsV1` 保存到外环、中间和底部槽位。主绑定为空表示隐藏；未知或暂时缺失的插件 ID 会保留并进入备用链，包恢复后原选择自动生效。

## 内置目录

| 插件 ID | 呈现 ID | 位置 |
| --- | --- | --- |
| `builtin.system-battery` | `ring` / `percentage` / `footer` | 外环 / 中心 / 底部 |
| `builtin.airpods-battery` | `ring` | 外环 |
| `builtin.network` | `center` / `footer` | 中心 / 底部（Wi-Fi 信号） |
| `builtin.input-source` | `center` | 中心 |
| `builtin.bluetooth-device` | `output` / `connected` | 中心，设置页合并为一个蓝牙入口 |
| `builtin.system-volume` | `footer` | 底部 |
| `builtin.bluetooth-device` | `pinned-glyph` | 中心，仅保留旧配置 |
| `builtin.legacy` | `ring` / `center` / `charging-status` / `power` | 外环 / 中心，仅保留旧配置 |

“无”是宿主的隐藏操作，不是需要启动的插件。注册器拒绝空 ID、重复插件 ID和同插件重复呈现 ID；不同插件可使用相同呈现名。编译内置目录只构造一次。

## 本地 JSON 包（暂未开放）

当前版本隐藏设置入口，也暂停读取已保存的包目录。以下说明供将来开放功能时参考。

### 目录与启用

用户在 **App 图标 → 本地 JSON 插件** 里选择一个包目录。目录必须同时包含：

```text
MyLatencyPlugin/
├── manifest.json
└── data.json
```

每个文件最多 16 KiB。宿主以 `O_NOFOLLOW | O_NONBLOCK` 打开固定文件名，再在打开后检查类型，拒绝符号链接、FIFO 等非普通文件，并在读取过程中再次限制字节数。包目录名本身不参与 ID 解析。

预留的外部入口面向 Direct 构建，启用后读取用户选定的目录。当前分支没有已验证的 App Store entitlement 或持久目录授权管线，因此沙箱构建完全隐藏外部包入口，也不会解析已保存的裸路径；内置来源保持不变。

### manifest.json

schema 1：

```json
{
  "schemaVersion": 1,
  "pluginID": "com.example.latency",
  "title": "Latency",
  "presentations": [
    { "id": "value", "slot": "center", "kind": "text" }
  ]
}
```

- `pluginID` / 呈现 `id`：ASCII 字母、数字、点、下划线或连字符，长度 1–128。插件 ID 不能以 `builtin.` 开头。
- `title`：显示在设置菜单里的包名称，最多 128 字符。
- 每个包最多 16 个呈现。
- 中间槽位只允许 `text`；外环和底部只允许 `fraction`。
- 两个已启用包使用同一个 `pluginID` 时，两个包都不可选，用户已保存的绑定不会被改写。

### data.json

```json
{
  "schemaVersion": 1,
  "observedAt": "2026-11-20T10:00:00Z",
  "values": {
    "value": "42 ms"
  }
}
```

- `observedAt` 为 UTC ISO 8601，可带小数秒。
- 时间超前当前时间 2 秒以上拒绝；15 秒后读数失效并回退。
- 同一包内更旧的读数不能覆盖仍在使用的新读数。
- `text` 最多 16 个字符，拒绝控制字符。
- `fraction` 必须有限且在 `0...1`。
- 缺失文件、畸形 JSON 或不合法值立即回退；脚本停止写入时由宿主按过期截止清理，不需要轮询。

### 原子替换示例

生产者应写临时文件再 rename，避免宿主读到半截 JSON：

```bash
#!/bin/bash
set -euo pipefail
pkg="$HOME/Library/Application Support/StatusTrio/Plugins/MyLatencyPlugin"
tmp="$(mktemp "$pkg/.data.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<JSON
{"schemaVersion":1,"observedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","values":{"value":"57 ms"}}
JSON
mv -f "$tmp" "$pkg/data.json"
```

宿主监听目录变更，因此 `mv` 原子替换会触发重新读取；不需要重启应用。

### 权限说明

- 用户只应启用自己信任的包目录。宿主不会上传、复制或执行包内容。
- 目录里的其他文件不会被读取；只打开固定文件名。
- 包目录和 `data.json` 的写权限属于用户；应用只需要读权限。
- 包被禁用或删除后，槽位按已保存的备用绑定显示；重新启用并恢复读取后原绑定自动恢复。

## 增加内置内容

1. 在 `Plugins/Builtin` 新建实现 `IconContentPlugin` 的类型。描述包含唯一插件 ID、每种呈现的位置、名称、用途和可选择性。
2. 实现 `resolve(presentationID:context:)`。只读 `context.inputs`、`configuration`、`legacy` 和 `now`，返回 `.available(.outerRing(...))`、`.available(.center(...))`、`.available(.footer(...))` 或 `.unavailable(reason)`。不能读设置、枚举设备或启动异步工作。
3. 声明 `dependencies` 和 `capabilities`：样例按来源去重；音频专用设置只对真实音频目标开放；权限和后台读取的同意仍由宿主检查。
4. 在 `BuiltinIconPlugins.makePlugins()` 注册。若呈现需要版本化持久化，在 `IconContentLegacyAdapter` 增加明确映射；外部/未知绑定不能伪装成现有来源。
5. 扩展纯模型、实际组合分发、依赖、菜单栏/Dock parity 及兼容测试，补齐全部 12 语言。只有新增专用设置时才增加 UI 控件；尺寸和配色继续使用宿主标准。

可用以下测试模块验证接口，不需要启动系统设备：

```swift
struct ExampleIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "test.example", presentations: [
        .init(id: "text", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        .available(.center(.text(IconTextState(text: "T", color: .primary, scale: 1))))
    }
}
```

把该模块注入测试 registry，再调用 `IconPluginSlotResolver` 可验证非内置绑定的解析。它仅用于测试，不应注册到生产目录。

## 数据和规则

每个候选在一次槽位解析中至多解析一次。首选失败且备用成功时，trace 保留首选失败原因和真实选中来源；首选为无时不查询备用。来自插件的 payload 必须匹配声明的位置。

网络异常覆盖由宿主决定，设置 `isAlertOverride` 后请求网络插件的警告表示。因此“Wi-Fi 关闭”虽然可使普通网络来源不可用，仍能按照已开启的全局规则显示警告；恢复后返回原首选/备用选择。

宿主从实际解析结果发布 `IconPresentationDemand`：`selectedBindings` 决定当前绘制所需的依赖，`subscribedBindings` 额外保留仍然可见的外部主绑定，使包暂时不可用时仍能恢复。硬件指标、蓝牙和 AirPods 采样由这份需求驱动，而不是由图标图片是否变化驱动。`IconLiveSourceCoordinator` 对同一绑定的多个槽位/表面去重，并通过 generation token 丢弃迟到的旧回调。

`IconSourceDemandBridge` 继续持有自己的 owner token，维持显式电量读取同意及连接条件；插件只声明需求，不直接控制监控。其他功能持有的需求不会被图标释放。

## 设置与迁移

运行时从 `IconSlotBindingsV1` 读取槽位选择。首次运行没有该存储时，从当前有效的外环、中间和底部分项设置一次性迁移，并原样保留旧 defaults 键。损坏或更高版本的数据保留原始字节，本次运行退回分项设置，不覆盖用户数据。

内置来源仍可通过原设置控件切换，控件写入会同步对应的主绑定。外部来源在现有槽位页面新增的“本地 JSON 来源”菜单里选择；选择“无”会保留原备用绑定，内置来源入口始终可用。

已停用的 2.0 图标设计器不参与运行时写回、编辑、撤销或检查器；保留的颜色控件、预览和资源继续服务当前设置页。

## 验证

```bash
swift test --filter 'LocalIconPluginTests|IconSlotBindingPersistenceTests|IconLiveSourceCoordinatorTests|IconContentPluginRegistryTests|IconContentLegacyAdapterTests|IconContentPluginResolutionTests|IconContentDependencyTests'
swift test
swift build -c release
swift test --filter Issue30WiFiAlignmentTests
```

涉及 SwiftUI bindings、actor 或 generics 的合并/发布，还需遵循 AGENTS.md 的非发布 release CI；本地较新工具链与模拟测试不替代 CI 或真实硬件验收。
