---
name: gitee-release-sync
description: Check, sync, and verify the Gitee mirror of an already published and verified Status Trio GitHub Release. Use when asked to mirror a release, diagnose a failed Gitee upload, or confirm that a public Gitee DMG and appcast match GitHub.
---

# Gitee release sync

This skill never builds, signs, notarizes, or creates a GitHub Release. It calls
the same \`scripts/sync-gitee-release.mjs\` used by \`.github/workflows/gitee-sync.yml\`.
GitHub stays the only authoritative source.

## Commands

Run from the repository root.

\`\`\`bash
# Read-only comparison: never writes Gitee.
node scripts/sync-gitee-release.mjs check v1.2.3

# Create or resume the mirror; safe to rerun after any failure.
GITEE_TOKEN=... node scripts/sync-gitee-release.mjs sync v1.2.3

# Download and re-verify the public mirror and feed; read-only.
node scripts/sync-gitee-release.mjs verify v1.2.3
\`\`\`

Optional environment: \`GITHUB_REPOSITORY\`, \`GITEE_REPOSITORY\`,
\`GITEE_FEED_URL\`, \`GH_TOKEN\` (read-only GitHub access for private repos).

## Preconditions

- The GitHub Release is published, stable, not a draft, and its manifest,
  DMG length, SHA-256, tag, commit SHA and Sparkle EdDSA signature were verified.
- The Gitee repository has an existing public \`appcast.xml\` at the configured
  HTTPS feed URL. The script refuses to start otherwise.
- \`GITEE_TOKEN\` is supplied only through the environment.

## Failure recovery

Every failure leaves the previous public feed intact and keeps uploaded
attachments. Retry the same tag; only missing or incomplete attachments are
uploaded. Never change bytes for an existing tag: a differing SHA-256 fails
immediately instead of overwriting.

- Attachment upload failed: rerun \`sync\` after checking token scope and capacity.
- Feed update failed after upload: verify public attachments with \`verify\`, then
  rerun \`sync\`; it reuses the verified bytes.
- Timeout or TLS failure: retry the same tag; source order never applies here.
- Concurrent feed change: retry the same tag after the other run finishes.

Do not delete an existing release or its attachments. Automatic capacity
reclamation is disabled until the real Gitee API is qualified.

## Output

A JSON object with GitHub/Gitee URLs, tag, version, build, SHA-256, feed URL,
elapsed time and result. Tokens and response bodies are never printed.
