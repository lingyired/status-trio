# macOS compatibility rule

Read this before changing `Package.swift`, `Support/Info.plist`, build scripts,
availability checks, AppKit/SwiftUI API use, or release metadata.

- The deployment target remains macOS 13. A successful build on a newer SDK is
  not macOS 13 runtime evidence.
- Formal builds require the macOS 26 SDK or newer so macOS adopts Liquid Glass.
  `scripts/build-app.sh` and `scripts/verify-platform-version.sh` enforce both
  boundaries; do not remove either guard.
- Run `bash scripts/verify-local.sh full` for build-pipeline or compatibility
  changes. Record runtime gaps as `NOT RUN`.

See `docs/macos13-compatibility-verification.md` and
`docs/swift-ci-compatibility.md`.
