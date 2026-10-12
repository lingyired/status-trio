# Status Trio Agent Rules

## Highest Priority: Match the CI Toolchain

The release workflow is the acceptance environment:

- Runner: `macos-26`
- Xcode: `26.6`
- Swift: `6.3.3`

A newer local toolchain is useful, but it is not proof that CI will compile. Swift code must remain buildable with the CI toolchain.

The app must be built with the macOS 26 SDK or newer. macOS reads the `LC_BUILD_VERSION` `sdk` field to decide whether an app adopts the current design language, so building with an older SDK silently ships the pre-Tahoe popover appearance (issue #40). `scripts/build-app.sh` fails when the SDK is older than 26, and `scripts/verify-platform-version.sh` asserts the result; do not remove either.

Before committing Swift changes:

```bash
swift test
swift build -c release
```

If a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources, also run a non-publishing release workflow before merging or publishing:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=<next-version> \
  -f build=<next-build> \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Do not create a release if that preflight has not passed.

Every failed GitHub Actions run must be added to
[Swift toolchain CI compatibility](docs/swift-ci-compatibility.md), including the
run ID, failed stage, root cause, fix, and verification result.

## Swift Toolchain Compatibility Rules

- Do not use `isolated deinit` or enable the `IsolatedDeinit` experimental feature. Use `deinit` with explicit cleanup; use `nonisolated(unsafe)` only for teardown-owned storage and explain why it is safe.
- Do not pass actor-isolated methods directly as function values. Use an explicit closure instead.
- Do not write `weak let`; weak reference bindings must be `var` (when the compiler asks for `weak let` to silence a never-mutated warning, use the test target's `DeinitProbe` instead and see [Swift toolchain CI compatibility](docs/swift-ci-compatibility.md)).
- Do not assume SwiftPM `Bundle.module` resource names or directory casing match local builds. For localized resources, try the canonical and lowercase `lproj` names and load with `Bundle(path:)`.
- If the Swift compiler crashes with `IRGenRequest`, `SmallVector unable to grow`, or a signal 6, reduce the code pattern that causes the crash. Do not treat it as a flaky failure and do not hide it with experimental compiler flags.

## Change Flow

- Small, low-risk changes — especially your own follow-up tweaks — go straight to `main`: commit directly, or use a short-lived branch and fast-forward it into `main`. No pull request is required.
- Use a pull request when a change is large, touches several subsystems, or when a review/discussion record is worth keeping.
- Whichever route is taken, the verification rules above still apply: `swift test` and `swift build -c release`, plus a non-publishing release workflow run when the change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources.
- The release workflow only runs on tags and manual dispatches, so a pull request does not add CI coverage on its own.

## Menu Bar and Dock Icon Parity

- Every change to a menu bar icon's rendering or icon-related settings must be mirrored in the Dock icon in the same change. Do not leave the Dock on a default or stale representation.
- When adding or changing an icon option, update both paths end-to-end as applicable: `SettingsStore` option derivation, `StatusBarController` subscriptions, `AppIconController` subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, and tests covering both menu bar and Dock output.
- If a setting is intentionally menu-bar-only, the issue or specification must say so explicitly, and the limitation must be documented and covered by a test.
- Icon Designer dimension controls and rendering must follow [Icon Designer sizing standard](docs/icon-sizing-standard.md): one measured 100–180% center-size scale for every primary/fallback source, shared 80–120% outer/footer stroke scale, and the existing outer battery text percentage baseline. Keep legacy storage/rendering unchanged until explicit user edits; never reintroduce per-source UI ranges.

## System Settings Pane Routes

- Every settings control must open the pane it promises, with that pane's own extension identifier first: the Wi-Fi gear goes to the Wi-Fi pane, and a wired row's gear goes to the Network pane, which is where a cable's own settings live. The Network pane lists services (Wi-Fi, Ethernet, VPNs) rather than networks, so routing the Wi-Fi gear through it lands users on the wrong list.
- Never make a pane route depend on the running macOS version. Wi-Fi has its own Settings extension on every release the app supports, and the `majorVersion >= 27` guard that shipped in 1.2.0 and 1.3.0 sent macOS 15 through 26 to the Network pane. See [System Settings pane routes](docs/settings-pane-routes.md).
- The first route decides the destination: System Settings launches even for an unknown pane identifier and `open` still reports success, so a wrong first route is never corrected by the entries after it — the later entries only cover the URL scheme itself failing to open.
- Verify a route by the Settings extension it loads, not by `open`'s exit status: `pgrep -fl "ExtensionKit/Extensions"` right after opening the URL names the pane, and needs neither a screen-recording nor an accessibility grant.
- `StatusMenuBuilderTests.testSystemSettingsURLFallbackOrder` pins the Wi-Fi route order. Update it with the route, never around it.
- A merged fix is not a shipped fix. When a pane-route report comes in, read the route order out of the shipped binary (`strings` on the app executable) before assuming the fix is in the build.

## Release Rules

- GitHub Release notes must use a top-level `# Version X.Y.Z （English + 中文， 中文在下方）` heading, followed by English notes and then Chinese notes, taken from `release-notes/<version>/en.md` and `release-notes/<version>/zh-Hans.md`; the release workflow combines them.
- Sparkle appcast items are localized per language: emit one `<title xml:lang="…">` and one `<description xml:lang="…">` for every language present in `release-notes/<version>/`, give every variant an explicit `xml:lang`, and keep `en` first because Sparkle falls back to the first node in document order when the user's preferred languages match nothing. Never stack two languages inside one `<description>`.
- User-facing release notes live in `release-notes/<version>/<language>.md`, one file per language the app ships (`Sources/StatusTrioCore/Resources/*.lproj` names, case-sensitive). `en.md` and `zh-Hans.md` are always required and also form the GitHub Release body; `publish=true` additionally requires all 12 languages. Every file starts with a `# <title>` line containing the `%VERSION%` and `%BUILD%` placeholders. Terminology must match the language's existing `.lproj` strings. `bash scripts/validate-appcast-notes.sh` checks coverage and the generated appcast XML, and the release workflow runs it on every dispatch, including `publish=false` preflights.
- GitHub Release bodies must append the first-launch commands `xattr -dr com.apple.quarantine "/Applications/Status Trio.app"` and `open "/Applications/Status Trio.app"` after the bilingual notes. Do not include these commands in the Sparkle appcast.
- Release announcements remain in English.
- Release through `.github/workflows/release.yml`; do not publish manually unless the workflow is unavailable and the user explicitly asks for a manual fallback.
- Version and build numbers must be explicit and must increase the published build number.
- Confirm tests, DMG creation, Release upload, and appcast publication in the workflow result.
- The current repository has no Developer ID certificate or notarization secrets. Releases are Ad-hoc signed; document this limitation rather than claiming notarization.

## Project Skills

- Skills live in `.agents/skills/<skill-name>/`, and the directory name must match the skill's frontmatter `name`. `skills-lock.json` at the repository root records the upstream GitHub source of each vendored skill.
- Update them from the repository root with `npx skills update -p -y`. The project path re-installs from source instead of diffing hashes, so the run is idempotent but always rewrites files — review with `git diff` before committing. The lock covers 24 of the 25 skills; `ui-ux-pro-max` is intentionally excluded.
- Do not add `ui-ux-pro-max` to `skills-lock.json`. `npx skills add nextlevelbuilder/ui-ux-pro-max-skill` resolves to the repository's own `.claude/skills/ui-ux-pro-max` variant — a thin orchestrator that delegates to six sub-skills this project does not vendor — whereas the copy here is the render of `src/ui-ux-pro-max/templates/base/skill-content.md` for the `.agents` layout, produced by the vendor's `uipro` CLI. To update it, re-render that template and take `src/ui-ux-pro-max/{data,scripts}`; never sync `.claude/skills/`.
- `npx skills update -p` skips `swiftui-pro` and `swift-testing-pro` because both upstream repositories ship two skills under the same name (`<skill>/SKILL.md` and `<skill>/skills/<skill>/SKILL.md`), which makes the target path ambiguous. Update those two by hand.
- When re-vendoring by hand, sync each whole upstream skill folder rather than `SKILL.md` alone, and delete files the upstream removed.

See [Swift toolchain CI compatibility](docs/swift-ci-compatibility.md) for the incident history and examples, and [System Settings pane routes](docs/settings-pane-routes.md) for how a settings-pane route is verified.
