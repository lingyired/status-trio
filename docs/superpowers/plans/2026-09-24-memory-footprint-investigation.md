# Status Trio Memory Footprint Investigation and Optimization Plan

> **For agentic workers:** Implement each independent task with the project skills and verification gates. Track progress with the checkboxes below. The measurement gate decides which conditional changes are justified.

**Goal:** Identify why a menu-bar-only Status Trio can show more than 100 MB of memory use, then reduce measured idle footprint and post-interaction high water without changing status accuracy or update behavior.

**Architecture:** Measure the release app in controlled states before changing code. Make one independently measurable change at a time, separating cold-start ownership, popover/Settings lifetime, icon rasterization, and long-run worker recovery. Keep menu-bar and Dock icon output in parity.

**Tech Stack:** SwiftPM, Swift 6.3.3 on CI (Xcode 26.6, macOS 26 runner), AppKit, SwiftUI, Combine, CoreGraphics, Sparkle, macOS `footprint`/`vmmap`/Instruments.

**Spec:** The user's 2026-09-24 request and the referenced “项目优化建议” conversation. Existing findings and implementation details: [2026-09-20 review index](2026-09-20-review-findings-index.md), [R-04 icon preview plan](2026-09-20-icon-preview-rendering.md), and [R-07 render key plan](2026-09-20-menubar-render-key-normalization.md).

## Evidence and limits (2026-09-24)

- The running `dist/StatusTrio.app` is v1.3.2 (15), PID 33850, launched 18:34 local time, with preference `appIconPlacement = menuBar`. At about 44 minutes, `ps` reported RSS 226,352 KB; `footprint` and `vmmap -summary` reported **129 MB physical footprint**, peak **535 MB**. This is **not a cold-start sample**; prior UI interactions are unknown.
- Dirty footprint included about **73 MB Malloc Small**, **13 MB CoreAnimation**, **12 MB CG Raster Data**, **4.5 MB CG Image**, and **3.2 MB IOSurface**. The malloc-zone summary reported **41.9 MB allocated** against **75.8 MB dirty**, including **33.9 MB fragmentation**. The stack's physical footprint was about **0.3 MB**. These categories point first to heap and graphics attribution, not to a demonstrated thread accumulation.
- `heap -s -H` counted 214,236 live malloc nodes, including SwiftUI and CoreSVG objects. It cannot show allocation backtraces without Malloc Stack Logging. `leaks` said this release process is not debuggable and could inspect only read-only contents; its output does **not** rule out a leak.
- The machine showed AC attached but **not charging** during this sample, so the charging animation is not the cause of this particular 129 MB observation. It still needs an A/B test for charging users.
- The 2026-09-20 review's 25 MB figure used `top` RSS on an idle installed 1.2.x app. It cannot be subtracted from today's `phys_footprint`; compare the **same metric, scenario, macOS version, and build style** before calling 1.3.x a regression.

## File map

| Responsibility | Production files | Existing tests/plans |
|---|---|---|
| Startup ownership | `App/AppDelegate.swift`, `App/AppEnvironment.swift`, `App/UpdaterManager.swift`, `Store/SystemStatusStore.swift` | `UpdaterManagerTests.swift`, `SystemStatusStoreTests.swift`, `SettingsWindowControllerTests.swift` |
| Background readers | `Monitoring/VPNMonitor.swift`, `Monitoring/ReadWatchdog.swift`, `Monitoring/WiFiMonitor.swift`, `Monitoring/VolumeMonitor.swift`, `Monitoring/BluetoothDeviceController.swift` | `VPNMonitorTests.swift`, `ReadWatchdogTests.swift`, monitor test suites |
| Menu-bar graphics | `UI/StatusBarController.swift`, `UI/Icon/StatusBarRenderCache.swift`, `UI/Icon/StatusBarChargingFrameCache.swift`, `UI/Icon/StatusBarAnimationLayerPresenter.swift` | `StatusBarRenderCacheTests.swift`, `ChargingEffectFrameCacheTests.swift`, R-07 plan |
| Popover and preview | `UI/StatusBarController.swift`, `UI/IconPreviewComponents.swift`, `UI/Icon/DockIconRenderer.swift`, `UI/Settings/SettingsWindowController.swift`, `Monitoring/BluetoothProfilerReportCache.swift`, `Monitoring/WiFiNetworkController.swift` | `PopoverLifecycleTests.swift`, `SettingsWindowControllerTests.swift`, R-04 plan |
| Dock-only resources | `App/AppIconController.swift`, `App/SystemIconAppearanceMonitor.swift`, `UI/Icon/DockIconRenderCache.swift` | `AppIconControllerTests.swift`, `DockIconRenderCacheTests.swift` |

## Global constraints and acceptance

- Do not promise a specific MB reduction from source review. Record **RSS and `phys_footprint` separately** and compare medians of at least three same-scenario runs; keep raw `vmmap -summary` output for before/after.
- Measure release builds with macOS 26 SDK or newer. Use the macOS 26 / Xcode 26.6 / Swift 6.3.3 release workflow as the compatibility gate; a newer local build alone is insufficient.
- Before committing Swift changes run `swift test` and `swift build -c release`. For actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` changes, run a non-publishing `release.yml` dispatch and watch it pass before merging. Log each failed Actions run in `docs/swift-ci-compatibility.md`.
- A menu-bar icon rendering or option change must keep the Dock rendering path and tests in parity. Preserve VoiceOver updates when an image render is skipped.
- Keep automatic update checks functioning when enabled. Do not infer that delaying `SPUUpdater` initialization reduces steady-state memory without an A/B measurement.
- Treat memory gained from framework loading or allocator fragmentation separately from still-reachable application objects; do not label a high RSS alone a leak.

## Review focus

1. **Cold launch, menu-bar only, no UI opened:** measure 2 minutes, 10 minutes, and 1 hour after launch; ask whether the footprint is already above 100 MB and whether it grows.
2. **Popover used once and ten times:** measure open, close, after 15 seconds, and after 2 minutes; check whether the hosting tree is actually released and whether reopen latency stays acceptable.
3. **Settings preview and sliders:** measure graphics categories and allocation peaks before/open/close; compare 512 px and scale-appropriate preview rendering.
4. **Charging on/off and noisy signals:** while truly charging, compare memory and CPU with animation enabled/disabled and count full 36-frame rebuilds when RSSI/volume changes within the same visible bucket.
5. **Long system read stall:** verify bounded abandoned workers and recovery on wake/device change, without losing normal monitor updates.

---

### Task 1: Establish a reproducible memory baseline (P0, prerequisite)

**Files:** Create `docs/performance/memory-footprint-2026-09.md` for raw tables and conclusions. No production edit.

**Steps**

- [ ] Record exact binary path, version/build, git SHA, macOS, architecture, power/charging state, display scale, app placement, and whether Settings/popover/Dock have opened. Do not measure the user's current long-running PID as a cold launch.
- [ ] On a controlled release build, collect the same snapshots at cold idle 2/10/60 minutes, popover open/closed and settled, Settings preview open/closed and settled, Dock on/off, and a one-hour idle run. For each snapshot run `ps -p "$pid" -o pid,etime,rss,command`, `footprint -p "$pid"`, and `vmmap -summary "$pid"`; save timestamped outputs. Use Instruments Allocations with Malloc Stack Logging on a debuggable build to attribute large heap growth.
- [ ] Repeat the cold idle scenario three times. Compare v1.2.1 with v1.3.2 under the same OS and preferences if both can be run safely, using identical footprint metrics. Record whether the difference is a build regression, an interaction high water, or a long-run slope.
- [ ] Select the next task from the evidence: cold heap/framework delta → Task 4; post-popover or Settings delta → Task 2; charging-only graphics/CPU delta → Task 3; monotonic thread/stack growth → Task 5. Preserve the baseline and repeat the same scenario after each change.

**Exit gate:** A table names the build, scenario, RSS, `phys_footprint`, peak, major `vmmap` regions, and a repeatable delta. If no repeatable delta appears, use a fresh Instruments trace before editing production code.

### Task 2: Bound post-interaction graphics and view lifetime (P1; only if Task 1 implicates UI use)

**Files:** `UI/StatusBarController.swift`, `UI/IconPreviewComponents.swift`, `UI/Icon/DockIconRenderer.swift`, possibly `UI/Settings/SettingsWindowController.swift`, `Monitoring/BluetoothProfilerReportCache.swift`, or `Monitoring/WiFiNetworkController.swift`; existing popover/Settings tests and the [R-04 plan](2026-09-20-icon-preview-rendering.md).

**Steps**

- [ ] Probe popover closed-state retention at the present 60 seconds, then at 15 seconds and immediate release. Choose the shortest delay that avoids a measured reopen latency regression. Test that open cancels the release task, a detail panel releases immediately, and closing cannot leave observers or scans active.
- [ ] Implement the existing R-04 preview design, rebased to the current renderer: render 44/56 pt previews at the current backing scale (for example 88/112 px at 2×), cache by visible icon inputs **and pixel length**, and keep the real Dock icon at 512 px. Test preview pixel dimensions, visual parity, cache invalidation, and scale change.
- [ ] Check whether the shared Bluetooth profiler JSON `Data` or the Wi-Fi scanned-network list remains large after their panels close. `BluetoothProfilerReportCache.freshData()` rejects an expired entry but does not clear it; expire or clear the bytes on surface close only if the retained payload is material. Preserve reuse by the device and battery readers within the five-second freshness window.
- [ ] Measure `CG Raster Data`, `CG Image`, `CoreAnimation`, `IOSurface`, peak footprint, and reopen latency after ten popover cycles and a Settings slider drag. Add a memory-pressure purge only if retained images or views remain a measurable problem after normal close.

**Exit gate:** The same post-interaction scenario has a reproducible lower physical footprint or peak, with unchanged preview appearance and no stale popover state. Do not use a lower RSS alone as proof of released objects.

### Task 3: Reduce menu-bar raster churn (P1; especially if charging is the trigger)

**Files:** `UI/Icon/StatusBarRenderCache.swift`, `UI/Icon/StatusBarChargingFrameCache.swift`, `UI/StatusBarController.swift`, `UI/Icon/StatusIconRenderer.swift`; matching Dock key/renderer tests. Rebase the [R-07 plan](2026-09-20-menubar-render-key-normalization.md).

**Steps**

- [ ] Instrument how often `StatusBarChargingFrameCache` rebuilds its 36-frame set and how many bytes/time each rebuild costs. Its `FrameSetKey` currently inherits the complete `MenuBarStatus` from `StatusBarRenderKey`, so sub-bucket RSSI/volume changes can invalidate the whole set.
- [ ] Normalize the image render key to values that change pixels, while preserving exact continuous values if the selected arc style draws them. Move the VoiceOver update to its own gate so SSID, exact percentage, and charged state remain current even when artwork is reused. Verify the Dock key responds to the same visual changes.
- [ ] A/B test steady charging animation on/off with power and settings held constant. If measured animation cost remains material after key normalization, compare fewer cached frames or lower tick cadence **with a visual smoothness check**; avoid adding another unbounded image cache.

**Exit gate:** A sub-bucket RSSI/volume update does not rebuild 36 bitmaps; a real visible change does; VoiceOver stays current; the charging A/B result includes both CPU and footprint.

### Task 4: Remove demonstrated cold-start ownership (P1, evidence-gated)

**Files:** `App/AppEnvironment.swift`, `Store/SystemStatusStore.swift`, `Monitoring/VPNMonitor.swift`, `App/UpdaterManager.swift`, `App/AppDelegate.swift`, `UI/Settings/SettingsWindowController.swift` and their tests.

**Steps**

- [ ] A/B isolate startup contributors one at a time in a debug/profile build: Sparkle, VPN watcher, Settings controller, and detail controllers. Measure **steady footprint**, not only first-second startup. Keep a temporary probe out of the release branch.
- [ ] If VPN is measurable, start it only while the enabled VPN row is visible and stop/pause it on close. `VPNMonitor.stop()` is terminal today, so introduce a safe pause/resume or re-create-and-rebind contract rather than calling `start()` after `stop()`. Test row toggles, reopen, wake recovery, stale status, and no duplicate `SCDynamicStore` subscription.
- [ ] If controller graph is measurable, lazily create Settings and detail controllers at first use. Preserve the Settings Bluetooth permission-resurface subscription and all existing `SystemStatusStore` call sites; test first open, repeated open, close, and deinit.
- [ ] If Sparkle is measurable, test a delayed initialization or an opt-out path for users who disabled automatic checks. Preserve enabled automatic checks and manual Check for Updates, including startup failures and fallback feed behavior. A mere 5-second delay is not an idle-memory optimization if the same updater remains resident afterward.

**Exit gate:** Each accepted change reduces median cold-idle footprint beyond run-to-run noise and passes behavioral tests. Reject/revert probes with negligible gain or altered update/status behavior.

### Task 5: Bound hidden Dock resources and long-run recovery (P2; separate outcomes)

**Files:** `App/AppIconController.swift`, `App/SystemIconAppearanceMonitor.swift`, `UI/Icon/DockIconRenderCache.swift`, `Monitoring/ReadWatchdog.swift`, `Monitoring/WiFiMonitor.swift`, `Monitoring/VolumeMonitor.swift`, `Monitoring/BluetoothDeviceController.swift`; corresponding tests.

**Steps**

- [ ] When no Dock tile is visible, stop its appearance monitor and release its image cache; restart and redraw on temporary regular-mode windows and explicit Dock placement. Keep `NSApplication.applicationIconImage` and cache behavior in sync. This avoids unnecessary work and post-Dock retention, but is **not expected to explain a fresh menu-bar-only launch**.
- [ ] If the one-hour run or induced stall shows growing abandoned reads, give the watchdog/worker owners a fixed outstanding-abandonment budget and an explicit suspended state. Resume one read on wake/device event/user action; test late completion, repeated timeout, stop, and recovery. Keep this independent of cold-start changes.
- [ ] Re-measure an hour of menu-bar-only idle and a controlled stuck-read test; report stack resident size, thread count, footprint slope, and status correctness.

**Exit gate:** Hidden Dock retains no application-owned Dock bitmaps or timer; stuck readers cannot accumulate workers without bound; normal Dock and monitor behavior remains intact.

## Handoff and order

Run **Task 1 first**. Then take the triggered P1 tasks independently; Task 2 and Task 3 address graphics/high water, while Task 4 addresses a verified cold baseline. Task 5 is split into two small changes during implementation so Dock cleanup and watchdog recovery can be reviewed separately. Use a fresh task-specific version/build for any required non-publishing release preflight; the old R-04/R-07 plans contain historical version examples that must not be copied verbatim.
