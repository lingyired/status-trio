# Continuous Dock charging animation performance gate

## Decision

Dock charging animation is disabled, including steady playback and short plug-in or level-change bursts. The 10 fps implementation averaged 16.60% Status Trio CPU across three runs. The 5 fps fallback averaged 7.78% in its 60-second run. Both exceed the 3% limit, so Dock animation controls and phase rendering were removed. The Dock icon stays static and reflects actual battery status, including while the menu bar's charging bolt plays its heartbeat response. Menu bar charging animation and its development test switch remain available.

The current `applicationIconImage` approach does not meet the CPU budget. Any future attempt should first prototype `NSDockTile.contentView` with explicit `display()` and compare app and Dock CPU; no claim is made that this approach will be cheaper.

## Setup and method

- Date: 2026-09-24
- Machine: Mac15,9, arm64, macOS 27.0 (26A428)
- Toolchain: Xcode 27.0 (27A266a), Swift 6.4; local toolchain is newer than the project CI toolchain.
- App: branch `feature/charging-effects`, debug `.dev.` bundle built by `bash scripts/build-worktree.sh debug no-open`; SDK assertion passed for macOS SDK 26.0.
- Placement: Both; master charging effect on; development test-charging input on; Settings closed during samples.
- Sampling: `top -l 61 -s 1 -pid <PID> -stats pid,command,cpu,mem`. Each result below is the arithmetic mean and peak of the 61 per-process `%CPU` samples. Dock was sampled concurrently in its own `top` process. RSS is the observed `MEM` range.
- Raw captures are under [`artifacts/`](artifacts/). Runs 1–3 alternate steady Dock animation on/off. An additional off run and a test-input-off diagnostic were collected to investigate one anomalous off run.

## Results

| Mode | Run | Status Trio mean / peak CPU | Status Trio RSS | Dock mean / peak CPU |
|---|---:|---:|---:|---:|
| 10 fps steady Dock | On 1 | 16.71% / 20.60% | 98–102 MB | 4.42% / 14.10% |
| 10 fps steady Dock | Off 1 | 1.44% / 5.20% | 88 MB | 0.01% / 0.60% |
| 10 fps steady Dock | On 2 | 16.24% / 19.30% | 119–123 MB | 4.13% / 11.20% |
| 10 fps steady Dock | Off 2 | 1.55% / 6.10% | 106 MB | 0.02% / 0.70% |
| 10 fps steady Dock | On 3 | 16.60% / 22.30% | 139–142 MB | 3.95% / 5.30% |
| 10 fps steady Dock | Off 3* | 17.04% / 21.60% | 147–153 MB | 0.19% / 6.60% |
| 10 fps steady Dock | Off 4 | 1.76% / 6.20% | not retained | 0.01% / 0.20% |
| 5 fps steady Dock | On 1 | 7.78% / 12.30% | 86–89 MB | 2.05% / 2.80% |

The 10 fps on-run median is 16.60%; the median of the first three off runs is 1.55%, despite the anomalous Off 3 result. Off 4 returned to 1.76%. Turning the test-charging input off for a separate 16-sample diagnostic reduced Status Trio to 0.08% mean CPU, confirming that this development input also drives the menu bar animation. The raw measurements are retained rather than silently discarding the inconsistent run.

The 5 fps fallback is still 4.78 percentage points above the 3% absolute limit. It is therefore disabled. Its sample followed an app restart, so its RSS is not used for a paired memory-increment claim. The two normal 10 fps on/off pairs showed roughly 12–15 MB higher RSS while on; memory was below the 40 MB allowance in those pairs, but CPU failed decisively.

The controller tests verify that menu bar test mode does not change Dock artwork, menu bar clock phases do not rerender the Dock, and battery status changes still refresh the static Dock icon. Menu bar animation behavior remains covered by the clock and status bar tests.

## Raw samples

- 10 fps: [`charging-effects-on-1-app.txt`](artifacts/charging-effects-on-1-app.txt), [`charging-effects-on-1-dock.txt`](artifacts/charging-effects-on-1-dock.txt)
- 10 fps: [`charging-effects-off-1-app.txt`](artifacts/charging-effects-off-1-app.txt), [`charging-effects-off-1-dock.txt`](artifacts/charging-effects-off-1-dock.txt)
- 10 fps: [`charging-effects-on-2-app.txt`](artifacts/charging-effects-on-2-app.txt), [`charging-effects-on-2-dock.txt`](artifacts/charging-effects-on-2-dock.txt)
- 10 fps: [`charging-effects-off-2-app.txt`](artifacts/charging-effects-off-2-app.txt), [`charging-effects-off-2-dock.txt`](artifacts/charging-effects-off-2-dock.txt)
- 10 fps: [`charging-effects-on-3-app.txt`](artifacts/charging-effects-on-3-app.txt), [`charging-effects-on-3-dock.txt`](artifacts/charging-effects-on-3-dock.txt)
- 10 fps: [`charging-effects-off-3-app.txt`](artifacts/charging-effects-off-3-app.txt), [`charging-effects-off-3-dock.txt`](artifacts/charging-effects-off-3-dock.txt)
- Additional baseline: [`charging-effects-off-4-app.txt`](artifacts/charging-effects-off-4-app.txt), [`charging-effects-off-4-dock.txt`](artifacts/charging-effects-off-4-dock.txt)
- 5 fps: [`charging-effects-5fps-on-app.txt`](artifacts/charging-effects-5fps-on-app.txt), [`charging-effects-5fps-on-dock.txt`](artifacts/charging-effects-5fps-on-dock.txt)
- Diagnostic: [`charging-effects-diagnostic-app.txt`](artifacts/charging-effects-diagnostic-app.txt), [`charging-effects-diagnostic-dock.txt`](artifacts/charging-effects-diagnostic-dock.txt)
