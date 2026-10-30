# Contributing

Sidekick is a personal project, but bug reports and fixes are welcome.

## Issues

- **Bugs:** use the bug report form. Give your macOS version, what you asked or did, what happened and what you expected; a suggested fix is a bonus. Never paste an API key.
- **Security problems:** report them privately, see [SECURITY.md](SECURITY.md).
- **Feature ideas:** open an issue to discuss it first. Sidekick stays small on purpose (for example, it has no long-term memory or history), so not every idea will fit.

## How the project is developed

Most of the code is written by coding agents. `AGENTS.md` holds the rules they follow. In short:

- `./scripts/verify.sh` passes: the unit tests (`swift test`), the release script check, a release build and the app bundle check. CI runs `swift test` and `./scripts/test_release_app.sh` on pushes and pull requests to `main`.
- A build handed to a person for testing is signed with a Developer ID Application identity and checked with `codesign --verify --deep --strict`. Ad hoc builds are for automated local checks only, and packaging never falls back to ad hoc signing.
- Public releases are notarized through the workflow in `.agents/skills/release-sidekick-macos`.
- Keys for local runs go in `.env`, which Git ignores. `./scripts/smoke_api.sh` and `./scripts/eval_prompt.sh` call the real APIs and cost a little; run them when you change the API code or the system prompt.

## Pull requests

The maintainer's own changes go straight to `main`; pull requests from others are reviewed. Describe the change, list the commands you ran and their results, and say what you checked in the running app.
