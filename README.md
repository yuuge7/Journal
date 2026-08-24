# Journal

[![Release](https://github.com/yuuge7/Journal/actions/workflows/release.yml/badge.svg)](https://github.com/yuuge7/Journal/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/yuuge7/Journal?label=latest)](https://github.com/yuuge7/Journal/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white)](#install)

An offline-first journaling app for Android. Entries, photos, moods, tags and statistics live in a local SQLite database on the device — nothing is uploaded, there is no account, and the only way data leaves the phone is a password-encrypted backup file you export yourself.

---

## Features

**Writing**

- Rich text editor (flutter_quill): headers, lists, checkboxes, bold/italic/underline, code blocks, colours
- Auto-save with a 2 s debounce — a crash or a swipe-away never costs you text
- Writing templates (Daily Reflection, Gratitude, Dream Log, Travel Log, Goals Check-in)
- Photo attachments from camera or gallery, with a thumbnail strip and a full-screen viewer
- Mood picker (1–5) per entry
- The entry date is separate from the creation date, so old memories can be backfilled onto the day they happened

**Organisation**

- Chronological feed with full-text search over titles and content
- Multiple journals with their own name, colour and emoji; the feed filters per journal
- Tags, created inline while writing

**Reliving**

- "On this day" throwback: entries from the same calendar day in earlier years, surfaced at the top of the feed
- Calendar with a dot per day that has entries; tap a day to read it or write for it

**Statistics**

- Word count and time spent writing, per entry (both shown on the feed card) and in total
- Writing streaks: current and longest run of consecutive days
- Totals for entries, words, writing time and photos, plus a 30-day activity chart

**Backup**

- Export everything — entries, journals, tags, images — into one password-encrypted `.mjbackup` file, saved anywhere on the device or shared to another app
- Import merges a backup back in: journals and tags are matched by name, entries are always added

## Install

Grab the APK from the [latest release](https://github.com/yuuge7/Journal/releases/latest) and open it on the device. Android 7.0 (API 24) or newer.

Every release is signed with the same key, so a newer APK installs straight over an older one.

## Architecture

| Layer | Choice |
|---|---|
| Database | [drift](https://drift.simonbinder.eu/) over SQLite, reactive `watch()` queries |
| State | [flutter_riverpod](https://riverpod.dev/) — `StreamProvider`s wrapping the drift streams |
| Editor | [flutter_quill](https://pub.dev/packages/flutter_quill) 11, documents stored as delta JSON plus a plain-text mirror for search |
| Debounce | rxdart `debounceTime` |
| Calendar | table_calendar |
| Backup crypto | cryptography (PBKDF2 + AES-GCM) and archive (ZIP) |

Data flows one way: drift `watch*()` query → `StreamProvider` → widget. Screens never touch the database for feed-level data, writes go through `AppDatabase`, and every dependent stream re-emits on its own — there is no cache to invalidate.

```
lib/
├── main.dart                   # app shell + Material 3 theme (light/dark)
├── providers.dart              # every Riverpod provider
├── data/
│   ├── database.dart           # drift tables, day math, streaks, calendar and stats queries
│   └── templates.dart          # writing templates as quill deltas
├── services/
│   ├── attachment_service.dart # image storage in the app documents directory
│   ├── backup_service.dart     # encrypted export/import
│   └── save_file.dart          # bridge to the SAF save channel
├── screens/                    # feed, editor, calendar, stats, journals, settings
└── widgets/                    # entry card, template sheet
```

Schema: `journals 1—N entries`, `entries M—N tags` (junction table), `entries 1—N attachments`. Foreign keys cascade, so deleting a journal cleans up everything beneath it. Attachment rows store a file name only; the bytes live in `attachments/` under the app documents directory.

**Days are bucketed in Dart, never in SQL.** drift stores `DateTime`s as unix seconds and returns them in local time, while SQLite's `strftime(…, 'unixepoch')` formats in UTC — grouping by day inside a query pushes anything written near midnight into the neighbouring day. Calendar dots, streaks, throwbacks and the activity chart therefore group with `localDay()` / `dayOrdinal()` from [`lib/data/database.dart`](lib/data/database.dart), and SQL only ever receives range filters whose bounds are local midnights. Day differences use `dayOrdinal()` rather than `Duration.inDays`, which reports 23-hour DST days as zero and silently breaks streaks.

### Backup format

A `.mjbackup` file is a chunked AES-256-GCM container around a ZIP:

```
magic "MJRNLv1\0" (8 B) | salt (16 B) | PBKDF2 iterations (4 B BE)
then per chunk: cipherLen (4 B BE) | nonce (12 B) | ciphertext | GCM tag (16 B)
```

- Key derivation: PBKDF2-HMAC-SHA256, 210 000 iterations, 256-bit
- 1 MiB plaintext chunks, so encryption and decryption use bounded memory whatever the archive size
- Inside the ZIP: `manifest.json`, `journals.json`, `tags.json`, `entries.ndjson`, `images/`
- Entries are NDJSON — export streams database pages out, import parses line by line, neither side materialises the whole dataset
- A wrong password fails GCM authentication on the first chunk and is reported as such

## Getting started

### Prerequisites

| Tool | Version |
|---|---|
| Flutter SDK | 3.47.0 (stable) — `flutter --version` |
| Dart | 3.13 (ships with Flutter) |
| JDK | 17 or newer (21 is what CI uses) |
| Android SDK | Platform 36 + build-tools, e.g. via Android Studio |

### Set up a clone

```bash
git clone https://github.com/yuuge7/Journal.git
cd Journal
flutter pub get
flutter run                 # debug build on a connected device or emulator
```

`android/local.properties` is machine-specific and is not committed; Flutter regenerates it on the first build. If it does not, create it with your own paths:

```properties
sdk.dir=/path/to/Android/sdk
flutter.sdk=/path/to/flutter
```

### Everyday commands

```bash
flutter analyze                                            # lints, must be clean
flutter test                                               # full test suite
flutter test test/streak_test.dart                         # one file
flutter test --plain-name 'streak'                         # one test
dart run build_runner build --delete-conflicting-outputs   # drift codegen, after any schema change
flutter build apk --release                                # release APK
dart run flutter_launcher_icons                            # after changing assets/icon/*.png
```

`lib/data/database.g.dart` is generated. Never edit it by hand — change `lib/data/database.dart` and re-run build_runner.

Tests run on the host machine and use a real in-memory SQLite database (`AppDatabase.withExecutor(NativeDatabase.memory())`), so day bucketing, streaks and calendar queries are covered against actual SQL rather than mocks.

## Signing

Release builds are signed with an RSA key held outside the repository. `android/app/build.gradle.kts` reads `android/key.properties`; when that file is absent — a fresh clone, a contributor's machine — release builds fall back to the debug key so the project still compiles.

```
journal-release.jks        # the keystore, in the project root, git ignored
android/key.properties     # storePassword / keyPassword / keyAlias / storeFile, git ignored
```

> **Keep a backup of the keystore and its password.** Android identifies an app by its signing key: lose it and no future build can update an installed copy — users would have to uninstall and lose their journal. Store the `.jks` and the password in a password manager or another offline backup, never in the repository.

### Moving the key to another machine

1. Copy `journal-release.jks` into the project root of the clone on the new machine.
2. Recreate `android/key.properties` next to it (both files are git ignored, so they never travel with a clone):

   ```properties
   storePassword=<the store password>
   keyPassword=<the key password>
   keyAlias=journal
   storeFile=../../journal-release.jks
   ```

3. Verify the key before relying on it:

   ```bash
   keytool -list -v -keystore journal-release.jks -alias journal
   flutter build apk --release
   ```

   The SHA-256 fingerprint printed by `keytool` must match the one on the existing releases — check with
   `apksigner verify --print-certs <downloaded>.apk`.

### Signing in CI

The release workflow rebuilds those two files from repository secrets. Under **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | the keystore, base64 encoded (see below) |
| `KEYSTORE_PASSWORD` | `storePassword` from `key.properties` |
| `KEY_PASSWORD` | `keyPassword` from `key.properties` |
| `KEY_ALIAS` | `journal` |

Encode the keystore:

```bash
# Linux / macOS / Git Bash
base64 -w0 journal-release.jks > journal-release.jks.base64

# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("journal-release.jks")) | Set-Content journal-release.jks.base64
```

Paste the contents of that file as the secret value, then delete the file. The workflow fails fast with a pointer to this section if the secrets are missing — releasing a debug-signed APK would break updates for everyone who already installed one.

## Releases

`.github/workflows/release.yml` runs on every push to `main`:

1. `flutter analyze` and `flutter test` — a red build never ships
2. The next version is chosen: the minor number climbs until it reaches a tag that does not exist yet (`v1.0` → `v1.1` → `v1.2` …) and the Android `versionCode` climbs with it, so a run can never overwrite an earlier release and every APK installs over the previous one
3. The release APK is built and signed with the key from the secrets, and its certificate is printed into the run summary
4. If the version changed, the bump is committed back to `main` as `chore(release): Journal vX.Y [skip ci]` and tagged
5. A GitHub release named **Journal vX.Y** is published with generated notes and `Journal-vX.Y.apk` attached

Nothing else needs to be touched to cut a release — merge to `main` and the tag, the version bump and the APK follow. `workflow_dispatch` runs the same job manually.

## Contributing

1. Fork and branch off `main` (`git checkout -b feat/short-description`).
2. Keep `flutter analyze` clean and `flutter test` green; add tests for anything touching day math, streaks, drafts or backup.
3. Re-run `dart run build_runner build --delete-conflicting-outputs` after any change to the drift schema, and commit the regenerated `database.g.dart`.
4. Conventional commit subjects (`feat:`, `fix:`, `chore:`) — they land in the generated release notes.
5. Open a pull request against `main`. Merging it publishes a release, so make sure the change is one you want shipped.

Worth knowing before you dig in:

- `isDraft` means "the editor never closed cleanly", i.e. crash recovery. Both the Done button and system back finalise an entry; drafts are excluded from streaks, calendar dots and statistics, so anything that leaves an entry stuck as a draft silently zeroes the user's stats.
- Every calendar, streak, throwback and activity query keys off `entryDate` (the day an entry belongs to), never `createdAt`.
- `backup_service.dart` streams in both directions on purpose — keep any change to it streaming.
- `file_picker` is deliberately unused: its bundled Kotlin Gradle Plugin does not compile under the Flutter toolchain in use. Opening files goes through `file_selector`, saving through the `journal/save_file` platform channel in `MainActivity.kt`.
- `intl` is pinned to `^0.20.2` because `flutter_localizations` pins it; loosening it makes the resolver fall back to an ancient flutter_quill.

## License

No license file is present yet, so the default applies: all rights reserved. If you intend to accept outside contributions, add a `LICENSE` (MIT or Apache-2.0 are the usual choices for a Flutter app) before the first pull request arrives.
