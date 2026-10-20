# Release validation rule

Read this before merging work that affects release orchestration or before
asking a maintainer to run the formal release workflow.

- Local full verification proves source-level tests, a Release build, and the
  native compatibility checks. Its app bundle is non-Universal development
  output and does not prove Universal packaging, signing, notarization, DMG
  creation, appcast publication, or a macOS 13 runtime pass.
- PR 2 does not change the release workflow. PR 3 owns enforcement of a frozen
  SHA, same-package reuse, and rejection of a Tag whose SHA differs from the
  verified manifest. Treat those as required migration work, not implemented
  guarantees.
- Do not point a release at a moving branch or rebuild a different SHA while
  preparing that migration.
- A non-publishing diagnostic run is an explicit exception, not a routine PR
  gate. It needs maintainer approval and must not touch a release or appcast.

See `docs/github-actions-release.md`, `docs/privileged-helper.md`, and
`docs/verification/`.
