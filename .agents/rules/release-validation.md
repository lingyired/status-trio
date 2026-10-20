# Release validation rule

Read this before merging work that affects release orchestration or before
asking a maintainer to run the formal release workflow.

- Local full verification proves source-level tests, a Release build, and the
  native compatibility checks. It does not prove signing, notarization, DMG
  creation, appcast publication, or a macOS 13 runtime pass.
- The release workflow must use the exact verified commit and reuse its package.
  Do not point a release at a moving branch or rebuild a different SHA.
- A non-publishing diagnostic run is an explicit exception, not a routine PR
  gate. It needs maintainer approval and must not touch a release or appcast.

See `docs/github-actions-release.md`, `docs/privileged-helper.md`, and
`docs/verification/`.
