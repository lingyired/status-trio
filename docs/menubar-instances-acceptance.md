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

## Known limitations in this build (to verify/finish)

- **Hover** opens the configured panel (panel-type only) and leaves it open until you click elsewhere; there is no auto-close on leave yet.
- Instance position/order across restarts is best-effort (macOS `autosaveName`), not guaranteed.
- The new Settings UI uses English labels except the sidebar tab title.

Record PASS/FAIL per row above; anything failing is a finding, not a retry.
