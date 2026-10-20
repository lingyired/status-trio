# Release rule

Read this before changing `release.json`, `Support/Info.plist`,
`.github/workflows/release.yml`, `scripts/release.sh`, release notes, appcast
generation, signing, notarization, or versioning.

- Merged, built, and released are different states. A merge is not a release,
  and a successful build is not notarization or runtime acceptance.
- Local `full` verification produces a non-Universal development app bundle;
  it is not a Universal release package.
- The PR 2 local-first workflow does not change `release.yml`. PR 3 owns
  release-only gating, frozen-SHA enforcement, same-artifact reuse during
  publish, and Tag/manifest SHA validation.
- The formal-release target is that CI runs only when a maintainer prepares a
  release, passes on the exact frozen commit, and publishes that commit's
  packaged artifact. Do not describe that target as current behavior before
  PR 3 lands.
- Do not create tags, releases, DMGs, or appcast changes during ordinary
  development verification.
- Developer ID plus notarization is the signed path; Ad-hoc is a fallback and
  must be reported honestly. Never read or print credentials.

See `docs/github-actions-release.md` and `docs/macos13-compatibility-verification.md`.
