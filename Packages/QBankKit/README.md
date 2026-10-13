# QBankKit

The app's connection to the QBank server, with no UI: the API client, the session store, and the offline core. The app target and its screens build on it.

## What is in it

- **`QBankClient`** - the endpoints the phase-1 screens use: password sign-in, session check, sign-out and password change; semesters, courses with their weeks and sets, terms, practice sets, and restoring a replaced set; answers (`recordAttempt`, keyed by `clientAttemptID`); Review and its runner; exam setup with per-week wrong counts, start (`pool` `.all` or `.wrong`), read, and finish; study place, progress export, and passkeys for Settings. Calls are `async throws(QBankError)`. Sign-in stores the bearer token through a `SessionStore`, and every later call sends it as `Authorization: Bearer`. The only server fact here is the public address in `APIConfiguration.production`; there is no API key.
- **`SessionStore`** - `KeychainSessionStore` keeps the token, its expiry, and the account as one Keychain item under `<bundle id>.session` (this device only, readable after first unlock). `InMemorySessionStore` is for tests and previews.
- **`AttemptQueue`** - every answer is saved on the phone first, then sent oldest first. An answer made without signal waits and goes out when the connection is back. The server saves each `clientAttemptID` once and answers a repeat with the saved attempt, so a send whose reply was lost is simply sent again. An answer the server refuses (a 4xx such as `exam_finished`) leaves the queue and is reported; one that can succeed later (no signal, 5xx, 429, signed out, a temporary password) waits. `FilePendingAttemptStore` keeps the queue in `Application Support/QBankKit`.
- **`ContentCache`** - loaded semesters, courses, practice sets, terms, and Review lists, keyed by `CacheKey` and stamped with when they were saved. `FileContentCache` keeps one JSON file per value in `Application Support/QBankKit/Content`, out of backups.
- **`Scoring`** - the server's scoring rules, so an answer given offline shows the same mark the server records later. The contract tests check it against the server's own marks for every format.
- **Models** - `Codable` types matching the server's responses. A question's format-specific `body` is read into `QuestionBody`, and kept as sent in `rawBody`, so tables, images, and fields added later survive the offline cache. A question format this version does not know decodes as `.unsupported` instead of failing the whole set.

## Tests

```sh
swift test --package-path Packages/QBankKit
```

`test/package-tests.sh` runs this on Linux for pull requests and on macOS in `xcode.yml`. On the iOS Simulator:

```sh
cd Packages/QBankKit
../../test/sim.sh -- xcodebuild test -scheme QBankKit \
  -destination 'platform=iOS Simulator,id={{UDID}}'
```

Nothing in a test run reaches the network: the client talks through `HTTPTransport`, and tests answer with recorded responses. The Keychain tests write real items under a throwaway service on macOS; a package test bundle on the iOS Simulator has no Keychain entitlement, so they skip there.

### Contract fixtures

`Tests/QBankKitTests/Fixtures/contract/` holds one recorded exchange per file: the request the app sends and the response the server's real routes gave. They were recorded in-process against a throwaway in-memory database with invented accounts, courses, and questions, at the server commit named in each file's `recordedFrom`. Session tokens are replaced with `synthetic-*` placeholders. They hold no real student data and no real credentials.

`Tests/QBankKitTests/Fixtures/openapi.json` is a copy of the server's public OpenAPI document (`https://qbank.dimitrygallego.com/openapi.json`); a test checks that every recorded call and status is documented there.

When the server's API changes, record the fixtures again the same way and update `openapi.json`, then run the tests.
