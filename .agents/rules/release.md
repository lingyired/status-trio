# Release rule

Read this before changing `release.json`, `Support/Info.plist`,
`.github/workflows/release.yml`, `scripts/release.sh`, release notes, appcast
generation, signing, notarization, or versioning.

- Merged, built, and released are different states. A merge is not a release,
  and a successful build is not notarization or runtime acceptance.
- Local `full` verification produces a non-Universal development app bundle;
  it is not a Universal release package.
- Release CI runs only when a maintainer explicitly dispatches `release.yml`
  for a frozen lowercase 40-character `candidate_sha` from `main`. Ordinary
  commits, pull requests, and merges do not run it.
- The verify job runs the full tests and native contracts on that SHA. The
  package job builds one Universal artifact on `xcode-27`; the publish job
  downloads that artifact and must not rebuild, repackage, sign, or notarize.
- The candidate SHA, manifest `source_sha`, Release Tag, DMG SHA-256, appcast
  enclosure, and public download must all refer to the same artifact. Tag
  mismatch or a lower-than-current build number fails closed.
- Do not create tags, releases, DMGs, or appcast changes during ordinary
  development verification.
- Developer ID plus notarization is the signed path; Ad-hoc is a fallback and
  must be reported honestly. Never read or print credentials.

See `docs/github-actions-release.md` and `docs/macos13-compatibility-verification.md`.
