# Sidekick Repository Instructions

## Human Acceptance Artifacts

- Any `.app` delivered to a human for acceptance testing must be signed with a valid `Developer ID Application` identity.
- Ad-hoc signed or unsigned apps are allowed only for local automated verification and must never be presented as human acceptance artifacts.
- Before delivery, verify the app with `codesign --verify --deep --strict` and confirm that its signing authority is `Developer ID Application`.
- Packaging must fail when a Developer ID identity is unavailable. Never silently fall back to ad-hoc signing.
