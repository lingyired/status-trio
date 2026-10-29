# Dual-distribution integrated verification

Date: 2026-10-29 (Asia/Shanghai).

This is the final integrated verification record. A pending row is not a pass.
The execution ledger is `dual-distribution-progress.md`; the architecture,
product matrix and operational procedures are one directory above.

## Provenance

- Branch base `origin/main`:
  `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`.
- Latest fetched `origin/main`:
  `7903d044a763b6232c8ed4c513d7890a675ebc47`. The development branch remains a stacked PR, is 100
  commits behind that tip, and has not merged those later `main` commits. The
  only later `main` change included here is the scoped macOS 27.2 raster
  baseline fix from `ffae6046`, cherry-picked as `ee571139`.
- Final tested pre-commit tree: `ee5711392f0fb347e0d8a957a33343153962eacd`
  plus 64 modified and 3 new files completing the dual-distribution work. No
  hosted run covers this snapshot.
- Phase A commit: `95858e076a91bf4837f8101d681b23e6d7d8b1f5`.
- Integrated B/E policy commit:
  `a4c9f34a1c9ade2c1116f02781ea549521eaa370`.
- Integration worktree:
  `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`.
- Toolchain: Xcode 27.0 (27A266a), macOS SDK 27.0.
- The branch base version source remains `Support/Info.plist`, `1.7.0 (38)`.
  Later `main` release commits are outside the frozen development range.
- `Package.swift`, `scripts/build-app.sh`, `Support/Info.plist` and
  `.github/workflows/release.yml` have no diff from the fetched base.
- The original checkout's unrelated release documentation and release-note
  changes are outside this worktree and outside the delivery scope.

## Verification inventory

| Scope | Observed evidence | Acceptance |
| --- | --- | --- |
| Phase A foundation | 750 Core + 15 Helper tests; full/docs; independent review | PASS at A commit |
| DDC boundary | 70 focused tests: 5 isolation, 20 coordinator, 45 monitor | PASS on platform implementation tree |
| Coexistence | 14 focused tests; independent spec/quality review | PASS for offline locks/defaults; runtime NOT RUN |
| Source closure | Complete 89-case fixture run and scoped independent re-review | PASS for frozen auditor/fixtures |
| Local-profile wrapper integration | `test-verify-local.sh` and `test-verify-local-bundle.sh` rerun by parent | PASS |
| Workflow/copy review round 2 | 105 policy, 77 semantic, 28 shell; final localization checks | PASS for workflow/copy fixtures |
| Bundle/public providers | 80 bundle scenarios; 20 tests / 33 public-provider cases | PASS for fixtures/process-free parsing |
| Store contracts | Project 75/75, source closure 89/89 and bundle 80/80 | PASS for offline contracts |
| Store engineering | Actual archive compiled 304 Store sources; app/Core are `arm64+x86_64`, minos 13 / SDK 27 | PASS for unsigned archive; runtime NOT RUN |
| Final Direct full | Current fix snapshot: 1,981 XCTest (7 skipped), 784 Swift Testing tests in 116 suites, Release build and local/native contracts | PASS |
| Final docs/policy | Current fix snapshot: localization filters and workflow policy; 114/114 policy, 85/85 semantic and 29/29 embedded-shell checks | PASS |
| Focused review fixes | 49 focused XCTest cases across policy, composition, onboarding, Bluetooth, UI and audit regressions | PASS |
| Final Store unsigned/archive | 304 compiled sources; dSYM, source closure and recursive bundle audit passed | PASS for unsigned archive and static audit; sandbox/runtime NOT RUN |
| Scoped independent review | B/E and C/D findings re-reviewed | PASS; runtime/hardware NOT RUN |
| Final whole-branch review | Rawls closed findings 1-5; independent 62 focused XCTest and `git diff --check` passed | PASS for code review; runtime/hardware/hosted CI NOT RUN |
| GitHub dual-channel PR run | Run `40142748595` covers only `e8d3108` | NOT RUN for the current fix snapshot; local full does not prove hosted CI |

The first final `full` run failed only in
`nilPhaseKeepsThePreEffectStaticPixelFingerprint`: the branch predated the
upstream macOS 27.2 raster baseline. The scoped compatibility commit was
cherry-picked, its macOS 26 baseline conflict was resolved without dropping
either recorded variant, and the complete profile then passed on the current
64 modified plus 3 new files.

The first actual Store builds found a resource-reference root mismatch.
Those failed logs are retained separately; offline project fixtures were not
treated as proof of an actual build.

The first actual Store bundle audit after the fix set also exposed a test
assumption: Xcode archives compile `.lproj/InfoPlist.strings` as UTF-16 LE with
a BOM, while the auditor accepted only UTF-8. A RED fixture reproduced the
failure; the auditor now decodes `utf-8-sig` first and falls back to `utf-16`.
This was not a resource-generator defect. Generated Store source resources
remain UTF-8, and the re-audited archive passes.

## Evidence boundaries

The source auditor proves agreement with reviewed membership and rejects known
private tokens/selectors; it is not a general discovery tool for every private
API. The bundle auditor complements it with recursive Mach-O, dependency,
symbol, string, signature, entitlement, component and symlink checks.

Unsigned compilation and an unsigned archive are internal diagnostics.
Ad-hoc signing with sandbox entitlements is static signing evidence. Neither
proves sandbox runtime, provisioning, Apple Distribution signing or review.

The following remain separate manual acceptance items:

| Category | State and reason |
| --- | --- |
| macOS 13 Ventura runtime | NOT RUN; no Ventura device/environment exercised |
| Public Wi-Fi/Bluetooth/CoreAudio/IOKit/Huawei hardware | NOT RUN; no device or TCC state is inferred from fixtures |
| Allow/deny/revoke, sleep/wake and device removal | NOT RUN on a signed Store product |
| Actual containers/co-installation/Login Items | NOT RUN; offline lock/defaults tests do not prove system registration |
| Privacy policy | Store isolation PASS: source closure excludes `VolumeFeedback.swift` and `DirectSystemIconAppearanceReader`, Store injects nil feedback plus the default icon appearance, and the bundle audit rejects global-preference symbols/keys. Direct retains those readers. Policy compliance for Direct's system-written preference reads remains NOT VERIFIED; see `distribution-privacy.md` |
| Store App ID, signing/profile/build-number checks | NOT RUN; no App Store Connect changes authorized |
| Universal binary metadata | Store app/framework arm64+x86_64 observed; Direct Universal packaging NOT RUN |
| Developer ID/notarization/DMG/release | NOT RUN; existing formal Direct release contracts preserved |
| Submission/publication | Not performed; explicitly outside this task's authorization |

## Delivery references

Phase A draft PR: https://github.com/lingyired/status-trio/pull/145.
Phases B-F stacked draft PR: https://github.com/lingyired/status-trio/pull/148.
No development PR is automatically merged.
