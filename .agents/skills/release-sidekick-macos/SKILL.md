---
name: release-sidekick-macos
description: Prepare or publish Sidekick's notarized macOS GitHub release. Use for Apple notarization, release-grade archives, or public GitHub Releases; do not use for ordinary Developer ID acceptance packages or local /Applications updates.
---

# Release Sidekick for macOS

Use `scripts/release_app.sh` as the deterministic release entrypoint. Keep signing, notarization, publication, and public-download verification as separate reported facts.

## Choose the authorized mode

- For a notarized release candidate, run `scripts/release_app.sh --tag vMAJOR.MINOR.PATCH`. This submits to Apple's notary service but does not create a GitHub Release.
- Add `--publish` only when the user has explicitly authorized a public GitHub Release. A request for a signed package, acceptance build, notarization, or local installation does not authorize publication.
- Use `--dry-run` to inspect the intended mode without building, notarizing, pushing, tagging, or publishing.

Before a live run, make sure the requested version is already present in the app, the intended source changes are committed, and the worktree is clean. The script requires `main`; publication additionally requires local `main` to equal `origin/main`. Do not push merely to satisfy that gate unless the user has authorized shipping.

## Credentials and execution

Set `SIDEKICK_NOTARY_PROFILE` to the name of an existing notarytool Keychain profile. Never inspect, export, print, or place raw notarization credentials in the repository. Let the script select the Developer ID identity unless `SIDEKICK_CODE_SIGN_IDENTITY` is deliberately supplied.

The live workflow can require network, Keychain, Apple notarization, and GitHub access. Request the minimum necessary execution approval when the environment blocks those operations. Do not weaken a failed signing, notarization, stapling, Gatekeeper, source-provenance, or downloaded-asset gate.

## Completion evidence

Report the source commit and tag, test/build result, Developer ID and Team ID, notarization status, stapled-ticket validation, extracted-archive Gatekeeper result, archive SHA-256, and whether GitHub publication ran. When publication ran, also report the public release URL and the re-downloaded asset's digest and distribution-gate result.
