# Release: TestFlight (phase 2)

How a QBank build gets from `main` to Khine's iPhone, and the checklist that sets it up. It follows the plan's phase 2 and copies the shape of Kun's Eddie's Wallet pipeline (`kunchenguid/eddies-wallet`, `docs/release.md`), without its App Review automation, StoreKit, or self-hosted Mac mini.

Phase 2 is done when builds reach TestFlight by themselves, the first one at parity with the web app, and Khine uses it for a week the way she uses the web app.

## How a release works, once set up

1. Pull requests merge to `main` with conventional commit titles (`feat:`, `fix:`, ...).
2. release-please opens or updates a **release PR** that bumps the version and writes the changelog.
3. **The owner merges the release PR.** That is the release trigger. No agent or automation merges, auto-merges, or approves a release PR.
4. Merging creates a GitHub Release and a tag `qbank-vX.Y.Z` (the first is `qbank-v0.1.0`).
5. `release.yml` runs for that tag on `${{ vars.MAC_RUNNER || 'macos-26' }}`: it checks out exactly the tag, archives the Release build with App Store Connect cloud signing, exports an IPA, uploads it to App Store Connect, and deletes the API key from the machine in a step that always runs.
6. Apple processes the build (usually 5 to 30 minutes). With automatic distribution on, it appears in the TestFlight app for the internal testers with an **Install** or **Update** button. Internal builds need no review.

Versions and build numbers, as in Eddie's Wallet:

- The marketing version comes from the tag, a zero patch trimmed: `qbank-v0.1.0` builds as `0.1`, `qbank-v0.1.2` as `0.1.2`.
- The build number is `GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`, so every upload is unique and a rerun uploads the next number instead of colliding.
- Settings shows both (for example "QBank 0.1 (12.1)"), so anyone can tell which build Khine has.

A TestFlight build expires **90 days** after upload. If nothing has shipped for about 80 days, a worker opens a small release PR so the owner can merge a fresh build before hers stops opening.

## Who does what

The owner does only what needs his Apple account, his money, his machine, or his merge. Workers do everything else and walk him through each owner step when it comes up.

### Only the owner

Each step is done once unless it says otherwise. Steps 1 to 3 come before phase 1 can run on a phone; 4 to 9 come before the first TestFlight build.

- [ ] **1. Install Xcode** from the Mac App Store, open it once, and let it install the iOS platform. Needed to run the app on his own iPhone; CI does not need it on his Mac.
- [ ] **2. Join the Apple Developer Program** ($99 a year, individual) with his Apple Account, and wait for the approval email (a day or two). TestFlight is impossible without it; the free Personal Team cannot upload.
- [ ] **3. Sign in to Xcode** (Settings > Accounts) with that Apple Account, so the paid team appears and automatic signing works on his iPhone.
- [ ] **4. Create the app record** in [App Store Connect](https://appstoreconnect.apple.com) > Apps > + > New App: platform iOS, name **QBank** (fallback **QBank Nursing** if the name is taken), primary language English (U.S.), bundle ID `com.dimitrygallego.qbank`, SKU `qbank-ios`, user access Full. If the bundle ID is not in the list, register it first under Certificates, Identifiers & Profiles > Identifiers > App IDs, with no extra capabilities.
- [ ] **5. Create the App Store Connect API key**: Users and Access > Integrations > App Store Connect API > Team Keys > +, name `qbank-release`, access **Admin** (Kun's guide allows App Manager or Admin; Admin avoids signing-permission errors with cloud signing). Write down the **Key ID** and the **Issuer ID** shown above the table, and download the `.p8` file. Apple offers the download **once**: keep it in his password manager, never in a repository, chat, or issue.
- [ ] **6. Store the key as repository secrets and the team ID as a variable**, from his own Mac, in Terminal. The values never appear on screen or in a file:

  ```sh
  REPO=D-E-A-G/qbank
  KEY_ID=REPLACE_WITH_KEY_ID
  ISSUER_ID=REPLACE_WITH_ISSUER_ID
  P8_PATH=~/Downloads/AuthKey_${KEY_ID}.p8
  TEAM_ID=REPLACE_WITH_TEAM_ID   # developer.apple.com > Account > Membership details

  printf '%s' "$KEY_ID" | gh secret set APP_STORE_CONNECT_KEY_ID --repo "$REPO"
  printf '%s' "$ISSUER_ID" | gh secret set APP_STORE_CONNECT_ISSUER_ID --repo "$REPO"
  base64 -i "$P8_PATH" | gh secret set APP_STORE_CONNECT_API_KEY --repo "$REPO"
  gh variable set APPLE_TEAM_ID --repo "$REPO" --body "$TEAM_ID"
  ```

  Then move the `.p8` from Downloads into the password manager and delete the file.
- [ ] **7. Invite Khine to App Store Connect**: Users and Access > + with her Apple Account email, a low role such as Marketing or Customer Support, access to QBank only. She accepts the email. If she is not offered when adding testers, change her role, as Apple's help says.
- [ ] **8. Make the tester group**: QBank > TestFlight > Internal Testing > +, name `Home`, tick **Enable automatic distribution**, add himself and Khine.
- [ ] **9. Khine installs the TestFlight app** from the App Store on her iPhone and taps the invitation email, signed in with the same Apple Account.
- [ ] **10. Merge each release PR** when he wants a build to go out. This repeats for every release.
- [ ] **Later, when he wants the MacBook Pro 14 to run the Mac jobs:** set it up as a self-hosted runner (plugged in, Remote Login, Tailscale, no sleep, Xcode installed, a dedicated macOS user, runner registered with label `macbook-14` and installed as a service, fork workflows require approval for all outside collaborators). Until then GitHub's hosted Mac runs everything, free on a public repository.
- [ ] **Later, before the App Store (phase 4):** decide to submit, fill in the privacy contact in [privacy-policy.md](privacy-policy.md), answer App Privacy in App Store Connect from [privacy-manifest.md](privacy-manifest.md), make the demo account in [app-review.md](app-review.md), confirm with Khine whether her questions may appear in public screenshots, and press **Submit for Review**.

### Workers

- [ ] **Phase-0 project and CI** (in flight in its own PR): Xcode project with bundle ID `com.dimitrygallego.qbank`, iOS 18, `ci.yml` running Linux checks on pull requests with no secrets, macOS build and tests on `main` pushes and tags only.
- [ ] **Release pipeline PR**, copied from Eddie's Wallet and adapted:
  - `release-please-config.json` and `.release-please-manifest.json` with tag prefix `qbank-v`, seed `0.0.0`, `initial-version` `0.1.0`, and the "only the owner merges this" warning in the release PR header;
  - `release.yml`: triggered only by `qbank-v*` tags, published releases, and tag dispatches, never by pull requests; `runs-on: ${{ vars.MAC_RUNNER || 'macos-26' }}`; restores the base64 `.p8` into the runner's temp folder with mode 600; archives with `-allowProvisioningUpdates`, API-key authentication and `CODE_SIGN_STYLE=Automatic`; writes `APPLE_TEAM_ID` into a temp copy of `ExportOptions.plist`; uploads with `xcrun altool --upload-app`; removes every copy of the key in an `always()` step; uploads logs and the IPA as run artifacts; one concurrency group per tag; every action pinned to a full commit SHA;
  - `.github/scripts/resolve_release_version.sh` for the version and build number rules above;
  - `test/release-checks.sh` asserting all of it, run by `ci.yml` on every pull request with no credentials or network.
  - The pipeline must fail clearly, not silently skip, when the secrets are missing.
- [ ] **Privacy manifest and Info.plist**: add `PrivacyInfo.xcprivacy` to the app target from [privacy-manifest.md](privacy-manifest.md) and set `ITSAppUsesNonExemptEncryption` to `NO`.
- [ ] **Version in Settings**: show the marketing version and build number at the bottom of Settings, as in the approved wireframe.
- [ ] **Privacy policy check**: before Khine's first build, re-read every claim in [privacy-policy.md](privacy-policy.md) against the app and the server, fix what differs, and set "Last reviewed against the code".
- [ ] **Server follow-up in qbank-web** (optional, small): stop recording the IP address and user agent on sessions, which QBank never uses; then drop that line from the policy and the manifest notes.
- [ ] **Walk the owner through steps 4 to 9** when the release pipeline PR is ready, one step at a time, and confirm each one (for example `gh secret list -R D-E-A-G/qbank` shows the three names; values are never read back).
- [ ] **Release-PR setting**: release-please needs "Allow GitHub Actions to create and approve pull requests" (Settings > Actions > General) on the repository, and on the D-E-A-G organization if the organization blocks it. A worker sets it through the API if its token has admin rights; otherwise the owner ticks the box.
- [ ] **After every release**: confirm App Store Connect accepted the exact build (processing or ready in TestFlight), not just a green upload step, and tell the owner the build is on Khine's phone. A worker can add Kun's read-only `asc-build-status.yml` for this.
- [ ] **When the MacBook runner is registered**: set `MAC_RUNNER=macbook-14`; deleting the variable falls back to `macos-26` at once.

## Security boundaries

- Pull requests, including forks, run only Linux checks with `contents: read` and no secrets. No workflow uses `pull_request_target`. No macOS job runs for a pull request, so a stranger's code never runs on the owner's Mac.
- The App Store Connect key is reachable only from `qbank-v*` tags, published releases, and tag dispatches, all of which need write access to the repository.
- The key lives on the runner only for the length of one job and is deleted even when the job fails or is cancelled.
- The Apple team ID stays out of Git; `release.yml` reads it from the `APPLE_TEAM_ID` variable.
- Nothing in this pipeline submits for App Review or publishes to the App Store. It ends at TestFlight.
- The repository holds no backend code, server credentials, deployment files, or infrastructure configuration; those stay in the private server repository.

## When something fails

- Every failing step fails the run visibly, with the archive and export logs attached.
- Rerun a failed upload from the run page, or dispatch `release.yml` for the same tag. The tag fixes the source; the build number advances with each attempt.
- If the failure was in the workflow itself and its fix is now on `main`: `gh workflow run release.yml --ref main -f tag_name=<tag>` runs main's workflow on the tagged source.
- "No profiles for 'com.dimitrygallego.qbank' were found" or an authentication-looking error with correct secrets usually means a capability was added in code but not enabled on the App ID in the developer portal. Any change that adds a capability (passkeys' Associated Domains in phase 3, for example) needs that portal step before its release, which is an owner step.
- An upload that succeeded but stays in processing is waited on, not re-uploaded.
