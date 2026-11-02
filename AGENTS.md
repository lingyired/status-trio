# Status Trio Agent Rules

## Local-First Change Flow

Ordinary development does not require GitHub Actions. Use focused local tests
while developing, then run the verification profile sized to the risk before
delivery and merge.

### Iteration vs. delivery

A full profile is a **delivery gate, not a per-edit step**. While iterating, run
only the focused filter that covers the behavior you touched, e.g.
`bash scripts/test.sh 'SettingsViewTests'` or
`bash scripts/test.sh 'IconPresentationMapperTests'`. Do not re-run the full
Swift suite after every edit; run it once on the final integrated tree before
merge. The profiles below size the *delivery* check, not each save.

Pick one bounded profile with
`bash scripts/verify-local.sh <quick|docs|full> [swift-test-filter]`:

- `quick`: shell syntax, forbidden patterns, and focused Swift tests. This is
  the default for a small isolated code change.
- `docs`: shell syntax, forbidden patterns, the localization regression
  filters, and workflow-policy checks. Use this for documentation or
  localization-only changes.
- `full`: the full Swift suite, Release build, a non-Universal local app
  bundle, its platform/SDK and Helper contracts, and the native compatibility
  and dependency checks, plus offline release-pipeline simulations. Use this
  for state, concurrency, rendering, Helper, build-pipeline, or other high-risk
  changes.

The script reports the tested SHA, branch, tracked and untracked working-tree
changes, toolchain, commands, exit status, scope, and unverified items. A filter
is evidence for that filter only, not for the full suite. Local verification is
not a runtime, signing, notarization, DMG, Universal-package, or release pass.

Small follow-up changes may commit directly to `main` or use a short-lived
branch and fast-forward it. Use a pull request for larger, multi-subsystem, or
review-worthy work. No pull request is required for every task, and no GitHub
Actions run is required for ordinary development, commits, pull requests, or
merges.

Before delivery:

1. Fetch and compare with the latest `origin/main`; record the branch base.
2. Run the risk-sized local profile on the final integrated tree.
3. Check for shared-file and public-file conflicts; coordinate ordering for
   shared state or renderer edits instead of overwriting another agent.
4. Merge in completion order. If `main` advanced during the merge, recheck the
   diff and re-run the affected verification scope.

Do not force-push `main`, rewrite another agent's branch, or treat a remote CI
run as a replacement for local evidence.

### High-risk optional remote check

A high-risk change may use a non-publishing diagnostic GitHub Actions run when
a maintainer explicitly approves it. This is an exception, not a routine
pre-merge requirement. It must not create a Release, tag, appcast update, or
other public side effect.

### State vocabulary

- `merged`: the change is in `main`.
- `built`: an artifact was produced from a known SHA; it is not yet public.
- `released`: a published artifact was verified from the same frozen SHA and
  its public metadata matches the signed/notarized package.

Do not use these words interchangeably.

## Risk-Based Verification

The following table is the minimum for local work. Read the mapped rule under
`.agents/rules/` before editing the listed paths; these files are not loaded
automatically by Codex.

| Change | Read | Minimum local profile |
| --- | --- | --- |
| Documentation, copy, localization, translations | `.agents/rules/release.md` only for release copy; otherwise the affected UI rule | `docs`; release-note coverage when applicable |
| Ordinary isolated feature or unit test | Rule for its subsystem | Focused `quick` tests; add the subsystem regression filter |
| State/store schema, migration, `@MainActor`, `Sendable`, actor isolation, concurrency, `deinit`, generic/resource plumbing | `.agents/rules/performance.md`, `.agents/rules/macos-compatibility.md` | `full` before delivery; while iterating, the focused store/behavior tests |
| Settings pane layout, control styling, copy or previews that only read existing state (no change to mapper, renderer, scene or stored schema) | `.agents/rules/rendering.md` only if a preview calls the renderer | `quick` with the pane's focused tests (e.g. `SettingsViewTests`); `full` only if the same change also touches rendering/model below |
| Icon scene, renderer, `StatusIconRenderer`, `StatusIconGeometry`, `IconPresentationMapper`, `IconSceneState`, `StatusBarController` icon path, `AppIconController`, `DockIconRenderKey`, `DockIconRenderer` | `.agents/rules/rendering.md` | `full` before delivery, plus `Issue30WiFiAlignmentTests` and Dock/Menu Bar parity tests; iterate with the focused renderer/mapper filter |
| Bluetooth, nearby BLE, audio, battery, permission or privacy behavior | `.agents/rules/bluetooth.md` or the matching device rule | Affected focused tests; `full` for lifecycle or permission changes |
| Wi-Fi, Ethernet, VPN, SSID/location, Settings pane route | `.agents/rules/network.md` | Focused network tests and `StatusMenuBuilderTests` for route changes |
| Helper, XPC, LaunchDaemon, signing or privileged behavior | `.agents/rules/release-validation.md` | `full`; manual Developer ID and XPC checks remain `NOT RUN` until performed |
| Build script, SDK/deployment metadata, `Package.swift`, `Info.plist` | `.agents/rules/macos-compatibility.md` | `full` |
| Release workflow, appcast, versioning, signing, notarization | `.agents/rules/release.md` and `.agents/rules/release-validation.md` | `full` plus offline release simulations; no real publish |

`bash scripts/test.sh [filter]` remains the single Swift test entry point. It
always runs `scripts/check-forbidden-patterns.sh`, including when a filter is
provided. Do not duplicate its test or filter logic in a second wrapper.

For any icon work, use the existing isolated-ink and full-composite
`Issue30WiFiAlignmentTests`; never replace them with a tolerance that hides a
half-unit shift. Keep `ChargingEffectRenderingTests` fingerprints honest.

## Non-Negotiable Invariants

- The app runs on macOS 13 and later. The local macOS 13 static contract does
  not prove runtime compatibility; record real Ventura and current-macOS checks
  separately as PASS, FAIL, BLOCKED, or NOT RUN.
- Formal releases use the `xcode-27` runner, Xcode 27, and the SDK it provides.
  The build must still use the macOS 26 SDK or newer; an older SDK ships the
  pre-Tahoe appearance. Keep the guard in `scripts/build-app.sh` and the
  assertion in `scripts/verify-platform-version.sh`.
- Menu Bar and Dock rendering and settings stay on the same scene source. A
  menu-bar-only setting needs an explicit product decision, documentation, and
  a test.
- Preserve Universal `arm64 + x86_64` release requirements, Main App and Helper
  minimum versions, MobileBattery dependency bounds, Sparkle, and the existing
  Developer ID plus Ad-hoc fallback branches.
- Preserve permission boundaries and low-power idle behavior. Do not add
  polling, animation, logging, caches, or background work without an owner and
  a stop path.
- Development bundles must display their `STDevelopmentCodename` beside the
  status-panel Settings control and in the Settings About identity area.
  Release bundles must not show a development codename. Build manual
  development bundles through `scripts/build-worktree.sh` so the codename is
  populated; never infer it from a checkout or process at runtime.
- Never weaken, skip, or silently retry a test to make a local or release run
  green. A failing test is a finding until its root cause is addressed.

## Swift Toolchain Compatibility

The formal release runner and its Xcode version are defined by
`.github/workflows/release.yml`: `xcode-27`, Xcode 27, and its matching SDK.
The floor remains SDK 26 for Liquid Glass behavior. Historical Xcode 26.6 runs
remain evidence only for that toolchain; they are not the current release
environment. Local Xcode 27 / Swift 6.4 is useful for development but is not
proof that the release runner compiles. The Swift rules below are compatibility
requirements, not a reason to run a remote preflight for every edit:

- Do not use `isolated deinit` or enable experimental `IsolatedDeinit`.
- Do not pass actor-isolated methods directly as function values; use an
  explicit closure.
- Do not write `weak let`; weak bindings are `var`. Use the test target's
  `DeinitProbe` for teardown-owned observations.
- Do not assume `Bundle.module` resource names or directory casing match
  between local and release builds. Load localized resources with
  `Bundle(path:)` and the canonical/lowercase `lproj` fallback.
- If the compiler crashes with `IRGenRequest`, `SmallVector unable to grow`, or
  signal 6, reduce the triggering code shape. Do not hide it with compiler
  flags.

Historical failures and their evidence are in
`docs/swift-ci-compatibility.md`. Failed release diagnostics should be added
there by root cause, with the run ID, failed stage, fix, and re-verification;
do not copy long reports for repeated runs.

## Menu Bar and Dock Icon Parity

- Every icon-rendering or icon-setting change updates both the Menu Bar and
  Dock paths in the same change.
- Where applicable, update `SettingsStore` option derivation,
  `StatusBarController` subscriptions, `AppIconController`
  subscriptions/state, `DockIconRenderKey` cache inputs,
  `DockIconRenderer` rendering, and tests for both surfaces.
- If a setting is intentionally menu-bar-only, state that in the issue/spec,
  document the limitation, and add a test.

See `.agents/rules/rendering.md` and
`docs/issue-30-wifi-centering-analysis.md`.

## System Settings Pane Routes

- The Wi-Fi gear opens the Wi-Fi pane with
  `com.apple.wifi-settings-extension` first; a wired row opens the Network pane
  with its own extension first.
- Do not make a pane route depend on the running macOS version.
- The first route decides the destination. `open` success is not proof of the
  pane; verify the loaded Settings extension, as documented in
  `docs/settings-pane-routes.md`.
- Keep `StatusMenuBuilderTests.testSystemSettingsURLFallbackOrder` aligned with
  the route order.

## Release Boundaries

- Release CI is required only before a formal release, not for ordinary commits,
  pull requests, or merges.
- The only release entry point is a maintainer-dispatched manual
  `release.yml` run. A `v*` tag push must never publish automatically.
- Dispatch from `main` with a frozen lowercase 40-character `candidate_sha`.
  The `verify` and `native` jobs run the full suite and native contracts on
  that exact commit; `package` waits for both and builds one Universal
  artifact; `publish` downloads that artifact without rebuilding, repackaging,
  signing, or notarizing.
- The `verify` and parallel `native` jobs must not receive signing or
  notarization secrets. `package` and `publish` wait for both. Formal
  publication always uses the reviewed `distribution` Environment;
  owner-triggered diagnostics may use `distribution-owner-signing`, while all
  other triggering actors and reruns use `distribution`. Publication is allowed
  only when the candidate SHA, manifest SHA, Release Tag, appcast, DMG digest,
  and public URLs all agree.
- A failed Appcast or upload may be retried only with the same verified artifact.
  A retry must not create a second Release or rewrite a public appcast item.
- Never publish a different SHA, rebuild during publish, or let a tag point at
  a commit that differs from the package manifest.
- Never create a real Release, tag, DMG, or online appcast change while
  validating workflow logic. Use offline fixtures and fake external tools.
- Keep the `distribution` Environment and its manual approval boundary. The
  owner-only signing Environment may skip review only for `publish=false`
  diagnostics and only while workflow changes remain owner-controlled. Do not
  read, print, or commit signing keys, API keys, or notarization credentials.
- Version and build numbers are explicit and must increase over the published
  build number.
- Release notes require `en.md` and `zh-Hans.md`; `publish=true` requires every
  shipped language. Keep localized appcast variants explicit, with `en` first.
- A Developer ID/notarized release must not include first-launch `xattr`
  instructions. Only an Ad-hoc fallback may append them, and never inside the
  Sparkle appcast.
- Report `Ad-hoc` honestly when credentials are unavailable. Do not claim
  notarization, Universal packaging, or runtime Helper behavior without
  evidence.

Use `.agents/rules/release.md` and `.agents/rules/release-validation.md` for the
detailed release and recovery rules.

## Worktree Safety

- Reuse an existing isolated worktree when possible. Create one only when
  concurrent writes or branch isolation require it.
- `bash scripts/build-worktree.sh release [no-open]` derives an independent dev
  bundle ID from the branch; use it instead of installing a preflight build
  over the production app.
- Before removing a worktree, verify there are no uncommitted changes and no
  running app/process from it. Never use destructive bulk deletion.
- Do not alter another agent's worktree, shared branch, or uncommitted files.

## Background UI Testing

- **Default route:** unless the task explicitly requires human visual
  inspection or a documented foreground-only step, every agent and harness
  that will operate or observe a live macOS UI must first read
  `.agents/skills/background-ui-testing/SKILL.md` and start through
  `bash scripts/launch-computer-use.sh [--display secondary]`. Do not choose a
  normal foreground launch or ask the user to operate the app merely because
  that path is more familiar. Non-GUI unit tests, headless tests, static
  inspection and command-line diagnostics retain their normal workflows.
- Default background UI scenarios include: opening, navigating or changing
  Settings and verifying the resulting state; first-run guide and transition
  checks; supported menu-bar, status-panel, Dock and shortcut interactions;
  screenshot, layout and visual-regression capture; secondary-display checks;
  permission-recovery paths before a system-owned prompt requires handoff; and
  any request to inspect or test the running app while the user continues
  working. "Background" is the default test entry point, not a promise that
  every control can be operated without activation.
- Pause only the affected step and request a foreground/manual handoff when
  explicit human visual or UX judgement is required; the user must see or
  physically operate something; a system authorization, password, security
  prompt, locked-screen action or app installation requires the user; the
  current harness cannot perform the action without foreground/global input;
  or the test specifically verifies normal/Release activation semantics that
  the Debug background mode intentionally changes. Continue any remaining
  background-safe work before or after the handoff, and report manual and
  automated evidence separately. Ask at the blocked step, not pre-emptively.
- The Skill defines the common non-interference contract; this section
  supplies Status Trio's adapter. A secondary display does not isolate focus
  or input. Establish the active harness's capabilities before live
  attachment/input and stop unsafe steps.
- Scope every acceptance claim to its actual app instance, harness, controls,
  and observation interval. Check that manual actions occurred before the
  recording deadline; expired sampling is not zero interference. Report
  functional behavior and background non-activation separately.
- Start an isolated Debug test instance with
  `bash scripts/launch-computer-use.sh [--display secondary]`. This always builds
  through `build-worktree.sh`, checks this branch's dev identity, and starts a
  new background test process. Release does not interpret the test flags.
- **Computer Use providers:** Status Trio accepts any provider that passes the
  background capability gate, not only Codex native Computer Use. First-class
  providers are Codex native Computer Use, `kimi-cu` MCP, and `agent-desktop`;
  other instance-scoped AX/DOM providers are allowed under the same gate. When
  the project or user `AGENTS.md` names a preferred CU tool (for example a
  user-level rule that prefers `kimi-cu` MCP), use it if the current session
  exposes it. A provider counts as available only when the harness actually
  exposes it; installed-but-unconnected does not count. Input must be
  instance-scoped remote AX/DOM/window input, not foreground/global input;
  never substitute `osascript`/System Events, `CGEventPost`, `cliclick`, or
  per-pixel pointer automation.
- First trace foreground PID/Bundle ID with the bounded
  `scripts/measure-ui-focus.swift` tool; continue a background step only when
  its actual setting change, sidebar navigation and screenshot work without a
  foreground transition. Do not activate an app and restore focus.
- If no Computer Use provider is available, stop and report the affected
  click/input steps as `BLOCKED (no Computer Use provider)`, naming the
  providers checked and what connecting one (such as the `kimi-cu` MCP server)
  would unlock. Do not downgrade them to a bare `NOT RUN`, and do not silently
  hand the work to the user as the only option.
- Background support covers Settings presentation, the first-run guide's
  verified Next/Back/preview/Customize path, and verified Settings controls.
  Menu-bar/shortcut popovers, real Dock activation, text input, shortcut
  recording, guide menu-bar help/links/system dialogs and system permission
  dialogs need separate evidence.
  Pause a step that requires activation or an unavailable/unlocked display and
  report `FAIL`, `BLOCKED` or `NOT RUN`; do not substitute foreground/global
  input, private APIs or additional permissions.
- In background mode, do not enable the Bluetooth row from either the
  Bluetooth page's "Show in status panel" control or the status-panel page's
  Bluetooth visibility control: both retain explicit app activation, even
  after permission is granted. Pause these tests and report `NOT RUN`.
- The launcher may gracefully stop only this path's existing test instance.
  A non-test instance or a Bundle ID collision stops the launch. It never
  terminates production or other worktrees. See
  `docs/background-computer-use-testing.md` for evidence and rollback.
- Restore this run's isolated preference changes and stop its observers and
  test instance after testing. Preserve concurrent user/agent changes.

## Project Skills

- Skills live in `.agents/skills/<skill-name>/`; the directory name must match
  the frontmatter `name`.
- `skills-lock.json` records upstream sources. Update with
  `npx skills update -p -y` from the repository root, then review `git diff`.
- `ui-ux-pro-max` is intentionally excluded from the lock and must be updated
  by re-rendering its upstream template, not by syncing `.claude/skills/`.
- `swiftui-pro` and `swift-testing-pro` are updated by hand because their
  upstream folders contain two same-named skills.

## References

- [Swift toolchain CI compatibility](docs/swift-ci-compatibility.md)
- [macOS 13 compatibility verification](docs/macos13-compatibility-verification.md)
- [GitHub Actions release](docs/github-actions-release.md)
- [Local-first workflow and merge protocol](docs/local-first-workflow.md)
- [System Settings pane routes](docs/settings-pane-routes.md)
- [Issue #30 analysis](docs/issue-30-wifi-centering-analysis.md)
- [Privileged Helper](docs/privileged-helper.md)
