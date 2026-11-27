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

## Editor (v3)

The pane is one scrolling Settings column with a pinned live preview: an
instance picker with its visibility switch, then the selected instance's
basics, rows, element inspector, row style, and interaction settings. There is
no palette column; each row owns its own "添加" button.

| # | Case | Expected |
|---|---|---|
| E1 | 设置页布局 | 顶部固定实时预览；下方单列 Settings 卡片，实例用弹出菜单选择、旁边是显示开关；默认窗口宽度（720）内不横向溢出，最小宽度（640）下也不裁切 |
| E2 | 新建空白/预设实例 | “新建”菜单可建空白或预设；新建后自动选中并显示在编辑区 |
| E3 | 行内添加指标 | 点该行的“添加”→指标→搜索→选中；只插入指标值（如 `35%`），不带指标名；新元素自动选中 |
| E4 | 添加文字/图标 | 点“添加”→文字与图标；可加自定义文字、SF Symbol、Emoji、资源名 |
| E5 | 拖动排序/跨行 | 同一行拖动排序；上行拖到下行正确移动；均有右键“左移/右移/删除”替代操作 |
| E6 | 单/双行切换 | 切单行时下行内容保留但不渲染；选中下行元素时切单行，编辑焦点回到上行 |
| E7 | 选中元素编辑 | 点 chip 选中并在该行下方出现“选中的元素”；可改文字/图标；可左移/右移/删除；再次点击取消选中 |
| E8 | 行样式作用域 | “行样式”卡片顶部“应用到”明确选择上行/下行；颜色/粗体/等宽/对齐立即生效 |
| E9 | 显示开关与编辑区一致 | 用“在菜单栏显示”关闭实例后，再在编辑区改名称/元素，实例仍保持隐藏；预览同时变暗 |

## Known limitations in this build (to verify/finish)

- **Hover** opens the configured panel (panel-type only) and leaves it open until you click elsewhere; there is no auto-close on leave yet.
- Instance position/order across restarts is best-effort (macOS `autosaveName`), not guaranteed.
- The menu-bar instance editor's copy is translated for English and Simplified/Traditional Chinese; other languages still fall back to English for the strings added by this editor.
- Instances are capped at 20; the “新建” menu is disabled at the cap.

Record PASS/FAIL per row above; anything failing is a finding, not a retry.
