# Local-first development and merge protocol

This page is the operational companion to `AGENTS.md`. It keeps ordinary agent
work independent of GitHub Actions without weakening the formal release gate.

## Workflow

1. Start from the latest `origin/main` and record the base SHA.
2. Work in a short branch or an existing isolated worktree. A separate worktree
   is required only when concurrent writes or branch isolation demand it.
3. Run focused tests while developing. Before delivery, run
   `bash scripts/verify-local.sh quick <filter>`, `docs`, or `full` according
   to the risk table in `AGENTS.md`.
4. Compare the branch with `origin/main`, then merge in completion order. If
   `main` moved, re-check the diff and re-run the affected scope on the final
   integrated tree.

`merged`, `built`, and `released` are separate states. A merge is not evidence
that a DMG exists, and a local DMG is not evidence of notarization, runtime
acceptance, or a public release.

## Dual-channel pull request checks

The Direct and App Store builds share application sources, so
`.github/workflows/pr-checks.yml` checks both channels for every pull request
at the same merge SHA. These checks use read-only permissions, no signing
secrets and no protected distribution Environment. The Store job additionally
checks the actual compiler source inputs and every bundled Mach-O image.
Unsigned CI output is compilation and static audit evidence only.

Run the applicable local profile before delivery. A successful PR source check
does not establish sandbox runtime behavior, hardware compatibility,
Developer ID signing, notarization or App Store upload readiness.

## Parallel worktree simulation

This sequence is safe to run offline with disposable commits; do not create a
Release or Tag:

```bash
# Worktree A
git fetch origin main
git switch -c codex/parallel-a origin/main
bash scripts/verify-local.sh quick BatteryMonitorTests
git commit -am "test: worktree A fixture"
git switch main
git merge --ff-only codex/parallel-a

# Worktree B, after A has landed
git switch main
git fetch origin main
git merge --ff-only origin/main
git switch -c codex/parallel-b
bash scripts/verify-local.sh quick BatteryMonitorTests
git commit -am "test: worktree B fixture"
git switch main
git merge --ff-only codex/parallel-b
```

Replace the fixture commit with the actual task change. If `main` moved between
the branch's verified SHA and the merge, the affected verification is rerun on
the merged result. The merge does not call `release.yml`.

Branch B must update the local `main` before branching. If local `main` has
unpushed commits, `git merge --ff-only origin/main` must stop; inspect and
resolve that divergence instead of branching from a stale or silently rewritten
base.

## Worktree app builds

Use the existing helper so a concurrent build gets a unique bundle ID and does
not overwrite the installed production app:

```bash
bash scripts/build-worktree.sh release no-open
```

Inspect `git -C <worktree> status` and check for a running process before
removing a worktree. Preserve another agent's branch, uncommitted changes, and
ignored evidence unless cleanup is explicitly authorized.

## High-risk exception

A maintainer may explicitly approve a non-publishing diagnostic workflow run
for a high-risk change. It remains an exception, uses no release publishing,
and must not be converted into a mandatory per-PR release gate. The separate
dual-channel source checks above do not dispatch this diagnostic workflow.

## Formal release handoff

Freeze the candidate SHA before asking for a formal release. Local verification
and all README/PR evidence should name the tested SHA so the handoff cannot
accidentally use a moving branch.

The formal workflow checks out the exact lowercase 40-character `candidate_sha`,
runs the full suite and native contracts, builds one Universal package, and
publishes that downloaded artifact without rebuilding. A Tag or manifest whose
SHA differs from the candidate is rejected. See
[GitHub Actions release](github-actions-release.md#formal-release-dispatch) for
the dispatch command and recovery rules.
