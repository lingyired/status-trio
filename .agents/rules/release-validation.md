# Release validation rule

Read this before merging work that affects release orchestration or before
asking a maintainer to run the formal release workflow.

- Local full verification proves source-level tests, a Release build, and the
  native compatibility checks. Its app bundle is non-Universal development
  output and does not prove Universal packaging, signing, notarization, DMG
  creation, appcast publication, or a macOS 13 runtime pass.
- `release.yml` verifies a frozen `candidate_sha`, builds one Universal artifact,
  then publishes that exact downloaded artifact. It never points a Tag at a
  moving branch and never rebuilds during publish.
- The package and publish jobs use the protected `distribution` Environment.
  The verify job receives no signing or notarization secrets.
- Tag SHA, manifest SHA, DMG digest, asset sizes, appcast metadata, and public
  download checks are fail-closed. Re-running a draft may re-upload the same
  artifacts; re-running a public release may only verify it.
- A non-publishing diagnostic run is an explicit exception, not a routine PR
  gate. It needs maintainer approval and must not touch a release or appcast.

See `docs/github-actions-release.md`, `docs/privileged-helper.md`, and
`docs/verification/`.
