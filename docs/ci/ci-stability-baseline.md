# Release CI stability baseline

Audit date: 2026-10-26. Repository: `lingyired/status-trio`.
Baseline: `origin/main` at `e5cd7954ee35677a46d796eedf33d39699f17b52`.

This is a read-only baseline of the 26 newest `release.yml` runs available at
audit time. It distinguishes observed behavior from inference. It does not
publish, dispatch, tag, or modify a release.

## Method

The runs were listed and read with read-only `gh` commands:

```bash
gh run list --repo lingyired/status-trio --workflow release.yml \
  --limit 30 --json databaseId,headSha,status,conclusion,createdAt,updatedAt,url
gh run view <RUN_ID> --json jobs
gh api --allow-escape-sequences \
  repos/lingyired/status-trio/actions/jobs/<JOB_ID>/logs
```

For the selected sample, all 15 failed-job logs were read. Successful logs were
opened only for the package/publish and stage-timing evidence needed below.
Full successful logs were not downloaded indiscriminately.

Definitions used in the inventory:

- **Wall**: `updated_at - run_started_at`, rounded to whole seconds.
- **Active**: the sum of each non-skipped job's
  `completed_at - started_at`.
- **Unattributed**: `wall - active`. It can contain runner scheduling,
  environment approval, artifact handoff, and other gaps. It is not called
  "approval time" unless the logs show a specific approval/queue boundary.
- **SHA in the inventory**: the run's recorded `head_sha`. This is the run
  head, not independent proof of the dispatched candidate. Recovery runs use a
  newer workflow commit as their run head while retaining the original package
  candidate; the detailed evidence below records that distinction.

Skipped jobs can expose sentinel timestamps (the API showed a start later than
the end). They are excluded from active time. Durations are observations from
GitHub metadata, not runner CPU seconds or a local benchmark.

## 26-run inventory

All links below are public workflow-run links.

| Run | SHA | Result | Wall | Active | Unattributed | Stage timings (seconds) |
| --- | --- | --- | ---: | ---: | ---: | --- |
| [40349355595](https://github.com/lingyired/status-trio/actions/runs/40349355595) | `2b0d7a5caf17` | success | 611s | 556s | 55s | verify 520; publish 36; package skipped |
| [40347873632](https://github.com/lingyired/status-trio/actions/runs/40347873632) | `57828a41960e` | failure | 31s | 25s | 6s | verify 25; package/publish skipped |
| [40344113013](https://github.com/lingyired/status-trio/actions/runs/40344113013) | `57828a41960e` | success | 1,205s | 1,101s | 104s | verify 485; package 616; publish skipped |
| [40341717461](https://github.com/lingyired/status-trio/actions/runs/40341717461) | `07ed1ab221bb` | failure | 337s | 331s | 6s | verify 331 |
| [40335449161](https://github.com/lingyired/status-trio/actions/runs/40335449161) | `3ea2de3f6d28` | failure | 277s | 272s | 5s | verify 272 |
| [40333652240](https://github.com/lingyired/status-trio/actions/runs/40333652240) | `b018eb741caa` | failure | 344s | 338s | 6s | verify 338 |
| [40112321642](https://github.com/lingyired/status-trio/actions/runs/40112321642) | `6265b6422298` | success | 1,160s | 532s | 628s | verify 503; publish 29; package skipped |
| [40110818728](https://github.com/lingyired/status-trio/actions/runs/40110818728) | `6265b6422298` | failure | 1,066s | 972s | 94s | verify 394; package 563; publish 15 |
| [40106014873](https://github.com/lingyired/status-trio/actions/runs/40106014873) | `17fa060e4be2` | success | 1,036s | 970s | 66s | verify 354; package 591; publish 25 |
| [39932737472](https://github.com/lingyired/status-trio/actions/runs/39932737472) | `c965743abd2f` | success | 519s | 408s | 111s | verify 375; publish 33; package skipped |
| [39929918779](https://github.com/lingyired/status-trio/actions/runs/39929918779) | `6d3d5efded05` | failure | 642s | 494s | 148s | verify 481; publish 13; package skipped |
| [39923069756](https://github.com/lingyired/status-trio/actions/runs/39923069756) | `af7f637f186c` | failure | 1,489s | 1,115s | 374s | verify 330; package 765; publish 20 |
| [39899558271](https://github.com/lingyired/status-trio/actions/runs/39899558271) | `03a858489236` | success | 1,209s | 1,187s | 22s | verify 305; package 882; publish skipped |
| [39825794228](https://github.com/lingyired/status-trio/actions/runs/39825794228) | `b17a9a7dc703` | success | 979s | 915s | 64s | verify 293; package 622; publish skipped |
| [39824152450](https://github.com/lingyired/status-trio/actions/runs/39824152450) | `bd980186119d` | failure | 301s | 296s | 5s | verify 296 |
| [39822549809](https://github.com/lingyired/status-trio/actions/runs/39822549809) | `6a061ce705ab` | failure | 355s | 350s | 5s | verify 350 |
| [39821223609](https://github.com/lingyired/status-trio/actions/runs/39821223609) | `461eb07c6eff` | failure | 335s | 330s | 5s | verify 330 |
| [39819697604](https://github.com/lingyired/status-trio/actions/runs/39819697604) | `1e3d23e4a7a5` | failure | 276s | 272s | 4s | verify 272 |
| [39817193272](https://github.com/lingyired/status-trio/actions/runs/39817193272) | `b292443f099d` | failure | 314s | 295s | 19s | verify 295 |
| [39817139417](https://github.com/lingyired/status-trio/actions/runs/39817139417) | `b292443f099d` | cancelled | 36s | 31s | 5s | verify 32 (cancelled) |
| [39809532587](https://github.com/lingyired/status-trio/actions/runs/39809532587) | `40685c4dcbcd` | failure | 257s | 252s | 5s | verify 252 |
| [39460291539](https://github.com/lingyired/status-trio/actions/runs/39460291539) | `daacfe7c0c34` | success | 1,241s | 1,068s | 173s | legacy release job 1,068 |
| [39457652321](https://github.com/lingyired/status-trio/actions/runs/39457652321) | `be93f4dec926` | failure | 457s | 441s | 16s | legacy release job 441 |
| [39453350816](https://github.com/lingyired/status-trio/actions/runs/39453350816) | `065a6789846a` | success | 993s | 981s | 12s | legacy release job 981 |
| [39451283618](https://github.com/lingyired/status-trio/actions/runs/39451283618) | `f2209af2fa4f` | failure | 347s | 336s | 11s | legacy release job 336 |
| [39449716319](https://github.com/lingyired/status-trio/actions/runs/39449716319) | `c21106e2b585` | cancelled | 546s | 220s | 326s | legacy release job 220 (cancelled) |

Sample totals: 9 success, 15 failure, 2 cancelled. These are the 26 newest
release-related runs returned at audit time, not a statistically complete
history of the workflow.

## Latest full and recovery evidence

### Full verify/package run

`40344113013` used candidate
`57828a41960eccae5b62d0f66e90fca9b74ad8c1`, verified it for 485 seconds,
then packaged for 616 seconds. Its package log ended with:

```text
signing=developer_id, notarization=accepted_and_stapled
```

The run wall was 1,205 seconds (20m05s). The gap from verify completion
(`15:02:59Z`) to package start (`15:04:37Z`) was 98 seconds. Publish was
skipped because this was a package-only run.

### Publish recovery

`40349355595` was a recovery-only run. Its recorded run head was
`2b0d7a5caf17596b228b15698b7c0278a49ae0dc`, while its package source was
`40344113013` and candidate
`57828a41960eccae5b62d0f66e90fca9b74ad8c1`.

The verify job ran for 520 seconds. The publish job ran for 36 seconds. The gap
between verify completion (`15:35:24Z`) and publish start (`15:36:13Z`) was
49 seconds. The publish log validated the original artifact
(`12662021620`, SHA-256
`71ce144a6de99a17083b934b8c88ff3f99a8f3b87c7412a5d191314172ffeaf0`)
and did not rebuild the app. It published v1.7.5 at 15:36:45Z with:

```text
Signing: developer_id; notarization: accepted_and_stapled.
```

`40112321642` is the clearest example that wall time is not working time. It
had 503 seconds of verify, 29 seconds of publish, and a 623-second gap before
publish (10m23s). Its 1,160-second wall includes that gap. The logs establish
the gap, but do not prove that every second was reviewer approval; queue and
environment scheduling are included in the category.

## Failure ledger

Each entry records the failed job/step and the first actionable failure in the
job log. "Current state" refers to repository evidence visible on this
baseline; a later green run is not proof that every adjacent release path was
exercised.

| Run | Failed stage | Exact observed failure | Fix/current state |
| --- | --- | --- | --- |
| [40347873632](https://github.com/lingyired/status-trio/actions/runs/40347873632) | verify / `Validate frozen package source run` (3s) | `Release recovery error: source run did not conclude with the expected publish failure.` The source was `40344113013`, which had succeeded as a package-only run. | Fail-closed behavior, not a build failure. Commit `2b0d7a5c` later accepts a verified package-only source, and `40349355595` validated it and published successfully. |
| [40341717461](https://github.com/lingyired/status-trio/actions/runs/40341717461) | verify / `Run tests` | `MobileBatteryHelperReaderTests.swift:300`: `clock.now - started < .seconds(2)` was false; measured `2.081378792s`. The deadline, SIGKILL, and reaping assertions passed. | `57828a41` changed the test to observe the launched child instead of racing a PID file and added the documented kill/drain allowance. The later full run `40344113013` passed tests. |
| [40335449161](https://github.com/lingyired/status-trio/actions/runs/40335449161) | verify / `Run tests` | `AppIconPreviewTests.swift:117`, decoded artwork comparison failed for both light and dark; both sides displayed `4,194,304 bytes` (decoded byte counts), so byte size did not identify the pixel difference. | The observed CI artwork differed at anti-aliased Wi-Fi edges. `07ed1ab2` retained exact decoded-RGBA fingerprints and approved explicit local/CI pairs; no tolerance was added. A later full run passed. |
| [40333652240](https://github.com/lingyired/status-trio/actions/runs/40333652240) | verify / `Run tests` | `AppIconPreviewTests.swift:102`: light `72,619` versus expected `69,951` bytes; dark `71,023` versus expected `69,428` bytes. | Same CI/local rendering-boundary investigation. `07ed1ab2` added exact paired fingerprints; a later full run passed. |
| [40110818728](https://github.com/lingyired/status-trio/actions/runs/40110818728) | publish / `Publish the verified package without rebuilding` (6s) | `Created draft Release v1.7.4 but could not discover it in the release list.` Verify and package had succeeded (package 563s). | `b471b7f6` added bounded Draft Release discovery retries and process-drain stabilization. Recovery `40112321642` later published successfully from the original package artifact. |
| [39929918779](https://github.com/lingyired/status-trio/actions/runs/39929918779) | publish / `Recover publication from the verified source artifact` | The publish checkout was `6d3d5efded05`, but the manifest/source artifact belonged to `af7f637f186c`; logs show the trusted-tooling check and expected source run. The recovery rejected the mismatch before publication. | `c965743a` switched the publisher to the explicit candidate identity instead of workflow context. `39932737472` later completed recovery successfully. |
| [39923069756](https://github.com/lingyired/status-trio/actions/runs/39923069756) | publish / `Publish the verified package without rebuilding` | `gh: Not Found (HTTP 404)` after the draft URL had been created. Verify and package succeeded; package took 765s. | `ffb2c30f` added recovery from the verified package artifact; later `c965743a` fixed candidate identity handling. Do not treat this isolated 404 as proof of the later fix without the recovery evidence. |
| [39824152450](https://github.com/lingyired/status-trio/actions/runs/39824152450) | verify / `Run native and release-contract tests` | `FAIL: legacy truncating pipeline exited 1 instead of SIGPIPE (141).` | The fixture was made to restore `SIG_DFL` in its synthetic producer; the exact expected status remains 141. The later green run `39825794228` includes this stage. |
| [39822549809](https://github.com/lingyired/status-trio/actions/runs/39822549809) | verify / `Run native and release-contract tests` | `FAIL: release script did not reject publish without a Sparkle signing key`; the fixture also emitted `TAG 'v1.7.1' does not match VERSION '1.0'`. | The fixture now supplies its own `TAG=v1.0`, deliberately overrides inherited CI Tag state, and preserves the missing-key rejection. Later green run `39825794228`. |
| [39821223609](https://github.com/lingyired/status-trio/actions/runs/39821223609) | verify / `Run native and release-contract tests` | `warning: remote HEAD refers to nonexistent ref, unable to checkout` followed by `fatal: ambiguous argument 'HEAD'`, exit 128. | Fixture repositories now explicitly initialize with `main`; later green run `39825794228`. |
| [39819697604](https://github.com/lingyired/status-trio/actions/runs/39819697604) | verify / `Run tests` | `ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`; actual `377721...`; accepted set contained `9dcba3...` and `e08ab4...`. | Platform-specific fingerprint selection was added, retaining the known values and requiring the observed symbol layout. |
| [39817193272](https://github.com/lingyired/status-trio/actions/runs/39817193272) | verify / `Run tests` | Same static fingerprint mismatch: actual `377721...`, expected known hashes `9dcba3...` and `e08ab4...`. | Same fingerprint/platform investigation as `39819697604`; later successful CI evidence is recorded in the existing compatibility log. |
| [39809532587](https://github.com/lingyired/status-trio/actions/runs/39809532587) | verify / `Run tests` | `BatteryDetailsLayoutTests.swift:58`, `29.5 != 29.0 +/- 0.25`. | Test sampling was pinned to a deterministic 2x display scale; the 0.25pt assertion was retained. The later `39825794228` run passed the stage. |
| [39457652321](https://github.com/lingyired/status-trio/actions/runs/39457652321) | legacy `release` / `Run tests` | Four Swift Testing issues: `ChargingEffectControllerTests.batteryLevelChangesStillUpdateStaticDockArtwork` failed `didReachStore`; three App-icon coalesced-redraw/settings expectations timed out (5s). | This run preceded the deterministic scheduler/clock test migration merged from main. `39460291539` later passed the full stage. |
| [39451283618](https://github.com/lingyired/status-trio/actions/runs/39451283618) | legacy `release` / `Run tests` | 12 Swift Testing issues concentrated in five `@MainActor` icon suites; examples: surface expectation not met within 5s, coalesced redraw not run within 5s, and two `DockChargingEnvironmentTests` issues. | `065a678984` serialized those shared suites; `39453350816` then passed. Do not label every icon timing failure a generic flake: the shared scheduling boundary is evidence, while the exact per-run causal chain was not independently proven. |

## Current state

Evidence on this baseline:

- The newest full build chain, `40344113013`, passed verify and package, with
  Developer ID signing and accepted-and-stapled notarization.
- Its package-only publish job was skipped by design.
- The newest recovery, `40349355595`, validated the original artifact and
  published it without rebuilding.
- The 12-14 minute promise is not supported by these data. A recovery-only
  successful run took 10m11s, but a recent full verify/package run took 20m05s.
  A recovery run omits package and must not be compared as if it were one.

Hypothesis, not measured here:

- Stage reordering, structured diagnostics, and native-prefix caching may
  reduce avoidable work. Their net effect on remote cold/hot jobs has not been
  measured.
- Approval and queue gaps can dominate wall time even when compute is stable.
  The `40112321642` 623-second gap is the strongest observed example, but the
  logs do not decompose it into approval versus scheduling.

## Follow-up: DDC observation boundary (2026-10-28)

The later diagnostic
[`40530484687`](https://github.com/lingyired/status-trio/actions/runs/40530484687)
found four assertions in one topology presentation case, matching the older
`37416172832` symptom. A controlled probe reproduced the cause: the fake
transport's valid fresh-generation result replaced the synchronous
invalidation before the newest-only stream consumer resumed. This was a
test-observation defect; no production generation guard was removed or changed.

PR #167 gates the new read until the test observes the nil scalar, nil device
and selected-row values, and disabled volume control, then requires fresh
confirmation after release. Removing immediate invalidation makes it fail.
Twenty focused repetitions and full local verification passed. The post-fix
remote `40538437122` passed, and final frozen
`40d6ca4c981c5bef687b6156c854a3a6a2bdbafa` passed `40542058689` and its
same-SHA repetition `40544097423` after PR #168's guard scan optimization.
Test counts remain 1,928 Core XCTest (eight existing skips), 15 Helper XCTest
and 763 Swift Testing, with zero failures.

These runs are non-publishing Ad-hoc diagnostics. Current timings, repeat-run
results, artifact checks, and the remaining measured optimization boundary are
recorded in [the performance report](ci-performance-report.md). The historical
30-run baseline above remains unchanged.

## Follow-up: deterministic Bluetooth waits (2026-10-28)

PR #170 merged as `667464e9ebdd54801f69b88fb3145e20c8b8f234`. Frozen
run `40550251784` passed 1,929 Core XCTest cases (eight existing skips),
15 Helper XCTest cases, and 763 Swift Testing cases with zero failures. The
new extra Core case asserts the unchanged 5s/1s/1s/2s HUAWEI production timing
defaults. Nine fixed-wait cases fell from 22.021s to 0.025s; the run wall was
527s with `publish=false` and `notarize=false`. The package remained Ad-hoc,
Universal, and un-notarized. Current timing interpretation and artifact
checks are in [the performance report](ci-performance-report.md).

## Follow-up: final deterministic DDC and PrimaryLink waits (2026-10-28)

PR #173 merged as `e9fc67ec611267de1cd2ad9a9d8d4a0399b491ed`. It replaces the
DDC presentation test's real 2.2s transport sleep with a watchdog-only
controlled sleep and proves the timeout emission completes before the physical
read is released. Production keeps the two-second watchdog.

PR #174 merged as `4d034760986ee273d43c3e3904294ae3a8b10271`. It injects the
existing PrimaryLink main-actor completion hop so the late-read test executes
the queued callback explicitly instead of polling a negative condition.
Independent mutations prove both the inactive-session and stale-request guards.
A reactivation regression covers a completion queued by the prior session.

Frozen `4d034760` completed non-publishing diagnostic
[`40566245708`](https://github.com/lingyired/status-trio/actions/runs/40566245708)
with `publish=false`, `notarize=false`, and version 1.7.6/build 44:

- wall 442s / 7m22s;
- verify 197s, native 144s in parallel, package 223s;
- 1,932 Core XCTest cases with eight existing skips, 15 Helper XCTest cases,
  and 763 Swift Testing cases in 112 suites, all with zero failures;
- all four artifact ZIP digests matched, DMG SHA-256
  `b590625956b7d28c80ec529cda089ee6795669a61f746525a11dfa773d8ff428`
  matched the manifest, and ten binaries passed arm64+x86_64, macOS 13/SDK 27,
  Sparkle, and deep strict Ad-hoc checks;
- Release/tag counts, appcast blobs, and the protected `distribution`
  Environment were unchanged.

The five post-PR-170 fixed candidates total 17.858s of pre-change test-case
time; the earlier HUAWEI batch separately has a 21.996s controlled test-case
reduction. They are different metric categories, are not summed, and neither
is an end-to-end wall saving. A final read-only audit at `4d034760` found no
remaining safe material candidate. Current phase details and the explicit
NO-GO boundaries are in
[the performance report](ci-performance-report.md).
