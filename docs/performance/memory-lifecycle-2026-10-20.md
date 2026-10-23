# Memory lifecycle sampling and evidence (2026-10-20)

## Scope and result

`scripts/measure-memory-lifecycle.swift` is a read-only macOS sampler for a
single existing PID. It records monotonic timestamps, elapsed time, process
identity, physical footprint, RSS, lifetime peak footprint, and the number of
on-screen CoreGraphics windows owned by that process.

The tool is ready for a controlled product A/B run. The sampler implementation
task did not launch, stop, or modify a Status Trio app, and it did not reproduce the historical
342.1 MiB lifetime peak. The existing 30 MiB closed and 59 MiB open
observations remain historical evidence, not output from the new sampler.
There is no evidence for a leak or a Bluetooth attribution.

## Invocation

```bash
swift scripts/measure-memory-lifecycle.swift \
  --pid <pid> \
  --seconds 60 \
  --interval-ms 100 \
  --output /path/to/new-run.jsonl
```

The destination must not already exist. Publication uses
`renameatx_np` with `RENAME_EXCL`, so a concurrent creator can never be
overwritten. A failed or interrupted run removes its temporary file and never
publishes partial JSONL. This prevents an old or partial file, or another
process's output, from being mistaken for the requested run.

Each JSONL sample contains:

- `timestamp` and `elapsed`, both based on monotonic `systemUptime`;
- `pid`, `executablePath`, `executableUUID`, and `startAbstime`;
- `footprintBytes` / `footprintMiB`;
- `rssBytes` / `rssMiB`;
- `lifetimePeakFootprintBytes` / `lifetimePeakFootprintMiB`;
- `visibleWindowCount`;
- the sampler's separate `observer.pid` and `observer.executablePath`.

`visibleWindowCount` is the count of rows returned by
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`
whose owner PID matches the target. It does not identify a panel, read a
window title, or capture window content. A zero window count is not treated as
unknown; failure to obtain the CoreGraphics list is an error.

Memory and identity come from `proc_pid_rusage` with `RUSAGE_INFO_V4`, plus
`proc_pid_path`. Zero footprint, RSS, or lifetime peak is rejected. Every
sample is compared with the initial process identity, and a final identity
check runs after the scheduled samples. A kqueue `EVFILT_PROC` watcher for
`NOTE_EXEC | NOTE_EXIT` is registered before canonical identity is read, which
closes the identity-read/registration interval for same-path re-exec. After
the final identity check, the nonblocking process-event query is the immediate
operation before exclusive publication, while the monitor remains active.
That validation is the accepted measurement boundary: no post-publication
polling attempts to invalidate the completed measurement, and no output path
is removed after a successful rename. Target exit, PID reuse, or exec before
the boundary causes a nonzero exit with no retained output.

## Historical evidence, kept separate

On 2026-10-20, PID 30128 was manually observed in the development build
`dist-dev/Status Trio (Memory Optimization).app` from source baseline
`99d6fa998187ba2d5beced13377ed9ceee6ca263`.

| Manual state | Samples | Footprint median / peak (MiB) | RSS median / peak (MiB) | Lifetime peak (MiB) | Window observation |
|---|---:|---:|---:|---:|---|
| Closed as labeled | 60 | 30.0009 / 30.0477 | 128.375 / 128.422 | 65.45 | not captured for this interval |
| Open as labeled | 60 | 59.1962 / 59.2509 | 164.938 / 165.000 | 342.1 | 1 visible window in 60/60 samples |

Raw files:

- `/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/manual-dev-current-30128.json`
- `/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/manual-dev-panel-open-30128.json`
- `/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/manual-dev-panel-open-30128.windows.jsonl`

The window file establishes that a window owned by PID 30128 was on screen
during the labeled open interval. It does not prove which panel was visible.
The 29.2 MiB difference between the two medians and the 342.1 MiB cumulative
lifetime peak have different measurement scopes. The peak cannot be used as a
steady-state cost or assigned to the open panel.

The earlier fixed-closed three-run comparison is also historical input, not
new Task 5 output:

| Variant | Three-run footprint median of medians (MiB) | Highest sampled peak (MiB) | Highest lifetime peak among runs (MiB) |
|---|---:|---:|---:|
| Baseline | 14.6571 | 14.7977 | 18.6414 |
| Earlier optimized build | 14.8602 | 15.0633 | 18.8758 |

That result showed no steady-state reduction in the fixed-closed scenario.
Raw data is under
`/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/task7-confirm-20261020T0444/`.
A separate passive observer recorded no on-screen windows for those 82-83
sample target runs. These values must not be merged with the PID 30128 manual
open/closed pair.

## Final local development build

The final lifecycle changes were built as development version `1.6.0 (37)`
with Bundle ID `com.lingsmbp.StatusTrio.dev.memory-optimization`. The app and
privileged/mobile helper bundles passed their build-version, signature, and
bundle-integrity checks. The development bundle launched from:

`/Users/lingsmbp/.codex/worktrees/memory-optimization/status-trio/dist-dev/Status Trio (Memory Optimization).app`

It ran as PID 72135 with executable SHA-256
`00cb5c49a33d4adfeea3b3edf7e5476c4b9b8e8b41a83d1670468e0639527453`
and UUID `ed10eac7322c3052b235dcbf3046069c`. A passive 15-second capture while
the panel was closed and the app remained idle produced 31 samples:

| Metric | Median / peak |
|---|---:|
| Physical footprint | 22.954 MiB / 22.954 MiB |
| RSS | 95.047 MiB / 95.047 MiB |
| Lifetime peak footprint | 59.813 MiB |
| On-screen windows | 0 / 0 |

Raw JSONL:
`.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/final-dev-72135-20261021-011059.jsonl`.

A later 30-second capture after more than two minutes of process uptime produced
31 samples with a 22.938 MiB median and 22.954 MiB peak footprint; RSS ranged
from 95.047 to 95.078 MiB, lifetime peak stayed at 59.813 MiB, and all samples
reported zero visible windows. Raw JSONL:
`.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/final-dev-72135-stability-20261021-011305.jsonl`.

This run is development-build evidence, not a baseline/candidate A/B. It had
no panel, Settings, or Onboarding interaction and cannot establish long-running
stability, phase-specific reduction, or Bluetooth/AirPods attribution.

## Tool verification

The portable tests compile the Swift tool while holding the plan's
`swift.lock`, the same mutex used by `run-swift.py`, and target macOS 13
deployment. The test-first run failed because the implementation did not yet
exist. The completed suite covers:

- invalid and missing arguments;
- nonexistent, exited, and mid-run exiting PIDs;
- executable identity changes without PID reuse;
- same-binary re-exec detection with unchanged path/UUID/start identity;
- same-binary re-exec during the registration handshake;
- same-binary re-exec before the final identity/event boundary;
- post-boundary exec and atomic output-path replacement, proving there is no
  post-publication revalidation or cleanup that can delete the competitor;
- fresh-output enforcement, concurrent-creator exclusion, and no partial output
  on failure;
- stable nonzero memory/identity records and monotonic timestamps;
- absence of window-title or content fields;
- nonzero launch-marker publication failure through the GUI-free helper seam.

Command:

```bash
python3 -m unittest discover -s scripts/tests -v
```

Result: 17 tests ran; 15 portable tests passed, 2 opt-in desktop probes were
skipped. The skipped tests are intentional so default discovery neither creates
an AppKit window nor treats the desktop probe as a pass. The default marker seam
calls the same phase-helper implementation used by the GUI harness.

## Native window probe boundary

`scripts/tests/memory-lifecycle-window-harness.swift` is a test-only AppKit
helper. When explicitly enabled with
`STATUS_TRIO_ENABLE_WINDOW_HARNESS_TESTS=1`, it schedules
launch -> first expand -> close -> reopen and writes timestamped phase markers.
The sampler remains the independent observer. A privacy canary verifies that
the marker and JSONL path do not expose the helper window's title. A phase
marker write failure terminates the helper with a nonzero status; it cannot
silently yield incomplete phase evidence. The default suite verifies launch
marker publication failure through a GUI-free executable seam. The opt-in GUI
phase and unwritable-path probes were not run in the final residual validation,
so no native window-probe pass is claimed.

An earlier short helper-window probe confirmed that the CGWindow count changed
from one visible helper window to zero after hiding it and that the canary title
was absent. The six-second closed/reopen version did not produce a reliable
complete phase sequence across three attempts. The doubtful assumption was
that helper main-run-loop timers and an external sampler would stay aligned
without a controller. The workspace's Computer Use attempt also failed to
control the target window reliably.

The probe therefore stays opt-in and skipped by default. Its failure is not
counted as a pass, and it is not evidence about optimized Status Trio memory.
The parent's `StatusBarController` lifecycle test will provide the product
controller functional proof; a separately coordinated native menu-bar run is
still needed for full-app footprint and real WindowServer acceptance.

## Remaining measurement protocol

A valid product comparison should use the same source, feature settings,
display environment, and input/charging state for baseline and candidate.
Warm up by the same duration, sample at 100-1000 ms, and record at least three
fresh processes per variant. Each run must retain its process identity and
phase markers for launch, first expansion, at least six closed seconds, and
reopen.

The report should calculate each phase's sampled footprint peak separately
from `lifetimePeakFootprint`, preserve all raw JSONL, and inspect SwiftUI
hosting or image decode only when a reproducible phase or allocation trace
identifies a source. Until then, the 342.1 MiB event remains unreproduced and
does not justify a product patch.

The original implementation and its local verification are complete. The
2026-10-21 main synchronization adopts the current local-first policy:
`bash scripts/verify-local.sh full` validates the integrated tree, while a remote
diagnostic is optional and requires maintainer approval. The formal release
runner now uses Xcode 27; historical Xcode 26.6 / Swift 6.3.3 notes describe only
the earlier environment.

A full product comparison still needs native macOS 13 runtime tests, physical
Bluetooth, iPhone, and AirPods states, WindowServer/Spaces and multi-display
coverage, and manual panel, Settings, and Onboarding interaction. The sampled
PID 72135 and its hashes above belong to the earlier development build, not the
main-synchronized source.

## Closed-panel icon-only follow-up on 2026-10-22

This follow-up is limited to resident memory while the status panel is closed
and only the menu-bar icon is visible. Panel glass, first-open hosting, and
open-panel allocations are outside this phase.

The final development build is `1.6.0 (37)` with Bundle ID
`com.lingsmbp.StatusTrio.dev.memory-optimization`. Its executable SHA-256 is
`27072bfc95098416785a99ae848cc6d71d8d6f6f7482115dc64813f543f4a156`
and UUID `317f124373ff3cba9e7b378740f13cdd`; deep strict signature
verification passed. Persisted popup sections were Battery and Network, so
Bluetooth and Volume were both hidden. Bluetooth-audio replacement of the
network icon retained its false default, and Bluetooth listening-mode preview
was off.

A passive 30-second capture from PID 60428 produced 61 samples:

| Metric | Median / peak |
|---|---:|
| Physical footprint | 14.235 MiB / 14.235 MiB |
| RSS | 62.906 MiB / 62.906 MiB |
| Lifetime peak footprint | 17.220 MiB / 17.220 MiB |
| On-screen windows | 0 / 0 |

Raw JSONL:
`.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/main-sync/final-dev-closed-bt-volume-off-60428-20261022.jsonl`.

`vmmap -summary` reported 1.12 MiB of `CG Raster Data`, down from the 9.9 MiB
closed-state observation before the renderer changes. The remaining region
split is small-object Malloc data rather than Bluetooth, CoreAudio, or an open
panel resource. The largest shallow heap entries were unclassified non-object
allocations, Swift metadata, and CoreFoundation dictionaries; the closed stack
showed no retained Bluetooth object graph. With both relevant popup sections
hidden and the replacement icon option off, there is no measured evidence that
Bluetooth monitoring is a meaningful closed-state component.

Final local verification on the same source passed `bash
scripts/verify-local.sh full`: 1,851 XCTest cases with seven existing opt-in
skips and zero failures, 731 Swift Testing cases, Release build, local app and
Helper contracts, and all offline release-pipeline checks. The Bluetooth-only
visibility regression and hidden Audio Input `completedScalarRequestID`
restoration are covered. An independent read-only review returned no Critical,
Important, or Minor findings and approved the tree for merge.

### First-open retention boundary

After PID `60428` had opened and closed the status panel, it remained at
27.22-27.25 MiB physical footprint for 11 samples with zero visible windows,
versus 14.24 MiB before the first open. RSS was 89.73-89.77 MiB. The cumulative
lifetime footprint peak was 301.28 MiB.

The retained frame is not the popover object tree:

- `heap` found no `StatusPopoverView`, `NSHostingController`, or duplicate
  popover tree. It found one controller, one `NSPopover`, and one 64-byte
  `NSHostingViewBase`.
- `leaks` reported about 19.5 KiB, chiefly LinkServices XPC cycles.
- `CG Raster Data` remained 1.12 MiB.
- `malloc_zone_pressure_relief(NULL, 0)` returned zero bytes during a live
  diagnostic probe, so adding a close-time allocator-relief call would not
  reduce this state.
- Existing native lifecycle tests retain weak references to both hosting
  controllers across 20 close/reopen cycles and verify that every one
  deallocates.

The remaining initial-use floor is distributed across live SwiftUI
metadata/AttributeGraph, ColorSync, and Metal/IOGPU/IOSurface caches. A clean
process restart returned PID `71336` to 14.204-14.329 MiB footprint
(66.09-66.22 MiB RSS), 16.923 MiB lifetime peak, and zero visible windows.
No source change was added for the framework cache because no app-owned object,
leak, or releasable allocator page was found. Separating the panel into another
process would be required to unload these framework caches, which is a much
larger lifecycle and IPC change than this optimization warrants.

## Main synchronization on 2026-10-21

The existing `codex/memory-optimization` worktree was fast-forwarded from
`99d6fa998187ba2d5beced13377ed9ceee6ca263` to the fetched `origin/main`
`e682e4bd6f7177672aa221b0547e0201e19152d3`. A second fetch after verification
confirmed the same main SHA. Uncommitted lifecycle work was restored from
backup stash `7d3d6cdd44921f9f5f4668945a2e378129ce3e9e`; the stash is retained.

The three textual conflicts were in `SystemStatusStore` and the two Bluetooth
Settings bindings. Integration keeps main's monitoring API name, radio power
controller, permission gates, and confirmed-write behavior. Power-off suspends
consumer reconciliation; power-on resumes only demand that still exists.
Bluetooth-only presentation now has its own shared listening-mode task identity
so HUAWEI discovery follows device and output membership without mapping or
publishing hidden volume rows. The view reads current HUAWEI presentations from
their controller, avoiding a second retained dictionary.

An inherited HUAWEI fixture directly activated a controller without registering
any demand. Its device-list and task-identity assertions failed after the
authorization callback correctly reconciled that missing demand. The fixture
now uses store startup and popover visibility, with the original assertions
preserved. Radio-power fixtures also stop their stores and use isolated report
caches.

| Final integrated-tree check | Result |
|---|---|
| `bash scripts/verify-local.sh full` | PASS, exit 0 |
| XCTest | 1,834 executed including 7 existing opt-in skips; zero failures |
| Swift Testing | 695 passed |
| Bluetooth permission and panel integration filter | 39 passed |
| Issue #30 / Menu Bar and Dock parity | 6 XCTest and 8 Swift Testing passed |
| Python sampler suite | 15 passed, 2 opt-in GUI skips |
| Conflict markers and `git diff --check` | None / PASS |
| Independent integration reviews | No Critical or Important findings |

The full profile includes the Release build, a local arm64 Ad-hoc app bundle,
SDK/platform and Helper checks, native dependency contracts, and offline release
simulations. Its built bundle ID is `com.lingsmbp.StatusTrio.dev.verify-local`;
executable SHA-256:
`e4fdd89b9a386590b04ec831576d4ef9e01b642b8aaf3a6cb36bbbb6758427a3`.

## Closed-panel icon-only phase (2026-10-22)

This phase measures the resident state when the status panel is closed and the
app presents only its menu-bar item. Panel hosting, SwiftUI material layers,
glass, detail sheets, and first-open costs are outside this phase. A closed
process reported zero on-screen CoreGraphics windows in the sampler runs.

The `CG Raster Data` region in this state was about 9.9 MiB. Component probes
showed that two unnecessary menu-bar symbol measurements dominated it:

- about 8.16 MiB came from the battery plug calibration drawing a 200-point
  symbol at 8x even though that calibration reads only the symbol's layout
  height;
- about 1.9 MiB came from measuring the center Wi-Fi symbol's visible ink at
  8x.

`StatusIconRenderer` now has a separate `configuredSymbolImage` factory for the
plug-height calibration and a measured-symbol path only where visible ink is
needed. The default ink measurement scale is 6x. A 5x sample put the default
Wi-Fi optical-alignment result at 0.462 point of error, above the existing
0.45-point acceptance threshold, so it was rejected. The 6x result remains
below the 0.25-point icon-grid quantum and passes
`Issue30WiFiAlignmentTests`.

The component A/B runs used the same Release binary and removed the temporary
measurement switches before the final source build:

| Connected, non-charging plug path | Physical footprint median | Lifetime peak |
|---|---:|---:|
| Legacy calibration that measured ink at 8x | 24.0 MiB | 56.1 MiB |
| Height-only calibration | 16.8 MiB | 19.7 MiB |

| Normal closed state | Physical footprint median | Lifetime peak |
|---|---:|---:|
| Wi-Fi ink measurement at 8x | 15.1 MiB | 20.0 MiB |
| Wi-Fi ink measurement at 6x | 14.6 MiB | 17.2 MiB |

The independent plug-path effect was about 7.2 MiB of steady physical footprint
and 36.5 MiB of lifetime peak avoidance. The independent 6x Wi-Fi effect was
about 0.5 MiB steady and 2.8 MiB peak avoidance. These are attribution
diagnostics; the lifetime peak is not a steady-state value.

Physical footprint is the process-owned memory measure used above. RSS is also
recorded because it exposes shared file-backed pages, but it can be much larger
than the app's attributable footprint and is not used to claim the savings.
Allocation mappings and lifetime peak are separate again. Activity Monitor's
process memory column is the practical place to observe the physical-footprint
effect; RSS from `ps` should not be compared as though it were the same metric.

With Bluetooth monitoring disabled and the Bluetooth-replaces-Wi-Fi option off,
the closed-state trace produced no evidence of a retained Bluetooth object
graph, discovery task, or ongoing Bluetooth work. The disabled panel sections
release their source subscriptions; visible audio rows keep only the Bluetooth
demand they actually need. The closed-state raster cost was owned by menu-bar
symbol rendering, not Bluetooth. The temporary probe sources are retained
under `.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/main-sync/`;
the production tree contains only the renderer fix.

## Latest main integration (2026-10-22)

`origin/main` advanced to `b642a1fe78be7062e3458a600d46b75f015526b6bd` while
the closed-panel work was active. The existing branch was fast-forwarded from
`e682e4bd6f7177672aa221b0547e0201e19152d3` to that commit. A pre-integration
workspace hash manifest and stash backup were retained. Restoring the local
work produced conflicts only in `StatusPanelViewModel` and its test file.

The resolution keeps main's popover-generation and currently-selected-output
parts of the listening-mode identity, main's AirPods discovery tests, and the
memory branch's demand-aware source subscriptions and presentation release.
It also adapts the local audio-input release path to main's
`completedScalarRequestID` field. No conflict was resolved by discarding one
side wholesale.

The final integrated tree passed `bash scripts/verify-local.sh full` at
`b642a1fe78be7062e3458a600d46b75f015526b6bd`: 1,851 XCTest cases with seven
existing opt-in skips and zero failures, 730 Swift Testing cases, the Release
build, the arm64 local app and Helper contracts, and all offline release-pipeline
checks. The 6x measurement changed the macOS 27 static pixel fingerprint; the
new `e08ab4…` value was stable across two runs and replaced the old local
fingerprint rather than being appended beside it.

The clean development bundle was rebuilt after verification as version
`1.6.0 (37)`, Bundle ID
`com.lingsmbp.StatusTrio.dev.memory-optimization`, executable SHA-256
`8a7e5e5ec6837ca853d9f9ccd3efa25895509b7a7eb8873f5d2fa2e4554cb1b4`.
PID 99800 was left running with the panel closed. A 30-second, 500 ms sampler
capture produced 61 samples:

| Metric | Median / peak |
|---|---:|
| Physical footprint | 14.063 MiB / 14.282 MiB |
| RSS | 62.781 MiB / 62.781 MiB |
| Lifetime peak footprint | 17.079 MiB |
| On-screen windows | 0 / 0 |

Raw JSONL:
`.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/main-sync/final-dev-closed-latest-main-99800-20261022.jsonl`.
This is a development-build spot check, not a multi-run release comparison.
It was not launched. The earlier memory-optimization development app was not
replaced or restarted during this synchronization.

Evidence is under
`.superpowers/sdd/2026-10-20-memory-lifecycle-optimization/main-sync/`;
`full.log` and `.build/local-verification/log.txt` record the full profile.
`tested-files.json` records hashes for changed source, test, and script paths;
they were unchanged throughout verification. The seven XCTest skips are
existing opt-in image-export and local telemetry-worker probes.

Changes remain uncommitted on the same branch and worktree. No push, remote
diagnostic, release, tag, DMG, or appcast publication was performed. Physical
hardware, macOS 13 runtime, WindowServer/Spaces, multi-display, and controlled
baseline/candidate memory measurements remain NOT RUN for this integrated tree.

## Disabled Bluetooth and Volume follow-up on 2026-10-22

The user disabled both popover sections in the running memory-development app
(PID 93796). Its persisted enabled sections were Battery and Network; Bluetooth
icon replacement, Apple-device batteries and background refresh were disabled.
The executable still matched the 2026-10-21 development build.

| Existing development process | Before the user's open/close cycle | After the cycle |
| --- | --- | --- |
| Physical footprint median, 41 samples over 20 seconds | 66.360 MiB | 66.501 MiB |
| RSS median | 217.484 MiB | 217.813 MiB |
| Process lifetime peak footprint | 514.517 MiB | 514.517 MiB |

These samples were taken after the user operated the panel, so they do not
capture its opening peak. The 0.141 MiB median difference does not establish a
leak or a feature's memory cost. Five-second stack samples captured no Bluetooth
or audio-device read work; they cannot prove every listener was inactive.
The heap capture still contained the Bluetooth controller (896 bytes shallow)
and profiler cache (64 bytes shallow), which excludes their referenced objects
and shared-framework costs. Approximately 10 MiB of CG Raster Data remained.

Code inspection identified a separate, reproducible source of unnecessary work:
`SystemStatusStore.updateDetailsVisibility()` enabled audio output details for
every open popover, even when both consuming sections were disabled. The
follow-up gates those details on a visible Volume or Bluetooth section, retaining
the independent Settings-window owner and legacy unbound API. Bluetooth-only
panels still need audio output membership for listening modes. Delivered
Settings values drive immediate changes and rebinding; enabling a consumer in
an already open panel also refreshes its device list. Unrelated Settings
changes do not repeat the detail read.

Base volume listeners and icon snapshots remain active. Losing the final detail
consumer uses `VolumeMonitor`'s existing list-cache clearing path. This change
removes unnecessary reads and retained detail lists; no measured MiB saving is
claimed.

The new `VolumeDetailsDemandTests` first reproduced nine assertion failures
across six tests without a compilation error. After the fix, the focused
VolumeDetails, Store, VolumeMonitor, BluetoothDemand and StatusPanelDemand filter
passed 147 tests. Evidence lives in the same `main-sync` directory:
`volume-details-red.log`, `volume-details-green.log`, and the
`disabled-bt-volume-*` / `after-panel-cycle-*` captures.

The follow-up branch base remains `e682e4bd6f7177672aa221b0547e0201e19152d3`.
The fetched `origin/main` is now `7071fbe90e1806ff757d630aaecbccf03b88a7d9`;
its Store change concerns microphone request IDs outside this patch. These
new upstream microphone, UI and documentation changes are not included in this
follow-up or its development bundle.

Independent review found no production defect in the follow-up, and required
the new tests to use fake Bluetooth readers, a denied state monitor and an
isolated profiler cache. The revised fixture also proves Settings can own
details with all popover sections off and that unrelated setting changes do
not read details while they are off.

The first full profile stopped at
`DDCVolumeCoordinatorTests.testFailedReadsBackOffAndCapAtSixtySeconds` with
12 cascading timeout assertions; Swift Testing's 695 tests passed. The DDC
filter then passed 20/20 as a diagnostic, not a retry-based acceptance.
Inspection identified a test-clock ambiguity: the initial read watchdog and
first backoff both used the same injected two-second sleep, so the test could
advance the watchdog before the initial read completed and mistake that read
for the next retry. The two backoff tests now use a distinct one-second
watchdog; their original backoff and recovery assertions are unchanged.
No production DDC timing or timeout was changed.

The final combined filter, including the DDC tests and isolated fixture,
passed 167/167. The original failure remains in `volume-details-full.log`;
`volume-details-ddc-diagnostic.log` and `volume-details-final-focused.log`
record the diagnostic and final focused run.

The final full local profile passed on the integrated tree at HEAD
`e682e4bd6f7177672aa221b0547e0201e19152d3`: 1,830 XCTest executed with seven
existing opt-in skips and zero failures, 695 Swift Testing tests across 103
suites passed, and the Release build plus application, Helper, SDK, dependency
and offline release-pipeline contracts passed. Production Swift source hashes
were unchanged between the candidate development-app build and final
verification. The full result is `volume-details-final-full.log`.

The updated development bundle replaced only the previous Memory Optimization
instance (PID 93796) and launched as PID 37298. The old bundle is retained at
`dist-dev/Status Trio (Memory Optimization).backup-20261022-114106.app`.
Its Bundle ID remains `com.lingsmbp.StatusTrio.dev.memory-optimization`; deep
strict signature verification passed. The persisted sections remained Battery
and Network, with Bluetooth icon replacement, Apple-device batteries and
background refresh still disabled.

After restart, 41 passive closed-panel samples over 20 seconds held at
23.063-23.110 MiB physical footprint (23.079 MiB median), with 92.641-92.688
MiB RSS and zero visible windows. This fresh-process run peaked at 59.985 MiB,
versus the previous long-lived process's lifetime peak of 514.517 MiB. Those
numbers are different process lifetimes, so their difference is not a claimed
saving from this patch. A five-second stack sample contained no Bluetooth,
CoreAudio, volume-detail or DDC work at the sampled instants. About 9.9 MiB of
CG Raster Data remained, so the fix did not remove all graphics resources.
After the user opened and closed the panel, the same PID retained a bounded
first-open cost but did not continue growing. Raw evidence is
`volume-details-fixed-closed-37298-20261022.jsonl`, its `.sample.txt`, `.vmmap.txt`
and `.summary.json` files.

### Post-open retention on PID 37298

The user opened and closed the panel once with Bluetooth and Volume still
disabled. A second passive capture sampled the unchanged PID 41 times over 20
seconds:

| Measurement | Closed after restart | After one open/close | Settled 20 seconds later |
| --- | ---: | ---: | ---: |
| Physical footprint median | 23.079 MiB | 35.626 MiB | 35.579 MiB |
| Physical footprint range | 23.063-23.110 MiB | 35.548-35.688 MiB | 35.532-35.610 MiB |
| RSS median | 92.656 MiB | 119.688 MiB | 119.750 MiB |
| Visible windows | 0 | 0 | 0 |

The first open/close cycle added 12.547 MiB of median physical footprint. A
later settled capture was only 0.047 MiB below the first post-cycle median, so
the result is a bounded first-use allocation rather than continued growth.
Manual post-cycle retention acceptance therefore passed for this process.

A five-second stack sample after close contained no Bluetooth, CoreAudio,
volume-detail or DDC work at the sampled instants. This is sampled evidence,
not proof that no listener can run between samples. `vmmap` still reported
9.9 MiB of CG Raster Data, unchanged from the closed baseline. IOAccelerator
graphics increased from the earlier 64 KiB resident to 736 KiB and IOSurface
reported 1.088 MiB resident. The heap retained small owning objects
(`StatusPanelViewModel` 2,048 bytes shallow, `BluetoothDeviceController` 896,
`VolumeMonitor` 448 and `DDCVolumeCoordinator` 320), while Swift metadata and
shared framework/runtime mappings dominated the remaining footprint. The heap
size histogram also contained 12,784 KiB and 8,192 KiB non-object allocations
without owner stacks; they cannot be attributed to the panel from this capture.

The evidence therefore points to loaded SwiftUI/AppKit and graphics runtime
state plus allocator residency as the main post-open cost, not ongoing
Bluetooth or audio-detail polling. A further reduction would require a focused
first-open framework/graphics investigation with ownership stack evidence;
there is no safe product-code change identified by this measurement.

Evidence is
`volume-details-fixed-after-panel-37298-20261022.jsonl`,
`volume-details-fixed-after-panel-37298-20261022.{comparison.json,sample.txt,vmmap.txt}`
and
`volume-details-fixed-after-panel-settled-37298-20261022.{jsonl,heap.txt}`.
Controlled baseline/candidate A/B runs, multi-display and Spaces behavior, and
macOS 13 runtime checks remain NOT RUN.

### First-open allocation stack follow-up

A temporary release-probe bundle used the production menu-bar toggle path with
full `MallocStackLogging` and the same preferences. The temporary probe source
was removed afterward and the regular distribution bundle was rebuilt from the
restored source.

The largest live-allocation deltas after the first open/close were:

| Allocation owner | Delta |
| --- | ---: |
| ColorSync `CMMMemMgr::New` | 3.102 MiB |
| IOGPU `IOGPUResourceCreate` | 2.938 MiB |
| IOSurface `IOSurfaceClientCreateChild` | 1.062 MiB |
| Swift metadata allocator | 1.047 MiB |
| AttributeGraph table | 1.000 MiB |
| C++ typed allocations | 0.954 MiB |

The largest individual groups included a 1.520 MiB IOGPU resource, a 1.088 MiB
IOSurface, a 1.024 MiB AttributeGraph table reached through
`installPopoverContentIfNeeded`, four 771 KiB ColorSync allocations reached
through SwiftUI drawing, and another 768 KiB IOGPU resource. SwiftUI layout and
text metrics, CoreText shaping, Metal resource/setup state, Swift metadata and
Objective-C caches account for most of the rest.

The production menu-bar path added 3.001 MiB with
`StatusBarController.presentPopover` as the first application frame and
1.063 MiB with `installPopoverContentIfNeeded`. These application-frame groups
overlap the allocation-owner table and must not be added together. No large
group reaches `SystemStatusStore`, `BluetoothDeviceController`,
`VolumeMonitor`, `DDCVolumeCoordinator` or another device-detail owner.

MallocStackLogging itself inflated the instrumented footprint, so its raw
36.4-to-84.3 MiB header values are not product measurements. The uninstrumented
41-sample result remains 23.079-to-35.626 MiB. The normal post-close `vmmap`
matched the stack evidence with 736 KiB resident IOAccelerator graphics and
1.088 MiB IOSurface; CG Raster Data stayed at 9.9 MiB.

`leaks` could not fully inspect the release task because macOS reported it as
not debuggable. Its 294 root cycles totaling 14,768 bytes were dominated by
LinkServices XPC state and are too small and unrelated to account for the
popover delta. A complete leak pass remains NOT RUN.

No high-confidence product change follows from this probe. The residual cost
is created by the first SwiftUI layout and owned mainly by Apple framework,
Graphics and metadata caches. A possible future experiment would compare the
current material/color presentation against a simpler renderer, but that needs
full visual and Menu Bar/Dock parity review. Evidence and method are recorded in
`main-sync/allocation-probe-20261022/report.md`.
