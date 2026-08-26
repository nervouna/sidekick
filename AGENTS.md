# Sidekick Repository Instructions

## Delivery

- When the user asks to ship, commit the confirmed scope, merge it locally, and push directly to `main` without requiring pull-request review.

## Human Acceptance Artifacts

- Any `.app` delivered to a human for acceptance testing must be signed with a valid `Developer ID Application` identity.
- Ad-hoc signed or unsigned apps are allowed only for local automated verification and must never be presented as human acceptance artifacts.
- Before delivery, verify the app with `codesign --verify --deep --strict` and confirm that its signing authority is `Developer ID Application`.
- Packaging must fail when a Developer ID identity is unavailable. Never silently fall back to ad-hoc signing.

## Public Releases

- Public release artifacts must be signed with `Developer ID Application`, accepted by Apple notarization, and carry a stapled notarization ticket.
- Before publication, extract the final archive and verify it with `codesign --verify --deep --strict`, `xcrun stapler validate`, and Gatekeeper. Gatekeeper must report `Notarized Developer ID`.
- The release tag must resolve to the exact source commit used to build the artifact. After publication, re-download the asset and verify its digest and distribution gates.
