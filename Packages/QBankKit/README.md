# QBankKit

The app's connection to the QBank server, with no UI: the API client, the session store, and the offline core. The app target and its screens build on it.

## What is in it

- **`QBankClient`** - the endpoints the phase-1 screens use: password sign-in, session check, sign-out and password change; semesters, courses with their exam pages, folders, sets and exams, terms, practice sets, and restoring a replaced set; adding, renaming and removing a course's exam pages ("Exam 1" and the folders on it); making and renaming folders, putting a folder on an exam page, saving her folder order, and moving sets between folders; adding, renaming, moving, and archiving semesters and courses from Settings; answers (`recordAttempt`, keyed by `clientAttemptID`); Review and its runner; exam setup with per-folder wrong counts, start (`pool` `.all` or `.wrong`), read, and finish; study place, progress export, and passkeys for Settings; checking and importing a question file (`checkImport`, `importSet`, with its replace question); and making questions on the accounts the server allows (`questionMakerStatus`, `questionJobs`, `startQuestionJob`, the samples and copies she checks, the result, and cancel). Calls are `async throws(QBankError)`. Sign-in stores the bearer token through a `SessionStore`, and every later call sends it as `Authorization: Bearer`. The only server fact here is the public address in `APIConfiguration.production`; there is no API key.
- **`SessionStore`** - `KeychainSessionStore` keeps the token, its expiry, and the account as one Keychain item under `<bundle id>.session` (this device only, readable after first unlock). `InMemorySessionStore` is for tests and previews.
- **`AttemptQueue`** - every answer is saved on the phone first, then sent oldest first. An answer made without signal waits and goes out when the connection is back. The server saves each `clientAttemptID` once and answers a repeat with the saved attempt, so a send whose reply was lost is simply sent again. An answer the server refuses (a 4xx such as `exam_finished`) leaves the queue and is reported; one that can succeed later (no signal, 5xx, 429, signed out, a temporary password) waits. `FilePendingAttemptStore` keeps the queue in `Application Support/QBankKit`.
- **`ContentCache`** - loaded semesters, courses, practice sets, terms, and Review lists, keyed by `CacheKey` and stamped with when they were saved. `FileContentCache` keeps one JSON file per value in `Application Support/QBankKit/Content`, out of backups.
- **`WaitingProgress`** - answers still waiting on the phone, counted into a set's and a course's answered and fully right counts, so a set practiced without signal shows her answers before they are sent. It never counts high: where the phone cannot know whether a question was answered before, it counts at least the waiting answers.
- **`Scoring`** - the server's scoring rules and its feedback wording (Correct, Partly correct, the points line and the scoring rule), so an answer given offline shows the same mark the server records later. The contract tests check it against the server's own marks for every format.
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

`Tests/QBankKitTests/Fixtures/openapi.json` is a copy of the server's OpenAPI document (`apps/api/openapi.json` in the server repository, served at `https://qbank.dimitrygallego.com/openapi.json`), taken at the newest commit any fixture was recorded from; a test checks that every recorded call and status is documented there.

When the server's API changes, record the fixtures again the same way and update `openapi.json`, then run the tests.

The make-questions fixtures were recorded the same way, with the server's background runner and its own stand-in for Claude, so no recording called Claude. Those routes send a job's `createdAt`, `updatedAt`, and `finishedAt` in Postgres's own text (`2026-10-15 20:06:54.585+00`) rather than ISO 8601, and `QBankJSON.parseDate` reads both.
