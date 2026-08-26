#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
RELEASE_SCRIPT="$ROOT/scripts/release_app.sh"

fail() {
  print -u2 -- "$1"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  grep -Fq -- "$needle" <<< "$haystack" || fail "Expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if grep -Fq -- "$needle" <<< "$haystack"; then
    fail "Expected output not to contain: $needle"
  fi
}

HELP_OUTPUT="$($RELEASE_SCRIPT --help)"
assert_contains "$HELP_OUTPUT" "--publish"
assert_contains "$HELP_OUTPUT" "SIDEKICK_NOTARY_PROFILE"

PREPARE_PLAN="$($RELEASE_SCRIPT --dry-run --tag v1.2.3)"
assert_contains "$PREPARE_PLAN" "prepare notarized archive for v1.2.3"
assert_contains "$PREPARE_PLAN" "submit with SIDEKICK_NOTARY_PROFILE"
assert_contains "$PREPARE_PLAN" "verify extracted archive"
assert_not_contains "$PREPARE_PLAN" "create GitHub Release"

PUBLISH_PLAN="$($RELEASE_SCRIPT --dry-run --tag v1.2.3 --publish)"
assert_contains "$PUBLISH_PLAN" "create GitHub Release v1.2.3"
assert_contains "$PUBLISH_PLAN" "as a draft"
assert_contains "$PUBLISH_PLAN" "verify the draft asset before making the release public"
assert_contains "$PUBLISH_PLAN" "download and verify the published asset"

if "$RELEASE_SCRIPT" --dry-run --tag 1.2.3 >/dev/null 2>&1; then
  fail "Expected a tag without the v prefix to be rejected"
fi

if "$RELEASE_SCRIPT" --dry-run --tag v1.2 --publish >/dev/null 2>&1; then
  fail "Expected an incomplete semantic version tag to be rejected"
fi

print -r -- "Release script interface verified"
