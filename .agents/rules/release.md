# Release rule

Read this before changing `release.json`, `Support/Info.plist`,
`.github/workflows/release.yml`, `scripts/release.sh`, release notes, appcast
generation, signing, notarization, or versioning.

- Merged, built, and released are different states. A merge is not a release,
  and a successful build is not notarization or runtime acceptance.
- Formal release CI runs only when a maintainer prepares a release. It must
  pass on the exact frozen commit and publish that commit's packaged artifact.
- Do not create tags, releases, DMGs, or appcast changes during ordinary
  development verification.
- Developer ID plus notarization is the signed path; Ad-hoc is a fallback and
  must be reported honestly. Never read or print credentials.

See `docs/github-actions-release.md` and `docs/macos13-compatibility-verification.md`.
