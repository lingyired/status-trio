# Local-first development and merge protocol

This page is the operational companion to `AGENTS.md`. It keeps ordinary agent
work independent of GitHub Actions without weakening the formal release gate.

## Workflow

1. Start from the latest `origin/main` and record the base SHA.
2. Work in a short branch or an existing isolated worktree. A separate worktree
   is required only when concurrent writes or branch isolation demand it.
3. Run focused tests while developing. Before delivery, run
   `bash scripts/verify-local.sh quick <filter>` or `full` according to the risk
   table in `AGENTS.md`.
4. Compare the branch with `origin/main`, then merge in completion order. If
   `main` moved, re-check the diff and re-run the affected scope on the final
   integrated tree.

`merged`, `built`, and `released` are separate states. A merge is not evidence
that a DMG exists, and a local DMG is not evidence of notarization, runtime
acceptance, or a public release.

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
git fetch origin main
git switch -c codex/parallel-b origin/main
bash scripts/verify-local.sh quick BatteryMonitorTests
git commit -am "test: worktree B fixture"
git switch main
git merge --ff-only codex/parallel-b
```

Replace the fixture commit with the actual task change. If `main` moved between
the branch's verified SHA and the merge, the affected verification is rerun on
the merged result. The merge does not call `release.yml`.

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
and must not be converted into a mandatory per-PR gate.

## Formal release handoff

Freeze the candidate SHA before asking for a formal release. The release
workflow must checkout that SHA, verify and package it once, and publish the
same artifact. Local verification and all README/PR evidence should name the
tested SHA so the handoff cannot accidentally use a moving branch.
