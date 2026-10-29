# Dual-distribution CI verification

Date: 2026-10-24
Scope: Phase F workflow scaffold and offline policy evidence
Branch: `codex/dual-distribution-platform`
HEAD: `a4c9f34a1c9ade2c1116f02781ea549521eaa370`
Base: `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`

This record covers workflow source and offline fixtures only. No GitHub Actions
run was dispatched. No release, tag, App Store Connect request, upload, signing,
notarization, or secret access occurred.

## Added files

- `.github/workflows/pr-checks.yml`
- `.github/workflows/app-store.yml`
- `scripts/check-dual-distribution-workflows.py`
- `scripts/test-dual-distribution-workflows.sh`
- `docs/distribution-ci.md`
- `docs/verification/dual-distribution-ci.md`

The existing `.github/workflows/release.yml` and
`scripts/check-workflow-policy.sh` were not modified.

## Offline evidence

| Command | Result | Exit |
| --- | --- | --- |
| `python3 scripts/check-dual-distribution-workflows.py` | policy accepted | 0 |
| `bash scripts/test-dual-distribution-workflows.sh` | 105/105 checks; 77/77 semantic fixtures; 28/28 embedded shell syntax checks | 0 |
| `bash scripts/test-app-store-source-closure.sh` | 88/88 scenarios | 0 |
| `bash scripts/test-app-store-project-contract.sh` | 74/74 scenarios | 0 |
| `bash scripts/test-app-store-bundle-contract.sh` | 75/75 scenarios | 0 |
| `bash scripts/test-app-store-archive-dsyms.sh` | 5/5 scenarios | 0 |
| `bash scripts/test.sh DistributionLocalizationTests` | NOT RUN in round 2; parent final verification owns the SwiftPM slot | N/A |
| `python3 -m py_compile scripts/check-dual-distribution-workflows.py` | Python syntax accepted | 0 |
| Ruby `YAML.load_file` on both new workflows | YAML parse accepted | 0 |
| `bash -n` on `scripts/test-dual-distribution-workflows.sh` | shell syntax accepted | 0 |
| `git diff --check` on the added files | no whitespace errors | 0 |

The policy test is negative-first. It starts from empty and placeholder
workflows, then rejects semantic mutations including a push trigger,
`pull_request_target`, job-level write permissions, secrets, the protected
`distribution` environment, a non-merge checkout, removed SHA assertions,
skipped Direct or Store jobs, path filtering, an SDK floor below 26, a missing
Store build or source-closure audit, missing source-closure negative fixtures,
Homebrew/latest XcodeGen, a guessed checksum, unexpected network access, unsafe
workflow-input interpolation, a tag trigger, write permissions, signed output
labeled unsigned, omitted hidden-file handling, whole-repository and unrelated
`.build/` uploads, ASC upload, tag/push, and a build number derived from
`run_number`.

Round-one review fixtures additionally require:

- `pull_request` to have an empty parsed mapping, rejecting block and inline
  `paths`, `branches`, and `types` filters.
- Expression parsing across whitespace and bracket syntax. `secrets` and `vars`
  are rejected anywhere; `inputs`, `github.event.inputs`, and event data are
  rejected inside shell steps.
- Every required Direct and Store command to be blocking, unconditional, and
  an executable statement with `set -euo pipefail`. Comments and commands
  nested behind shell conditions do not satisfy the gate.
- The PR Store build invocation to include the exact
  `APP_STORE_UNSIGNED=1` prefix and no signing identity or provisioning profile.
- XcodeGen version evidence to come from exactly one installed-binary
  `xcodegen --version` capture and one normalization line; a hard-coded literal
  or an extra `ACTUAL_XCODEGEN_VERSION=` override fails the policy.

## Workflow contracts

### Pull requests

`pr-checks.yml` is triggered only by `pull_request`. Both `direct` and `store`
jobs use GitHub-hosted `macos-26`, check out `github.sha` at the PR merge
commit, and assert that checkout `HEAD`, `GITHUB_SHA`, and the frozen merge SHA
are the same lowercase 40-character commit. The workflow-level SHA expression
is captured in `PR_MERGE_SHA`; a direct run showed the nested
`pull_request.merge_commit_sha` context was empty there even though checkout
received the correct merge commit.
The workflow has only `actions: read` and `contents: read`; it has no secrets,
repository variables, environment approval, path filter, or job-level `if`.
Concurrency cancels obsolete runs for the same pull request, and both job
timeouts are finite.

The Direct job runs `bash scripts/verify-local.sh full`. The Store job runs the
project, bundle, and source-closure negative fixtures; builds an unsigned
archive with
`APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive bash scripts/build-app-store.sh release no-open`;
runs
`bash scripts/verify-app-store-bundle.sh dist/AppStore/StatusTrio.app
--unsigned`; and requires
`python3 scripts/verify-app-store-source-closure.py
.build/app-store/source-membership.json`. That last path is a mandatory
interface, not an `if exists` optional. The archive path is mandatory because
the same job verifies archived dSYMs against the actual app/Core frameworks.
The Store job runs the
`scripts/test-app-store-source-closure.sh` negative fixtures before the real
audit.

Diagnostic uploads are internal logs and unsigned build output. They contain no
credentials and do not make the result signed, sandbox-runtime verified, or
uploadable. Every upload uses an exact `.build/` or `dist/AppStore/` path
allowlist and sets `include-hidden-files: true`, because those paths are hidden
from `actions/upload-artifact@v4` by default. This includes the unsigned
archive, source-membership manifest, unsigned app, and failure logs; it never
uploads the repository root or a user directory. The policy fixtures reject
both omitted hidden-file handling and an unrelated `.build/` upload path.

### Manual unsigned archive

`app-store.yml` is `workflow_dispatch` only. It requires explicit
`candidate_sha`, `version`, and `build` inputs, validates a lowercase
40-character SHA, freezes the checkout to that SHA, requires dispatch from
`main`, and checks that the candidate is an ancestor of `origin/main`. The build
number is explicit; the workflow does not use `run_number`.

The archive command is:

```bash
APP_STORE_UNSIGNED=1 \
APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \
bash scripts/build-app-store.sh release no-open
```

It then runs the unsigned bundle audit and source-closure audit. The workflow
has no App Store Connect upload, export, review, release, tag, push, or
`contents: write`; it uses no `distribution` environment and no secrets. The
job summary labels the artifact as needing signing credentials and does not
claim that it can be uploaded.

## Toolchain and runner provenance

The new workflows use the GitHub-hosted `macos-26` label. GitHub's official
runner reference was checked on 2026-10-24:

- <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>

That reference lists standard `macos-26` as arm64 and also lists
`macos-26-intel`. The workflows use `macos-26`; they do not place untrusted PR
code on a self-hosted production release runner. `xcode-27` is currently a
public preview and is not assumed to be installed for these checks.

Each job enumerates `DEVELOPER_DIR` and `/Applications/Xcode*.app`, reads the
SDK and Swift versions, and selects the newest installation with macOS SDK 26
or newer and Swift 6 or newer. It fails with a diagnostic if no installation
meets those floors. The deployment target remains macOS 13. The formal release
workflow remains unchanged on `xcode-27`.

## XcodeGen pin provenance

The Store project generator requires exactly XcodeGen `2.46.0`. The CI pin is
the official tagged release, not Homebrew latest or a guessed archive:

- Release tag: `2.46.0`
- Tag commit: `8445e778451c7e44237b90281bde622d764b0084`
- Archive: `https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip`
- Archive size: `4278764` bytes
- SHA-256: `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`

The tag commit was read from the official repository's `refs/tags/2.46.0`.
The archive digest and size were read from the official GitHub release asset
metadata (asset ID `478866069`). The parent downloaded the archive and recorded
the 4,278,764-byte size and matching SHA-256 in
`.build/dual-distribution-logs/xcodegen-pin-verification.log`. The extracted
binary contains arm64 and x86_64 slices and reports `Version: 2.46.0`.

The workflows capture that output by executing the installed
`${TOOL_ROOT}/bin/xcodegen --version`, remove the exact `Version: ` prefix, and
then compare the remainder exactly with `${XCODEGEN_VERSION}`. The policy
checker requires that exact runtime capture, rejects any extra
`ACTUAL_XCODEGEN_VERSION=` assignment, and rejects missing normalization,
substring/wildcard comparison, a changed version, or a changed checksum. A real
download and installation on a GitHub-hosted runner remains `NOT RUN` until CI
is dispatched.

## Interface dependencies

The Store checks consume these stable interfaces:

- `scripts/build-app-store.sh` with `APP_STORE_UNSIGNED=1` and optional
  `APP_STORE_ARCHIVE_PATH`
- `scripts/verify-app-store-bundle.sh <app> --unsigned`
- `scripts/test-app-store-project-contract.sh`
- `scripts/test-app-store-bundle-contract.sh`
- `scripts/test-app-store-source-closure.sh`
- `scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json`

The source-membership manifest remains the C-owned interface. Its absence,
stale SHA, changed source-tree digest, wrong action/configuration file list,
unclassified source, or mismatch with the actual Swift file lists is a failure.

## Explicitly not run

- GitHub Actions dispatch or a real pull-request run
- Unsigned Store app or archive build
- Pinned XcodeGen archive installation
- Signed build, entitlements inspection, or App Sandbox runtime
- Real TCC allow/deny/revoke, hardware, sleep/wake, or two-channel installation
- App Store Connect upload, review, publication, tag, release, or appcast update

These remain separate evidence classes; the offline policy pass does not prove
any of them.
