# QBank privacy policy

Status: draft, written before the app's code. Before the first TestFlight build reaches anyone but the owner, a worker re-reads every claim below against the app and the server, fixes what changed, and sets the date on the next line. See [release.md](release.md).

Last reviewed against the code: not yet.

This policy will be published at the privacy policy URL named in [app-store-listing.md](app-store-listing.md). A change to what the app or the server keeps updates this file first.

## What this app is

QBank is an iPhone and iPad app for practicing nursing exam questions (NCLEX style). It is the phone and tablet version of the QBank web app. Both talk to the same private QBank server, which one person runs for himself and a few invited users. You sign in with the account the owner set up for you; the app has no sign-up of its own.

## What we do not do

- No advertising, ad networks, or advertising identifiers.
- No tracking. Nothing about you is shared with data brokers or used across other companies' apps or websites.
- We do not sell, rent, or share your data with anyone.
- No analytics or crash-reporting services. The app bundles no third-party code that collects data.
- No access to your contacts, location, microphone, health data, or other apps. The camera and your photos are used only to make questions, and only for the photos you take or pick (see section 4).
- No chat, public profiles, or feeds.

## What the app and the server keep

### 1. Your account

- **Email address and password.** You sign in with the email address and password of your QBank account. The server stores the email address and a one-way hash of the password, never the password itself. The app sends your password only to the QBank server, over HTTPS, at sign-in, and does not store it. iOS may offer to save it in your own Passwords app; that is Apple's feature and under your control.
- **Passkeys.** You can save a passkey for your account, in the app or on the web, and sign in with it instead of your password. The passkey's private key stays in your Passwords app, or the passkey app you chose, and never leaves your devices; iOS checks your face, fingerprint, or passcode before using it. When you save one, the server keeps its public key and id, a name (in the app, the device it was saved on, such as "iPhone"), when it was saved, and what the device reported about it (whether it syncs between your devices, and how it can be used). Signing in sends only a signature over a one-time challenge. Settings lists your passkeys and removes them; a removed passkey no longer signs you in, and its copy in your Passwords app stays until you delete it there.
- **Display name.** Your account has a name, set by the owner when the account is made. The app may show it; it does not ask you for one.
- **Account role.** Whether the account is a user account or the owner's admin account, and whether you must choose a new password at your next sign-in.

### 2. Your sign-in session

- When you sign in, the server creates a session and the app receives a session token. The app stores the token in the iOS Keychain on that device only, and sends it with every request so you stay signed in.
- With each session the server stores when it was created and expires, the IP address the sign-in came from, and the device description the app sends (its user agent). The sign-in library records these by default; QBank does not use them, and never uses them to work out where you are.
- Sessions expire on their own after a long period of no use. Signing out removes the token from the device and ends the session on the server when the device can reach it.
- After 5 wrong passwords in a row the server locks sign-in for that email address for a short time. For that it keeps the email address, a count of failed tries, and when the lock ends.

### 3. Your answers and progress

This is what the app is for. For your account the server keeps:

- every answer you submit: which question, your response, whether you marked it as a guess, its score, and when you answered;
- your progress per question (how many tries, how many fully right, the latest result) and which questions are on your Review list, including ones you cleared by hand;
- your study sessions: practice sets, Review runs, and exams, with when they started and ended, the folders and question pool you picked for an exam, the time limit, and the score;
- the course you opened most recently, so the app and the web app open where you left off.

Your answers and progress are yours alone among users: other users cannot see them. Every semester, course, topic, page, folder, set, question, and term belongs to your account. The server keeps that study content with your account, and another account cannot see or reach it. There is no shared question bank.

**The owner can see your progress.** The server's admin account can look at a user's own study content, answers, and progress (to help with studying) and can set a temporary password for a user who forgot theirs. He looks at one account at a time, and his changes apply only to that account. No email is sent; the owner gives you the temporary password himself.

### 4. Importing and making questions

- **Importing a question file.** The file you choose or paste is sent to the server and checked. If you import it, it becomes a set in the course and folder you pick. The set is your account's own study content, kept on the server with your account.
- **Making questions** (only on the accounts the owner turns it on for). The notes you paste, the photos you take or pick, or the file you choose are sent to the server with the course, folder, and choices you make. The server deletes the photos and files once it has read them. It keeps the text of your material (what you pasted, and what it read from your photos and files) in the record of that set, with the questions it wrote, so the set can carry on where it stopped; the record is deleted with your account. To read your material and to write and check the questions, the server sends it to Anthropic's Claude API under the owner's own Anthropic account; the app never contacts Anthropic itself and holds no key. The questions become a set in the course and folder you pick, your account's own study content like an imported file. The server also keeps a record of each set you start (when, for which course and folder, how far it got, and how much of the AI service it used), to show your recent sets and to keep to a daily limit. **Exam twins** work the same way: Write exam twins on Exam setup sends the course, the folders you tick, and whether to use only the questions you last got wrong; the server sends those practice questions, already in QBank, to Anthropic's Claude API to write a new exam question for each, files them in the same folders, and keeps a record of the job like a set's.
- **Camera and photos.** The app uses the camera only when you tap Take photo while making questions. The photo picker gives the app only the photos you pick; the app cannot see the rest of your photo library.

### 5. What stays on your device

- **Saved for offline.** So you can practice without a signal, the app keeps a copy of the courses on your Home screen, with their sets and questions, and your recent progress, plus the Review list and terms of each course you open, in its own storage on the device. It saves them by itself while it is online. Answers you give without a connection are scored on the device and wait there until they can be sent. The server ignores an answer it already has, so nothing is counted twice. Exams need a connection and are not kept for offline use.
- **Settings on the device.** Your light or dark look choice, whether the Face ID lock is on, and whether you answered the offer to save a passkey are stored on the device.
- **The Face ID lock.** When you turn it on, iOS checks your face, fingerprint, or passcode and tells the app only whether it matched. The app never receives or stores any biometric data, and nothing about the lock is sent to the server.
- **Signing out** removes the session token, the offline copy, and any answers still waiting to send. The app warns you before it removes answers that have not been sent.
- Deleting the app removes everything it stored on that device.

### 6. Exporting your data

Settings has **Export my progress**, which asks the server for your answers, progress, Review list, scores, and study sessions as one JSON file and hands it to the iOS share sheet. Where the file goes from there (Files, AirDrop, another app) is your choice; QBank keeps no record of it.

### 7. TestFlight

While the app is tested through Apple's TestFlight, Apple may share with the owner the feedback, screenshots, and crash reports you choose to send from the TestFlight app, plus basic information Apple attaches to them (device model, iOS version). That is Apple's service, covered by Apple's privacy policy. The app itself sends nothing to Apple.

## Where the data lives and who handles it

- The QBank server runs on a rented server in the United States. All traffic between the app and the server is encrypted with HTTPS.
- The server's database is backed up so it can be restored after a failure. Backup copies are kept in private storage that only the owner can read, and are deleted automatically after about 30 days.
- The hosting and backup storage companies store the server's data on the owner's behalf and do not use it for anything else. No other company receives your data from QBank, except Anthropic, which receives the material you send to make questions, and the practice questions you pick for exam twins (section 4), and processes them under Anthropic's own commercial terms and privacy policy.

## How long data is kept

- **On the server:** your account, study content, answers, and progress are kept until the account is deleted. Expired sessions stop working; their records are removed with the account. Photos and files sent to make questions are deleted once the server has read them; the text of your material stays in the record of that set until the account is deleted. Deleting a set, a folder, or a past exam in the app hides it everywhere, and Undo can bring it back as it was for 30 days; the server keeps it, with your answers to it, until the account is deleted, and nothing is ever deleted unless you confirm it.
- **In backups:** up to about 30 days after deletion from the live server.
- **On your iPhone or iPad:** until you sign out or delete the app.

## Deleting your account and data

The app has no in-app sign-up, so accounts are made and removed by the owner. To delete your account, ask the owner (contact below). He removes the account from the server, and with it everything linked to it: sign-in, sessions, passkeys, your study content (semesters, courses, topics, pages, folders, sets, questions, and terms), answers, progress, Review list, exams, the records of the sets you made questions for, and your last-opened course. Backup copies age out within about 30 days. To remove the copy on your device, sign out or delete the app.

If you only want a copy of your data, use **Export my progress** first.

## Children

QBank is made for nursing students preparing for licensing exams. It is not directed at children, and accounts are only made by the owner for people he knows.

## Features that will change this policy

This is planned and is not in the app yet. It updates this policy before it ships:

- **Using the app on this device without an account:** courses, answers, and progress would stay only on the device and nothing would be sent to the server.

## Contact

For privacy questions or to delete your account, email PRIVACY_CONTACT_EMAIL (the owner fills this in before the policy is published; see [release.md](release.md)). For questions about the source code, open an issue at https://github.com/D-E-A-G/qbank/issues; never put personal data in a public issue.
