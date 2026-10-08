# Presentation State Architecture

Status Trio maps live system data into immutable values before drawing. Producers and controllers own collection, policy, and actions; presentation mappers own decisions about what the user sees; views and renderers consume those decisions without repeating domain rules.

For the three icon regions, concrete Swift API contracts, update timing, examples, and future plugin boundaries, see [三图形展示与更新 API](api/icon-presentation.md).

## Data flow

```text
SystemStatusStore ──► IconPresentationInputs ─┐
SettingsStore ──────► IconPresentationConfiguration ─┤
                                                     ▼
                                          IconPresentationViewModel
                                          lifecycle / publication
                                                     │
                                                     ▼
                                               IconSceneMapper
                                  default: IconPresentationMapper.scene
                                                     │
                                                     ▼
                                               IconSceneState
                                           ┌─────────┴─────────┐
                                           ▼                   ▼
                                  StatusBarController   AppIconController
                    │                         │
                    ▼                         ▼
            Menu Bar renderer          static Dock renderer/cache

SystemStatusStore / SettingsStore / controllers / Localization
                    │
                    ▼
           StatusPanelViewModel ──► panel and detail mappers
                    │                         │
                    ▼                         ▼
       six panel regions/details      immutable region states
                    │                         │
                    └── StatusPanelActions ───► views and user actions
```

`IconPresentationMapper` is a pure transformation from `IconPresentationInputs` and `IconPresentationConfiguration` to `IconSceneState`. It selects the ring, center, and footer, including priority and visible styling. `IconPresentationResourceResolver` is the boundary for filesystem and image availability: it checks whether a device image can be used and returns a value-only symbol choice. System APIs and `NSImage` checks stay in this adapter; the mapper and scene do not import AppKit, SwiftUI, or CoreGraphics. SSIDs and other spoken metadata do not enter the icon scene.

`IconPresentationViewModel` owns publication, lifecycle, and snapshot debounce. Its MainActor `IconSceneMapper` closure maps resolved inputs and configuration into the scene; production defaults to `IconPresentationMapper.scene`. Alternate closures support composition, testing, and future host integration. This is not a plugin API: there is no dynamic registration, public SDK, or external scene publication path.

`PanelPresentationMapper`, `PanelDetailMapper`, `BluetoothPanelMapper`, and `AudioPanelMapper` turn domain values into section-specific immutable states. `StatusPanelViewModel` owns subscriptions, refresh coalescing, section values, and the panel lifecycle. It does not draw or decide icon precedence. `StatusPanelActions` routes intents to existing controller operations; it does not own presentation state or settings reorder policy. Settings reorder controls continue to call `SettingsStore` directly.

The Bluetooth mapper combines eligible nearby BLE battery readings with paired rows before applying saved order and visible-row limits. Matching mobile devices reuse their paired row and battery report; a model-only mobile device becomes a read-only row led within its connection group, while other BLE devices remain in the nearby section. `PanelBluetoothDeviceRow.isActionable` controls whether the view exposes a button, and the action coordinator checks the live domain device again before performing an operation. Closing the summary releases its scan claim with cached results retained; turning the preference off clears the retained cache, including when the summary is closed. The controller's popover claim remains the gate that stops the scanner when the popover closes.

`AccessibilityPresentation` keeps status-item spoken identity separate from icon raster identity. Its Wi-Fi name and exact volume value are derived from the current snapshot and language. The panel mappers provide reusable localized battery and Wi-Fi text without moving SSIDs into `IconSceneState` or changing localized strings.

## Publisher and lifecycle rules

When a publisher carries the state needed for a presentation update, map the value delivered by that subscription. Do not receive a notification and then silently substitute a potentially newer unrelated property read. The icon owner synchronizes its initial snapshot and settings deliveries before publishing, debounces domain snapshot bursts by 500 ms, and publishes preference changes immediately. Its scheduler is cancelled on stop and when an immediate preference update supersedes a pending snapshot update.

The panel owner starts once while its panel is presented and stops with the panel lifecycle. Detail collectors and device claims remain paired with the corresponding view appearance/disappearance callbacks. Panel controller notifications are coalesced into a union of dirty regions; generation checks prevent a scheduled update from a stopped lifecycle from publishing. Equal mapped region values are not republished. Hidden panel regions retain their existing lifecycle rules rather than starting new producers.

## Identity and cache inputs

`IconSceneState` equality contains visible semantic drawing choices: ring segment/accessory/stroke values, center glyph and color role, and footer values. It excludes animation frame phase, menu-bar point size, Dock pixel length, resolved dynamic appearance colors, and spoken metadata. Size-dependent symbol scales remain in the scene because they change geometry. Renderers resolve the foreground role for the active appearance and receive the surface size separately.

Menu Bar animation receives its current phase at render time. Dock artwork is static: `DockIconRenderKey` retains the canonical scene for the renderer but normalizes the animation-only ring effect out of equality and hashing because Dock drawing always uses a nil phase. Ring geometry, accessory, center, footer, background style, and pixel length remain cache inputs. The Dock image cache and preview cache use the same key semantics. A changed static visual invalidates the cache; toggling heartbeat/effect intent alone does not rerasterize the Dock.

## Adding or changing an icon setting

For each new icon option or changed rendering rule, update all applicable parts together:

1. Add the setting value and derive its effective option in `SettingsStore`.
2. Include it in `IconPresentationConfiguration` and map its visible effect in `IconPresentationMapper`.
3. Preserve the option through the Menu Bar and Dock owners, including `AppIconController` and `StatusBarController`; do not create a surface-only rendering path unless the product specification explicitly declares it menu-bar-only.
4. Add mapper tests for priority and normalized scene identity, renderer tests for the affected geometry, and integration/cache tests for both surfaces. Animation-only controls must also assert that static Dock output is unchanged.
5. Update the behavior matrix and this document when the responsibility or cache identity changes.

Tests should compare pure scene/state values for branch and identity behavior, then use focused renderer tests for the drawing rule. Pixel snapshots are appropriate only for established raster conventions; they are not a substitute for mapper priority or cache identity tests.

## Extension boundary

Future status producers must provide values to a mapper or owner; they must not draw directly from domain models. Ring and center remain value-based drawing primitives. Split-ring presentation and remote status inputs are examples for future design work, not implemented features or extension points in this architecture. No dynamic registration, remote transport, or user-configurable presentation slots are part of the current system.
