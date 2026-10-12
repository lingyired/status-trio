#!/usr/bin/env bash
set -euo pipefail

# An explicitly supplied identity is authoritative. In particular, "-" is a
# supported opt-out for callers who deliberately want an ad-hoc dev build.
if [[ "${CODE_SIGN_IDENTITY+x}" == "x" ]]; then
    if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
        echo "Error: CODE_SIGN_IDENTITY is set but empty; use '-' for an intentional ad-hoc build." >&2
        exit 2
    fi
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    exit 0
fi

if ! command -v security >/dev/null 2>&1; then
    echo "Error: security is unavailable; set CODE_SIGN_IDENTITY explicitly or run on macOS." >&2
    exit 2
fi

if ! identity_output="$(security find-identity -v -p codesigning 2>&1)"; then
    echo "Error: unable to enumerate valid code-signing identities." >&2
    if [[ -n "$identity_output" ]]; then
        printf '%s\n' "$identity_output" >&2
    fi
    exit 2
fi

# `-v` returns only valid identities. Match only Developer ID Application
# certificates and pass the stable SHA-1 identity to codesign/build-app.sh.
developer_id_hashes=()
while IFS= read -r hash; do
    [[ -n "$hash" ]] && developer_id_hashes+=("$hash")
done < <(
    printf '%s\n' "$identity_output" \
        | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"Developer ID Application:.*"[[:space:]]*$/\1/p'
)

case "${#developer_id_hashes[@]}" in
    1)
        printf '%s\n' "${developer_id_hashes[0]}"
        ;;
    0)
        echo "Error: no valid Developer ID Application identity found; set CODE_SIGN_IDENTITY explicitly (or '-' for ad-hoc signing)." >&2
        exit 2
        ;;
    *)
        echo "Error: multiple valid Developer ID Application identities found; set CODE_SIGN_IDENTITY explicitly to choose one (or '-' for ad-hoc signing)." >&2
        exit 2
        ;;
esac
