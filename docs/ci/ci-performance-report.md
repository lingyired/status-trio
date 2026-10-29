# Release CI performance report

Status: native-cache, layout, guard, DDC, and deterministic test-wait
optimizations are merged. The verified tree subsequently merged as
`4d034760986ee273d43c3e3904294ae3a8b10271` passed a non-publishing remote
diagnostic on 2026-10-28 (Asia/Shanghai). A final read-only audit found no
remaining safe material candidate in the measured evidence.

This report uses existing GitHub Actions evidence. It makes no promise of a
12-14 minute release and does not claim a speedup from any unmeasured change.

## Observed baseline

- Latest recent full verify/package chain `40344113013`: 20m05s wall,
  including 485s verify and 616s package.
- Latest recovery-only chain `40349355595`: 10m11s wall, including 520s verify
  and 36s publish. Package was skipped, so this is not a full-release time.
- Cold remote package spent roughly 5-6 minutes rebuilding pinned MobileBattery
  dependencies for both architectures in the measured 1.7.3-1.7.5 runs.
- Hot remote / cache-hit behavior: measured 2026-10-27 in
  [run `40428015193`](https://github.com/lingyired/status-trio/actions/runs/40428015193).
- A full remote release with the new cache and stage instrumentation:
  package-only cold/warm measured; publication not run.

## Measurement methodology

The timings came from GitHub Actions metadata and existing job logs:

```bash
gh run list --repo lingyired/status-trio --workflow release.yml \
  --limit 30 --json databaseId,headSha,status,conclusion,createdAt,updatedAt,url
gh run view <RUN_ID> --json jobs
gh api --allow-escape-sequences \
  repos/lingyired/status-trio/actions/jobs/<JOB_ID>/logs
```

For the latest full/recovery runs:

- **Wall duration** is `updated_at - run_started_at`.
- **Active job duration** is `completed_at - started_at` for each completed
  job, excluding skipped jobs.
- **Gap** is wall minus completed-job active time. It includes approval,
  queueing, runner allocation, artifact handoff, and other idle periods. The
  report does not call the entire gap "approval" unless logs identify a
  boundary. This subtraction applies to the serial runs only.
- **Stage duration** is the corresponding job's start/end timestamps.

For the parallel profile, the verification critical path runs from the first
verification job's start to the last verification job's completion. The
verification-to-package gap is package start minus the later verification
completion; it includes approval and runner scheduling. Active job durations
are also summed as a runner-time observation, but overlapping job time must
not be subtracted from wall time to estimate idle time. These durations are
not GitHub billing measurements.

For MobileBattery, the phase boundaries are log timestamps:

- arm64 start: `Configuring OpenSSL ... darwin64-arm64-cc`
- x86_64 start: `Configuring OpenSSL ... darwin64-x86_64-cc`
- dependency package complete: `Built source-pinned mobile battery helper
  package`
- app build complete: `Built ... StatusTrio.app`
- DMG processing: `Processing: ...StatusTrio-<version>.dmg`

The interval from arm64 configuration to the dual-architecture package marker
is labeled **MobileBattery interval**, not pure MobileBattery CPU time. It
excludes source checkout, which precedes OpenSSL configuration. It includes
both dependency builds, helper compilation,
lipo/package assembly, licensing, and validation performed by that script.
The x86-to-package interval is an approximation of the second architecture's
remaining dependency/helper/assembly work because the log does not emit a
per-architecture completion marker.

These are remote runner observations, not a local benchmark. Integer phase
timings from the new `build-timing.sh` TSV are useful for comparing later runs,
but the earlier 1.7.2-1.7.5 runs predate or do not expose those TSV records
consistently. No local cold/hot timing was substituted for remote evidence.

## Latest run evidence

| Run | SHA | Scope | Wall | Verify | Package | Publish | Gap |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| [40344113013](https://github.com/lingyired/status-trio/actions/runs/40344113013) | `57828a41960e` | full package-only | 1,205s / 20m05s | 485s | 616s | skipped | 98s verify-to-package |
| [40349355595](https://github.com/lingyired/status-trio/actions/runs/40349355595) | `2b0d7a5caf17` run head; `57828a41960e` package candidate | recovery/publish | 611s / 10m11s | 520s | skipped | 36s | 49s verify-to-publish |
| [40112321642](https://github.com/lingyired/status-trio/actions/runs/40112321642) | `6265b6422298` | recovery/publish | 1,160s / 19m20s | 503s | skipped | 29s | 623s / 10m23s |

`40349355595` is not a full release timing. It validated an existing package
artifact and published it, while package was skipped. `40112321642` shows why
wall time alone is misleading: nearly half its wall time was an unattributed
gap between verify and publish.

## MobileBattery per-architecture costs

The following successful package jobs are the clearest cold remote evidence.
All three cloned pinned sources and configured/builded both architectures; no
repository cache step is visible in these logs.

| Version / job | arm64 config to x86 config | x86 config to package marker | MobileBattery interval | Package job |
| --- | ---: | ---: | ---: | ---: |
| 1.7.3 / [`120909079608`](https://github.com/lingyired/status-trio/actions/runs/40106014873/job/120909079608) | 149s (2m29s) | 166s (2m46s) | 315s (5m15s) | 591s |
| 1.7.4 / [`120923504263`](https://github.com/lingyired/status-trio/actions/runs/40110818728/job/120923504263) | 154s (2m34s) | 144s (2m24s) | 298s (4m58s) | 563s |
| 1.7.5 / [`121651066894`](https://github.com/lingyired/status-trio/actions/runs/40344113013/job/121651066894) | 150s (2m30s) | 189s (3m09s) | 339s (5m39s) | 616s |

Observed range:

- Per-architecture phase: about 2m24s-3m09s.
- Cold dual-architecture MobileBattery interval: 4m58s-5m39s.
- Apple Swift universal build in the same package path: about 96-110s
  (`Build complete!` values: 108.42s for 1.7.3, 110.34s for 1.7.4, 96.31s for
  1.7.5).
- Signing, DMG creation/notarization, and upload consume the remainder of the
  package job. They are not part of the MobileBattery interval.

The 1.7.2 job `120239165370` used an older build path and took 532s inside the
same MobileBattery boundaries. It is useful historical evidence but is not
included in the 1.7.3-1.7.5 comparison because the build path differs.

## Why the cold cost recurs

Evidence:

- `scripts/build-mobile-battery-helper.sh` computes a per-architecture build
  key from arch, SDK, minimum macOS, clang version, script version, and the
  dependency manifest hash.
- The guard reuses an existing
  `.build/mobile-battery/<arch>/.dependencies-build-key` plus the expected
  installed dylibs.
- The release workflow has no `actions/cache` entry in the audited baseline.
- The audited package jobs show source cloning and both dependency builds even
  when a previous job built the same manifest and toolchain; no dependency
  cache restore appears in those logs.
- Both architecture prefixes are built; the helper and dylibs are combined
  with `lipo`. A cache of only the final helper would not preserve the dylibs
  required by the Universal bundle.

Hypothesis:

- Persisting the unsigned, path-compatible dependency prefixes could remove
  some or all of the cold dual-architecture interval on an exact cache hit.
- The saving is bounded by the 4m58s-5m39s observed cold interval and offset
  by cache download, extraction, validation, and any cache miss.
- Exact path binding makes safe reuse harder and may produce misses when the
  checkout path or toolchain identity changes. That is intentional until
  validation proves a broader key safe; it reduces speculative reuse.
- SwiftPM caches are separate and should not be credited with MobileBattery
  savings.

## What can and cannot be concluded

Can be stated from evidence:

- Recent full verify/package runs are around 20 minutes wall time.
- Verify is approximately 8 minutes; package is approximately 10 minutes in
  the latest full chain.
- MobileBattery is a material cold package cost: roughly 5-6 minutes for both
  architectures in the measured release packages.
- Recovery-only runs are much shorter because they skip package.
- Approval/queue gaps can add 10 minutes or more to wall time.

Cannot be stated without new remote evidence:

- That caching will save a specific number of minutes or make a full release
  12-14 minutes.
- That cache hits are reliable across checkout paths, SDK updates, or runner
  image changes.
- That static-check reordering, diagnostics, or `build-timing.sh` changes
  reduce runner wall time.
- That local `verify-local.sh` timings predict hosted-runner behavior.

## Local native cold/warm measurement

Scope: `scripts/build-mobile-battery-helper.sh` with `UNIVERSAL_BUILD=1`, on
the implementation tree based on
`e5cd7954ee35677a46d796eedf33d39699f17b52`. This is an unsigned native
helper/library package measurement, not a full Universal app or release.

Environment: Mac15,9, arm64, 16 logical CPUs, 128 GiB memory; macOS 27.0.1
(`26A434`), Xcode 27.0 (`27A266a`), Swift 6.4, macOS SDK 27.0. Other local
test work ran concurrently, so these are single-run observations rather than
an isolated CPU benchmark.

The cold run removed only architecture build/prefix/marker outputs and native
package assembly. Pinned source repositories were already present and verified.
The warm run immediately reused the exact same source tree, toolchain and paths.
Neither run used GitHub Actions cache download, compression or upload.

```bash
BUILD_TIMING_FILE=.build/ci-optimization-evidence/native-universal-final-cold.tsv \
  UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
BUILD_TIMING_FILE=.build/ci-optimization-evidence/native-universal-final-warm.tsv \
  UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

| Scope | Cold | Warm |
| --- | ---: | ---: |
| Complete native script, monotonic wall time | 141.301s | 6.974s |
| Source pin/checkout phase, integer timing | 0s | 0s |
| arm64 dependency phase, includes cache validation | 70s | 2s |
| x86_64 dependency phase, includes cache validation | 69s | 3s |
| arm64 helper and thin-copy staging | 1s | 1s |
| x86_64 helper and thin-copy staging | 1s | 0s |
| Universal package assembly | 0s | 1s |

The measured local native difference is 134.327s (95.1%). It is not a remote
net saving or an end-to-end release improvement. The separately observed
initial source checkout took 96.582s; it is excluded from both cold/warm
dependency comparisons, and source repositories are not persisted by the new
Actions prefix cache.

## Warm source-checkout removal

The final same-SHA remote run still spent 27s checking out all pinned
MobileBattery source trees before discovering that both dependency prefixes
were exact cache hits. Those trees were not needed to compile the Helpers or
assemble the package; they were only needed for a dependency rebuild or to
regenerate license files that are already reviewed and committed under
`Support/MobileBatteryHelper/ThirdPartyNotices/`.

The build now prepares sources only when at least one architecture actually
misses or rejects its dependency cache. Cache-hit runs use the tracked
license texts. On a cold rebuild, the script still verifies every source pin
and compares each upstream license with the reviewed copy after normalizing
line endings and trailing whitespace;
drift fails closed instead of rewriting tracked files. Cache validation no
longer requires a source checkout because the exact key and marker bind the
dependency manifest, build scripts, canonical prefix and full installed
inventory.

The synthetic cache contract covers three new boundaries: a warm build does
not invoke source preparation, a warm Universal build succeeds after the
source trees are removed, and differing reviewed license text fails a cold
build. This is a local contract result, not yet a remote timing claim.

Both warm cache candidates validated and skipped third-party compilation.
Helpers were rebuilt, and complete prefix inventories were byte-identical
before/after the warm run. Uncompressed prefix disk usage was 21,152 KiB
(arm64) and 21,512 KiB (x86_64); this is not a compressed transfer size.

Native contract evidence uses disposable copies, the existing
`rewrite_mobile_battery_binary` function from `build-app.sh`, and ad-hoc
signatures. It verifies the Universal helper plus seven real dylibs, both
slices, minimum macOS 13.0, SDK 27.0, bundled dependencies and allowed rpaths.
This native-only check does not prove a full Universal app, Developer ID or
notarization. The separate app-level check below covers the complete
Universal development bundle.
Raw native package libraries intentionally retain prefix dependency references
until the existing app-assembly rewrite; checks must observe that boundary.

Evidence is retained under `.build/ci-optimization-evidence/`:
`native-universal-final-{cold,warm}.{json,log,tsv}`,
`prefix-*-{before,after}-warm.json`, and `native-universal-contracts.{json,log}`.
These ignored local files are not committed release artifacts.

The first real Universal attempt failed because development rpaths were
removed after `lipo`, where each slice had a different prefix path. A
synthetic Universal test reproduced that failure before the fix. Packaging
now strips disposable thin copies before `lipo`, leaving sealed prefixes
unchanged. The successful times above are from the corrected implementation;
the failed 151.189s attempt is not counted as a successful cold benchmark.

## Full Universal development app

The complete app was built separately with the existing worktree pipeline:

```bash
UNIVERSAL_BUILD=1 \
  BUILD_TIMING_FILE="$PWD/.build/ci-optimization-evidence/universal-app-final.tsv" \
  bash scripts/build-worktree.sh release no-open
```

The build passed in 56.364s using the same implementation and toolchain as
the native measurements. It reused local Swift compilation outputs and
validated native prefixes; this is not a clean-runner app benchmark.
The app has the independent bundle identifier
`com.lingsmbp.StatusTrio.dev.ci-stability-native-cache` and an Ad-hoc signature.

The main executable and both Helpers have exactly `arm64` and `x86_64`
slices. The app-level MobileBattery and privileged Helper contracts,
minimum macOS 13.0 / SDK 26-or-newer contracts, Sparkle Ventura metadata,
and deep strict codesign verification passed. MobileBattery's existing
`--list` bundle smoke test also passed. No app window or privileged
registration was exercised.

Evidence: `universal-app-final.{json,log,tsv}`,
`universal-app-contracts-final.{json,log}`, and
`universal-app-files-final.json` under `.build/ci-optimization-evidence/`.
A copy is retained in `universal-development/StatusTrio.app` under that
directory, separate from later verification outputs. This is a built
development app, not a DMG, Developer ID/notarized package, or release.

## SwiftPM download-cache experiment and P2 decision

A separate local experiment used two new scratch directories and private
SwiftPM cache/config/security directories. It did not reuse the project's
existing `.build` output or the global SwiftPM cache. Both resolutions used
the unchanged `Package.resolved`, with Sparkle 2.9.6 pinned to
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`.

Both commands used `swift package resolve` with
`--manifest-cache local --disable-keychain --disable-netrc
--force-resolved-versions --skip-update` and explicit private paths.
The first resolution populated an empty cache. Only its `repositories` and
`artifacts` directories were compressed and restored into another empty
cache; the second resolution created a fresh working copy.

| Scope | Measured result |
| --- | ---: |
| Empty-cache resolution and dependency downloads | 14.435s |
| Download-cache resolution in a new scratch directory | 1.783s |
| Compressed repositories/artifacts archive | 62,248,695 bytes |
| Local archive compression | 1.075s |
| Local extraction | 0.079s |
| Compilation outputs included | None |

The resolve-only difference is 12.652s. After local extraction, 12.573s
remains before counting Actions download; including compression leaves
11.498s before combined transfer costs. These are single observations of
local file operations and network conditions, not a measured Actions net
saving. SwiftPM reported both the repository and binary artifact as fetched
from cache in the second run. The lockfile SHA-256 remained
`082a01a05e1ab193c61878e6587ed42846ea06a01a3c1b68f612182dd82a6bb4`.

**Decision: do not add a SwiftPM Actions cache in this change.** The measured
download budget is small compared with the native build interval, and
hosted transfer time and hit rate have not been measured. Debug or
Universal Release compilation caches were not included or enabled; their
cross-job correctness and net benefit remain unmeasured. A compilation-cache
experiment is conditional follow-up, not a missing enabled feature.

Repeated-work audit: workflow-policy regression now runs once in static
preflight. Debug tests and the Universal Release build have different
outputs and remain required. Candidate release-pipeline fixtures and trusted
recovery-tool fixtures validate different revisions during recovery and
remain separate. Helper compilation after native-prefix reuse and final
bundle validation remain required. No further work was removed or
parallelized without evidence of equivalent contracts and independent
outputs. Recovery's frozen artifact and trusted-tooling model is retained.

Raw evidence and the reproducible experiment driver are retained in
`.build/ci-optimization-evidence/measure-swiftpm-downloads.py` and
`swiftpm-download-benchmark/{results.json,metadata.json,cold.log,download-cache.log}`.

## Remote cold/warm package measurement

After PR #156 was merged, GitHub rejected the first dispatch because a
job-level environment variable used `runner.temp`. That expression is not
available at job scope. A policy regression and the official `actionlint`
v1.7.12 both reproduced the error. PR #157 moved the timing file under the
workspace and added a fail-closed context check. The rejected dispatch and two
zero-job push validation records were not counted as cold builds.

Both successful diagnostics were dispatched from `main` with the same frozen
SHA `c4fd84196ced2a0c340eabda32fef2b40bec32f0`, version `1.7.6`, build `44`,
`publish=false`, `notarize=false`, and no recovery package. Their source tree
was identical to locally verified commit `aa9ec53d`. Both passed Verify on
`xcode-27` / Xcode 27.0 / Swift 6.4 / SDK 27.0, and both published nothing.
Cheap static preflight, complete Swift tests and native/release regressions
remained in Verify in both runs.

| Stage / job | [Cold `40426198186`](https://github.com/lingyired/status-trio/actions/runs/40426198186) | [Warm `40428015193`](https://github.com/lingyired/status-trio/actions/runs/40428015193) | Change |
| --- | ---: | ---: | ---: |
| Verify job | 372s | 612s | +240s |
| Package job | 484s | 254s | **-230s** |
| Total wall | 901s | 906s | +5s |
| Swift Universal Release build | 122s | 148s | +26s |
| MobileBattery source checkout | 27s | 26s | -1s |
| arm64 dependencies | 142s | 12s | -130s |
| x86_64 dependencies | 135s | 2s | -133s |
| MobileBattery total | 307s | 45s | **-262s** |
| App build/sign/verify | 440s | 203s | -237s |
| Native cache restore interval | 0s | 4s | +4s |
| Native cache save interval | 2s | 0s, skipped | -2s |

The warm cache had two exact hits. Each architecture logged cache restored,
complete prefix validation, and native dependency build skipped. Both Helpers
were rebuilt, final Universal/MobileBattery/signature contracts passed, and
the cache save steps were skipped. The two cache entries remained the same
IDs and keys, together occupying 14,459,151 bytes; their access timestamps
advanced on the warm Runner. The cache transfer interval excludes Actions
download details hidden inside `actions/cache`; it is not a pure network
measurement.

The Package saving is 230s (47.52%) and the MobileBattery interval saving is
262s (85.34%) on this pair. Total wall increased by 5s (+0.55%, no overall
speedup) because Verify was 240s slower. The warm Verify compile took 188.18s
versus 68.43s cold, and its XCTest body took 172.059s versus 147.741s. Runner
load or another external cause was not measured, so the variation is not
attributed to the cache. The result supports a material package-stage
improvement when the exact cache hits, without claiming a guaranteed or
end-to-end 12-14 minute release.

Both DMGs passed local download-only verification after the runs: GitHub
artifact digests matched, manifests identified the frozen SHA, and DMG
sha256 matched the manifest and adjacent checksum. The cold DMG digest was
`97599b8295e1779eeabce155f9d762ea1c62b7e776d31afd7eec9c6c528aa258`;
the warm digest was
`a4af4aad9e9d03afa789966f6dd6ca03e74d5331e486976527198d538581e693`.
The two DMGs came from independent builds, so their byte-level difference is
not a failed digest check. Each archive matched its own manifest and adjacent
checksum; the reason for the byte difference was not diagnosed.

Read-only mounts verified each DMG's version/build, ten app, Helper, and
native binaries as `arm64 + x86_64` with minimum macOS 13.0 / SDK 27 metadata,
and deep strict Ad-hoc signatures. Sparkle's Ventura-compatible minimum was
checked separately as metadata, not as part of the ten-binary contract. No
app launch, XPC/helper registration, Developer ID signing, notarization or
macOS 13 runtime was exercised. After the runs, public releases and tags still
had 18 entries each, `main/appcast.xml` retained the same Git blob, and the
`distribution` Environment protection rules were unchanged.

Raw remote evidence: `.build/ci-optimization-evidence/remote-2026-10-27/`.
It includes run/job JSON, logs, timing TSVs, artifact digests, manifests,
mounted-DMG checks and before/after public-state audits. These local evidence
files are not committed release artifacts.

## Parallel verify/native profile

The latest `main` rerun before the profile change was
[`40435617420`](https://github.com/lingyired/status-trio/actions/runs/40435617420)
at `894a7787b4b9a0fb6add2224cccd85235ff54923`. It passed both cached native
restores, rebuilt both Helpers, and uploaded a valid Universal Ad-hoc package.
Package took 214s and the MobileBattery interval stayed at 45s. Verify took
403s: 13s static preflight, 240s Swift tests, and 134s native/release
contracts. The 240s test stage included a reported 73.64s Swift build and a
134.368s Core XCTest body. Total wall was 737s, including a 116s interval
between verification completion and package start. The job timestamps were
02:04:27Z and 02:06:23Z; the earlier 146s figure was a reporting error.

The subsequent profile moves the native/release contracts into a separate
`native` job on the same `xcode-27` runner. Both jobs check out and reassert
the frozen candidate independently. `package` and `publish` require both jobs
to pass; neither new job receives secrets or Environment access. Diagnostics
remain separate artifacts, so a native failure cannot be hidden by a passing
Swift suite. The full local profile passed after the workflow, policy and
documents changed.

PR #159 merged the profile as
`08644c04ce2f23a69a64582f5f1563b7cc2bb525`. Two diagnostics used that same
frozen SHA, `version=1.7.6`, `build=44`, `publish=false`, `notarize=false`,
and no recovery source. Both used Xcode 27 / Swift 6.4 / SDK 27, passed all
three active jobs, and skipped Publish.

| Scope | Serial baseline `40435617420` | [Parallel 1 `40447422731`](https://github.com/lingyired/status-trio/actions/runs/40447422731) | [Parallel 2 `40448654960`](https://github.com/lingyired/status-trio/actions/runs/40448654960) |
| --- | ---: | ---: | ---: |
| Total wall | 737s / 12m17s | 591s / 9m51s | 667s / 11m07s |
| Verification critical path | 403s | 285s | 368s |
| Swift/static Verify job | 403s, includes native | 285s | 368s |
| Separate Native job | none | 224s | 163s |
| Package job | 214s | 274s | 236s |
| Verification-to-package gap | 116s | 28s | 59s |
| Sum of active job durations | 617s | 783s | 767s |
| Swift test stage | 239.748s | 257.901s | 329.586s |
| Native contract stage | 133.901s | 202.087s | 140.987s |
| Reported Swift test build | 73.64s | 74.85s | 116.68s |
| Core XCTest body | 134.368s | 150.383s | 165.240s |
| Swift Universal Release build | 120s | 152s | 128s |
| MobileBattery total | 45s | 57s | 48s |
| Native cache restore interval | 1s | 5s | 4s |

Verify and Native started at the same second in both parallel runs. Package
started after both succeeded. The 19 unconditional native/offline contracts
remain in Native; the two additional trusted recovery regressions remain
conditional in Verify. Neither normal diagnostic exercised online recovery.
Each full Swift run reported 1,928 Core XCTest and 15 Helper XCTest, with
eight existing skips and zero failures, plus 763 passing Swift Testing tests.

Compared with the serial baseline, the observed verification critical path
fell by 118s (29.28%) and 35s (8.68%). Wall time fell by 146s (19.81%) and
70s (9.50%). The verification-to-package gap also fell by 88s and 57s,
while Package increased by 60s and 22s. Thus the entire wall reduction must
not be attributed to parallel verification. Even with the same candidate,
the two parallel runs differed by 76s wall and 83s in Verify. Runner load
was not measured, and no causal explanation for the stage variation is
established.

The sum of active job durations increased by 166s (26.90%) and 150s
(24.31%). This profile trades a shorter observed verification critical path
for another concurrent runner and more observed runner time. These values
are not billed minutes or proof of a cost reduction. The evidence supports
the structural overlap and the observed elapsed-time ranges; it does not
guarantee a fixed formal-release duration or runner-capacity availability.

Both packages restored and validated the same two exact native cache entries,
skipped third-party dependency compilation, rebuilt both Helpers, and skipped
cache saves. Artifact ZIP digests matched GitHub metadata. Their DMGs matched
their respective frozen-SHA manifests and adjacent checksum files:

| Run | Package artifact | Artifact ZIP SHA-256 | DMG SHA-256 |
| --- | --- | --- | --- |
| `40447422731` | `12708584167` | `d9c71869ea2b0401d9f6940406e7f5a48b5b964fe929df3d95573bdbc9604b63` | `e7f7bd161b4b3a8b3c510ab863c419384da8126ef65cee2c4c389cc3661332a3` |
| `40448654960` | `12709324023` | `c126161c714c8d01c64d5e3644737fd2dbd515371155dcc98c0326ee50462675` | `d614903bab7f5091ca47ab85f824cf7260db70943b66352aec4c14a981e35db4` |

The independent builds are not expected to share a DMG digest. Read-only
inspection checked each package's version/build, ten Universal binaries,
minimum macOS 13 / SDK 27 metadata, Sparkle metadata, and deep strict Ad-hoc
signatures. It did not launch either app or register a Helper.

Raw evidence and the reproducible comparison script are retained in
`.build/ci-optimization-evidence/parallel-native-remote-2026-10-27/`,
including `comparison.json`, `compare.py`, per-run diagnostics, package
manifests, and read-only DMG inspection logs. Cache keys are omitted from
the report.

## Recovery compatibility and policy follow-up

Independent review after the two normal diagnostics found a recovery
compatibility defect: `validate-release-recovery.sh` still required exactly
three source jobs, and its workflow regression retained the old
`package.needs: verify` expectation. Thus normal four-job package runs
could pass while a later recovery would reject their artifacts. This was
found by inspection and reproduced with offline fixtures, not by attempting
a public release.

The validator now matches source-job metadata to the frozen candidate's
workflow. It accepts the exact historical three-job shape or current
four-job shape with their corresponding Package dependencies; the current
shape also requires Native success. A missing Native job cannot downgrade
a four-job workflow to legacy acceptance. New offline cases cover both
valid shapes, package-only and failed-publication sources, missing/failed/
skipped Native, extra jobs, metadata/workflow shape mismatches, and missing
Native dependency.

Policy regressions additionally pin all 19 unconditional native commands and
both conditional trusted recovery regressions, require the normal success
gates, reject conditional Swift/preflight tests, replacement shells, write
permissions or Environment access in verification jobs, and preserve the
release runner and diagnostic ordering. Native summaries now identify Native,
its actual job status, and the `native-diagnostics` artifact. The new missing-
contract, conditional-preflight, and Native-label regressions were observed
failing before their fixes. Full local verification passed in 332.198s,
including the complete Swift suite, Release/local app build, and native/
offline contracts; the recovery regression also passed separately.

Recovery still requires `publish=true` and `notarize=true`; those guards were
not changed to allow a diagnostic recovery. Online recovery/publication,
Developer ID, notarization, Helper/XPC runtime, and macOS 13 runtime remain
`NOT RUN`. The two timing runs above predate this compatibility follow-up
and must not be presented as recovery acceptance.

## Remote warm-source-checkout measurement

PR #162 merged as `518f4e961ceaa26f76fb9f9b120dd6eb4a67d3d2`.
Both diagnostics below used that exact frozen candidate, `version=1.7.6`,
`build=44`, `publish=false`, `notarize=false`, and no recovery source.
The workflow, candidate, toolchain, and inputs were unchanged between runs:
`xcode-27`, Xcode 27.0, Swift 6.4, and SDK 27.0. Changed build scripts made
the first run miss the old keys; the second restored the two newly sealed
prefixes.

| Scope | [Cold `40486083712`](https://github.com/lingyired/status-trio/actions/runs/40486083712) | [Warm `40488843296`](https://github.com/lingyired/status-trio/actions/runs/40488843296) |
| --- | ---: | ---: |
| Total wall | 1,191s / 19m51s | 705s / 11m45s |
| Verification critical path | 405s | 297s |
| Swift/static Verify job | 405s | 297s |
| Separate Native job | 200s | 134s |
| Package job | 750s / 12m30s | 324s / 5m24s |
| Verification-to-package gap | 31s | 79s |
| Sum of active job durations | 1,355s | 755s |
| Swift test stage | 357.227s | 263.756s |
| Reported Swift test build | 141.25s | 80.91s |
| Core XCTest body | 178.443s | 149.490s |
| Swift Universal Release build phase | 223s | 208s |
| MobileBattery source checkout | 34s, six clones | not run, zero clones |
| arm64 dependency phases | 228s | 21s |
| x86_64 dependency phases | 189s | 6s |
| MobileBattery total | 456s | 34s |
| Native cache restore interval | 0s, two misses | 4s, two exact hits |
| Native cache save interval | 2s | 0s, skipped |

The cold TSV emits a dependency row before source preparation and another
after it. The per-architecture values above sum repeated rows with the same
label, including key/inspection work. Source checkout is timed separately
and no longer absorbs compilation. Parent phases still include child phases;
the complete table must not be summed as independent work.

The observed Package saving is **426s (56.80%)** and the MobileBattery saving
is **422s (92.54%)**. Wall fell by **486s (40.81%)**. The 108s shorter
verification critical path and 48s longer verification-to-package gap also
contributed to wall time; the full 486s must not be attributed to caching.
Both Swift test builds and XCTest execution varied on an unchanged candidate.
Runner load was not measured, so the variation has no established cause.
These are two observations, not a guaranteed release duration or billing
measurement. This cold native build was also slower than earlier cold runs;
it is retained rather than replaced with a more favorable sample.

The warm package logged validation and skipped third-party compilation for
both architectures. It rebuilt both Helpers, emitted no
`mobile-source-checkout` row, performed no source clone, and skipped both
cache saves. The two new cache entries remained the same IDs, keys, sizes,
and creation timestamps through the warm run, totaling 14,460,360 compressed
bytes. The previous two entries were preserved.

The preceding warm run
[`40451490957`](https://github.com/lingyired/status-trio/actions/runs/40451490957)
still recorded 27s of source checkout, a 55s MobileBattery interval, a 281s
Package job, and 733s wall. The new warm run eliminated source checkout and
reduced the native interval to 34s, but Package was 43s slower and wall was
28s shorter. Different candidates and runner variation prevent treating
that comparison as an isolated 27s end-to-end speedup.

Both complete Swift runs reported 1,928 Core XCTest and 15 Helper XCTest,
with eight existing skips and zero failures, plus 763 passing Swift Testing
tests. Native and offline release contracts passed in both runs. Downloaded
artifact ZIPs matched GitHub digests, and each DMG matched its own frozen-SHA
manifest and adjacent checksum:

| Run | Package artifact | Artifact ZIP SHA-256 | DMG SHA-256 |
| --- | --- | --- | --- |
| `40486083712` | `12726116510` | `03b92c3de936047720dff57f2ea642685c624e5ade2336803abb5cb09a585865` | `4ac1be9ada0de30170a7079b9041dc34f1e7c044829d6bc0db9b4798b1a5e8db` |
| `40488843296` | `12728321361` | `2a994df647484c2ff3e4790d9844fd9d0847a92ccf712584b404a553eb892556` | `501d4e642098444a31adac23a40a4f1e075793a63f40a21e9f710d483ba9812c` |

Read-only DMG inspection verified version/build, ten binaries with both
architectures, minimum macOS 13 / SDK 27 metadata, Sparkle metadata, and deep
strict Ad-hoc signatures. The workflow retained its Helper `--list` smoke
check. GUI/hardware behavior, privileged Helper/XPC registration, macOS 13
runtime, Developer ID, notarization, and online recovery were not exercised.
Publish was skipped twice. All 18 releases and their asset digests, 18 tags,
the appcast blob, protected Environment settings, and the original worktree
status were unchanged.

Raw run/job metadata, logs, diagnostics, timing TSVs, verified packages,
read-only inspection logs, comparison and public-state audits are retained
under `.build/ci-optimization-evidence/warm-source-skip-remote-2026-10-27/`.

## Reviewed-license cache follow-up

Independent review found that a notice-only change did not alter the cache
identity. A warm cache could therefore package changed reviewed text without
the cold source comparison. It also exposed an ordering defect: the cold
build sealed its marker before comparing licenses, so repeating an input
that failed license verification could reuse that premature marker.

The follow-up binds all reviewed-notice relative paths and file digests to
the cache identity and rejects missing, unreadable, symlink, or unsupported
notice paths. It reuses the existing source comparison before dependency
compilation and cache sealing. Unchanged notices still allow a warm build
without sources. Regressions first reproduced warm acceptance, silently
skipped unreadable directories, and acceptance on a repeated failed build;
the corrected cache fixture passes all three boundaries and the existing
cold/warm, corruption, inventory, and Universal contracts.

The remote pair above predates this follow-up and verifies `518f4e96`, not
the later notice-binding code. Its regression evidence is local. The cache
identity change intentionally causes one cold rebuild per architecture on a
subsequent remote run; no additional performance gain is claimed for it.

## Layout capture fixed-delay removal

The warm Swift XCTest body remained 149.490s after the native-cache work.
Investigation of the slowest case,
`BluetoothDeviceRowLayoutTests.testSupportedDeviceKindsDoNotReserveEmptySubtitleSpace`,
found 204 rows behind a fixed 50ms `Task.sleep` before capture. The test's rows
consume immutable fixtures and have no appearance task that publishes a later
state. The same fixed delay was also present in `BatteryDetailsLayoutTests`,
whose injected `onAppear` callback is a no-op.

Before removing the delays, both suites were captured twice with the existing
bitmap and geometry assertions. Synchronous two-pass
`fittingSize`/`layoutSubtreeIfNeeded` produced identical sizes, control rects,
and spinner counts for all 252 row captures, plus identical PNG bytes for all
250 static rows (the two animated spinner images were excluded from the byte
comparison). The battery snapshots exposed
a separate nondeterministic fixture input: two `Date()` values changed the
rendered timestamp between runs. Replacing those inputs with one fixed
`observedAt` date made all 46 battery PNG bytes identical in a separate
before/after pair. The date is presentation data only; no freshness policy or
assertion was removed.

| Local scope | Before | After | Observed saving |
| --- | ---: | ---: | ---: |
| `BluetoothDeviceRowLayoutTests` XCTest body | 16.943s | 1.684s | 15.259s / 90.1% |
| `testSupportedDeviceKinds...` | 13.658s | 1.198s | 12.460s / 91.2% |
| `BatteryDetailsLayoutTests` XCTest body | 3.599s | 2.022s | 1.577s / 43.8% |
| Combined 17 focused tests | 20.542s | 3.706s | 16.836s / 82.0% |

The before battery value has the fixed-date fixture but the original delay;
the row before value predates the fixed-date change, which does not affect that
suite. The combined before value sums two separate suite invocations; the
after suites ran together. These observations are local to macOS 27.0.1,
Xcode 27.0, Swift 6.4, arm64, Mac15,9, 16 logical CPUs. The command wall times
below include the unchanged forbidden-pattern guard and SwiftPM startup,
and do not measure cold compilation.

The 17 focused tests then passed 20 consecutive runs: 20/20 exit zero, focused
XCTest body 1.601-1.751s (median 1.650s), and 8.963-9.990s including the test
command. A temporary production mutation that restored an unwanted subtitle
failed the optimized empty-subtitle test with 78 assertion failures; the
mutation was reverted before the fixed commit.

This change is local test evidence only. It has not yet been measured on
`xcode-27` GitHub Actions, so no remote wall-clock saving is claimed; the
16.8s observation is strictly local. The warm remote XCTest body was 149.490s;
this test was 29.596s there, so the remote reduction may differ with runner and
display settings. A subsequent diagnostic should retain the full 1,928-test
count and compare the same frozen candidate.

Implementation commit: `1fb89ddcbbfacd72d8307cd02b41e35973a4cae4`, based on
`2a5576468dddf804f7b246f911a21f21ac23dac2`. All comparison PNGs, geometry
records, mutation logs, and 20 repetition logs are retained under
`.build/ci-optimization-evidence/layout-performance-2026-10-27/`.
The temporary capture/profiling code and production mutation are not included
in the implementation. Independent review found no actionable issues.
`bash scripts/verify-local.sh full` passed on that implementation commit:
1,928 Core XCTest tests (eight existing skips), 15 Helper XCTest tests, and
763 Swift Testing tests, all with zero failures, plus the Release build,
non-Universal local bundle, native contracts, cache corruption/invalidation
fixtures, and offline release simulations. The complete log is
`verify-local-full.log` in the evidence directory above. Live GitHub CI,
headless/older-macOS rendering, GUI/hardware behavior, Universal packaging,
Developer ID, notarization, and publication remain `NOT RUN` for this change.

## Layout optimization remote diagnostic

The first authorized diagnostic on frozen
`aa15b78c28561901fa8f4848f56405fea4c7d258`
([`40525552482`](https://github.com/lingyired/status-trio/actions/runs/40525552482))
used `version=1.7.6`, `build=44`, `publish=false`, and `notarize=false`.
It completed successfully in 867s, including a 538s package job. Both native
locks were cold because the prior reviewed-license identity change requires
one rebuild. The package job therefore spent 338s in MobileBattery and 136s
in the Universal Swift Release phase. This is not a warm end-to-end baseline.

The slowest layout case fell from 29.596s in the earlier warm run to 0.936s.
The complete verification still ran 1,928 Core XCTest tests (eight existing
skips), 15 Helper XCTest tests, and 763 Swift Testing tests with zero failures.
The downloaded DMG matched its manifest SHA-256, had ten binaries in both
architectures, version 1.7.6/build 44, minimum macOS 13/SDK 27 metadata,
Sparkle metadata, and valid deep strict Ad-hoc signatures. Releases remained
at 18, tags at 18, and the appcast and protected Environment were unchanged.
The run created two new exact native-cache entries.

A second run with the same frozen SHA
([`40530484687`](https://github.com/lingyired/status-trio/actions/runs/40530484687))
stopped in verification before package. Its layout case again passed, but
four assertions in the unrelated
`DDCVolumePresentationTests.testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately`
observed the prior `0.75` value after `topologyChanged()`. This matches the
recorded intermittent DDC ordering failure in `docs/swift-ci-compatibility.md`;
it is not evidence that the layout change caused the failure. Do not retry
that run until the separate DDC ordering root cause is fixed. The second run
therefore provides no warm package comparison and no end-to-end timing claim.

Raw run metadata, logs, timing tables, downloaded artifact, manifest,
signature checks, and public-state snapshots are retained under
`.build/ci-optimization-evidence/layout-performance-remote-2026-10-27/`.
The Apple Developer ID, notarization, runtime UI/Helper behavior, and
publication gates remain `NOT RUN`.

## DDC stabilization warm diagnostic (2026-10-28)

After the test observation fix merged in PR #167, frozen
`27ef4ca27217f09cdd3ee9efa4f5e1ad59209f89` completed
[`40538437122`](https://github.com/lingyired/status-trio/actions/runs/40538437122)
with the same 1.7.6/build 44, `publish=false`, `notarize=false` inputs:

| Scope | Observation |
| --- | ---: |
| Total wall | 475s / 7m55s |
| Verify | 267s |
| Native, in parallel | 165s |
| Package | 174s |
| Swift test stage | 223.557s |
| Debug test compilation | 80.46s |
| Core XCTest body, 1,928 tests / eight skips / zero failures | 108.132s |
| Swift Testing, 763 tests / zero failures | 6.033s |
| DDC topology case | 0.001s |
| Universal Swift Release phase | 102s |
| MobileBattery total | 15s |

Both exact native caches restored and validated; both dependency builds were
skipped and no source-checkout phase ran. Four downloaded artifact ZIPs were
independently hashed and matched their GitHub digests. The DMG SHA-256
`765c3af866bdebcff1674a251196eb1d88d30eb65f0c5fef41058c01f2ea1812`
matched the manifest. Read-only inspection passed ten arm64+x86_64 binaries,
macOS 13/SDK 27 platform metadata, Sparkle metadata, and deep strict Ad-hoc
signature checks. Release, tag, appcast and protected Environment snapshots
were identical before and after this run.

This run predates the guard declaration-index change. The 475s result is a
warm diagnostic observation, not a guaranteed formal release duration or a
controlled attribution of all wall-time differences to code. Runner variation
also affects compilation. Raw data and contracts are under
`.build/ci-optimization-evidence/ddc-stability-2026-10-27/baseline/`.
Developer ID, notarization, runtime/hardware acceptance, and publication were
not exercised.

## Final frozen-candidate diagnostics

PR #168 merged the guard optimization. Frozen source
`40d6ca4c981c5bef687b6156c854a3a6a2bdbafa` completed two independent runs,
[`40542058689`](https://github.com/lingyired/status-trio/actions/runs/40542058689)
and [`40544097423`](https://github.com/lingyired/status-trio/actions/runs/40544097423),
with `publish=false`, `notarize=false`, version 1.7.6/build 44:

| Scope | Guard-before | Final run 1 | Final run 2 |
| --- | ---: | ---: | ---: |
| Run | 40538437122 | 40542058689 | 40544097423 |
| Wall | 475s / 7m55s | 705s / 11m45s | 539s / 8m59s |
| Verify | 267s | 341s | 264s |
| Native, parallel | 165s | 148s | 137s |
| Package | 174s | 295s | 205s |
| Verify-to-package gap | 28s | 64s | 63s |
| Preflight | 25.623s | 22.230s | 14.673s |
| Swift test stage | 223.557s | 297.067s | 231.472s |
| Debug test build | 80.46s | 121.72s | 84.33s |
| Core XCTest body | 108.132s | 127.210s | 115.084s |
| Guard scan case | 7.775s | 4.516s | 4.079s |
| Guard self-test case | 2.617s | 4.902s | 8.764s |
| Universal Swift Release phase | 102s | 190s | 120s |
| MobileBattery total | 15s | 35s | 18s |

The final repeat range is **8m59s-11m45s**. The guard scan case is consistently
faster, and the final preflight reached 14.673s, but this is not an isolated
end-to-end attribution: compilation, test execution, the synthetic self-test,
and the verification-to-package gap all vary materially between runners.
Do not use the fastest observation as a guaranteed release duration. All three
runs restored and validated two exact native caches with zero source clones.
Each passed the same required 1,928 Core XCTest cases (eight existing skips),
15 Helper XCTest cases, and 763 Swift Testing cases. The topology case took
0.001s, 0.002s, and 0.003s.

Every artifact ZIP in both final runs was independently hashed and matched its
GitHub digest. DMG SHA-256 values
`e093988e6db390590d1bf0dc6a09bcee4cd975d88d55de4f86830417afdb7fbe`
and `67ee0c5f565536f829e94c6b55b65e552871cdede1c8508a3a8bf76bd89bbbfe`
matched their frozen manifests. Both packages passed read-only inspection of
ten arm64+x86_64 binaries, minimum OS/SDK, Sparkle metadata, and deep strict
Ad-hoc signatures. Public Release/tag/appcast and protected Environment
snapshots remained unchanged. Evidence is under
`.build/ci-optimization-evidence/ddc-stability-2026-10-27/{baseline,warm,warm2}/`.
This is diagnostic packaging; Developer ID, notarization, runtime/hardware
acceptance and publication remain unexercised.

## Deterministic Bluetooth test waits (2026-10-28)

PR #170 merged as `667464e9ebdd54801f69b88fb3145e20c8b8f234`.
The change adds timing injection to the existing HUAWEI RFCOMM `Hooks` and
uses zero waits only in synchronous fake-device ownership tests. Production
defaults remain exactly 5s connection-ready, 1s SDP settling, 1s SDP service
wait, and 2s channel open. The never-connect branch still performs the single
timeout condition check and retains all open, close, SDP, and ownership
assertions.

The rollback tests now subscribe before starting the write and record the
`.failed` then `.idle` presentations. Both CoreAudio rollback cases and the
HUAWEI rollback case use a 1 ms test-only failure linger; the production
default remains 2s. No assertion was skipped, relaxed, or replaced with a
retry.

Frozen `667464e9` completed the non-publishing diagnostic
[`40550251784`](https://github.com/lingyired/status-trio/actions/runs/40550251784)
with version 1.7.6/build 44, `publish=false`, and `notarize=false`:

| Scope | Final guard run 2 | Test-wait run |
| --- | ---: | ---: |
| Run | 40544097423 | 40550251784 |
| Wall | 539s / 8m59s | 527s / 8m47s |
| Verify | 264s | 222s |
| Native, parallel | 137s | 155s |
| Package | 205s | 280s |
| Verify-to-package gap | 63s | 20s |
| Swift test stage | 231.472s | 184.944s |
| Core XCTest body, eight existing skips | 115.084s | 81.705s |
| Swift Testing | 763 tests | 763 tests |
| Universal Swift Release phase | 120s | 186s |
| MobileBattery total | 18s | 31s |

The nine audited fixed-wait cases (seven HUAWEI transport ownership cases and
two CoreAudio rollback cases) fell from **22.021s to 0.025s**, a measured
**21.996s reduction in test-case time** on the remote runner. The HUAWEI
rollback case changed from 0.053s to 0.059s while gaining explicit event
assertions, so it is not counted as a saving.

The verify job, test stage, and wall time were also lower, while the native and
package jobs were slower. The total run difference is therefore a run-to-run
observation, not a controlled end-to-end attribution: only the fixed cases
have a same-test before/after boundary. The required counts passed with
1,929 Core XCTest cases (eight existing skips), 15 Helper XCTest cases, and
763 Swift Testing cases in 112 suites, all with zero failures. The extra Core
case is the new production-default assertion.

All four downloaded artifact ZIPs matched their GitHub digests. DMG SHA-256
`d4b1beed32253095148242b8c6942bd9e046bebc0822407cbe6ba0c23ebd5164`
matched the frozen manifest at 15,281,833 bytes. Read-only inspection passed
ten arm64+x86_64 binaries, minimum macOS 13/SDK 27 metadata, Sparkle metadata,
and deep strict Ad-hoc signatures. Release and tag counts remained 18, and
the appcast blobs and protected `distribution` Environment were unchanged.

Evidence is under
`.build/ci-optimization-evidence/task7-2026-10-28/`. Developer ID,
notarization, app launch, real Bluetooth hardware, helper registration, and
publication remain `NOT RUN`.

## Final deterministic DDC and PrimaryLink diagnostic (2026-10-28)

PR #173 merged the DDC watchdog test change as
`e9fc67ec611267de1cd2ad9a9d8d4a0399b491ed`. The test now has a watchdog-only
async sleep gate and observes the coordinator's timeout emission before
releasing the gated physical read. Production retains its two-second watchdog
and the generic debounce/poll sleep is unchanged. The target fell from
2.210s locally to 0.155s in focused runs and measured 0.202s on the final
remote runner.

PR #174 merged the PrimaryLink completion gate as
`4d034760986ee273d43c3e3904294ae3a8b10271`. The injected dispatcher preserves
the production main-actor `Task` hop, while tests execute queued completions
explicitly. The late-read case fell from the 3.922s audit measurement to
0.000s remotely. Both the inactive-session guard and the stale-request guard
have independent mutation evidence, and a reactivation regression covers a
completion queued by the prior session.

Frozen `4d034760` completed non-publishing diagnostic
[`40566245708`](https://github.com/lingyired/status-trio/actions/runs/40566245708)
with version 1.7.6/build 44, `publish=false`, and `notarize=false`:

| Scope | Run 40550251784 at `667464e9` | Run 40566245708 at `4d034760` |
| --- | ---: | ---: |
| Wall | 527s / 8m47s | 442s / 7m22s |
| Verify | 222s | 197s |
| Native, parallel | 155s | 144s |
| Package | 280s | 223s |
| Verify-to-package gap | 20s | 16s |
| Static preflight | 20s | 14s |
| Swift test stage | 184.944s | 167.249s |
| Debug test build | 73.78s | 75.00s |
| Core XCTest body | 81.705s | 65.095s |
| Swift Testing | 5.760s | 4.145s |
| Build/sign/package step | 243s | 183s |
| Universal Swift Release phase | 186s | 128s |
| MobileBattery total | 31s | 30s |

The **85s wall difference is an observation, not an isolated attribution**.
The DDC and PrimaryLink changes directly remove fixed test-case waits, and the
test stage was 17.695s shorter. The package's Universal Release phase was also
58s shorter in this run, but Debug and Release compilation are independent
and runner variation remains material. Do not promise the observed 7m22s as a
fixed release duration.

The final remote run passed 1,932 Core XCTest cases (eight existing skips),
15 Helper XCTest cases, and 763 Swift Testing cases in 112 suites, with zero
failures. All four downloaded artifact ZIPs matched their GitHub digests. DMG
SHA-256
`b590625956b7d28c80ec529cda089ee6795669a61f746525a11dfa773d8ff428`
matched the frozen manifest. Read-only inspection passed ten arm64+x86_64
binaries, version 1.7.6/build 44, macOS 13/SDK 27 platform metadata, Sparkle
metadata, and deep strict Ad-hoc signatures. Release and tag counts remained
18, and the appcast blobs and protected `distribution` Environment were
unchanged.

The five post-PR-170 candidate measurements total **17.858s** of
candidate-specific pre-change fixed test-case time:

```text
5.751 + 3.922 + 3.900 + 2.206 + 2.079 = 17.858 seconds
```

The earlier HUAWEI fake-device batch separately has a **21.996s controlled
test-case-time reduction** (22.021s to 0.025s). The 17.858s pre-change budget
and the 21.996s reduction are different metric categories and are not summed.
Neither is an end-to-end wall-time saving.

Evidence is under
`.build/ci-optimization-evidence/final-primary-link-remote-2026-10-28/`.
Developer ID, notarization, app launch, real display/Bluetooth hardware,
helper registration, and publication remain `NOT RUN`.

## Remaining optimization decisions

### Guard declaration lookup (2026-10-28)

The guard deliberately runs before tests, in preflight, and inside the test
suite. Those enforcement points remain. Its declaration lookup previously
rescanned all Swift source files for each candidate name. It now builds
zero-argument and any-argument name indexes once per `report()` call and uses
exact whole-name membership. Indexes reset for each root; forwarded closures,
allowlists, overload behavior, diagnostics, and exit codes are preserved.

Five alternating local original/optimized scans on Bash 3.2 measured median
6.34s versus 2.45s (61.36% lower command wall time). All pairs returned zero,
had empty stderr, and had identical stdout. The real 289-line `--list`,
self-test, empty root, and synthetic prefix/EOF corpus matched the original
stdout, stderr, and status. Same-shell reset fixtures fail when index reset is
removed, and also fail when an otherwise identical report is forced to return
an error. The focused two `ForbiddenPatternGuardTests` passed.

Evidence is under `.build/task5-guard-evidence-20261028-001356/`. This local
measurement is not an end-to-end CI saving; remote measurements follow
separately.

`bash scripts/verify-local.sh full` passed on base
`27ef4ca27217f09cdd3ee9efa4f5e1ad59209f89` with the final guard patch:
1,928 Core XCTest tests (eight existing skips), 15 Helper XCTest tests,
763 Swift Testing tests, Release/local-bundle builds, platform/Helper/native
contracts, and offline cache/release regressions. The log is
`.build/ci-optimization-evidence/ddc-stability-2026-10-27/verify-local-guard-full.log`.

The warm run spent 208s in the Universal Swift Release build phase. Debug
test outputs and Universal Release outputs remain different required work;
no compatible compilation-cache experiment has established safe reuse.
The earlier SwiftPM download-only experiment remains local evidence.

The warm job spent 9s resolving exact cache keys, 11s installing/checking
build tools, and 5s validating prefixes before the skipped cache saves.
Avoiding redundant pre-save inspection is a possible seconds-scale
experiment, but its net benefit and replacement integrity boundary have not
been verified. No checks were removed for that unmeasured saving. Further
native-job splitting has no per-contract benchmark or runner-capacity
evidence yet.

### Final safe-boundary audit (2026-10-28)

The final read-only audit at `4d034760` returned **NO SAFE MATERIAL CANDIDATE**.
Remaining visible costs are not removable without weakening the contract:

- the cfprefsd deletion case waits 1.5s for real asynchronous write-back and
  has no completion event;
- the Bluetooth handoff lifecycle suite uses 150ms SwiftUI settling windows
  and has no verified equivalent completion boundary;
- the forbidden-pattern scan and its synthetic self-test are enforcement work;
- AppKit lifecycle cycles, rendering matrices, localization coverage, and
  real subprocess tests exist to exercise those behaviors;
- AirPods and charging Swift Testing cases already use continuation-controlled
  `ManualEventSleeper`; their reported completion boundary comes from the
  parallel runner;
- Debug XCTest and Universal Release compilation serve different contracts,
  and no safe compilation-cache design has measured hosted-runner proof;
- cache-key resolution, pre-save validation, tool provisioning, and frozen-SHA
  reassertion protect correctness or provenance for single-digit seconds.

The final audit is retained at
`.superpowers/sdd/ci-overnight-continuation-plan/task-15-final-audit.md`.

## Follow-up measurement plan

1. Completed: run the parallel profile twice on one frozen candidate with
   `publish=false` and no notarization; the comparison is recorded above.
2. Completed: measure source-checkout removal with a same-SHA cold/warm pair;
   retain both the dependency phases and the separate source phase.
3. On a later formal candidate, observe cache invalidation and hit behavior,
   including the reviewed-license binding, signing, and notarization costs.
4. Keep comparisons on the exact same candidate and toolchain; do not compare
   different SDKs or runner images as an isolated cache result.
5. Keep Developer ID signing, notarization, runtime Helper/XPC behavior, and
   public publication as `NOT RUN` until the corresponding protected and
   manual evidence exists. The Ad-hoc package contract and signature checks
   above passed but do not substitute for those gates.
6. Completed: the final post-merge audit found no deterministic, material,
   safely implementable optimization in the current evidence.

This report records the remote baseline, local native measurements, and
authorized `publish=false` diagnostics; it is not release authorization. The
diagnostics did not create a release or tag, update the appcast, or mutate
protected-environment settings.
