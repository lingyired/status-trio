# Gitee release mirror

GitHub Release remains the only authoritative build and publication source.
Gitee mirrors already published, notarized artifacts. It never rebuilds,
re-signs, or notarizes, and a Gitee failure never deletes or rolls back a
GitHub release.

## Source order

| Entry point | Order |
| --- | --- |
| Automatic and normal check | GitHub → Gitee → gh-proxy.com → ghfast.top |
| "Check via Gitee" | Gitee → GitHub → gh-proxy.com → ghfast.top |

The Gitee-first preference lives for one manual update cycle only. Ending,
cancelling or failing the cycle restores GitHub-first, including for the next
background check. Only transient network causes (DNS, timeout, unreachable
host, connection loss) move to the next source. Cancellation, TLS/certificate
failures, Sparkle EdDSA failures, corrupt packages and install failures never
switch sources.

## Pipeline

1. A maintainer dispatches \`release.yml\` with a frozen \`candidate_sha\`.
2. \`publish\` publishes one verified Universal, notarized DMG and appcast.
3. Only after that succeeds, \`publish\` dispatches \`gitee-sync.yml\`.
4. The Ubuntu job downloads the public GitHub manifest and DMG, verifies
   length, SHA-256, tag, commit and notarization identity, uploads the exact
   bytes to Gitee, downloads them anonymously, re-hashes them, derives the
   Gitee-only appcast from the GitHub appcast, and only then updates the public feed.
The Gitee feed contains only mirrored versions and no GitHub URLs at all.

Mirror order is fixed: upload → verify bytes → derive appcast → verify appcast
→ publish feed. The Gitee feed keeps the original package EdDSA signature and
only includes versions already mirrored to Gitee; unmapped historical items and
all GitHub URLs are removed. The public feed path is `appcast-gitee.xml`.

## Operations

\`\`\`bash
node scripts/sync-gitee-release.mjs check v1.2.3    # read-only
GITEE_TOKEN=... node scripts/sync-gitee-release.mjs sync v1.2.3
node scripts/sync-gitee-release.mjs verify v1.2.3   # read-only
\`\`\`

The same script is used by the \`.agents/skills/gitee-release-sync\` skill. A
failed run is safe to retry with the same tag; only missing attachments are
uploaded and a differing SHA-256 fails instead of overwriting.

## Network reality (verified 2026-11-14)

Uploading a real 20 MB DMG from a GitHub-hosted runner to Gitee timed out
with zero bytes received after 900 seconds, while the same upload succeeds
from a China-local machine. Keep `ubuntu-latest` only as a fallback; for
reliable production mirrors set the repository variable `GITEE_SYNC_RUNNER`
to a China-local self-hosted runner label, or run the local
`gitee-release-sync` skill command. Never treat a cross-border upload timeout
as proof that the DMG or token is invalid.

## Known limits (not yet qualified against the live service)

- The configured Gitee repository currently returns HTTP 451 on its anonymous
  raw appcast URL and has no Release. A public HTTPS feed must exist before the
  client can use Gitee-first.
- Automatic retention cleanup is disabled: the script never deletes releases
  or attachments. Retention must be re-enabled only after the live Gitee API
  and feed caching behavior are verified.
- Real Sparkle updates from Gitee and macOS 13–27 compatibility require an
  actual release test.

## Secrets

Only \`GITEE_TOKEN\` is a Gitee credential. It is read from the environment,
never logged, and never required by \`check\` or \`verify\`. The sync job needs no
Sparkle, Apple Developer ID, or notarization credentials.
