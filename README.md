# Journal

[![Release](https://github.com/yuuge7/Journal/actions/workflows/release.yml/badge.svg)](https://github.com/yuuge7/Journal/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/yuuge7/Journal?label=latest)](https://github.com/yuuge7/Journal/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white)](#install)

An offline-first journaling app for Android. Entries, photos, moods, tags and statistics live in a local SQLite database on the device — nothing is uploaded, there is no account, and data leaves the phone only through an export you choose. Encrypted backups and readable Markdown/PDF copies are available.

---

## Features

**Writing and recovery**

- Rich text with headings, lists, checkboxes, quotes, code, colours and inline Markdown shortcuts (`# `, `- `, `1. `, `> `).
- Autosave after two quiet seconds, explicit pending/failure/retry states, recovered-draft banners and a direct Continue writing action.
- Focus mode, compact controls for short screens, a live session clock and a separate accumulated writing time. Time stops while the app is inactive or in the background.
- Bundled writing templates, remembered template selection, a persistent start-blank option, and personal templates made from an existing entry.
- Photo attachments and locally recorded/playable voice notes. Photo-only entries receive a wide image preview.
- Inline existing-tag suggestions after `#`, optional locally stored location, and `[[` links to another entry.
- Separate entry and creation dates, with a backfill explanation when writing about an older day.

**Finding and organising**

- A weighted time spine, sticky day headings, long-press day totals, visible gaps, and collapsed weeks for entries older than 90 days.
- Indexed FTS5 search over titles and writing, plus tag search, matching preview highlights, and title/journal/year scopes.
- Bounded feed pages with Load older entries, year/month jumps, and a pull-down gesture to return to today.
- Bulk tagging/moving, journal colour and emoji previews, entry/word counts, last-written dates, reordering, and notebook archiving.
- Swipe or editor-menu deletion with an Undo action. Entries and entire notebooks remain recoverable in Recently deleted for 30 days.

**Looking back and measuring**

- On this day, this week last year, and your first entry.
- Swipeable months, a week strip, and a 12-month heat map weighted by time spent writing.
- Current/longest streaks, writing totals, 30-day activity, a 24-hour writing histogram, notebook word/time totals, mood history and words by mood, backfill rate, linked personal records, and earned milestones.

**Privacy and Android**

- Light, dark or system theme. Bundled fonts, large-text layouts, semantic actions and reduced-motion support.
- Optional biometric/device-PIN app lock and screenshot/recents protection.
- Edge-to-edge system bars and predictive back. Android cloud backup and device-transfer backup are disabled deliberately.
- A home-screen widget with today's bead, streak and Write action; a launcher shortcut and Quick Settings Write tile.
- No account, analytics or release-build network permission. Microphone and location permissions are requested only when those features are used.

**Keeping a copy**

- Password-encrypted `.mjbackup` export with a contents summary, numerical progress, full verification before delivery, and checksum verification when saved to a chosen device location.
- Stable entry IDs make repeated imports safe: choose Skip existing or Replace matching entries. Older version-1 backups remain readable.
- Readable Markdown (with an attachment ZIP when needed) and PDF exports, explicitly labelled as unencrypted copies.
- Optional local backup reminders, last-saved-backup information, and release notes linked from Settings.

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
│   ├── attachment_service.dart # photo/voice storage and orphan cleanup
│   ├── backup_service.dart     # encrypted export/import
│   ├── readable_export_service.dart # Markdown/PDF exports
│   ├── platform_service.dart   # lock, permissions, voice, widget and reminders
│   └── save_file.dart          # bridge to the SAF save channel
├── screens/                    # feed, editor, calendar, stats, journals, settings, bin
└── widgets/                    # entry rows, spine, templates, links and insights
```

Schema: `journals 1—N entries`, `entries M—N tags` (junction table), `entries 1—N attachments`. Foreign keys cascade when a notebook is permanently purged; ordinary deletion moves it to the 30-day bin. Attachment rows store a file name only; the bytes live in `attachments/` under the app documents directory.

**Days are bucketed in Dart, never in SQL.** drift stores `DateTime`s as unix seconds and returns them in local time, while SQLite's `strftime(…, 'unixepoch')` formats in UTC — grouping by day inside a query pushes anything written near midnight into the neighbouring day. Calendar days, streaks, throwbacks and the activity chart therefore group with `localDay()` / `dayOrdinal()` from [`lib/data/database.dart`](lib/data/database.dart), and SQL only ever receives range filters whose bounds are local midnights. Day differences use `dayOrdinal()` rather than `Duration.inDays`, which reports 23-hour DST days as zero and silently breaks streaks.

### Backup format

A `.mjbackup` is a ZIP wrapped in chunked AES-256-GCM encryption. New exports use container version 2:

```
magic "MJRNLv2\0" (8 B) | salt (16 B) | PBKDF2 iterations (4 B BE)
KDF identifier (1 B; 1 = PBKDF2-HMAC-SHA256) | password verifier (16 B)
then per chunk: cipherLen (4 B BE) | nonce (12 B) | ciphertext | GCM tag (16 B)
```

- PBKDF2 uses 210,000 iterations and a 256-bit key. Each plaintext chunk is at most 1 MiB.
- Associated data authenticates the header and chunk sequence. An authenticated empty final chunk detects truncation, including removal of whole chunks.
- The ZIP contains `manifest.json`, `journals.json`, `tags.json`, streaming `entries.ndjson`, and `images/` (photos and voice attachments).
- Export decrypts and reopens the result to verify its manifest and entry count before offering it to the user.
- Import validates paths and every entry before a database transaction. Files are copied under fresh names; matching entry IDs are skipped or replaced according to the user's choice.
- Invalid file, truncated data, wrong password and damaged authenticated data have distinct errors. A damaged password-verifier/header can also look like a wrong password; version-1 first-chunk authentication cannot distinguish wrong passwords from damage.
- Version-1 containers remain readable. Legacy entries receive deterministic IDs on import so repeated legacy imports also deduplicate.
- Device preferences, app lock settings and local notification schedules are never backed up.

### Schema and retention

Schema version 4 adds stable entry IDs, a locally computed month/day search key, optional location, notebook order/archive state and deletion timestamps. Migration snapshots for versions 3 and 4 and a data-integrity migration test are committed. Calendar queries use indexed local-midnight ranges; analytics project metadata without loading entry bodies. Attachment/tag subscriptions cover rendered entries. Expired bin items and unreferenced attachment files are swept on startup.

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
flutter test                                               # full host suite
flutter test --dart-define=TEST_TEXT_SCALE=2                # large-text CI pass
flutter test integration_test/app_test.dart -d emulator-5554 # real Android flows
flutter test test/streak_test.dart                         # one file
flutter test --plain-name 'streak'                         # one test
flutter test --exclude-tags golden                         # host suite without Windows goldens
dart run build_runner build   # drift codegen, after any schema change
flutter build apk --release                                # release APK
dart run flutter_launcher_icons                            # after changing assets/icon/*.png
```

`lib/data/database.g.dart` is generated. Never edit it by hand — change `lib/data/database.dart` and re-run build_runner.

Tests run on the host machine and use a real in-memory SQLite database (`AppDatabase.withExecutor(NativeDatabase.memory())`), so day bucketing, streaks and calendar queries are covered against actual SQL rather than mocks.

The golden images in `test/goldens/` are generated on Windows with Flutter 3.47.0. Fonts render differently across operating systems, so CI compares them in a dedicated Windows job and runs the remaining tests on Linux. On Linux or macOS, use `--exclude-tags golden` for both host-suite commands above. After an intentional visual change, run `flutter test test/visual_test.dart --update-goldens` on Windows with the pinned SDK, review the images, and commit them. Failed CI comparisons are saved in the `golden-failures` workflow artifact; a failed golden test blocks the release.

Android UI screenshots can be collected with `flutter drive --driver test_driver/integration_test.dart --target integration_test/app_test.dart -d emulator-5554`; they are written to `build/qa/`. Grant microphone and notification permissions on the test emulator when requested. The flow also injects a failed write to verify the retry indicator and that Back preserves unsaved writing.

For the small-display pass, set the emulator to 960×2100 pixels at 480 dpi (320dp wide), then run the same driver with `--target integration_test/large_text_test.dart`. It checks both themes with 2× text, including the editor with the keyboard open. Restore the display with `adb shell wm size reset` and `adb shell wm density reset` afterwards.

The optional `integration_test/platform_test.dart` pass uses `--dart-define=TEST_DEVICE_PIN=true`. Configure a temporary PIN on a test emulator, enter it in Android's unlock prompt, grant location permission and supply a GPS fix. The test verifies unlocking and relocking on backgrounding. Remove the temporary PIN afterwards. Physical Motorola launcher masks and enrolled biometric hardware still require checks on those devices.

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

1. `flutter analyze`, `flutter test` and a second large-text test pass — a red build never ships
2. The next version is chosen: the minor number climbs until it reaches a tag that does not exist yet (`v1.0` → `v1.1` → `v1.2` …) and the Android `versionCode` climbs with it, so a run can never overwrite an earlier release and every APK installs over the previous one
3. The release APK and AAB are built and signed with the key from the secrets; the certificate is printed into the run summary, and bundle symbols/mapping files are retained as workflow artifacts
4. If the version changed, the bump is committed back to `main` as `chore(release): Journal vX.Y [skip ci]` and tagged
5. A GitHub release named **Journal vX.Y** is published with generated notes and the APK and AAB attached

Nothing else needs to be touched to cut a release — merge to `main` and the tag, the version bump and the APK follow. `workflow_dispatch` runs the same job manually.

## Contributing

1. Fork and branch off `main` (`git checkout -b feat/short-description`).
2. Keep `flutter analyze` clean and `flutter test` green; add tests for anything touching day math, streaks, drafts or backup.
3. Re-run `dart run build_runner build` after a schema change, and commit `database.g.dart`, a new schema snapshot and migration coverage.
4. Conventional commit subjects (`feat:`, `fix:`, `chore:`) — they land in the generated release notes.
5. Open a pull request against `main`. Merging it publishes a release, so make sure the change is one you want shipped.

Worth knowing before you dig in:

- `isDraft` means "the editor never closed cleanly", i.e. crash recovery. Both the Done button and system back finalise an entry; drafts are excluded from streaks, calendar dots and statistics, so anything that leaves an entry stuck as a draft silently zeroes the user's stats.
- Every calendar, streak, throwback and activity query keys off `entryDate` (the day an entry belongs to), never `createdAt`.
- `backup_service.dart` streams in both directions on purpose — keep any change to it streaming.
- File import and saving use the Android Storage Access Framework through the `journal/save_file` channel. Journal explains the import policy in its own sheet before opening the required system document picker.
- `intl` is pinned to `^0.20.2` because `flutter_localizations` pins it; loosening it makes the resolver fall back to an ancient flutter_quill.

## License

No license file is present yet, so the default applies: all rights reserved. If you intend to accept outside contributions, add a `LICENSE` (MIT or Apache-2.0 are the usual choices for a Flutter app) before the first pull request arrives.
