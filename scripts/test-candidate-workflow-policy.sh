#!/usr/bin/env bash
# Regression for the candidate workflow policy contract.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioCandidatePolicy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "candidate workflow policy contract failed: $*" >&2; exit 1; }

run_policy() {
    STATUS_TRIO_CANDIDATE_POLICY_ROOT="$1" bash "$ROOT/scripts/check-candidate-workflow-policy.sh" >"$WORK/out" 2>&1
}

make_fixture() {
    local fixture="$1"
    mkdir -p "$fixture/.github/workflows"
    cp "$ROOT/.github/workflows/build-candidate.yml" "$fixture/.github/workflows/build-candidate.yml"
    cp "$ROOT/.github/workflows/publish-candidate.yml" "$fixture/.github/workflows/publish-candidate.yml"
    cp "$ROOT/.github/workflows/verify-candidate.yml" "$fixture/.github/workflows/verify-candidate.yml"
}

valid="$WORK/valid"
make_fixture "$valid"
run_policy "$valid" || { cat "$WORK/out" >&2; fail "valid candidate workflows were rejected"; }

# A publish workflow that regains a build step must be rejected.
mutated="$WORK/mutated-build"
make_fixture "$mutated"
printf '\n      - name: sneaky build\n        run: bash scripts/package-release.sh\n' \
    >> "$mutated/.github/workflows/publish-candidate.yml"
if run_policy "$mutated"; then
    fail "publish workflow with build step was accepted"
fi

# A publish workflow that regains signing must be rejected.
mutated_sign="$WORK/mutated-sign"
make_fixture "$mutated_sign"
printf '\n      - name: sneaky sign\n        run: codesign --sign "Developer ID" app\n' \
    >> "$mutated_sign/.github/workflows/publish-candidate.yml"
if run_policy "$mutated_sign"; then
    fail "publish workflow with signing step was accepted"
fi

# A build workflow that ignores the on_main branch check and always produces a
# publishable candidate must be rejected: only main builds may be publishable.
mutated_type="$WORK/mutated-type"
make_fixture "$mutated_type"
python3 - "$mutated_type/.github/workflows/build-candidate.yml" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    text = fh.read()
old = "CANDIDATE_TYPE: ${{ needs.prepare.outputs.on_main == 'true' && 'release_candidate' || 'test_candidate' }}"
new = "CANDIDATE_TYPE: release_candidate"
if old not in text:
    raise SystemExit("expected CANDIDATE_TYPE expression not found in fixture")
with open(path, "w") as fh:
    fh.write(text.replace(old, new))
PY
if run_policy "$mutated_type"; then
    fail "build workflow that ignores on_main was accepted"
fi

# A branch candidate must never skip the reviewed signing environment, even
# when the owner triggers it. Dropping the main-ref guard reintroduces that.
mutated_actor="$WORK/mutated-actor"
make_fixture "$mutated_actor"
python3 - "$mutated_actor/.github/workflows/build-candidate.yml" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    text = fh.read()
old = "needs.prepare.outputs.on_main == 'true' && github.ref == 'refs/heads/main' && github.triggering_actor == 'lingyired' && 'distribution-owner-signing' || 'distribution'"
new = "github.triggering_actor != 'lingyired' && 'distribution' || 'distribution-owner-signing'"
if old not in text:
    raise SystemExit("expected signing-environment expression not found in fixture")
with open(path, "w") as fh:
    fh.write(text.replace(old, new))
PY
if run_policy "$mutated_actor"; then
    fail "branch candidate with actor-only signing environment was accepted"
fi

# Keeping the actor check but dropping the ref check is still a branch bypass.
mutated_ref="$WORK/mutated-ref"
make_fixture "$mutated_ref"
python3 - "$mutated_ref/.github/workflows/build-candidate.yml" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    text = fh.read()
old = "github.ref == 'refs/heads/main' && "
if old not in text:
    raise SystemExit("expected main-ref guard not found in fixture")
with open(path, "w") as fh:
    fh.write(text.replace(old, "", 1))
PY
if run_policy "$mutated_ref"; then
    fail "signing environment without the main-ref guard was accepted"
fi

echo "test-candidate-workflow-policy: PASS"
