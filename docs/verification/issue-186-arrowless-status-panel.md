# Issue #186 — arrowless status panel (custom `NSPanel`)

Status: **implemented; automated `full` profile passes; the production panel code
was visually probed on macOS 27.2. A click-driven background UI session and
Ventura runtime checks were not possible in this harness.**

Related issues:

- [#186 去掉弹出面板顶部的尖角（NSPopover 箭头）](https://github.com/lingyired/status-trio/issues/186)
- [Issue #165 template-image view](issue-165-template-image-view.md) — the menu
  bar icon layout this change does not touch.
- [#40 菜单栏展开玻璃通透度](../popover-glass-investigation.md) — the native
  Liquid Glass decision this change preserves.

## Problem

`NSPopover` draws the small arrow that points at the status item. AppKit has no
public API to hide it (verified in the macOS 26, 27 and 27.2 SDK headers:
`NSPopover.h` contains no arrow property), so the only supported way to remove
it is to stop using `NSPopover` and draw/position the panel ourselves.

## Implementation

- New `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`:
  - `AnchoredStatusPanel: NSPanel` — borderless, `.nonactivatingPanel`,
    `.statusBar` level, `canBecomeKey == true`, `canBecomeMain == false`,
    `.canJoinAllSpaces + .fullScreenAuxiliary`. The ex-
    `enableDisplayOnFullScreenSpaces()` helper is still applied after showing,
    as a second guarantee of the same contract.
  - `StatusPanelHostingController` reports `NSHostingView.fittingSize` from
    `viewDidLayout`, so expanding rows and detail pages resize the window
    exactly as the popover did. `StatusPanelContentViewController` wraps that
    hosting controller in the glass background.
  - `close()` / `performClose(_:)` order the window out, post
    `AnchoredStatusPanel.didCloseNotification` and call `onClose`; this replaces
    `NSPopoverDelegate.popoverDidClose(_:)`. The controller's five-second
    content-retention contract is unchanged.
  - Escape, outside clicks (existing global monitor), app deactivation and the
    status item toggle all close the panel.
- New `Sources/StatusTrioCore/UI/StatusPanelPlacement.swift`: pure placement
  maths (anchor rect + preferred edge + content size + screen geometry), with
  the popover's centring, 6 pt gap, visible-frame clamping and
  flip-to-the-opposite-side fallback. Covered by
  `Tests/StatusTrioCoreTests/StatusPanelPlacementTests.swift`.
- `StatusBarController` uses `AnchoredStatusPanel` instead of `NSPopover`; the
  lifecycle calls (`show`, `performClose`, `isShown`, `contentViewController`)
  keep the same shape so the content lifecycle tests still exercise the same
  contracts.

## Glass

The popover's chrome came from the private `NSPopoverFrame`; the panel reproduces
it with public views only:

| macOS | Background |
| --- | --- |
| 26+ | `NSGlassEffectView(style: .regular)`, `cornerRadius = 16` |
| 13–25 | `NSVisualEffectView(material: .popover, blendingMode: .behindWindow)` |
| Reduce Transparency on | solid `windowBackgroundColor` with the same corner radius |

The window is transparent, `hasShadow == true`, and the rounded background is
what gives the shadow its shape. `NSGlassEffectView` is guarded with
`#available(macOS 26.0, *)`, matching the existing SDK-26 floor.

## Known differences from `NSPopover`

These are deliberate and recorded in `docs/known-limitations.md`:

- The panel does not continuously track the anchor while it is open; it
  repositions on show, on content resize and on screen-parameter changes.
  `NSPopover` moved with the status item frame.
- `NSPopover`'s show/close animation and detach-by-drag interaction are gone
  (`animationBehavior = .none`).
- Clicking another window **of this app** (for example an already-open Settings
  window) does not dismiss the panel; clicking another app, the status item,
  Escape, or any panel action does. Actions that open Settings already close the
  panel explicitly.
- The panel uses the public `NSGlassEffectView` / `NSVisualEffectView` path
  instead of the private `NSPopoverFrame`, so it cannot inherit AppKit's popover
  chrome on future releases; that is the trade-off issue #186 chose.

## Verification

Branch base: `e3477268` (`origin/main` at delivery time).

### Automated

- `bash scripts/test.sh 'StatusPanelContentTests|StatusPanelPlacementTests|StatusBarMemoryPressureTests|StatusBarContentLifecycleTests|PopoverFooterPresentationTests|CompactAudioLayoutTests'`
  — 21 tests pass, including the real close/reopen retention cycles.
- Full `swift test` suite — 805 tests / 117 suites pass.
- `bash scripts/verify-local.sh full` — pass on the PR branch head (full Swift
  suite, Release build, non-Universal app bundle and contracts, native checks and
  offline release simulations).

### Visual probe (production panel code, throwaway host)

A throwaway executable compiled the real `AnchoredStatusPanel` /
`StatusPanelPlacement` / `StatusPanelContentViewController` sources with a
sample SwiftUI body and a 1×1 anchor window at the status-item position
(`/tmp/panelprobe`, not part of the repo). It ran on this machine
(macOS 27.2, single 2048×1152 @2× display) and produced:

- `issue-186-arrowless-panel-static.png` — panel below the menu bar, no arrow,
  rounded glass corners, native shadow.
- `issue-186-arrowless-panel-expanded.png` — the same window after the sample
  content grew from 168 pt to 343 pt; the top edge stayed at
  `visibleFrame.maxY - 6` and the content was not clipped.

Captured frames: `(1718, 954, 330, 168)` → `(1718, 779, 330, 343)`. This
confirms the `NSHostingView.fittingSize` sizing path and the top-anchored
placement work on macOS 26+.

Region captures (not committed because they include the user's menu bar) showed
the menu bar and wallpaper blurred through the panel, confirming the public
glass path is live rather than a solid fill.

### Background UI testing

- `bash scripts/launch-computer-use.sh` built and launched the isolated Debug
  dev bundle (`com.lingsmbp.StatusTrio.dev.feat-issue-191-186-arrowless-panel`)
  with `--background-ui-testing` and the `--status-trio-ui-test-launch` token.
  Report: `sourceDirty: false`, `backgroundUITesting: true`.
- At sampling time the frontmost application was still Microsoft Edge, so no
  foreground transition was observed. The launcher stopped this worktree's test
  instance gracefully afterwards; no other instance was touched.
- The **status panel itself** was not opened through the launched app: this
  harness has no permitted Computer Use provider for a status-item click, and
  the project restricts GUI providers to Codex native Computer Use. The visual
  evidence above comes from the standalone probe, not a click-driven background
  session.
- Status: app launch / non-activation **PASS**, panel visual/interaction
  background gate **NOT RUN** (no permitted input path), manual visual
  acceptance **NOT RUN**.

### Not proven

- Ventura (macOS 13) runtime behaviour of the `NSVisualEffectView` fallback and
  the hosting-controller sizing path.
- Real multi-display placement, full-screen Spaces and Dock anchoring.
- Reduce Transparency appearance and appearance changes while open.
- Manual visual approval of the exact glass/shadow against the old popover.

