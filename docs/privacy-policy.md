# QBank privacy policy

Status: draft, written before the app's code. Before the first TestFlight build reaches anyone but the owner, a worker re-reads every claim below against the app and the server, fixes what changed, and sets the date on the next line. See [release.md](release.md).

Last reviewed against the code: not yet.

This policy will be published at the privacy policy URL named in [app-store-listing.md](app-store-listing.md). A change to what the app or the server keeps updates this file first.

## What this app is

QBank is an iPhone app for practicing nursing exam questions (NCLEX style). It is the phone version of the QBank web app. Both talk to the same private QBank server, which one person runs for himself and a few invited students. You sign in with the account the owner set up for you; the app has no sign-up of its own.

## What we do not do

- No advertising, ad networks, or advertising identifiers.
- No tracking. Nothing about you is shared with data brokers or used across other companies' apps or websites.
- We do not sell, rent, or share your data with anyone.
- No analytics or crash-reporting services. The app bundles no third-party code that collects data.
- No access to your contacts, location, microphone, camera, photo library, health data, or other apps.
- No chat, public profiles, or feeds.

## What the app and the server keep

### 1. Your account

- **Email address and password.** You sign in with the email address and password of your QBank account. The server stores the email address and a one-way hash of the password, never the password itself. The app sends your password only to the QBank server, over HTTPS, at sign-in, and does not store it. iOS may offer to save it in your own Passwords app; that is Apple's feature and under your control.
- **Display name.** Your account has a name, set by the owner when the account is made. The app may show it; it does not ask you for one.
- **Account role.** Whether the account is a student or the owner's admin account, and whether you must choose a new password at your next sign-in.

### 2. Your sign-in session

- When you sign in, the server creates a session and the app receives a session token. The app stores the token in the iOS Keychain on that iPhone only, and sends it with every request so you stay signed in.
- With each session the server stores when it was created and expires, the IP address the sign-in came from, and the device description the app sends (its user agent). The sign-in library records these by default; QBank does not use them, and never uses them to work out where you are.
- Sessions expire on their own after a long period of no use. Signing out removes the token from the phone and ends the session on the server when the phone can reach it.
- After 5 wrong passwords in a row the server locks sign-in for that email address for a short time. For that it keeps the email address, a count of failed tries, and when the lock ends.

### 3. Your answers and progress

This is what the app is for. For your account the server keeps:

- every answer you submit: which question, your response, whether you marked it as a guess, its score, and when you answered;
- your progress per question (how many tries, how many fully right, the latest result) and which questions are on your Review list, including ones you cleared by hand;
- your study sessions: practice sets, Review runs, and exams, with when they started and ended, the weeks and question pool you picked for an exam, the time limit, and the score;
- the course you opened most recently, so the app and the web app open where you left off.

Your answers and progress are yours alone among students: other students cannot see them. The question bank itself (semesters, courses, weeks, sets, questions, and terms) is shared by everyone on the server and is not personal data.

**The owner can see your progress.** The server's admin account can look at a student's answers and progress (to help with studying) and can set a temporary password for a student who forgot theirs. No email is sent; the owner gives you the temporary password himself.

### 4. What stays on your iPhone

- **Saved for offline.** So you can practice without a signal, the app keeps a copy of the courses, sets, and questions you have opened, and your recent progress, in its own storage on the phone. Answers you give without a connection are scored on the phone and wait there until they can be sent. The server ignores an answer it already has, so nothing is counted twice. Exams need a connection and are not kept for offline use.
- **Settings on the phone.** Your light or dark look choice is stored on the phone.
- **Signing out** removes the session token, the offline copy, and any answers still waiting to send. The app warns you before it removes answers that have not been sent.
- Deleting the app removes everything it stored on that phone.

### 5. Exporting your data

Settings has **Export my progress**, which asks the server for your answers, progress, Review list, scores, and study sessions as one JSON file and hands it to the iOS share sheet. Where the file goes from there (Files, AirDrop, another app) is your choice; QBank keeps no record of it.

### 6. TestFlight

While the app is tested through Apple's TestFlight, Apple may share with the owner the feedback, screenshots, and crash reports you choose to send from the TestFlight app, plus basic information Apple attaches to them (device model, iOS version). That is Apple's service, covered by Apple's privacy policy. The app itself sends nothing to Apple.

## Where the data lives and who handles it

- The QBank server runs on a rented server in the United States. All traffic between the app and the server is encrypted with HTTPS.
- The server's database is backed up so it can be restored after a failure. Backup copies are kept in private storage that only the owner can read, and are deleted automatically after about 30 days.
- The hosting and backup storage companies store the server's data on the owner's behalf and do not use it for anything else. No other company receives your data from QBank.

## How long data is kept

- **On the server:** your account, answers, and progress are kept until the account is deleted. Expired sessions stop working; their records are removed with the account.
- **In backups:** up to about 30 days after deletion from the live server.
- **On your iPhone:** until you sign out or delete the app.

## Deleting your account and data

The app has no in-app sign-up, so accounts are made and removed by the owner. To delete your account, ask the owner (contact below). He removes the account from the server, and with it everything linked to it: sign-in, sessions, passkeys, answers, progress, Review list, exams, and your last-opened course. Backup copies age out within about 30 days. To remove the copy on your phone, sign out or delete the app.

If you only want a copy of your data, use **Export my progress** first.

## Children

QBank is made for nursing students preparing for licensing exams. It is not directed at children, and accounts are only made by the owner for people he knows.

## Features that will change this policy

These are planned and are not in the app yet. Each one updates this policy before it ships:

- **Passkeys and Face ID sign-in:** the server would keep each passkey's public key, name, and creation date (it already does for the web app); the private key never leaves your Apple device.
- **Importing a question file in the app:** the file you choose is sent to the server and becomes shared course content.
- **Making questions from your notes or photos (one account only, on the owner's server):** the notes and photos you choose would be sent to the server and to the AI provider that writes the questions, used only to write that set.
- **Using the app on this phone without an account:** courses, answers, and progress would stay only on the phone and nothing would be sent to the server.

## Contact

For privacy questions or to delete your account, email PRIVACY_CONTACT_EMAIL (the owner fills this in before the policy is published; see [release.md](release.md)). For questions about the source code, open an issue at https://github.com/D-E-A-G/qbank/issues; never put personal data in a public issue.
