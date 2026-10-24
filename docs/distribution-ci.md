# Dual-distribution CI

This document describes the source checks for the Direct and App Store
channels. They are separate from the formal release workflow.

## Pull request checks

`.github/workflows/pr-checks.yml` runs only for `pull_request`. It does not
use `pull_request_target`, does not read pull-request titles or bodies as
shell code, and does not use release credentials or a protected environment.
The workflow declares only `actions: read` and `contents: read`.

Both jobs check out `github.sha`, which is the PR merge commit for this event.
The workflow captures that value in `PR_MERGE_SHA`, and each job checks that
`git rev-parse HEAD`, `GITHUB_SHA`, and the captured merge SHA are the same
lowercase 40-character commit. Do not source this value from workflow-level
`github.event.pull_request.merge_commit_sha`; a real run showed that nested
event expression evaluated empty before checkout. The Direct and Store jobs
run in parallel with the same cancellation group, so a new commit cancels an
obsolete PR run. The job timeouts are finite, and the workflow has no path
filter that could silently skip one channel.

The Direct job runs:

```bash
bash scripts/verify-local.sh full
```

This includes the repository tests and the existing bundle contract checks.
It does not create a release package.

The Store job first runs the Store project, bundle, and source-closure
negative fixtures, then performs an unsigned compile and static audit:

```bash
bash scripts/test-app-store-project-contract.sh
bash scripts/test-app-store-bundle-contract.sh
bash scripts/test-app-store-source-closure.sh
APP_STORE_UNSIGNED=1 \
APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \
bash scripts/build-app-store.sh release no-open
bash scripts/verify-app-store-bundle.sh dist/AppStore/StatusTrio.app --unsigned
bash scripts/verify-app-store-archive-dsyms.sh .build/app-store/StatusTrio.xcarchive
python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json
```

The last command is an explicit interface dependency. It must not be
replaced with an `if exists` check: a missing source-membership manifest is a
failure, not a skipped check. The source-closure audit compares the manifest
with the real `StatusTrioCore*.SwiftFileList` inputs and the compiled source
set.

Artifact uploads are diagnostic only. Each upload has an exact `.build/` or
`dist/AppStore/` path allowlist and sets `include-hidden-files: true`, because
`actions/upload-artifact@v4` otherwise skips those hidden directories. The
allowlist prevents uploading the repository or a user directory. The Store job
uploads no credentials and makes no App Store Connect request. An unsigned
result is evidence of compilation and static bundle/source inspection only. It
is not a signed, sandbox-runtime, notarized, or uploadable Store result.

## Toolchain selection

The PR and manual Store workflows use the GitHub-hosted `macos-26` runner.
This is a public runner suitable for untrusted pull-request code; it is not
the protected production release runner. The runner label and current
availability are documented by GitHub at:

<https://docs.github.com/en/actions/reference/runners/github-hosted-runners>

The workflow does not assume that one particular Xcode installation or SDK is
present. It enumerates `DEVELOPER_DIR` and `/Applications/Xcode*.app`, reads
the macOS SDK and Swift versions from each candidate, and selects the newest
candidate with:

- macOS SDK 26 or newer
- Swift 6 or newer

It fails with a diagnostic if no candidate meets those floors. The project
itself keeps the macOS 13 deployment target. The formal Direct release remains
unchanged on `xcode-27`.

## XcodeGen pin

The App Store project has an exact XcodeGen contract with the Store project
generator. The CI pin is XcodeGen `2.46.0`, not Homebrew's moving latest
formula:

- Official release: `https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0`
- Tag commit: `8445e778451c7e44237b90281bde622d764b0084`
- Archive: `https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip`
- SHA-256: `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`

The checksum is taken from the official GitHub release asset metadata, not
from a local guess. The workflow downloads the fixed tag archive, verifies the
digest with `shasum -a 256 -c`, installs it under `.build/tools`, and runs
`xcodegen --version` before exporting `XCODEGEN`. It removes the exact
`Version: ` display prefix and compares the result exactly with `2.46.0`; a
substring or wildcard comparison is rejected. It never installs XcodeGen from
Homebrew or a latest-release URL. The policy checker requires the exact
installed-binary capture
`ACTUAL_XCODEGEN_VERSION="$("${TOOL_ROOT}/bin/xcodegen" --version 2>&1 | head -n 1)"`
and rejects any additional assignment before the exact comparison.

`scripts/check-dual-distribution-workflows.py` and its offline fixtures
enforce this pin. If the Store project generator changes its exact XcodeGen
requirement, update the generator contract, both workflow constants, the
policy checker, and the fixtures together.

## Manual unsigned Store archive

`.github/workflows/app-store.yml` is available only through
`workflow_dispatch`. It accepts:

- `candidate_sha`: a lowercase 40-character commit SHA
- `version`: an explicit numeric marketing version
- `build`: an explicit numeric build number

Dispatch must select `main`. The workflow checks out the supplied candidate,
requires the checkout to equal `candidate_sha`, and requires the candidate to
be an ancestor of `origin/main`. Version and build are validated as explicit
inputs. The build number is not derived from `run_number`; monotonicity
against App Store Connect remains a maintainer check.

The archive step is:

```bash
APP_STORE_UNSIGNED=1 \
APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \
bash scripts/build-app-store.sh release no-open
```

It then runs the unsigned bundle verifier and source-closure audit. The
workflow uploads an artifact named
`app-store-unsigned-archive-diagnostic` only when the build and audits
succeed; diagnostic logs are uploaded even on failure and contain no
credentials. The job summary explicitly labels the result as unsigned,
not notarized, not signed, and not uploadable, and says that signing
credentials are still needed.

This workflow intentionally has no App Store Connect upload, export, review,
release, tag, push, or distribution Environment step. A future signed upload
must be a separately authorized workflow change.

## Formal release boundary

`.github/workflows/release.yml` remains the only formal Direct release entry
point. It keeps its frozen candidate SHA, `xcode-27` runner, Universal
package, Developer ID/signing and notarization controls, protected
`distribution` Environment, and verify/package/publish artifact flow. The
dual-distribution PR checks and the unsigned Store archive workflow do not
modify those contracts and do not prove a Direct release.

## Current evidence limits

On 2026-10-24 the parent downloaded the pinned official XcodeGen asset, verified
its 4,278,764-byte size and SHA-256, checked its arm64 and x86_64 slices, and
executed `--version` successfully as 2.46.0. The local evidence is
`.build/dual-distribution-logs/xcodegen-pin-verification.log`; the system
installation also reports 2.46.0. This verifies the generator prerequisite,
not the hosted workflow.

The offline workflow policy fixtures and shell syntax checks validate the
workflow definitions without dispatching GitHub Actions. This scaffold does
not claim that the current GitHub-hosted image contains the required
toolchain, that an unsigned Store app was built, or that App Sandbox behavior was
exercised. Those are CI or manual verification results to fill in when the
Store implementation is run.

The Store workflow depends on these repository interfaces:

- `scripts/build-app-store.sh`
- `scripts/test-app-store-project-contract.sh`
- `scripts/test-app-store-bundle-contract.sh`
- `scripts/test-app-store-source-closure.sh`
- `scripts/verify-app-store-source-closure.py`
- `scripts/verify-app-store-bundle.sh`
- `.build/app-store/source-membership.json`
