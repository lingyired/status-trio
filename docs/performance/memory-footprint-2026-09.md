# Status Trio memory footprint baseline (2026-09-24)

## Scope and environment

This is a read-only observation of the already-running process. No signal was sent and the app was not relaunched. It is **not a cold-start baseline** and cannot satisfy the plan's controlled scenario or three-run acceptance gate.

| Field | Observed value |
|---|---|
| Executable | `/Users/lingsmbp/Documents/aiwork/status-trio/dist/StatusTrio.app/Contents/MacOS/StatusTrio` |
| App version/build | 1.3.2 (15), from `dist/StatusTrio.app/Contents/Info.plist` |
| Executable SHA-256 | `8d19d62938fc67f6848a378c6b0fdbed437341be720bff29f95ff7aea80c5cbe` |
| Repository HEAD | `6505cd8be09d58ec85347f2265e50b835203d830` |
| Code signing | Ad-hoc; `TeamIdentifier=not set` |
| OS / architecture | macOS 27.0 (26A428), arm64 |
| Local toolchain | Xcode 27.0 (27A266a), Swift 6.4; this is not the plan's CI toolchain |
| Minimum OS | 15.0 |
| Power | AC attached, battery 80%, **not charging** |
| Display | 4096×2304 physical, UI Looks like 2048×1152 @ 100 Hz (2× backing scale) |
| App placement | `appIconPlacement=menuBar` |
| Process at first observation | PID 33850; elapsed 53:50–54:18 |
| UI history | Whether popover, Settings, or Dock UI had been opened is unknown. No controlled interaction state was established. |
| Build SDK | Not recorded in the app's Info.plist (`DTSDKName` absent); cannot certify this artifact's SDK from this run. |

## Samples captured

Commands used for the initial observations:

```sh
ps -p 33850 -o pid,etime,rss,command
footprint -p 33850
vmmap -summary 33850
```

| Local time (CST) | Process state / elapsed | RSS | `footprint` current / peak | `vmmap -summary` physical total | Notes |
|---|---:|---:|---:|---:|---|
| 19:27:52 | Running / 53:56 | 226,672 KB | 129 MB / 535 MB | 129.1 MB dirty; 77.3 MB malloc-zone resident | First complete read. |
| 19:28:20 | Running / 54:18 | 226,496 KB | 129 MB / 535 MB | 129.0 MB dirty; 77.1 MB malloc-zone resident | Second complete read, 28 seconds later. |
| 19:28:51 | PID absent | unavailable | unavailable | unavailable | `ps` had no row; `footprint` and `vmmap` reported PID no longer running. |
| 19:29:21 | PID absent | unavailable | unavailable | unavailable | Confirmed absent; no relaunch attempted. |

The two complete observations are nearly unchanged over 28 seconds: RSS differs by 176 KB and reported footprint stays 129 MB. This says nothing about a cold idle trajectory or a long-run slope. The recorded peak is lifetime high water and its cause/time are unknown.

### Major regions in the complete samples

`footprint` category values (dirty unless noted):

| Category | 19:27:52 | 19:28:20 |
|---|---:|---:|
| Malloc Small | 73 MB | 73 MB |
| CoreAnimation | 13 MB | 13 MB |
| CG Raster Data | 14 MB | 12 MB |
| CG Image | 4.5 MB | 4.5 MB |
| IOSurface | 3.2 MB | 3.2 MB |
| Stack | ~0.4 MB | ~0.4 MB |

The vmmap malloc-zone summary at 19:27:52 reported 39.7 MB allocated and 32.0 MB fragmentation in the default malloc zone. Across malloc zones it reported 41.9 MB allocated and 34.2 MB fragmentation. These are allocator accounting figures, not proof of a leak. No allocation backtraces or Instruments Allocations trace were collected.

## Limits and next measurement protocol

- The process was already approximately 54 minutes old when observed; prior activity and UI state are unknown. The observed 129 MB must not be labeled a cold-start value or regression.
- The process vanished during sampling, apparently independently of this read-only measurement. The cause is unknown; no crash or user action is inferred.
- The original long-running process has only two complete samples, 28 seconds apart. One fresh menu-bar-only run was sampled at 2:23; the exact nominal 2:00 point, 10/60-minute points, and additional launches for a three-run median are missing. There is no v1.2.1 comparator, no controlled popover/Settings/Dock state, and no charging A/B result.
- macOS 27.0 and local Xcode/Swift are outside the plan's macOS 26 / Xcode 26.6 / Swift 6.3.3 CI environment. The app artifact's SDK was not verified.

For a valid baseline, on a later authorized session when a fresh app launch is safe, record the exact binary and environment, explicitly confirm a fresh process and menu-bar-only placement, then save timestamped `ps`, `footprint`, and full `vmmap -summary` output at 2, 10, and 60 minutes. Repeat that cold-idle run three times. Capture popover and Settings open/closed states as separate controlled runs, and Dock placement separately. Use the same OS, artifact style, and metric for any v1.2.1 comparison. If heap attribution is needed, use a debuggable build with Instruments Allocations and Malloc Stack Logging. Do not use this partial observation to select a production optimization task.

## Fresh menu-bar-only idle sample

Following confirmation that `pgrep -x StatusTrio` returned no process and that the persisted placement was `menuBar`, the existing `dist/StatusTrio.app` was launched once. No popover or Settings window was opened during this run; no settings were changed. The app was left running after measurement.

| Field | Observation |
|---|---|
| Launch time | 2026-09-24 19:31:10 CST |
| Sample time | 2026-09-24 19:33:33 CST |
| Elapsed | 2:23 (sample taken 23 seconds after the nominal 2-minute point) |
| Process | PID 48824; still running at sample time |
| Scenario | Fresh launch, menu-bar placement, popover and Settings unopened |
| RSS | 58,672 KB |
| `footprint` | 17 MB current; 18 MB peak |
| `vmmap -summary` | 17.4 MB dirty total; 10.5 MB malloc-zone resident |
| Major `footprint` regions | Malloc Small 9,840 KB; CoreAnimation 32 KB; CG Raster Data not listed; CG Image 80 KB; Stack 224 KB; IOSurface not listed |

The fresh menu-bar-only sample is substantially below the earlier long-running process sample (17 MB versus 129 MB physical footprint; 58,672 KB versus 226,496 KB RSS). Because the earlier process had unknown UI history and this is one run on macOS 27.0, this difference does not isolate an interaction cost or establish a build regression. It is a single observation, not a median.

The 10-minute and 60-minute points, additional two-minute launches for a three-run median, and controlled popover/Settings/Dock scenarios remain outstanding. Keep PID 48824 running; capture later idle points against this same process only if it remains the same process and no UI is opened.

### Follow-up observation with Settings visible

| Local time (CST) | Process state / elapsed | RSS | `footprint` current / peak | `vmmap -summary` physical total | Notes |
|---|---:|---:|---:|---:|---|
| 19:35:01 | Running / 3:51 | 162,080 KB | 71 MB / 339 MB | 70.7 MB physical | Settings' App Icon pane was visible when inspected. The time at which the window became visible is unknown, so this is not a controlled before/after delta. |

At this observation, `vmmap` attributed about 33.7 MB dirty/resident to Malloc Small, 5.36 MB to CoreAnimation, 5.2 MB to CG Raster Data, 3.3 MB to CG Image, 0.27 MB to IOSurface, and 0.34 MB to stack. Compared with the earlier 17 MB sample, both elapsed time and UI state changed; the increase cannot be assigned to opening Settings. The 339 MB peak is lifetime high water and likewise has no known trigger. A controlled preview open/close sample is still required.

At elapsed 6:55, the same PID reported RSS 174,960 KB and current footprint 83 MB (peak still 339 MB). `Malloc Small` was 43 MB, `CoreAnimation` 9.2 MB, `CG Raster Data` 8.2 MB, and `CG Image` 4.3 MB. This short follow-up is another observation with Settings visible, not evidence of a steady growth slope; the view state and allocations during the interval were not controlled.

The Settings window was then closed through its normal close shortcut. At 19:39 (elapsed about 8:02), the process reported RSS 188,960 KB and footprint 90 MB (peak 362 MB). At 19:40:38 (elapsed 9:28), with no app window open for roughly one minute, it remained at RSS 188,880 KB and footprint 90 MB. Categories at the settled sample were Malloc Small 51 MB, CoreAnimation 9.5 MB, CG Raster Data 8.2 MB, and CG Image 2.3 MB. This suggests the window interaction left allocations resident for at least one minute, but the window-open time and exact initiating action are unknown, so it still does not isolate a specific preview render or prove an object leak. It does support prioritizing an instrumented preview open/close A/B.

At elapsed 11:28 (19:42 CST), about 3:26 after closing the Settings window, the same process remained at 90 MB footprint and 188,192 KB RSS. This is a settled post-interaction retention sample, **not** the plan's cold 10-minute point.

### Matched cold-idle repeat (2026-09-24)

To compare the base and preview-optimized code on the same machine with the same bundle ID and saved `menuBar` preference, I relaunched each release app and left its UI unopened. Both were built with the same macOS 26 SDK; base is the v1.3.2 (15) app already in `dist`, and the candidate is built from the optimized worktree as v1.3.3 (16). These are one-run samples, not three-run medians.

| Build | Local sample time (CST) | Elapsed | RSS | `footprint` current / peak | `vmmap` physical | Malloc Small | CG Image | CG Raster Data | CoreAnimation |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Base v1.3.2 (15) | 20:05:39 | 2:19 | 61,888 KB | 17 / 17 MB | 17 MB | 9.5 MB | 80 KB | not listed | 32 KB |
| Candidate v1.3.3 (16) | 20:08:21 | 2:19 | 58,304 KB | 17 / 17 MB | 17 MB | 9.4 MB | 80 KB | not listed | 32 KB |

The cold-idle physical footprint is unchanged at the tool's 1 MB display precision, with no new graphics footprint visible. This is consistent with the preview cache being lazy and having no idle Dock allocation when Settings and the guide are unopened. An earlier 44 MB reading used a fresh, different bundle ID and occurred while the Mac was locked, so the UI state and preferences were not controlled; it is excluded from this comparison. The original 17 MB sample and this repeat also remain below 100 MB physical footprint, while RSS is about 58–62 MB. If the reported “100 MB” comes from another metric or a post-Settings scenario, compare that same display and interaction state separately.
