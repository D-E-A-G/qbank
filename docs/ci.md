# CI

Two workflows run, with a trust boundary between them. `test/release-checks.sh` enforces every rule on this page that a file can show.

## Pull requests: `ci.yml`

Every pull request runs one Linux job on GitHub's `ubuntu-latest` machine:

- `shellcheck` over `test/*.sh`
- `test/release-checks.sh`: workflow pins and triggers, project settings, the Debug-only launch seam, and the frontend-only rule
- `test/package-tests.sh --linux`: `swift test` in each package under `Packages/` that builds on Linux (see below)

It references no secrets, reads the repository with a `contents: read` token, and never runs on a Mac. There is no `pull_request_target` workflow.

## Trusted code: `xcode.yml`

Pushes to `main`, `qbank-v*` tags, and manual runs (Actions > Xcode > Run workflow) run one Mac job:

1. `test/package-tests.sh --macos`: `swift test` in every package under `Packages/` on the Mac host
2. `xcodebuild test` of the `QBank` scheme (unit and UI tests) on a run-scoped iPhone simulator through `test/sim.sh`, then again on a run-scoped iPad simulator, where the iPad layout's UI tests run and the iPhone layout's skip themselves
3. a Release build for `generic/platform=iOS` without signing, which proves Debug-only code stays out of Release

It never runs on pull requests, because its machine may be the captain's own Mac.

### Which Mac

The job runs on `${{ vars.MAC_RUNNER || 'macos-26' }}`. With no `MAC_RUNNER` repository variable it uses GitHub's hosted `macos-26` image, free on a public repository, with that image's default Xcode at `/Applications/Xcode.app`.

To move the job to the self-hosted MacBook runner once it is registered with the label `macbook-14` (Xcode installed at `/Applications/Xcode.app`, a dedicated macOS user with nothing else on it):

```sh
gh variable set MAC_RUNNER --repo D-E-A-G/qbank --body macbook-14
```

Delete the variable to go back to the hosted Mac. The job uses `DEVELOPER_DIR` rather than `sudo`, so the runner user needs no administrator rights.

### Package hosts

A package that needs Apple frameworks (Security, SwiftUI, UIKit) adds an empty `.apple-only` file at its root; the Linux job then skips it and only the Mac job tests it. Every package declares a `.macOS` platform next to `.iOS(.v18)` so `swift test` can run on the Mac host.

## Repository settings that back this

- Secret scanning and push protection are on.
- Private vulnerability reporting is on (see `SECURITY.md`).
- Workflows from forks wait for approval for all outside collaborators.

## Not yet: TestFlight

There is no `release.yml` yet. The TestFlight upload, copied from Eddie's Wallet, is phase 2 and needs the owner's Apple Developer Program membership, an App Store Connect app record, three repository secrets (`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`), and the `APPLE_TEAM_ID` variable. It will run only for `qbank-v*` tags on the same `MAC_RUNNER` selection.
