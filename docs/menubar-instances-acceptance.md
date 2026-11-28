# Menu Bar Instances — Manual Acceptance Matrix

Build: development bundle from this worktree (see `scripts/build-worktree.sh`).
Feature: `settings.tab.menuBarInstances` → 设置 › 菜单栏实例.

## How to test

1. Build the dev app for this branch: `bash scripts/build-worktree.sh` (or `release no-open`).
2. Open Settings › 菜单栏实例.
3. Add instances from the presets, edit them, and check the real menu bar.

## Cases

| # | Case | Expected |
|---|---|---|
| 1 | Add CPU preset | One status item shows `CPU 45%` (or current value) |
| 2 | Add two instances | Two independent status items; hiding/deleting one never removes the other |
| 3 | Two-line instance (top CPU usage, bottom CPU temp) | Both lines render, sharing one width |
| 4 | Single-line instance | Line is vertically centered |
| 5 | Empty value | Segment shows `--`, item stays in place |
| 6 | Inner/outer margin sliders | Item widens/narrows; no clipping |
| 7 | Value changes (CPU 45%→8%) | Item does not visibly jump (tabular digits; content-adaptive width) |
| 8 | Light / dark appearance | Text and inherited colours follow appearance |
| 9 | Retina display | Text and icons stay crisp |
| 10 | Column icon (leading icon) + row icon | Both render; text starts after the column |
| 11 | Click action = Summary | Opens the summary panel anchored under that instance |
| 12 | Click action = CPU/GPU detail | Opens the matching detail page anchored under that instance |
| 13 | Click action = App Settings | Opens Status Trio settings |
| 14 | Click action = Activity Monitor | Opens Activity Monitor |
| 15 | Click action = Wi-Fi settings | Opens the Wi-Fi pane |
| 16 | Right-click | Shows only “Disable This Instance” (intended); clicking it hides that instance, keeps its config |
| 17 | ⌘-drag one instance out of the menu bar | Only that instance is disabled; other items remain |
| 18 | Restart app | Instances return in best-effort position/order |
| 19 | Toggle an instance off then on | Item is hidden then restored (slot kept); sampling released while off |
| 20 | Export/import settings | Menu-bar instances round-trip; >20 instances rejected with a warning |
| 21 | Hover action = Summary/CPU | Hovering the instance opens that panel; it stays until you click elsewhere |
| 22 | Main icon untouched | Dock icon and main menu-bar icon behave exactly as before |

## Editor (v4)

Two columns: the left column lists instances (visibility switch, name, menu)
and a visible 新建 section with the blank instance and the ready-made presets;
the right column is the selected instance's editor. The editor is one
scrolling column: live preview, name/layout, menu-bar strip, the element
library under the strip, the selected-element inspector, row style, and
spacing/interaction.

| # | Case | Expected |
|---|---|---|
| E1 | 两栏布局 | 左实例列表 / 右编辑区；默认窗口宽度（720）下右栏不横向裁切，最小宽度（640）下也能滚动使用 |
| E2 | 新建空白/预设实例 | 左下“新建”区直接列出空白实例和 CPU 占用 / CPU 温度 / 内存占用 / 下载 / 电池温度 预设，点击即建；新建后自动选中并显示在右栏 |
| E3 | 元素库添加 | 元素库在“菜单栏条带”下方；先选“添加到 上行/下行”，点指标/文字/图标 chip 即加入该行并自动选中 |
| E4 | 元素库拖放 | 从元素库把 chip 拖进任一行，落在指定位置；行内/跨行拖动排序同样可用 |
| E5 | 文字与图标 | 可加自定义文字、SF Symbol、Emoji；选中后在“选中的元素”里编辑 |
| E6 | 单/双行切换 | 切单行时下行内容保留但不渲染；元素库的“添加到”只显示上行 |
| E7 | 选中元素编辑 | 点 chip 选中并在条带下方出现“选中的元素”；可改文字/图标；可左移/右移/删除；再次点击取消选中 |
| E8 | 行样式作用域 | “行样式”卡片顶部“应用到”明确选择上行/下行；颜色/粗体/等宽/对齐立即生效；颜色显示当前值 + 色点 |
| E9 | 显示开关与编辑区一致 | 用左侧开关隐藏实例后，再在编辑区改名称/元素，实例仍保持隐藏；预览同时变暗 |
| E10 | 列表管理 | 左列可切换、重命名后即时更新；复制/上移/下移/删除在行尾菜单，删除有确认 |
| E11 | 行首图标 | 上行/下行标题前的圆形按钮可分别设置固定图标（SF Symbol/Emoji/资源），两行图标都贴左、共享同一图标列宽；右侧内容设右对齐后贴右 |
| E12 | 默认颜色 | 行颜色默认「系统默认」，随系统浅色/深色变化；菜单仍可选「跟随数据源」、固定蓝/绿/红，右侧色块可选任意自定义颜色 |
| E13 | 行首图标大小与颜色 | 图标选择器底部可调 10–30pt 大小；颜色默认跟随文字颜色，也可用色块设自定义固定颜色 |
| E14 | 固定宽度 | 「最小宽度」改为「固定宽度」：非 0 时状态项宽度恒等于该值，较长读数不会再撑宽；内容超出时按该宽度裁剪 |
| E15 | 实例右键菜单 | 顶部显示版本号；提供「打开 App 设置」（默认进入菜单栏实例页）和「禁用此实例」 |
| E16 | 点击面板选项 | 「点击」菜单包含主面板、CPU、GPU、内存、电池，以及网络、磁盘、风扇 |
| E17 | 行首图标列表 | 设置行首图标后，元素列表最左侧显示固定图标；不可拖动换位，点击打开同一图标选择器 |
| E18 | 导入导出实例 | 实例行尾菜单可「导出实例…」为 JSON 文件；左栏「导入实例…」可读取分享文件，生成新实例并选中；最多 20 个 |
| E19 | 图标库 | 行首图标只保留 SF Symbol 与 Emoji；Emoji 扩充为约 150 个常用图案；不再显示普通用户难以理解的资源名称入口 |
| E20 | 双行布局 | 布局菜单包含单行、双行、双行-上大下小、双行-上小下大；后两种默认字号分别为 11/8 与 8/11，行高不等 |
| E21 | 实例右键菜单 | 顶部版本号；「设置…」打开普通设置；「修改样式…」打开菜单栏实例页并选中该实例；「禁用此实例」保留 |
| E22 | 数据刷新频率 | 菜单栏条带下方显示当前实例实际使用指标的数据刷新间隔，例如「下载 1 秒 · 上传 1 秒」 |
| E23 | 悬浮行为 | 编辑器不再提供自定义悬浮动作；仅当设置中的「悬停显示状态面板」开启时，悬停跟随该实例的点击面板 |

## Known limitations in this build (to verify/finish)

- **Hover** opens the configured panel (panel-type only) and leaves it open until you click elsewhere; there is no auto-close on leave yet.
- Instance position/order across restarts is best-effort (macOS `autosaveName`), not guaranteed.
- The menu-bar instance editor's copy is translated for English and Simplified/Traditional Chinese; other languages still fall back to English for the strings added by this editor.
- Instances are capped at 20; the 新建 rows are disabled at the cap.

Record PASS/FAIL per row above; anything failing is a finding, not a retry.
