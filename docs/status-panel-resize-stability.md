# Status panel resize stability

This change separates the status panel's reusable layout and scrolling fixes
from the AirPods inline-controls feature.

## Geometry ownership

- Dynamic SwiftUI content owns its presented height. The panel follows the
  measured layout instead of running a second window-height animation.
- `StatusPanelResizeCoordinator` provides the reusable interruptible
  position/velocity/target trajectory for disclosure containers. Retargeting
  preserves momentum; cancellation and settling stop the timer. The synthetic
  integration fixture uses this same driver. Its AirPods row integration remains
  with the separate inline-controls feature.
- `AnchoredStatusPanel` locks the placement side selected for the current
  presentation. Intermediate heights cannot flip the panel, and the selected
  top, bottom or centred anchor is the one held fixed.
- Window writes use the current backing scale and skip an unchanged frame.
  Layout measurements are coalesced; animation callbacks do not force an extra
  synchronous layout pass.
- The hosted content always fills the actual native container. A final-height
  pin is not applied while the window is still moving.

`StatusPanelScrollArea` uses the native hosting bounds as the presentation
clock, so the scroll viewport and pinned footer move with the window. Its
natural-height callback reports the latest content measurement directly and
deduplicates unchanged values in `StatusPanelLayoutMetrics`.
Each production hosting tree has its own measurement ID. A delayed preference
from a replaced tree cannot overwrite the current tree's height.

## Scrollbar layout

The panel hides AppKit's system scroller and draws its existing 4pt overlay
indicator. `PanelScrollBridge` forces overlay scroller style even when macOS
prefers legacy scrollers, where a permanent 17pt gutter previously narrowed
the document and shifted the page left. The bridge reasserts overlay style when
the scroll view, clip view, document frame or system scroller preference
changes.

## Verification

Focused tests cover the trajectory, rapid retargeting, cancellation, physical
pixel alignment, height measurement, footer placement and the legacy-scroller
regression. Visible `NSPanel` integration tests remain opt-in through
`STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1`.

This change does not add the AirPods inline controls or their hardware-read
lifecycle. Synthetic AirPods disclosure coverage remains with that feature.
The panel does not turn an arbitrary implicit `withAnimation` transaction into
a measured container-height animation: the content must present intermediate
layout heights through the single disclosure driver.

The opt-in run passed 22 tests, including five real `NSPanel` methods. These
exercise a synthetic SwiftUI button through window-local mouse events,
30 alternating presses at 20–80ms intervals, reversal during collapse, screen
overflow, bottom placement and closing while layout is changing. The fixture
uses normal-level nonfloating windows, refuses key status and observes target
process activation through cleanup. All five methods passed the activation
and key-window assertions. Pointer, clipboard and every Space effect were
not independently measured.

An initial fixture using implicit `withAnimation` failed the continuity
assertions because it measured the final layout while SwiftUI was still drawing
intermediate positions. The final fixture uses the extracted disclosure driver,
retaining the original continuity, footer and anchor assertions.
