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

Two columns: the left column lists instances (visibility switch, name, menu);
the right column is the selected instance's editor. The editor is one
scrolling column: live preview, name/layout, menu-bar strip, the element
library under the strip, the selected-element inspector, row style, and
spacing/interaction.

| # | Case | Expected |
|---|---|---|
| E1 | 两栏布局 | 左实例列表 / 右编辑区；默认窗口宽度（720）下右栏不横向裁切，最小宽度（640）下也能滚动使用 |
| E2 | 新建空白/预设实例 | 左下“新建”菜单可建空白或预设；新建后自动选中并显示在右栏 |
| E3 | 元素库添加 | 元素库在“菜单栏条带”下方；先选“添加到 上行/下行”，点指标/文字/图标 chip 即加入该行并自动选中 |
| E4 | 元素库拖放 | 从元素库把 chip 拖进任一行，落在指定位置；行内/跨行拖动排序同样可用 |
| E5 | 文字与图标 | 可加自定义文字、SF Symbol、Emoji；选中后在“选中的元素”里编辑 |
| E6 | 单/双行切换 | 切单行时下行内容保留但不渲染；元素库的“添加到”只显示上行 |
| E7 | 选中元素编辑 | 点 chip 选中并在条带下方出现“选中的元素”；可改文字/图标；可左移/右移/删除；再次点击取消选中 |
| E8 | 行样式作用域 | “行样式”卡片顶部“应用到”明确选择上行/下行；颜色/粗体/等宽/对齐立即生效；颜色显示当前值 + 色点 |
| E9 | 显示开关与编辑区一致 | 用左侧开关隐藏实例后，再在编辑区改名称/元素，实例仍保持隐藏；预览同时变暗 |
| E10 | 列表管理 | 左列可切换、重命名后即时更新；复制/上移/下移/删除在行尾菜单，删除有确认 |

## Known limitations in this build (to verify/finish)

- **Hover** opens the configured panel (panel-type only) and leaves it open until you click elsewhere; there is no auto-close on leave yet.
- Instance position/order across restarts is best-effort (macOS `autosaveName`), not guaranteed.
- The menu-bar instance editor's copy is translated for English and Simplified/Traditional Chinese; other languages still fall back to English for the strings added by this editor.
- Instances are capped at 20; the “新建” menu is disabled at the cap.

Record PASS/FAIL per row above; anything failing is a finding, not a retry.
