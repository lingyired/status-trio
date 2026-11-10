# Release validation rule

Read this before merging work that affects release orchestration or before
asking a maintainer to run the formal release workflow.

- Local full verification proves source-level tests, a Release build, and the
  native compatibility checks. Its app bundle is non-Universal development
  output and does not prove Universal packaging, signing, notarization, DMG
  creation, appcast publication, or a macOS 13 runtime pass.
- `release.yml` verifies a frozen `candidate_sha` in parallel Swift and native
  jobs, builds one Universal artifact after both pass, then publishes that
  exact downloaded artifact. It never points a Tag at a moving branch and
  never rebuilds during publish.
- Formal publication always uses the reviewed `distribution` Environment.
  Owner-triggered diagnostic packages may use
  `distribution-owner-signing`; other triggering actors and reruns use
  `distribution`. The publish job always uses `distribution`. The verify and
  native jobs receive no signing or notarization secrets.
- Tag SHA, manifest SHA, DMG digest, asset sizes, appcast metadata, and public
  download checks are fail-closed. Re-running a draft may re-upload the same
  artifacts; re-running a public release may only verify it.
- A non-publishing diagnostic run is an explicit exception, not a routine PR
  gate. An owner-triggered diagnostic may bypass Environment review; any other
  triggering actor needs review. It must not touch a release or appcast.

See `docs/github-actions-release.md`, `docs/privileged-helper.md`, and
`docs/verification/`.
