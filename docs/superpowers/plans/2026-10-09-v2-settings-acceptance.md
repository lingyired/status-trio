# Status Trio 2.0 Icon Designer — Acceptance Handoff

**Status:** Preparation in progress. This file will be finalized only after fixed-SHA review, full local gate, non-publishing CI, and local package verification.

## Candidate and safety boundary

- Version/build candidate: `2.0.0` / `19`; confirm build 19 still exceeds the latest published build immediately before dispatch.
- Branch: `codex/v2-settings-icon-designer`.
- Current committed code-fix SHA: `295a9b835c946b583abec841a138daa6f4dc3134`; payload-expiry follow-up commit `1ec83860ba19f4b9c0ff92e96e80ebce47c91a5b` is awaiting separate fixed-SHA review.
- Release notes: `release-notes/2.0.0/` (12 languages; validate with `VERSION=2.0.0 BUILD=19 PUBLISH=false bash scripts/validate-appcast-notes.sh`).
- No merge to `main`, GitHub Release, or appcast publication is authorized. The release workflow must run with `publish=false`. Local tests use Xcode 27.0 / Swift 6.4 / SDK 27.0 and do not establish CI Swift 6.3.3 compatibility.
- Never overwrite or launch the user's installed `/Applications/Status Trio.app`; keep acceptance app and DMG inside the ignored worktree `dist-v2-acceptance/` (or record the exact alternate path).
- Signing is expected to be ad-hoc unless verified credentials are explicitly available. Do not claim notarization without notarization evidence.

## Automated and package evidence (fill with actual outputs)

| Gate | Result | Evidence |
|---|---|---|
| Fixed-SHA independent review | Pending | `1ec83860ba19f4b9c0ff92e96e80ebce47c91a5b` |
| `swift test` | Pass (local) | `/tmp/status-trio-task12-expiry-full-swift-test-retry.log`; 1551 XCTest, 7 skipped, 0 failures; 584 Swift Testing tests / 92 suites |
| `swift build -c release` | Pass (local) | `/tmp/status-trio-task12-expiry-swift-build-release.log`; Swift 6.4 / SDK 27.0 only |
| `VERSION=2.0.0 BUILD=19 PUBLISH=false bash scripts/validate-appcast-notes.sh` | Pass (local) | `/tmp/status-trio-task12-expiry-notes-validation.log`; 12 titles + 12 descriptions, English first |
| 12-language `plutil -lint` and `git diff --check` | Pass (local) | `/tmp/status-trio-task12-expiry-plutil.log`; 24 localized `.strings` files linted |
| `release.yml` workflow on current feature-branch SHA | Pending | Exact run ID, dispatch timestamp, head SHA, stage results, artifact IDs/paths; must show `publish=false` |
| Local app / DMG verification | Pending | Absolute artifact paths; version/build, architecture, SDK, code-signing, `hdiutil verify` output |
| PR | Pending | Draft PR number/URL; must be attached in Codex after creation |

## Manual acceptance checks (not yet performed)

1. Open the acceptance copy from the recorded worktree artifact location, not the installed app; confirm it reports version `2.0.0` and build `19`.
2. In Icon Designer, switch among outer ring, center, and footer; verify source, fallback, behavior, and appearance controls retain their configuration when changing slots.
3. Select AirPods battery and try single-ring and left/right dual-ring layouts; verify one known ear is shown alone and case-only data does not masquerade as an earbud reading.
4. Select a connected Bluetooth device as the center source, disconnect it, and verify the selection remains configured while fallback behavior is truthful.
5. Compare Menu Bar and Dock previews for live AirPods/device state and each Dock background; optionally repeat with VoiceOver and on macOS 13 if those environments are available.

## Not claimed as verified

No manual UI/VoiceOver pass, macOS 13 runtime pass, physical AirPods/device disconnect/reconnect or case-state pass, sleep/wake/CPU measurement, notarization, or public release is claimed until recorded here with direct evidence.
