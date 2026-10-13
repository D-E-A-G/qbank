# QBank for iPhone

QBank is an NCLEX practice question bank: courses, weekly practice sets, a review list of missed questions, and timed exams. This repository is its iPhone app, written in SwiftUI.

The app is a client of a private QBank server. The server, the web app, and their deployment live in a separate private repository; nothing here runs or configures them.

**Status:** early. The app signs in with an existing QBank account, shows your courses with their weeks and sets, practices a set in all eight question formats with the rationale after each answer and the set result at the end, keeps your courses on the phone so you can practice without signal and sends those answers when you are back online, and Settings has your account, password, semesters and courses, and light or dark Look; Review, exams, and Terms come next. There is no TestFlight build yet.

## Getting started

You need Xcode 26 or later. The app runs on iPhone with iOS 18 or later.

Open `QBank.xcodeproj` in Xcode and run the `QBank` scheme, or build and test from the command line:

```sh
test/sim.sh -- xcodebuild test \
  -project QBank.xcodeproj -scheme QBank \
  -destination 'platform=iOS Simulator,id={{UDID}}'
```

`test/sim.sh` creates a fresh simulator for the run and deletes it afterwards. `test/release-checks.sh` checks the repository rules and needs no Xcode.

## Layout

- `QBank/` - the app
- `QBankTests/` - unit tests (Swift Testing)
- `QBankUITests/` - UI tests (XCTest)
- `Packages/QBankDesign/` - the design system: colors, type, spacing and base SwiftUI components shared with the web app
- `Packages/QBankKit/` - the API client, session store, and offline core, as a Swift package with no UI
- `test/` - simulator wrapper, package tests, and repository checks
- `docs/ci.md` - how CI runs

## Security and support

Report security issues privately as described in [SECURITY.md](SECURITY.md). For build and code questions, see [SUPPORT.md](SUPPORT.md).

## License

No license for now.
