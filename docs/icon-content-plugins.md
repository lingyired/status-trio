# 内置图标内容插件

图标的内置内容通过 `Presentation/Icon/Plugins` 注册。插件接收宿主提供的快照并返回有类型的绘制状态；宿主负责首选/备用选择、异常临时覆盖、配色、统一尺寸、监控和实际渲染。

当前只支持编译进应用的模块。没有外部包安装、动态二进制或脚本执行接口；这些协议尚不是对外稳定 API。

## 内置目录

| 插件 ID | 呈现 ID | 位置 |
| --- | --- | --- |
| `builtin.system-battery` | `ring` / `percentage` | 外环 / 中心 |
| `builtin.airpods-battery` | `ring` | 外环 |
| `builtin.network` | `center` | 中心 |
| `builtin.input-source` | `center` | 中心 |
| `builtin.bluetooth-device` | `output` / `connected` | 中心，编辑器合并为一个蓝牙入口 |
| `builtin.system-volume` | `footer` | 底部 |
| `builtin.bluetooth-device` | `pinned-glyph` | 中心，仅保留旧配置 |
| `builtin.legacy` | `ring` / `center` | 外环 / 中心，仅保留旧配置 |

“无”是宿主的隐藏操作，不是需要启动的插件。注册器拒绝空 ID、重复插件 ID和同插件重复呈现 ID；不同插件可使用相同呈现名。编译内置目录只构造一次。

## 增加内置内容

1. 在 `Plugins/Builtin` 新建实现 `IconContentPlugin` 的类型。描述包含唯一插件 ID、每种呈现的位置、名称、用途和可选择性。
2. 实现 `resolve(presentationID:context:)`。只读 `context.inputs`、`configuration`、`legacy` 和 `now`，返回 `.available(.outerRing(...))`、`.available(.center(...))`、`.available(.footer(...))` 或 `.unavailable(reason)`。不能读设置、枚举设备或启动异步工作。
3. 声明 `dependencies` 和 `capabilities`：样例按来源去重；音频专用设置只对真实音频目标开放；权限和后台读取的同意仍由宿主检查。
4. 在 `BuiltinIconPlugins` 注册。若呈现需要 V1 持久化，在 `IconContentLegacyAdapter` 增加明确双向映射与相应 V1 存储支持；未知绑定不能伪装成现有来源。外部安装前必须另行设计版本化插件绑定存储。
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

把该模块注入测试 registry，再调用 `IconPluginSlotResolver` 可验证非 V1 绑定的解析。它仅用于测试，不应注册到生产目录，也不意味着该 ID 可被当前 V1 配置保存。`IconContentPluginResolutionTests` 另以测试模块替换内置电池/网络，验证实际 `IconCompositionResolver` 的输出由注册器决定。

## 数据和规则

每个候选在一次槽位解析中至多解析一次。首选失败且备用成功时，trace 保留首选失败原因和真实选中来源；首选为无时不查询备用。来自插件的 payload 必须匹配声明的位置。

网络异常覆盖由宿主决定，设置 `isAlertOverride` 后请求网络插件的警告表示。因此“Wi-Fi 关闭”虽然可使普通网络来源不可用，仍能按照已开启的全局规则显示警告；恢复后返回原首选/备用选择。

`IconContentDependencyResolver` 聚合有效配置的首选、备用和网络覆盖依赖。`IconSourceDemandBridge` 继续持有自身的 owner token，维持显式电量读取同意及连接条件；插件只声明需求，不直接控制监控。其他功能持有的需求不会被图标释放。

## 编辑与预览

主窗口在右侧固定元素切换，先编辑首选内容及显示方式，再调整共享外观。备用内容有自己的折叠区、目标选择和专用设置；网络异常规则位于中心的“提醒与切换”。旧静态图案和 automaticLegacy 继续可解析，但不会作为新内容选项出现。

V1 只有一份指定蓝牙设备地址。每个目标选择器根据自己编辑的首选/备用来源显示选中项；改为当前音频输出时保留其他来源仍引用的地址。会让主/备用变成同一来源的目标选项不可选择，宿主也会拒绝，防止 normalization 意外删除备用内容。需要授权、明确设备选择或重新连接的备用内容，在折叠时仍保留提示与设置入口。

中心首选为“无”时，若全局网络异常规则开启，网络警告仍是可达的绘制内容，因此保留相应外观与尺寸控件；关闭规则后隐藏这些无效设置。

大预览下只保留一份当前显示说明，名称来自 trace，数字只采用已解析的绘制文字。不能从弧线反推原始百分比，因为满电阈值等规则会改变几何比例。右侧仍明确当前编辑的首选/备用内容。

折叠状态、选中元素、模拟数据和预览底色仅存于 `IconDesignerPreviewSession`。它们不写 defaults，不进入撤销，不改变真实菜单栏/Dock。模拟面板保持独立 `NSPanel`，相同来源在多个元素使用时共用一份样例。

## 验证

```bash
swift test --filter 'IconContentPluginRegistryTests|IconContentLegacyAdapterTests|IconContentPluginResolutionTests|IconContentDependencyTests|IconDesignerInspectorModelTests'
swift test
swift build -c release
swift test --filter Issue30WiFiAlignmentTests
```

涉及 SwiftUI bindings、actor 或 generics 的合并/发布，还需遵循 AGENTS.md 的非发布 release CI；本地较新工具链与模拟测试不替代 CI 或真实硬件验收。
