#!/usr/bin/env bash
# Compatibility entry point for local/manual releases. The workflow calls the
# package and publish scripts directly; this wrapper keeps one implementation.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist" 2>/dev/null || true)}"
BUILD="${BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Support/Info.plist" 2>/dev/null || true)}"
TAG="${TAG:-v$VERSION}"
PUBLISH="${PUBLISH:-false}"
NOTARIZE="${NOTARIZE:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/release-package}"
RELEASE_REPO="${RELEASE_REPO:-$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("github_repo")' "$ROOT/release.json")}"
RELEASE_BRANCH="${RELEASE_BRANCH:-$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("git_branch")' "$ROOT/release.json")}"

SOURCE_SHA="${SOURCE_SHA:-$(git rev-parse HEAD)}"
export SOURCE_SHA
if [[ "$PUBLISH" == "true" ]]; then
    [[ "${GH_TOKEN:-}" != "" ]] || gh auth status >/dev/null 2>&1 || {
        echo "Error: gh is not authenticated. Set GH_TOKEN or run 'gh auth login'." >&2
        exit 1
    }
fi

env \
    SOURCE_SHA="$SOURCE_SHA" \
    VERSION="$VERSION" \
    BUILD="$BUILD" \
    TAG="$TAG" \
    PUBLISH_MODE="$PUBLISH" \
    NOTARIZE="$NOTARIZE" \
    RELEASE_REPO="$RELEASE_REPO" \
    RELEASE_BRANCH="$RELEASE_BRANCH" \
    OUTPUT_DIR="$OUTPUT_DIR" \
    APP_NAME="${APP_NAME:-Status Trio}" \
    BUNDLE_ID="${BUNDLE_ID:-com.lingsmbp.StatusTrio}" \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    KEYCHAIN_PATH="${KEYCHAIN_PATH:-}" \
    NOTARY_PROFILE="${NOTARY_PROFILE:-}" \
    SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}" \
    bash "$ROOT/scripts/package-release.sh"

if [[ "$PUBLISH" == "true" ]]; then
    env \
        MANIFEST_PATH="$OUTPUT_DIR/release-manifest.json" \
        PACKAGE_DIR="$OUTPUT_DIR" \
        bash "$ROOT/scripts/publish-release.sh"
fi
