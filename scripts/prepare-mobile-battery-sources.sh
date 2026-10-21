#!/usr/bin/env bash
# Check out the exact dependency commits declared by the helper manifest.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <dependency-manifest> <work-directory>" >&2
    exit 2
fi

MANIFEST="$1"
WORK="$2"

while IFS=$'\t' read -r name repository commit version; do
    source="$WORK/sources/$name"
    if [[ ! -d "$source/.git" ]]; then
        mkdir -p "$WORK/sources"
        git clone --filter=blob:none "$repository" "$source"
    fi

    if ! git -C "$source" cat-file -e "${commit}^{commit}" 2>/dev/null; then
        git -C "$source" fetch --quiet origin "$commit"
    fi

    git -C "$source" checkout --quiet --detach "$commit"
    actual="$(git -C "$source" rev-parse HEAD)"
    if [[ "$actual" != "$commit" ]]; then
        echo "Error: source pin mismatch for $name: expected $commit, found $actual." >&2
        exit 1
    fi
done < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); by={x["name"]:x for x in d["dependencies"]}; [print("\t".join((n,by[n]["repository"],by[n]["commit"],by[n]["version"]))) for n in d["sourceBuildOrder"]]' "$MANIFEST")
