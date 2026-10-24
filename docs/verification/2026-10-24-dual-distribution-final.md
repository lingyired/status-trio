# Dual-distribution integrated verification

Date: 2026-10-24 (Asia/Shanghai).

This is the final integrated verification record. A pending row is not a pass.
The execution ledger is `dual-distribution-progress.md`; the architecture,
product matrix and operational procedures are one directory above.

## Provenance

- Latest fetched `origin/main`:
  `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`.
- Phase A commit: `95858e076a91bf4837f8101d681b23e6d7d8b1f5`.
- Integrated B/E policy commit:
  `a4c9f34a1c9ade2c1116f02781ea549521eaa370`.
- Integration worktree:
  `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`.
- Toolchain: Xcode 27.0 (27A266a), macOS SDK 27.0.
- Direct version source remains `Support/Info.plist`, `1.7.0 (38)`.
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
| Source closure | Complete 85-case fixture run and scoped independent re-review | PASS for frozen auditor/fixtures |
| Local-profile wrapper integration | `test-verify-local.sh` and `test-verify-local-bundle.sh` rerun by parent | PASS |
| Workflow/copy review round 2 | 105 policy, 77 semantic, 28 shell; final localization checks | PASS for workflow/copy fixtures |
| Bundle/public providers | 75 bundle scenarios; 20 tests / 33 public-provider cases | PASS for fixtures/process-free parsing |
| Store engineering | Final archive `r2`: dSYM, source closure, project and signed static bundle audits passed | PASS for build/static audit; runtime NOT RUN |
| Final Direct full/docs | Final integrated tree rerun | PASS |
| Final Store unsigned/signed/archive | Final archive `r2` built after the B/E policy fix | PASS for unsigned archive and ad-hoc static audit |
| Scoped independent review | B/E and C/D findings re-reviewed | PASS; runtime/hardware NOT RUN |

The first actual Store builds found a resource-reference root mismatch.
Those failed logs are retained separately; offline project fixtures were not
treated as proof of an actual build.

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
| Privacy policy | NOT VERIFIED for system-written volume-feedback/global appearance preferences; see `distribution-privacy.md` |
| Store App ID, signing/profile/build-number checks | NOT RUN; no App Store Connect changes authorized |
| Universal binary metadata | Store app/framework arm64+x86_64 observed; Direct Universal packaging NOT RUN |
| Developer ID/notarization/DMG/release | NOT RUN; existing formal Direct release contracts preserved |
| Submission/publication | Not performed; explicitly outside this task's authorization |

## Delivery references

Phase A draft PR: https://github.com/lingyired/status-trio/pull/145.
Later phase commits/PRs and final tested SHAs will be recorded after integration
and review. No development PR is automatically merged.
