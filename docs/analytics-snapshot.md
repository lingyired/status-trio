# Analytics snapshot

GitHub only keeps two kinds of number, and neither is kept for long:

- **Repository traffic** (`views`, `clones`, referring sites, popular paths) is
  exposed for a **rolling 14-day window** and then discarded.
- **Release asset `download_count`** is a monotonic total with no history at
  all.

`scripts/snapshot-analytics.py` copies both into `analytics/` once a day so
long-term trends survive. The workflow is
[.github/workflows/analytics-snapshot.yml](../.github/workflows/analytics-snapshot.yml),
scheduled daily at 03:17 UTC.

This is GitHub repository bookkeeping, separate from Status Trio's optional
first-party app telemetry. The snapshot contains repository traffic and release
download counters already held by GitHub; it does not include heartbeat data.
The app telemetry choices and payload are documented in
[Status Trio telemetry and privacy](privacy-telemetry.md).

## What this can and cannot answer

It can answer: how many people look at the repository, where they come from,
which releases they download, and how the install base spreads across versions
(roughly, and including repeat downloads).

It **cannot** answer per-language app usage or count active installations. The
app's language in an update check or DMG download is not a reliable measure of
the language people use in the app. Those questions belong to the separate
opt-in heartbeat described in [the privacy notice](privacy-telemetry.md).

When app telemetry is off, the per-language README landing page remains a
separate repository-interest signal. `traffic/popular/paths` reports
`/blob/main/README.zh-CN.md` separately, so **when a new documentation language
ships, add `README.<lang>.md` and link it from the README language switcher**.
That path then appears in future GitHub snapshots. It counts repository page
views, not app users or installations. English has no separate path because
the repository root renders `README.md`.

## Files

| Path | Contents |
|---|---|
| `analytics/daily/<YYYY-MM-DD>.json` | One full snapshot per day: both traffic windows (per-day rows), referrers, popular paths, every release with per-asset download counts, repo counters, and an `errors` map. |
| `analytics/series.csv` | The durable per-day series (`date, views_count, views_uniques, clones_count, clones_uniques`), rebuilt from every daily snapshot on each run. |

A run that cannot read traffic never overwrites traffic data an earlier
snapshot of the same day already captured: the sections are carried forward and
listed in the snapshot's `carried_forward` field, while `first_fetched_at` keeps
the time of the first capture. Without that guard a single permission-less run
would delete rows that cannot be fetched again.

Snapshots overlap by design: each one contains the whole 14-day window, so a
missed day can often be filled in from the next run. When the same date appears
in several snapshots, the newest value wins in `series.csv` — a day's numbers
are final once it closes.

### Reading the numbers

- `count` is a plain sum of events (page views, clone requests).
- `uniques` is deduplicated **across the whole 14-day window**, not a sum of the
  daily uniques, and GitHub does not document the deduplication basis. Treat it
  as "roughly how many distinct visitors", never as users or installs. CI
  runners, crawlers and mirror bots inflate `clones`.
- Counters inside sub-entries (`referrers`, `paths`) count the same visitor once
  per entry, so they must not be added up into a total.
- `download_count` has no deduplication at all, and it misses downloads that go
  through the CN mirror fallbacks in
  [UpdateSourceFallback.swift](../Sources/StatusTrioCore/App/UpdateSourceFallback.swift#L9-L18).

## Running it locally

```bash
GH_TOKEN="$(gh auth token)" python3 scripts/snapshot-analytics.py
```

Options: `--repo OWNER/NAME` (defaults to `$GITHUB_REPOSITORY` or this
repository), `--out DIR` (defaults to `./analytics`), `--date YYYY-MM-DD`
(snapshot label, defaults to today in UTC). The script needs only the Python
standard library.

## Enabling traffic in CI

The traffic endpoints require the **"Administration: read"** repository
permission ([REST documentation](https://docs.github.com/en/rest/metrics/traffic)),
which the default `GITHUB_TOKEN` cannot be granted. Without a dedicated secret
the workflow still archives release counters, writes the error into the
snapshot's `errors` map, and emits a `::warning::` annotation instead of failing.

To archive traffic too, add a repository secret named `TRAFFIC_TOKEN`
(Settings → Secrets and variables → Actions) holding a **fine-grained personal
access token** scoped to this repository with `Administration: read`. The script
prefers `TRAFFIC_TOKEN`, then `GH_TOKEN`, then `GITHUB_TOKEN`.

Do not reuse a broad `gho_` OAuth token from `gh auth token` for this secret:
that token carries far more authority than this job needs, and every workflow in
the repository (including any future pull request workflow) can read it.

## Failure behavior

| Situation | Result |
|---|---|
| Traffic returns 401/403/404 | `::warning::`, snapshot written with `errors` **and** the previous traffic data carried forward, **exit 0** |
| Any other traffic error, a failed release or repo fetch, or no token | `::error::`, **exit 1** |
