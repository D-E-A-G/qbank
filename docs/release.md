# Release: TestFlight (phase 2)

How a QBank build gets from `main` to Khine's iPhone, and the checklist that sets it up. Builds are made, signed, and uploaded on the owner's MacBook by `scripts/testflight-upload.sh`. No CI job signs or uploads anything, and no GitHub machine ever holds an Apple credential.

Phase 2 is done when a build uploaded this way reaches Khine's iPhone through TestFlight, the first one at parity with the web app, and Khine uses it for a week the way she uses the web app.

## How an upload works

`scripts/testflight-upload.sh` runs on the owner's MacBook, where Xcode is signed in with his Apple Account. He is the team's Account Holder, so Xcode can create the distribution certificate and the App Store profile itself.

1. It fetches `origin`, resolves the ref it was given (default `origin/main`), refuses a commit that is on no origin branch, and clones that exact commit into a fresh temporary directory. Edits in the checkout it runs from never ship. The commit is recorded in the run's `build.txt`.
2. It archives the `QBank` scheme in Release with `CODE_SIGN_STYLE=Automatic` and `-allowProvisioningUpdates`. Signing goes through the Xcode account on the Mac. The App Store Connect key plays no part in it: an App Manager key cannot cloud-sign.
3. It exports an IPA with `scripts/ExportOptions.plist` (method `app-store-connect`, destination `export`), the team ID written only into a temporary copy. Then it checks the IPA: the bundle ID, the version and build number, an App Store profile for the team (no device list, `get-task-allow` false), and a distribution signature.
4. Only then, as a separate last step, it uploads the IPA with `xcrun altool --upload-app`. Automic Vault asks the owner to **Allow** the three key entries, and they reach that step alone.
5. Apple processes the build (usually 5 to 30 minutes). With automatic distribution on, it appears in the TestFlight app for the internal testers with an **Install** or **Update** button. Internal builds need no review.

### Running it

The team ID is on developer.apple.com > Account > Membership details. It stays out of Git: pass `--team-id`, or set `APPLE_TEAM_ID` in the shell (for example in `~/.zprofile` on the Mac).

```sh
export APPLE_TEAM_ID=REPLACE_WITH_TEAM_ID

# Everything except the upload: proves signing and the export, reads nothing from the vault.
scripts/testflight-upload.sh --no-upload

# Build origin/main and upload it.
scripts/testflight-upload.sh

# Build and upload a release tag, or any commit that is on origin.
scripts/testflight-upload.sh qbank-v0.1.0
```

Run it from any checkout of this repository on the Mac; it builds the ref's commit, never the checkout's files. Each run keeps its logs in `build/testflight/<build number>/` (`build.txt`, `archive.log`, `export.log`, `upload.log`), which Git ignores. A worker may start a run for the owner; the upload still waits for his Allow.

### Versions and build numbers

- **Version** (`CFBundleShortVersionString`): from the tag when the ref is a `qbank-vX.Y.Z` tag, otherwise from the project's `MARKETING_VERSION`. Either way a zero patch is trimmed: `qbank-v0.1.0` and the project's `0.1.0` build as `0.1`, `qbank-v0.1.2` as `0.1.2`. The project's version changes in an ordinary pull request.
- **Build number** (`CFBundleVersion`): the Unix time in seconds when the run started, for example `1792156600` (`date -r 1792156600` turns it back into a date). Every run gets a new, higher number, so a re-upload of the same ref never collides with an earlier upload. Two runs on the Mac never share a second: the later one waits for the next.
- Settings shows both (for example "QBank 0.1 (1792156600)"), so anyone can tell which build Khine has; that run's `build.txt` names its commit.

A TestFlight build expires **90 days** after upload. If nothing has been uploaded for about 80 days, a worker asks the owner for an upload so Khine's build keeps opening.

## Who does what

The owner does only what needs his Apple account, his money, his Mac, or his Allow. Workers do everything else and walk him through each owner step. A separate walkthrough page guides him through steps 4 to 9.

### Only the owner

Steps 4 to 9 come before the first upload. Each is done once unless it says otherwise.

- [x] **1. Install Xcode** from the Mac App Store, open it once, and let it install the iOS platform.
- [x] **2. Join the Apple Developer Program** ($99 a year, individual) with his Apple Account. TestFlight is impossible without it; the free Personal Team cannot upload.
- [ ] **3. Sign in to Xcode** (Settings > Accounts) with that Apple Account, and check that the paid team, not only the Personal Team, shows under it. The upload's signing depends on this sign-in.
- [ ] **4. Accept the agreements** waiting in App Store Connect (Business) and on developer.apple.com. A free app needs no Paid Applications agreement.
- [ ] **5. Create the app record** in [App Store Connect](https://appstoreconnect.apple.com) > Apps > + > New App: platform iOS, name **QBank** (fallback **QBank Nursing** if the name is taken), primary language English (U.S.), bundle ID `com.dimitrygallego.qbank`, SKU `qbank-ios`, user access Full. If the bundle ID is not in the list, register it first under Certificates, Identifiers & Profiles > Identifiers > App IDs, with no extra capabilities.
- [ ] **6. Invite Khine and make the tester group.** Users and Access > + with her Apple Account email, a low role such as Marketing, access to QBank only; she accepts the email. If she is not offered when adding testers, change her role, as Apple's help says. Then QBank > TestFlight > Internal Testing > +, name `Home`, tick **Enable automatic distribution**, and add himself and Khine.
- [ ] **7. Khine installs the TestFlight app** from the App Store on her iPhone and taps the invitation email, signed in with the same Apple Account.
- [ ] **8. Create the App Store Connect API key**, at his Mac: Users and Access > Integrations > App Store Connect API > Team Keys > +, any name (for example `qbank-testflight`), access **App Manager**, not Admin. Note the **Key ID** and the **Issuer ID** shown above the keys table, and download the `.p8` file. Apple offers the download **once**.
- [ ] **9. Save the key in Automic Vault**, in Terminal on the same Mac. The values never appear on screen or in chat:

  ```sh
  av save APP_STORE_CONNECT_KEY_ID      # hidden prompt: paste the Key ID
  av save APP_STORE_CONNECT_ISSUER_ID   # hidden prompt: paste the Issuer ID
  av save --stdin APP_STORE_CONNECT_API_KEY_P8 < ~/Downloads/AuthKey_REPLACE_WITH_KEY_ID.p8
  av list                               # shows the three names, never the values
  ```

  Then delete the `.p8` from Downloads and empty the Trash. The vault holds the only copy; if it is lost, revoke the key and make a new one under the same names.
- [ ] **10. Allow each upload** when Automic Vault asks. This repeats for every upload.
- [ ] **Later, before the App Store (phase 4):** decide to submit, fill in the privacy contact in [privacy-policy.md](privacy-policy.md), answer App Privacy in App Store Connect from [privacy-manifest.md](privacy-manifest.md), make the demo account in [app-review.md](app-review.md), confirm with Khine whether her questions may appear in public screenshots, and press **Submit for Review**.

### Workers

- [x] **Upload path**: `scripts/testflight-upload.sh`, `scripts/ExportOptions.plist`, and their rules in `test/release-checks.sh`, which `ci.yml` runs on every pull request with no credentials or network.
- [x] **Version in Settings**: the version and build number at the bottom of Settings.
- [ ] **Privacy manifest**: add `PrivacyInfo.xcprivacy` to the app target from [privacy-manifest.md](privacy-manifest.md) before the first upload. `ITSAppUsesNonExemptEncryption` is already `NO` in the project.
- [ ] **Privacy policy check**: before Khine's first build, re-read every claim in [privacy-policy.md](privacy-policy.md) against the app and the server, fix what differs, and set "Last reviewed against the code".
- [ ] **Server follow-up in qbank-web** (optional, small): stop recording the IP address and user agent on sessions, which QBank never uses; then drop that line from the policy and the manifest notes.
- [ ] **Walk the owner through steps 3 to 9**, one step at a time, and confirm each one (for example `av list` on his Mac shows the three names; values are never read back).
- [ ] **First upload, attended**: `scripts/testflight-upload.sh --no-upload` first, then the upload with his Allow.
- [ ] **After every upload**: confirm App Store Connect accepted the exact build (the version and build number, processing or ready in TestFlight), not just a script that finished, and tell the owner the build is on Khine's phone.

## Security boundaries

- The App Store Connect key lives only in Automic Vault, as `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_P8` (the `.p8` PEM text). Only the upload step reads them, through `av inject --mode=fd` after the owner's Allow. Nothing before that step, and nothing in a `--no-upload` run, touches the vault.
- On disk the key exists only as `AuthKey_<KEY_ID>.p8` (mode 600) in a mode-700 directory inside the run's temporary directory, while altool runs. Traps remove it, and the whole temporary directory, on every exit: success, failure, Ctrl-C, or a termination signal. Only `kill -9` or a power cut can skip them; then delete the `qbank-testflight.*` directory in `$TMPDIR` by hand.
- The script never prints or logs a vault value and never puts the `.p8` on a command line. altool receives the Key ID and Issuer ID as arguments, which name the key without unlocking it, and finds the `.p8` through `API_PRIVATE_KEYS_DIR`.
- The key has the **App Manager** role, not Admin: it can upload builds and run TestFlight, but cannot manage users or keys. If it leaks, revoke it in App Store Connect (Users and Access > Integrations) and save a new one under the same vault names.
- Signing uses the owner's Xcode sign-in on his Mac. No signing certificate, profile, or key is in this repository or in CI.
- The Apple team ID stays out of Git. It comes from `--team-id` or `APPLE_TEAM_ID`, and only a temporary copy of `ExportOptions.plist` holds it.
- No CI job holds Apple credentials: pull requests run only Linux checks with no secrets, and `xcode.yml` (pushes to `main`, `qbank-v*` tags, manual runs) builds Release without signing. See [ci.md](ci.md).
- An upload builds only a commit that is on origin, from a fresh clone, so local edits never reach TestFlight.
- Nothing here submits for App Review or publishes to the App Store. It ends at TestFlight.
- The repository holds no backend code, server credentials, deployment files, or infrastructure configuration; those stay in the private server repository.

## When something fails

- The script stops at the first failing step and prints the end of that step's log. Every log is in `build/testflight/<build number>/`.
- Run it again. It rebuilds with a new build number, so a retry never collides with an earlier upload.
- If Automic Vault refused or named a missing entry, nothing was uploaded: check that `av list` shows the three names, then run again.
- "No Accounts", "No signing certificate", or "No profiles for 'com.dimitrygallego.qbank' were found" means Xcode on the Mac is not signed in to the paid team, or a capability was added in code but not enabled on the App ID in the developer portal. Any change that adds a capability (passkeys' Associated Domains, for example) needs that portal step before its upload, which is an owner step.
- An upload that succeeded but stays in processing is waited on, not re-uploaded.
