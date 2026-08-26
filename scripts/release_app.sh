#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
EXPECTED_TEAM_ID="${SIDEKICK_EXPECTED_TEAM_ID:-T7976FL2LP}"
ASSET_NAME="Sidekick-macOS-arm64.zip"
TAG=""
PUBLISH=0
DRY_RUN=0
REMOTE_TAG_EXISTS=0

usage() {
  cat <<'USAGE'
Usage: scripts/release_app.sh --tag vMAJOR.MINOR.PATCH [--publish] [--dry-run]

By default, build, notarize, staple, and verify a release archive without
publishing it. Pass --publish only when creating a public GitHub Release is
explicitly authorized.

Environment:
  SIDEKICK_NOTARY_PROFILE       Required Keychain profile for live runs.
  SIDEKICK_CODE_SIGN_IDENTITY   Optional Developer ID Application identity.
  SIDEKICK_EXPECTED_TEAM_ID     Expected signing Team ID (default: T7976FL2LP).
USAGE
}

fail() {
  print -u2 -- "$1"
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --tag)
      (( $# >= 2 )) || fail "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --publish)
      PUBLISH=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--tag must match vMAJOR.MINOR.PATCH"
VERSION="${TAG#v}"

if (( DRY_RUN )); then
  print -r -- "Plan: prepare notarized archive for $TAG"
  print -r -- "- verify clean main and the app version"
  print -r -- "- build and test Developer ID artifact"
  print -r -- "- submit with SIDEKICK_NOTARY_PROFILE"
  print -r -- "- staple, archive, and verify extracted archive"
  if (( PUBLISH )); then
    print -r -- "- create GitHub Release $TAG as a draft from the verified source commit"
    print -r -- "- verify the draft asset before making the release public"
    print -r -- "- download and verify the published asset"
  fi
  exit 0
fi

[[ -n "${SIDEKICK_NOTARY_PROFILE:-}" ]] || fail "SIDEKICK_NOTARY_PROFILE is required"
command -v gh >/dev/null || fail "gh is required"
command -v xcrun >/dev/null || fail "xcrun is required"

cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || fail "Release requires a clean worktree"
[[ "$(git branch --show-current)" == "main" ]] || fail "Release requires the main branch"

SOURCE_COMMIT="$(git rev-parse HEAD)"
if (( PUBLISH )); then
  git fetch origin main --tags
  git rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1 || fail "origin/main is unavailable; fetch it before publishing"
  REMOTE_COMMIT="$(git rev-parse refs/remotes/origin/main)"
  [[ "$SOURCE_COMMIT" == "$REMOTE_COMMIT" ]] || fail "main must exactly match origin/main before publishing"
  if gh release view "$TAG" >/dev/null 2>&1; then
    fail "GitHub Release $TAG already exists"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    REMOTE_TAG_EXISTS=1
  fi
fi

if git rev-parse --verify "refs/tags/$TAG^{commit}" >/dev/null 2>&1; then
  TAG_COMMIT="$(git rev-parse "refs/tags/$TAG^{commit}")"
  [[ "$TAG_COMMIT" == "$SOURCE_COMMIT" ]] || fail "$TAG does not resolve to the release source commit"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sidekick-release.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
NOTARY_RESULT="$WORK_DIR/notary-result.json"
EXTRACTED_DIR="$WORK_DIR/extracted"
DOWNLOADED_DIR="$WORK_DIR/downloaded"
PUBLISHED_DIR="$WORK_DIR/published"
FINAL_ARCHIVE="$ROOT/dist/$ASSET_NAME"

"$ROOT/scripts/verify.sh"
SIGNED_ARCHIVE="$("$ROOT/scripts/package_for_acceptance.sh" | tail -n 1)"
APP_PATH="$ROOT/build/Sidekick.app"
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" ]] || fail "Tag $TAG does not match app version $APP_VERSION"

xcrun notarytool submit "$SIGNED_ARCHIVE" \
  --keychain-profile "$SIDEKICK_NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT"
NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
[[ "$NOTARY_STATUS" == "Accepted" ]] || fail "Apple notarization status was $NOTARY_STATUS"

xcrun stapler staple "$APP_PATH"
SIDEKICK_REQUIRE_DEVELOPER_ID=1 \
SIDEKICK_REQUIRE_NOTARIZED=1 \
SIDEKICK_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT/scripts/test_app_bundle.sh" "$APP_PATH"

mkdir -p "$ROOT/dist" "$EXTRACTED_DIR"
rm -f "$FINAL_ARCHIVE"
ditto -c -k --keepParent --norsrc --noextattr "$APP_PATH" "$FINAL_ARCHIVE"
ditto -x -k "$FINAL_ARCHIVE" "$EXTRACTED_DIR"
SIDEKICK_REQUIRE_DEVELOPER_ID=1 \
SIDEKICK_REQUIRE_NOTARIZED=1 \
SIDEKICK_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT/scripts/test_app_bundle.sh" "$EXTRACTED_DIR/Sidekick.app"

ARCHIVE_SHA256="$(shasum -a 256 "$FINAL_ARCHIVE" | awk '{print $1}')"
print -r -- "Source commit: $SOURCE_COMMIT"
print -r -- "Notarization status: $NOTARY_STATUS"
print -r -- "Archive: $FINAL_ARCHIVE"
print -r -- "SHA-256: $ARCHIVE_SHA256"

if (( ! PUBLISH )); then
  exit 0
fi

if (( REMOTE_TAG_EXISTS )); then
  DRAFT_URL="$(gh release create "$TAG" "$FINAL_ARCHIVE" \
    --verify-tag \
    --draft \
    --title "Sidekick $VERSION" \
    --generate-notes)"
else
  DRAFT_URL="$(gh release create "$TAG" "$FINAL_ARCHIVE" \
    --target "$SOURCE_COMMIT" \
    --draft \
    --title "Sidekick $VERSION" \
    --generate-notes)"
fi

mkdir -p "$DOWNLOADED_DIR"
gh release download "$TAG" --pattern "$ASSET_NAME" --dir "$DOWNLOADED_DIR"
DOWNLOADED_ARCHIVE="$DOWNLOADED_DIR/$ASSET_NAME"
DOWNLOADED_SHA256="$(shasum -a 256 "$DOWNLOADED_ARCHIVE" | awk '{print $1}')"
[[ "$DOWNLOADED_SHA256" == "$ARCHIVE_SHA256" ]] || fail "Draft asset digest does not match the verified local archive"

rm -rf -- "$EXTRACTED_DIR"
mkdir -p "$EXTRACTED_DIR"
ditto -x -k "$DOWNLOADED_ARCHIVE" "$EXTRACTED_DIR"
SIDEKICK_REQUIRE_DEVELOPER_ID=1 \
SIDEKICK_REQUIRE_NOTARIZED=1 \
SIDEKICK_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT/scripts/test_app_bundle.sh" "$EXTRACTED_DIR/Sidekick.app"

RELEASE_URL="$(gh release edit "$TAG" --draft=false --latest)"
[[ "$(gh release view "$TAG" --json isDraft --jq '.isDraft')" == "false" ]] || fail "GitHub Release $TAG is still a draft"

mkdir -p "$PUBLISHED_DIR"
gh release download "$TAG" --pattern "$ASSET_NAME" --dir "$PUBLISHED_DIR"
PUBLISHED_ARCHIVE="$PUBLISHED_DIR/$ASSET_NAME"
PUBLISHED_SHA256="$(shasum -a 256 "$PUBLISHED_ARCHIVE" | awk '{print $1}')"
[[ "$PUBLISHED_SHA256" == "$ARCHIVE_SHA256" ]] || fail "Published asset digest does not match the verified local archive"

rm -rf -- "$EXTRACTED_DIR"
mkdir -p "$EXTRACTED_DIR"
ditto -x -k "$PUBLISHED_ARCHIVE" "$EXTRACTED_DIR"
SIDEKICK_REQUIRE_DEVELOPER_ID=1 \
SIDEKICK_REQUIRE_NOTARIZED=1 \
SIDEKICK_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT/scripts/test_app_bundle.sh" "$EXTRACTED_DIR/Sidekick.app"

git fetch origin "refs/tags/$TAG:refs/tags/$TAG"
PUBLISHED_TAG_COMMIT="$(git rev-parse "refs/tags/$TAG^{commit}")"
[[ "$PUBLISHED_TAG_COMMIT" == "$SOURCE_COMMIT" ]] || fail "Published tag does not resolve to the release source commit"

print -r -- "Published release: $TAG"
print -r -- "Release URL: $RELEASE_URL"
print -r -- "Draft URL: $DRAFT_URL"
print -r -- "Published asset SHA-256: $PUBLISHED_SHA256"
