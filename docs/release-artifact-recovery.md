# Release artifact recovery

`release.yml` can recover publication from the package artifact of an earlier
run without rebuilding, signing, notarizing, or replacing that artifact. Leave
`package_run_id` empty for the ordinary verify/package/publish flow.

## Preconditions

Recovery is accepted only when all of these are true:

- The workflow is dispatched from `main`.
- `candidate_sha` is the lowercase 40-character source commit.
- `package_run_id` is the earlier run, not the current recovery run.
- `publish=true` and `notarize=true`.
- `version`, `build`, and `tag` are explicit and match the original manifest.
- The source run used this repository and the current `release.yml` workflow.
- The source run was a `workflow_dispatch` from `main` and checked out the
  same candidate SHA.
- Its `verify` and `package` jobs succeeded.
- The source run is either a failed publication attempt whose `publish` job
  failed, or a package-only run whose `publish` job was skipped.
- The run has exactly one unexpired `status-trio-release-package` artifact,
  and that artifact is correlated with the same run, branch, and commit.

The validator intentionally requires the source run's recorded `head_sha` to
equal `candidate_sha`. This is a conservative subset: a source run whose
candidate was an ancestor of the dispatched branch head is rejected, even if
that run was a valid normal release. Advancing `main` after the source run does
not change the source run's recorded head SHA.

Any mismatch stops the recovery before publication. An expired or ambiguous
artifact must be rejected; recovery does not fall back or reconstruct it. The
maintainer then decides what to do. If a new build is necessary, use a new
version and build number with its own candidate and full CI run; never replace
an existing Tag, Draft Release asset, or source artifact.

## Dispatch

For the failed `v1.7.2` publication, run 39923069756 produced the frozen
package. After this workflow is on `main`, the recovery dispatch is:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref main \
  -f candidate_sha=af7f637f186cd611fbc7b0053897ac8a5a17e8ed \
  -f package_run_id=39923069756 \
  -f version=1.7.2 \
  -f build=40 \
  -f tag=v1.7.2 \
  -f publish=true \
  -f notarize=true
```

The command above is an example. Do not run it until the workflow change is
merged and independently reviewed.

## Execution boundary

The recovery path keeps three jobs:

1. `verify` checks out and fully tests the frozen candidate. It separately
   checks out the workflow file's trusted `github.workflow_sha` into
   `release-tools`, validates the source run through the GitHub API, and runs
   the recovery, workflow-policy, and publish-pipeline offline regressions from
   that trusted checkout. This job receives no signing or notarization secrets.
2. `package` is skipped entirely when `package_run_id` is set.
3. `publish` uses the protected `distribution` environment. It downloads the
   original artifact by run ID with `actions: read` and the repository
   `github.token`, revalidates the source run and manifest, then runs
   `publish-release.sh` from the trusted `release-tools` checkout while
   `CANDIDATE_SHA` remains the explicit application identity for the checked
   out source and publisher.

`GITHUB_SHA` is the actual workflow-dispatch head context and cannot be
overridden in a step. It is not the recovery candidate. The source checkout,
recovery validation, and publisher identity use the explicit `CANDIDATE_SHA`
verified by the `verify` job and retained in the protected publish environment.

The downloaded manifest must match the candidate, version, build, tag,
Developer ID signing state, and accepted-and-stapled notarization state before
the publish script can write a Tag, Release, asset, or appcast item. The fixed
publish tooling from `github.workflow_sha` resolves the existing Draft Release
without rebuilding it.

Recovery does not permit:

- a package built by the recovery run;
- an Ad-hoc or un-notarized package;
- a moving branch, alternate repository, alternate workflow, or different SHA;
- selecting one artifact from multiple candidates;
- fallback to another run when the source artifact is missing or expired.

## Verification

Offline checks:

```bash
bash scripts/test-release-recovery.sh
bash scripts/test-release-workflow-policy.sh
bash scripts/test-release-pipeline.sh
```

Read-only live metadata check:

```bash
REPOSITORY=lingyired/status-trio \
SOURCE_RUN_ID=39923069756 \
CANDIDATE_SHA=af7f637f186cd611fbc7b0053897ac8a5a17e8ed \
EXPECTED_VERSION=1.7.2 \
EXPECTED_BUILD=40 \
EXPECTED_TAG=v1.7.2 \
MANIFEST_PATH=/path/to/downloaded/release-manifest.json \
bash scripts/validate-release-recovery.sh
```

This validates metadata only. It does not prove GitHub publication, signing,
notarization, public download, or appcast behavior.

## Build Candidate → Publish Existing Candidate

`build-candidate.yml` builds one notarized `release_candidate` artifact
(`status-trio-release-package`, schema v2 manifest) and never publishes it.
`publish-candidate.yml` takes only `candidate_run_id`, downloads that exact
artifact, validates it with `scripts/validate-candidate-provenance.sh`, and runs
`scripts/publish-release.sh` without rebuilding, re-signing, re-notarizing, or
re-packing.

### Provenance validation (schema v2)

`validate-candidate-provenance.sh` binds the artifact to a trusted source without
relying on `run.head_sha` (which is the reused `main` head for a frozen commit):

- run repository == head repository == expected repo; run event is
  `workflow_dispatch`; run completed successfully; run workflow path is
  `.github/workflows/build-candidate.yml`.
- manifest `schema_version == 2`, `candidate.publishable == true`,
  `candidate.source_sha == manifest.source_sha == CANDIDATE_SHA`,
  `candidate.build_run_id == SOURCE_RUN_ID`.
- version/build/tag match the manifest; `tag == v<version>`.
- `prepare` and `package` jobs succeeded; a `strict` candidate also requires
  `verify` and `native` to succeed (they may be skipped only for `fast`).
- exactly one non-expired `status-trio-release-package` artifact; optional
  `EXPECTED_ARTIFACT_ID` / `EXPECTED_ARTIFACT_DIGEST` must match.
- optional `STRICT_EVIDENCE_PATH` from `status-trio-strict-evidence` must name the
  same candidate run, source SHA, level `strict`, status `passed`; when present it
  upgrades a fast candidate's effective level to `strict`.

Self-recovery (`SOURCE_RUN_ID == current run`) is rejected. This validates
metadata and provenance only; it does not prove GitHub publication, signing,
notarization, public download, or appcast behavior.

### Compatible legacy entry

The original `release.yml` + `package_run_id` recovery path is unchanged and
still validates against schema v1 manifests through
`scripts/validate-release-recovery.sh`. New builds use schema v2 and
`publish-candidate.yml`; both share the same `publish-release.sh` publish core.

