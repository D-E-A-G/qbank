# CI

Two workflows run, with a trust boundary between them. `test/release-checks.sh` enforces every rule on this page that a file can show.

## Pull requests and `main`: `ci.yml`

Every pull request and every push to `main` runs two Linux jobs on GitHub's `ubuntu-latest` machine.

`Linux checks`:

- `shellcheck` over `test/*.sh` and `scripts/*.sh`
- `test/release-checks.sh`: workflow pins and triggers, project settings, the privacy manifest (it exists, lints, matches [privacy-manifest.md](privacy-manifest.md), and the app target's synchronized `QBank` group includes it), the Debug-only launch seam, the frontend-only rule, and the TestFlight upload script's rules (the key read only in its upload step, its cleanup traps, the export options, and no key or team ID in Git)
- `test/package-tests.sh --linux`: `swift test` in each package under `Packages/` that builds on Linux (see below)

`Secrets`: `test/leak-check.sh` runs [gitleaks](https://github.com/gitleaks/gitleaks), a pinned release whose checksum the job checks, over the commits the change adds and over every tracked file at HEAD, and fails on any finding. It uses gitleaks' own rules and the exceptions in `.gitleaks.toml`, which name the synthetic test values that look like keys. Findings print redacted. To run it on a Mac with gitleaks installed: `test/leak-check.sh origin/main HEAD`.

The workflow references no secrets, reads the repository with a `contents: read` token, and never runs on a Mac. There is no `pull_request_target` workflow.

## Trusted code: `xcode.yml`

`qbank-v*` tags and manual runs (Actions > Xcode > Run workflow, or `gh workflow run xcode.yml -R D-e-e-g/qbank --ref <branch>`) run one Mac job; a push to `main` does not:

1. `test/package-tests.sh --macos`: `swift test` in every package under `Packages/` on the Mac host
2. `xcodebuild test` of the `QBank` scheme (unit and UI tests) on a run-scoped iPhone simulator through `test/sim.sh`, then again on a run-scoped iPad simulator, where the iPad layout's UI tests run and the iPhone layout's skip themselves
3. a Release build for `generic/platform=iOS` without signing, which proves Debug-only code stays out of Release

It never runs on pull requests, because its machine may be the captain's own Mac.

### Which Mac

The job runs on `${{ vars.MAC_RUNNER || 'macos-26' }}`. With no `MAC_RUNNER` repository variable it uses GitHub's hosted `macos-26` image, free on a public repository, with that image's default Xcode at `/Applications/Xcode.app`.

To move the job to the self-hosted MacBook runner once it is registered with the label `macbook-14` (Xcode installed at `/Applications/Xcode.app`, a dedicated macOS user with nothing else on it):

```sh
gh variable set MAC_RUNNER --repo D-e-e-g/qbank --body macbook-14
```

Delete the variable to go back to the hosted Mac. The job uses `DEVELOPER_DIR` rather than `sudo`, so the runner user needs no administrator rights.

### Package hosts

A package that needs Apple frameworks (Security, SwiftUI, UIKit) adds an empty `.apple-only` file at its root; the Linux job then skips it and only the Mac job tests it. Every package declares a `.macOS` platform next to `.iOS(.v18)` so `swift test` can run on the Mac host.

## Repository settings that back this

- Secret scanning and push protection are on.
- A ruleset on `main` requires a pull request and the `Linux checks` and `Secrets` checks, and forbids force pushes and deletion.
- Private vulnerability reporting is on (see `SECURITY.md`).
- Workflows from forks wait for approval for all outside collaborators.

## TestFlight is not in CI

No workflow signs or uploads a build, and none holds an Apple credential. The owner's MacBook builds, signs, and uploads with `scripts/testflight-upload.sh`, which reads the App Store Connect key from Automic Vault for the upload step alone; see [release.md](release.md).
