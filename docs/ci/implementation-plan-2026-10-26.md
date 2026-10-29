# CI stability and native cache implementation

Goal: make release failures actionable and avoid rebuilding identical pinned
native dependencies while preserving the frozen-artifact release boundary.

Baseline: `origin/main` at `e5cd7954ee35677a46d796eedf33d39699f17b52`.
The original checkout contains unrelated local edits; all implementation uses
the isolated `codex/ci-stability-native-cache` worktree.

The supplied Downloads plan is design input. The user authorized adapting and
completing implementation without another approval exchange. Implementation
stays on one integration branch so workflow edits are serialized and testable
together. Commit, push, merge, release and remote workflow dispatch are separate
operations. The continuation request extends delivery through a committed
branch and review PR. Main-branch integration, remote workflow dispatch and
publication remain maintainer decisions.

## Execution

1. Audit at least 20 recent release/recovery runs and the current fixes.
   Write `ci-stability-baseline.md` and `ci-performance-report.md`. Audit the
   selected timing-sensitive tests and repeat their bounded filter 20 times.
   Change tests only for a demonstrated defect, retaining exact fingerprints
   and production timeout behavior.
2. Add a tested stage wrapper and structured diagnostics. Preserve command exit
   status, raw verify logs, first actionable failure and elapsed time. Only
   resource-related failures trigger resource-tree diagnostics. Move cheap
   static checks and release-note validation before Swift tests; run native
   regressions once.
3. Cache only pinned unsigned native prefixes and their validation inventories.
   Use an exact schema/toolchain/manifest/script/configuration/path key without
   fallback keys. Validate files, hashes, symlinks and Mach-O contracts before
   skipping native builds. Rebuild invalid/missing entries; always rebuild the
   helper and retain final Universal/signing/bundle verification.
4. Add phase timings, offline negative fixtures and workflow policy checks.
   Keep SwiftPM build caches disabled until measured net savings justify them.
   Run the full local profile on the integrated tree, then request independent
   review and fix material findings with regression evidence.
5. Record exact commands/results and remaining remote/runtime gaps. Re-fetch
   `origin/main`, compare the base and preserve the unrelated original edits.

## Review focus

- Partial, stale, corrupt or path-incompatible native caches must never be used.
- A command failing inside a logging/timing wrapper must retain its exit code.
- Failures before tests start must still produce a truthful job summary.
- Package/publish recovery must keep trusted tooling and original artifact
  validation; no diagnostics or cache may acquire publishing/signing powers.
- Tests still reject business/rendering regressions; 20 local passes are not
  evidence for runner load, Universal packages or macOS 13 runtime acceptance.

## Evidence ledger

- Preflight: current main already includes `57828a41` (observe launched child)
  and `07ed1ab2` (approved icon fingerprint pairs); do not repeat those fixes.
- Design decision: exact workspace/prefix identity is included in native cache
  keys rather than relocating Autotools metadata without evidence. Cost:
  runners with different checkout paths get safe misses and less cache reuse.
- Phase 3 decision: a private-cache SwiftPM download experiment measured
  14.435s cold versus 1.783s warm, with a 62,248,695-byte archive and 1.154s
  total local compression/extraction cost. Actions transfer and hit rate
  remain unmeasured, so no SwiftPM cache is enabled. Compilation caching and
  recovery trust changes are deferred. No local saving is reported as remote
  net performance.
- Reliability: final event-based test waits passed 20 consecutive selected
  runs (111 tests each, 344.861s total, 20.635s maximum command wall time).
  AppIcon's old selected filter did not fail locally; this removes a scheduling
  ambiguity, not a proven hosted-CI root cause. Dock's reused deadline was a
  concrete test defect. Production timeout/rendering behavior is unchanged.
- RED/GREEN: diagnostics did not exist before their regression; broken JSON and
  truncated TSV reproduced summary exceptions before the parsing fix. An
  unwritable timing file changed exit 31 to 1 before the timing fix and now
  preserves 31. A syntax error after the first file was accepted before the
  per-file syntax fix. The fixture now has a valid file after the broken file.
- Review ruling: the suggested `bash -n scripts/*.sh` would restore the proven
  first-script-only bug. Retain per-file parsing inside explicit `bash -e`;
  the workflow uses `bash -euo pipefail`. Cost if wrong: later syntax errors
  could reach Swift tests; the invalid-middle-script regression guards this.
- Review integration: event waiters now expose subscription readiness before
  cancellation, release their subscriptions/streams on every outcome, and join
  cancelled tasks. Dock's new-event regression registers before producing the
  event and verifies that a second waiter cannot reuse the previous event.
  The snapshot waiter subscribes before publishing.
- Review ruling: the earlier helper-rpath sealing report concerned a stale
  snapshot. A later real Universal build found a distinct, confirmed bug:
  deleting architecture-specific rpaths after `lipo` fails on the other slice.
  The new Universal fixture reproduced it before the production fix. Each
  thin library is now copied into disposable `package-libraries`, stripped
  there and then combined; sealed prefixes remain unchanged. The fixture
  also preserves injected strip exit 75 and lipo-create exit 76 and validates
  both prefixes after those failures.
- Review integration: current-workflow policy checks use trusted CI tools on
  recovery, while original candidate tests run in the candidate checkout.
  The trusted policy regression runs once, during static preflight.
- Native measurement: real Universal cold dependency build 141.301s, immediate
  warm run 6.974s. Source checkouts already existed. Both cache candidates
  validated, helper compilation still ran, and complete prefix inventories
  were unchanged. This does not include Actions cache transfer or prove remote
  savings; see the performance report for the environment and scope.
- Native contracts: disposable Universal copies using the existing app
  rewrite function passed both architectures, platform/SDK, dependencies,
  rpaths and ad-hoc signature checks for the helper plus seven dylibs.
  A raw prefix-linked native package is an intermediate, so dependency checks
  belong after the app-assembly rewrite.
- Complete Universal development app: `UNIVERSAL_BUILD=1` with
  `scripts/build-worktree.sh release no-open` passed in 56.364s. Main app,
  both Helpers, bundled MobileBattery libraries and Sparkle passed the final
  architecture/platform/dependency/signature contracts. The bundle is
  Ad-hoc signed with an independent development bundle ID. Developer ID,
  notarization, DMG, real UI/hardware and macOS 13 runtime remain `NOT RUN`.

## Final local acceptance

All implementation files were frozen before the final profile. A SHA-256
inventory of the 21 changed workflow/script/test files was recorded and
rechecked after verification; none changed. The first full profile ran on
uncommitted source, so the baseline SHA alone does not identify the
implementation. The delivery commit and source-digest inventory identify the
reviewed tree; final post-commit verification is recorded in the PR.

| Command / scope | Result |
| --- | --- |
| `bash scripts/verify-local.sh full` | PASS, 287.517s. 15 Helper XCTest + 1,928 Core XCTest (8 existing skips), zero failures; 763 Swift Testing tests in 112 suites, zero failures. Release build, non-Universal ad-hoc app, SDK/platform, MobileBattery/privileged Helper contracts and all 22 native/offline checks passed. |
| `bash scripts/test.sh 'MobileBatteryHelperReaderTests\|AppIconControllerTests\|IconSurfaceIntegrationTests\|DockChargingEnvironmentTests\|ChargingEffectControllerTests\|BluetoothListeningModeControllerLifecycleTests'` | 20/20 PASS on final code. Each run: 23 XCTest + 88 Swift Testing. Total 344.861s, max command wall 20.635s. No retry after a failure. |
| `bash scripts/test.sh 'Issue30WiFiAlignmentTests\|IconSurfaceIntegrationTests'` | PASS, 22.532s. 6 XCTest + 8 Swift Testing; zero failures. Exact alignment and surface-parity assertions retained. |
| `bash scripts/test-release-recovery.sh` | PASS, 4.708s; offline fixture only. |
| `bash scripts/test-mobile-battery-build-cache.sh` | PASS standalone and inside final full. Single/Universal cold/warm, identity invalidation, corruption, metadata paths, inspection errors and strip/lipo failure propagation covered. |
| `UNIVERSAL_BUILD=1 bash scripts/build-worktree.sh release no-open` and app-level contracts | PASS, build 56.364s. Complete Universal development app; both Helpers, MobileBattery libraries, Sparkle metadata, platform/SDK and strict Ad-hoc signatures verified. Existing local compilation outputs were reused. |
| Private-cache SwiftPM download comparison | PASS, lockfile unchanged. 14.435s cold, 1.783s warm; no compilation artifacts or global cache. SwiftPM Actions caching remains disabled pending net-benefit evidence. |
| `git diff --check` and final source-digest comparison | PASS. No trailing-whitespace errors or post-verification implementation changes. |

Independent read-only review found no remaining important issues in the final
Swift changes after the targeted fixes. Native review's missing-key fixture
finding was corrected with per-architecture `prepare-key`/`--expected-key`;
the requested failure-propagation cases were added and passed.

The first full attempt failed in the new cache fixture's quoted libtool-path
negative case. The parser was corrected, the fixture's inventory refreshed so
semantic path validation was actually reached, and the final full command
above passed. The first real Universal build failed on post-lipo rpath
deletion; its RED/GREEN evidence and successful replacement runs are recorded
in the performance report. Neither failed attempt is presented as acceptance.

Final `git fetch origin main` returned
`e5cd7954ee35677a46d796eedf33d39699f17b52`; branch and remote have no committed
divergence. The original checkout's dirty files were preserved. A read-only
three-way comparison found the overlapping release documentation and two
workflow policy files merge cleanly with those original edits; no merge was
performed.

Local evidence lives in `.build/ci-optimization-evidence/`, including the final
profile/rendering/recovery logs and JSON, stability TSV and 20 logs, native
cold/warm timings, prefix inventories, source digests and shared-file audit.
Logs from offline release fixtures can say "published" for their fake release;
those are disposable fixtures, not an actual GitHub publication.

Delivery uses a committed branch and review PR. No merge, workflow dispatch,
production secret change, tag, release, DMG or appcast update is included.
Remote cold/warm cache net savings, hosted-runner behavior, Developer ID,
notarization, real UI/hardware and macOS 13 runtime remain `NOT RUN`.

## Remote acceptance addendum (2026-10-27)

The preceding local-acceptance section records the initial delivery snapshot;
the remote diagnostics below were completed afterward. Both diagnostics used
the same frozen `main` source SHA
`c4fd84196ced2a0c340eabda32fef2b40bec32f0`, version `1.7.6`, build `44`,
`publish=false`, and `notarize=false`. They ran with Xcode 27 / Swift 6.4 /
SDK 27. The first diagnostic exposed a job-scope `runner.temp` expression;
PR #157 fixed it before the measured runs.

| Run | Result | Verify | Package | Wall | Cache |
| --- | --- | ---: | ---: | ---: | --- |
| [Cold `40426198186`](https://github.com/lingyired/status-trio/actions/runs/40426198186) | PASS | 372s | 484s | 901s | two misses, saved |
| [Warm `40428015193`](https://github.com/lingyired/status-trio/actions/runs/40428015193) | PASS | 612s | 254s | 906s | two exact hits |

Package fell by 230s (47.52%); the MobileBattery interval fell from 307s to
45s. Total wall rose by 5s (+0.55%), so these diagnostics do not prove an
end-to-end release speedup. Complete XCTest and Swift Testing suites passed in
both runs. Both downloaded DMGs matched their artifact/manifest digests and
passed read-only Universal, platform/SDK, and deep strict Ad-hoc signature
checks. Developer ID signing, notarization, Helper/XPC runtime behavior,
hardware/UI testing, and macOS 13 runtime acceptance remain `NOT RUN`.

No release, tag, appcast update, production secret change, or protected
Environment change was made. The two cache entries occupied 14,459,151 bytes
and were reused without changing IDs or keys. Raw evidence is retained under
`.build/ci-optimization-evidence/remote-2026-10-27/`; it is not committed.

## Latest-main rerun and parallel verification addendum (2026-10-27)

[Run `40435617420`](https://github.com/lingyired/status-trio/actions/runs/40435617420)
repeated the cache path on current `main`
`894a7787b4b9a0fb6add2224cccd85235ff54923` with `publish=false`. Both
architectures hit the existing exact cache entries, skipped third-party
dependency builds, and rebuilt both Helpers. Package took 214s; Verify took
403s; total wall was 737s. The downloaded Universal Ad-hoc package passed
manifest, digest, architecture, platform/SDK and strict signature checks.

The implementation profile runs Swift tests and native/offline release
contracts in parallel `verify` and `native` jobs on `xcode-27`. `package`
requires both to pass, and `publish` requires `verify`, `native`, and
`package`. The jobs have no signing/notarization secrets or `distribution`
Environment access. Full local verification passed before PR #159 merged as
`08644c04ce2f23a69a64582f5f1563b7cc2bb525`.

Two diagnostics on that same SHA, version `1.7.6`, build `44`,
`publish=false`, and `notarize=false` passed:

| Run | Verify | Native | Package | Wall |
| --- | ---: | ---: | ---: | ---: |
| [40447422731](https://github.com/lingyired/status-trio/actions/runs/40447422731) | 285s | 224s | 274s | 591s |
| [40448654960](https://github.com/lingyired/status-trio/actions/runs/40448654960) | 368s | 163s | 236s | 667s |

Both verification jobs started together; Package waited for both, and Publish
was skipped. The observed verification critical path fell by 35-118s versus
the 403s serial baseline. The active-job duration sum rose by 150-166s, and
approval/scheduling gaps differed, so the full wall difference is not a pure
parallelism or cost saving. The serial verification-to-package gap is 116s,
corrected from an earlier 146s reporting error.

Both architectures reused the same validated exact caches. Full Swift suites
passed with zero failures. Both downloaded DMGs passed artifact/manifest
digests, read-only Universal/platform/SDK/Sparkle metadata, and deep strict
Ad-hoc signature checks. Measurements, artifact hashes and the runner-time
tradeoff are in `ci-performance-report.md`; raw evidence is in
`.build/ci-optimization-evidence/parallel-native-remote-2026-10-27/`.

Independent post-run review found that recovery still assumed three source
jobs, so normal package success did not cover the new four-job recovery
shape. Recovery acceptance now matches source metadata to its frozen workflow,
supports the exact historical three-job and current four-job shapes, and
requires successful Native verification in the latter. The 19 unconditional
native contracts and two conditional trusted recovery regressions retain
their separate execution scopes. Online recovery remains outside these
non-publishing diagnostics.

The follow-up also pins every contract and the success/permission/runner
boundaries in workflow policy, and fixes Native summary identity/status.
RED/GREEN fixtures reproduced the missing-contract, conditional-preflight,
and summary-label gaps. Independent policy re-review resolved the reported
findings. Full local verification passed in 332.198s; the recovery regression
passed separately. The final runner-fixture refinement and documentation
receive focused verification before commit.
