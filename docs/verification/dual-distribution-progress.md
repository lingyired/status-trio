# Dual distribution execution ledger

Plan: `docs/superpowers/plans/2026-10-23-dual-distribution.md`
Base: `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`
Worktree: `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`
Initial branch: `codex/dual-distribution-foundation`
Current integration branch: `codex/dual-distribution-platform`

## Authorization

2026-10-23: user expanded scope to complete all development phases A–F through
subtasks, with no additional permission controls. Implementers use
`auto/deepseek-v4.1-flash`, reasoning `max`, direct native tools and the inherited
full-access profile. No nested task/chat delegation. No automatic merge,
production Secrets changes, GitHub Release, tag, ASC upload or review submission.
Parent owns integration, commit, branch push and PR.

## Ownership and progress

Implementation continued after midnight on 2026-10-24 (Asia/Shanghai). The
2026-10-23 document names identify the original plan, not the final test date.

| Phase | State | Owner / write scope | Evidence |
| --- | --- | --- | --- |
| A | complete | Erdos implementation; Curie independent review | `95858e0`; full/docs exit 0; review PASS; draft PR #145 |
| B | complete | Russell `01a16953-f083-7131-b896-a296175a20d9`; source adapters/DI and Store providers | 294 focused XCTest + 2 Swift Testing; final full PASS |
| C | complete | Raman `01a16952-8823-7942-8691-b7e346000204`; AppStore project/build scripts | final archive `r2`; app/framework arm64+x86_64, minos 13 / SDK 27; dSYM, source closure and signed static audit PASS |
| C/D review | complete | Maxwell implementation; Galileo `/ Mill review | final 80 bundle fixtures; source closure 89 fixtures; scoped re-review PASS |
| D | complete for implementation/offline evidence | Curie lock/defaults; Maxwell public providers | coexistence 14 tests; public providers 20 tests / 33 cases; sandbox/hardware NOT RUN |
| E | complete | Archimedes copy/privacy; Socrates UI/actions | 11 UI integration + 7 composition tests; 12-language copy; final archive/static audit PASS; interactive UI NOT RUN |
| F | complete | Archimedes `01a16956-2ee5-7531-9ace-cac280899677` | 114 policy / 85 semantic / 29 shell PASS at final fix tree; hosted workflow tracked separately |

## Coordination rulings

- The previous intermediary task is closed and the erroneously created user chat
  is archived/interrupted. Preserve its successful baseline test log and record
  its zsh `status` wrapper error honestly. Do not resume that execution chain.
- Use this ledger and phase verification files instead of `sdd-workspace`; its
  previous directory creation loop is not part of the product and must not run.
- Parallel work requires disjoint write scopes and no simultaneous builds in the
  same `.build` directory. Parent serializes integrated verification.
- Compilation, entitlement/signature inspection, sandbox runtime, real hardware,
  signing/notarization and publication are separate evidence classes.
- Ruling: independently compiled channel targets may consume the same shared
  source files with explicit source membership, following CotEditor, instead of
  forcing a broad public API migration of all internal Swift types. Store must
  compile its own safe module and must never link the complete Direct SwiftPM
  Core product. Excluded sources and actual build inputs need independent
  auditing. Cost if wrong: accidental source inclusion must fail the Store
  source-closure and bundle checks before delivery.
- Preserve reviewable staged delivery: commit each verified phase separately and
  use stacked development PRs where later phases depend on earlier unmerged
  phases. No phase is automatically merged into main. Shared worktree branch
  transitions happen only in the parent; workers never change HEAD/index.
- Ruling: publish the Store target (C) and its CI/release separation (F) as two
  ordered commits in one stacked engineering PR. The Store target must arrive
  with real PR build/audit checks, and the shared workflow policy fixtures
  validate both new workflows together. Cost if wrong: C and F require paired
  review; they remain separate commits and neither publishes anything. D public
  providers/coexistence and E product/localization stay in later stacked PRs.
  The minimal Store privacy manifest is a C packaging input even though the E
  copy worker authors it; E documents its scope and remaining policy review.
- Platform implementation uses
  `/Users/lingsmbp/.codex/worktrees/dual-distribution-platform/status-trio`,
  branch `codex/dual-distribution-platform-work`, from the same frozen base.
  Parent seeded and staged the seven Phase A source/test files plus spec/plan.
  Worker leaves that index untouched; integration takes only its unstaged delta,
  including explicitly enumerated new files. This permits independent builds
  without racing the foundation worktree's SwiftPM cache.
- Bundle audit review: reject CoreDisplay linkage explicitly and inspect nested
  code signatures/entitlements, allowing frameworks to omit app-sandbox while
  rejecting debug and escape entitlements. Real bundle audit remains pending.
- DDC work is now a disjoint platform-worktree slice owned by Gibbs
  `01a16958-7a78-7fd1-be6d-f6e6f4a8c80c`: `Audio/DDC*.swift`,
  `Monitoring/VolumeMonitor.swift`, new coordinator contract/channel factories,
  and DDC/Volume tests. Russell owns the other platform changes and canonical
  exclusions. Serialize their SwiftPM builds in that worktree.
- Source closure auditor review fixes passed 52 offline scenarios: legitimate
  zero-DerivedSources builds pass; manifest SHA is compared against real
  repository HEAD, with stale-SHA and Git failure checks.
- C review requests sent: mandatory bundle audit (no file-existence skip);
  exact XcodeGen version aligned with F; no global Bundle ID override on the
  Core framework; Bluetooth and location entitlements for retained public
  providers; main-app localized InfoPlist resources and existing AppIcon asset;
  embedded framework archive installation settings verified with a real archive.
  Additional requests: use XcodeGen's supported sources/buildPhase resources
  form, and canonicalize archive paths to reject traversal/symlink escape.
- B1 parent review found two issues in the in-progress patch and sent them back
  before integration: helper presentation publishers read old values during
  `@Published` willSet; update startup lost the existing shared activation-policy
  instance. Required fixes use delivered publisher values and explicit Direct
  configuration, with readiness/approval/error and presentation regressions.
- Helmholtz `01a1697b-d2b4-7891-8a05-f7073ec74e9b` is independently reviewing
  the frozen source-closure and coexistence patches from
  `.build/dual-distribution-reviews/source-and-coexistence.diff`.
  Review completed: coexistence spec/quality PASS, no findings. Source closure
  FAIL on the frozen intermediate snapshot. Its import case was fixed in the
  live 53-scenario suite, but five further gaps remain: exact known Bluetooth
  symbols/helper labels, derived-source scanning, non-hex HAL literals, and
  escaped raw/multiline string lexing. Gibbs must finish DDC focused tests,
  then fix these in the foundation auditor/fixtures (round 1); Helmholtz will
  re-review only those fixes. The original 52-case result is superseded by the
  newer fixture inventory and must not be used as final evidence.
- F worker continues into the disjoint E copy/localization slice after its F
  checkpoint: `.build/dual-distribution-briefs/phase-e-copy.md`.
  Maxwell continues from the bundle-audit review into new process-free public
  Bluetooth/accessory readers, without changing existing controller/factory
  files owned by B. Parent coordinates the foundation SwiftPM test slot.
- E also owns `AppStore/PrivacyInfo.xcprivacy`; C must include it in the main app
  resource phase. Own local defaults and app-internal uptime throttling have
  separate required-reason scopes. The existing public global system-preference
  reads (volume feedback and icon style) need explicit privacy-policy review;
  do not claim the own-defaults reason covers system-written data, silently
  delete public functionality, or change API spelling to evade the policy.
- F now pins XcodeGen 2.46.0 with an archive checksum; final evidence still
  needs its completion report and independent review. GitHub's official hosted
  runner reference was checked: standard `macos-26` is arm64; source workflows
  detect an installed SDK >=26 instead of assuming Xcode 27 availability.
  Parent downloaded the exact official asset and verified the pinned SHA-256,
  4,278,764-byte size, arm64+x86_64 Mach-O slices and executable version 2.46.0.
  Evidence: `.build/dual-distribution-logs/xcodegen-pin-verification.log`.

## Parent integration checks in progress

- DDC boundary focused tests passed 70/70 (Isolation 5, Coordinator 20,
  VolumeMonitor 45) in the platform worktree. Gibbs released the SwiftPM slot
  to Russell. Source closure round 1 passed 85/85 and is frozen for Helmholtz's
  scoped re-review; prior 52/53-case evidence is superseded.
- Maxwell completed three public providers: process-free paired Bluetooth,
  public IOPS accessory battery, and CoreWLAN preferred-network profiles.
  Their 20 tests / 33 cases and the seven localization tests passed; the
  foundation SwiftPM slot is now held by Archimedes for review fixes.
- Independent F review found policy-checker bypasses for inline event filters,
  expression whitespace/bracket access, non-blocking/comment-only gates and
  missing unsigned build mode. Current workflow YAML satisfies the intended
  contracts, but its checker is not accepted until round 1 and scoped review.
  E copy must become release-neutral and gain multilingual claim regression
  coverage in the same disjoint author-owned fix.
- Parent integrated a 70-file B/DDC snapshot without modifying the platform
  index. Snapshot manifest and patch are in
  `.build/dual-distribution-reviews/platform-integration-snapshot.*`;
  patch SHA-256 is
  `3a02a5e635e40d42b0713a963dbadacc60c87184c8348d93e1b152f99a53a403`.
  Russell continues platform verification; later changes are synchronized by
  comparing file hashes, preserving integration-owned changes.
- Store now injects the public paired-device/accessory readers, CoreWLAN
  preferred-network provider, public IOBluetooth connection events and existing
  CoreBluetooth BLE scanner. Permission/demand owners and polling intervals are
  unchanged. Their sandbox/hardware results remain NOT RUN.
- Ruling: accessory battery notify keys `com.apple.system.accpowersources.*`
  are undocumented even though notify(3) itself is public. Move the existing
  concrete class unchanged to Direct-only source membership, retain its shared
  lifecycle protocols, and leave Store on its existing refresh path. This
  preserves Direct events without shipping those system-private key strings.
  Cost if wrong: Store accessory changes may wait for an existing refresh;
  public IOPS reads and public Bluetooth events are retained.
- Parent found a Direct regression before accepting B: the safe discovery
  default replaced the MobileBattery reader, but Direct composition had not
  re-injected it for `AppleDeviceDiscoveryController`. Russell owns the fix and
  regression. B cannot be accepted from the current tests alone.
- Socrates `01a169a7-bec4-7e61-bcc6-aeefd157c1aa` owns E UI/actions in the
  integration worktree. B's platform worktree remains independent. Raman can
  now perform real Store unsigned/signed/archive builds with the integrated
  source manifest; no static fixture result is promoted to a runtime pass.

- Added the four new offline Store/workflow fixtures to `verify-local.sh full`,
  and dual-workflow policy fixtures to `docs`.
- Updated both local-verification synthetic fixture inventories.
- RED: the updated local-profile test rejected the missing dual workflow check.
  GREEN: `test-verify-local.sh` passed. The companion bundle test first failed
  because its synthetic repository lacked the four new scripts; after adding
  the fixtures, `test-verify-local-bundle.sh` passed.
- Updated `AGENTS.md` and `docs/local-first-workflow.md` to distinguish the
  explicitly requested read-only dual-channel PR source checks from formal
  release CI. These changes await the final integrated full/docs run.

## Stage A delivery

- Commit: `95858e076a91bf4837f8101d681b23e6d7d8b1f5`.
- Draft PR: https://github.com/lingyired/status-trio/pull/145, base `main`.
- Fresh `origin/main` comparison remained
  `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`.
- Full: 750 Core Swift Testing tests, 15 Helper XCTest tests, Release build,
  local non-Universal ad-hoc bundle and native/offline contracts passed.
- Docs: localization 19+7+1+2 tests and workflow policy passed.
- Independent review: spec and quality PASS, no findings. Staged whitespace
  check passed before committing. Store runtime and hardware remain NOT RUN.
- First full attempt was interrupted after dependency acquisition stalled.
  Six clean pinned source repositories were copied read-only and verified;
  no compiled prefixes were copied. Both attempts remain in separate logs.

## Integrated build checkpoint

- B source freeze: 2026-10-24 01:01:32 CST. Parent synchronized the final six
  files with recorded SHA-256 values. Its full pass covers Direct source/build
  behavior; integration-owned E/D/C changes still require final full.
- Earlier integrated checkpoint: actual Store unsigned and ad-hoc signed
  Release builds succeeded with 300 shared sources, 23 exclusions and 3 Store
  platform sources. Both app and Core framework contain arm64/x86_64, macOS 13
  minimum and SDK 27 metadata. Recursive signed audit verified four code items
  and three contained symlinks. The later 304-source archive supersedes this
  source inventory. No runtime claim follows from either check.
- The initial resource-root mismatch was resolved by inspecting actual PBX
  references and SRCROOT/PROJECT_DIR, then validating all 40 generated resource
  build entries before the next build. All failed attempts remain logged.
- Bundle review round 1 accepted CoreDisplay token coverage, strict nm error
  handling and bounded public-reader work. Round 2 addresses actual MH_EXECUTE
  classification irrespective of filename, and rejects Boolean IOPS capacities.
  The interim 68-case suite is not final accepted bundle evidence.
- F round 2 now validates a unique actual XcodeGen version read, with hard-coded
  and reassignment negative fixtures. E copy is evergreen in all 12 languages,
  without claiming a Store listing is published or under preparation.

## Final local and hosted verification

- Final tested pre-commit tree:
  `ee5711392f0fb347e0d8a957a33343153962eacd`, containing 64 modified and
  3 new files for phases B-F and their review fixes.
- The branch was based on `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`. At the
  final verification, fetched `origin/main` was
  `7903d044a763b6232c8ed4c513d7890a675ebc47`; the branch
  remained 100 commits behind and did not merge that later history.
- The first final `full` run failed only because the branch predated upstream
  macOS 27.2 static-raster baselines. `ffae6046` was cherry-picked as
  `ee571139`; its conflict was resolved while retaining every recorded macOS 26
  and macOS 27 variant. The complete profile then passed.
- `bash scripts/verify-local.sh full` passed on that working tree: 1,981 XCTest
  with 7 skipped and 0 failures, 784 Swift Testing tests in 116 suites, Release
  build, local ad-hoc app bundle, native contracts and offline workflow audits.
- `bash scripts/verify-local.sh docs` passed on the same tree: localization
  filters, workflow policy, 114/114 dual-workflow policy checks, 85/85 semantic
  fixtures and 29/29 embedded-shell syntax checks.
- Focused evidence: 49 XCTest cases passed; Store project contract 75/75,
  source closure 89/89 and bundle contract 80/80.
- The actual unsigned Store archive compiled 304 Store sources. The app and
  Core framework are arm64+x86_64 with macOS 13 minimum and SDK 27 metadata;
  dSYMs, source closure and the recursive bundle audit passed. Sandbox runtime,
  signing, notarization and App Store Connect remain `NOT RUN`.
- The first actual Store bundle audit failed because Xcode archived
  `.lproj/InfoPlist.strings` as UTF-16 LE with a BOM while the auditor required
  UTF-8. A RED fixture was added, and the auditor now accepts `utf-8-sig` then
  `utf-16`. Generated Store resources remain UTF-8; the re-audit passed.
- CI stabilization commits: `c5eb36b7` through `c5288c10` made hosted test
  geometry/process bounds deterministic, then `d89cb7dd` installed the mobile
  helper build tools required by the Direct job and `e8d31081` drained both
  icon presentation coalescers at an explicit test boundary.
- GitHub dual-channel run `40142748595` applies only to `e8d31081`. The current
  uncommitted fix snapshot has no hosted run; that evidence is not inferred from
  local or offline fixtures.
- Rawls closed findings 1-5 and declared the whole-branch code review clean.
  The reviewer independently ran 62 focused XCTest cases and `git diff --check`;
  no tracked files changed during review. Runtime, hardware, signing, sandbox,
  hosted CI for this uncommitted snapshot and publication remain `NOT RUN` as
  recorded in the final verification file.
